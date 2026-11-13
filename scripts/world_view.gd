extends Node2D
## Draws a World in isometric projection. All art is generated in code.
##
## Static scenery is baked into one mesh per diagonal row of cells (terrain,
## then canals/paths/roads, then standing objects) and only rebuilt where the
## world changed, so a frame is a few dozen draw calls plus the moving things:
## boats, chimney smoke and glints on the water.

signal boat_arrived

const World := preload("res://scripts/world.gd")
const Art := preload("res://scripts/art.gd")
const Sprites := preload("res://scripts/sprites.gd")
const T := World.T
const L := World.L
const B := World.B

const HW := Art.HW
const HH := Art.HH
const HSTEP := Art.HSTEP
const BASE := 16.0

const CANAL_W := 0.2
const BOAT_SPEED := 1.5
## Sprite name stem for each kind of building.
const BUILDING_SPRITE := {
	B.COTTAGE: "cottage", B.TERRACE: "terrace", B.SHOP: "shop", B.CAFE: "cafe", B.PUB: "pub",
	B.BOATYARD: "boatyard", B.WINDMILL: "windmill", B.CHURCH: "church", B.FARM: "farm", B.MANOR: "manor",
}
const TREES := ["oak_a", "oak_b", "oak_c", "oak_d", "oak_a", "oak_c", "birch_a", "poplar_a", "pine_a", "pine_b"]

var world: World
var hover := Vector2i(-1, -1)
var hover_ok := true
var show_labels := true

var _t := 0.0
var _font: Font
var _puffs: Array = []
var _boats: Array = []

var _fields: Array = []
var _field_polys := {}
var _hedges := {}
var _cell_field := {}
var _river_dirs := {}
var _tp_in := {}

var _terrain: Array = []       # per diagonal: ArrayMesh
var _linkm: Array = []
var _objm: Array = []           # ground-level props that are still meshes
var _sprites: Array = []        # per diagonal: [[Texture2D, Rect2], ...]
var _place_top := {}            # cell -> height of the building sprite on it
var _smoke: Array = []         # per diagonal: [Vector2] chimney tops
var _water: Array = []         # per diagonal: [Vector2i] canal cells
var _over := {}                # cell -> ArrayMesh drawn above boats (bridges, locks)
var _over_cells: Array = []    # per diagonal: [Vector2i]
var _dirty := {}
var _focus := 0
var _seen_version := -1
var _seen_net := -1


func _ready() -> void:
	_font = ThemeDB.fallback_font
	Sprites.ensure_loaded()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func set_world(wd: World) -> void:
	world = wd
	_boats.clear()
	_puffs.clear()
	hover = Vector2i(-1, -1)
	var rows := world.w + world.h
	for arr in [_terrain, _linkm, _objm, _sprites, _smoke, _water, _over_cells]:
		arr.clear()
		arr.resize(rows)
	_over.clear()
	_build_fields()
	_river_dirs.clear()
	for course in world.rivers:
		for i in course.size():
			var c: Vector2i = course[i]
			var dirs := []
			if i > 0:
				dirs.append(Vector2(course[i - 1] - c))
			if i < course.size() - 1:
				dirs.append(Vector2(course[i + 1] - c))
			if dirs.size() < 2 and world.open_ends.has(c):
				dirs.append(Vector2(world.open_ends[c]))
			_river_dirs[c] = dirs
	for d in rows:
		_terrain[d] = _bake(d, 0)
	_seen_version = -1
	_seen_net = -1
	refresh(Vector2i(-1, -1))
	_rebuild(999)


## Call after the world changes. `near` is the cell that was edited, if known.
func refresh(near: Vector2i) -> void:
	if world.version == _seen_version:
		return
	_seen_version = world.version
	var rows := world.w + world.h
	if world.net_version != _seen_net or near.x < 0:
		_seen_net = world.net_version
		_orient_towpaths()
		for d in rows:
			_dirty[d] = true
	if near.x >= 0:
		_focus = near.x + near.y
		for d in range(_focus - 2, _focus + 4):
			if d >= 0 and d < rows:
				_dirty[d] = true
		_rebuild(6)


func add_puff(c: Vector2i) -> void:
	_puffs.append({"c": c, "t": _t})


# Re-bakes up to `budget` dirty rows, nearest the last edit first.
func _rebuild(budget: int) -> void:
	if _dirty.is_empty():
		return
	var rows := _dirty.keys()
	rows.sort_custom(func(a, b): return absi(a - _focus) < absi(b - _focus))
	for d in rows.slice(0, budget):
		_dirty.erase(d)
		_linkm[d] = _bake(d, 1)
		_objm[d] = _bake(d, 2)
		for c in (_over_cells[d] if _over_cells[d] != null else []):
			_over.erase(c)
		var cells := []
		var row: Array[Vector2i] = []
		for c in _row(d):
			if not _forward(c):
				row.append(c)
		if d > 0:
			for c in _row(d - 1):
				if _forward(c):
					row.append(c)
		for c in row:
			var mb := Art.MB.new()
			_emit_over(c, mb)
			var mesh := mb.mesh()
			if mesh != null:
				_over[c] = mesh
				cells.append(c)
		_over_cells[d] = cells
	queue_redraw()


func _row(d: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(maxi(0, d - world.h + 1), mini(world.w, d + 1)):
		var c := Vector2i(x, d - x)
		if world.in_bounds(c):
			out.append(c)
	return out


# True if a cell's links reach forward across a corner, so they must be
# drawn after the two cells that flank that corner.
func _forward(c: Vector2i) -> bool:
	return world.link(c, c + Vector2i(1, 1)) != -1


func _bake(d: int, layer: int) -> ArrayMesh:
	var mb := Art.MB.new()
	match layer:
		0:
			for c in _row(d):
				_emit_terrain(c, mb)
		1:
			var water := []
			for c in _row(d):
				if not _forward(c):
					_emit_links(c, mb)
				if world.has_canal(c):
					water.append(c)
			if d > 0:
				for c in _row(d - 1):
					if _forward(c):
						_emit_links(c, mb)
			_water[d] = water
		2:
			var smoke := []
			var sprites := []
			for c in _row(d):
				_emit_objects(c, mb, sprites, smoke)
			_smoke[d] = smoke
			_sprites[d] = sprites
	return mb.mesh()


# --- Boats ------------------------------------------------------------------

func boat_count() -> int:
	return _boats.size()


func clear_boats() -> void:
	_boats.clear()


## Sends a boat along `path`, arriving from off the map and leaving the same way.
func spawn_boat(path: Array[Vector2i], dir_in: Vector2i, dir_out: Vector2i) -> void:
	var cells: Array[Vector2i] = [path[0] + dir_in]
	cells.append_array(path)
	cells.append(path[path.size() - 1] + dir_out)
	_boats.append({"cells": cells, "s": 0.0, "look": randi() % maxi(Sprites.boat_liveries, 1)})


func _process(delta: float) -> void:
	_t += delta
	if world == null:
		return
	_rebuild(4)
	var alive := []
	for boat in _boats:
		var cells: Array[Vector2i] = boat.cells
		var n := cells.size()
		var i := clampi(int(floor(boat.s)), 0, n - 1)
		var here := world.height(cells[clampi(i, 1, n - 2)])
		var slow := here != world.height(cells[clampi(i - 1, 1, n - 2)]) or here != world.height(cells[clampi(i + 1, 1, n - 2)])
		boat.s += (0.5 if slow else BOAT_SPEED) * delta
		if boat.s >= n:
			boat_arrived.emit()
		else:
			alive.append(boat)
	_boats = alive
	queue_redraw()


func _boat_state(boat: Dictionary) -> Dictionary:
	var cells: Array[Vector2i] = boat.cells
	var n := cells.size()
	var i := clampi(int(floor(boat.s)), 0, n - 1)
	var f: float = boat.s - i
	var cell := cells[i]
	var a := Vector2(cells[i - 1] - cell) if i > 0 else Vector2(cell - cells[1])
	var b := Vector2(cells[i + 1] - cell) if i < n - 1 else Vector2(cell - cells[n - 2])
	var centre := Vector2(cell) + Vector2(0.5, 0.5)
	var p0 := centre + a * 0.5
	var p1 := centre + b * 0.5
	var p := p0.lerp(centre, f).lerp(centre.lerp(p1, f), f)
	var dir := (centre - p0).lerp(p1 - centre, f)
	dir = b.normalized() if dir.length() < 0.001 else dir.normalized()
	p += Vector2(-dir.y, dir.x) * 0.075

	var lv := func(j: int) -> float: return float(world.height(cells[clampi(j, 1, n - 2)]))
	var z: float = lv.call(i)
	if f < 0.3:
		z = lerpf((lv.call(i - 1) + z) * 0.5, z, f / 0.3)
	elif f > 0.7:
		z = lerpf(z, (lv.call(i + 1) + z) * 0.5, (f - 0.7) / 0.3)
	var alpha := 1.0
	if i == 0:
		alpha = smoothstep(0.3, 0.9, f)
	elif i == n - 1:
		alpha = 1.0 - smoothstep(0.1, 0.7, f)
	var other := cells[i - 1] if (f < 0.5 and i > 0) else cells[mini(i + 1, n - 1)]
	return {"pos": Vector3(p.x, p.y, z * HSTEP), "dir": dir, "alpha": alpha, "cell": cell, "other": other,
		"near": [cells[maxi(i - 1, 0)], cell, cells[mini(i + 1, n - 1)]], "look": boat.look}


# --- Projection -------------------------------------------------------------

func cell_center(c: Vector2i) -> Vector2:
	return Art.iso(Vector2(c) + Vector2(0.5, 0.5), world.height(c) * HSTEP)


## View-local position -> cell, taking terrain height into account.
func cell_at(p: Vector2) -> Vector2i:
	for lvl in range(world.max_height, -1, -1):
		var a := p.x / HW
		var b := (p.y + lvl * HSTEP) / HH
		var c := Vector2i(floori((a + b) * 0.5), floori((b - a) * 0.5))
		if world.in_bounds(c) and world.height(c) == lvl:
			return c
	return Vector2i(-1, -1)


func bounds() -> Rect2:
	var top := -world.max_height * HSTEP - 50.0
	return Rect2(-world.h * HW, top, (world.w + world.h) * HW, (world.w + world.h) * HH + BASE - top)


func _zc(c: Vector2i) -> float:
	return world.height(c) * HSTEP


# --- Fields and hedgerows ---------------------------------------------------

static func _clip(poly: PackedVector2Array, m: Vector2, n: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var da := (a - m).dot(n)
		var db := (b - m).dot(n)
		if da <= 0.0:
			out.append(a)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


# Splits the land into irregular fields (a Voronoi diagram of random points)
# and cuts each field to the cells it covers, so fields ignore the grid.
func _build_fields() -> void:
	_fields.clear()
	_field_polys.clear()
	_hedges.clear()
	_cell_field.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world.title) + world.w * 131 + world.h
	var count := maxi(8, world.w * world.h / 16)
	for i in count:
		var pick := rng.randf()
		var kind := 0 if pick < 0.44 else (1 if pick < 0.64 else (2 if pick < 0.8 else (3 if pick < 0.92 else 4)))
		var col: Color = Art.FIELD[kind]
		col = col.lightened(rng.randf_range(0.0, 0.06)).darkened(rng.randf_range(0.0, 0.05))
		_fields.append({
			"seed": Vector2(rng.randf_range(0, world.w), rng.randf_range(0, world.h)),
			"kind": kind, "col": col, "angle": rng.randf() * PI})

	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			if not world.in_bounds(c):
				continue
			var centre := Vector2(x + 0.5, y + 0.5)
			var nearest := 0
			for i in count:
				if centre.distance_to(_fields[i].seed) < centre.distance_to(_fields[nearest].seed):
					nearest = i
			_cell_field[c] = nearest
			var reach: float = centre.distance_to(_fields[nearest].seed) + 1.5
			var near := []
			for i in count:
				if centre.distance_to(_fields[i].seed) <= reach:
					near.append(i)
			var polys := []
			var hedges := []
			for i in near:
				var poly := PackedVector2Array([Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)])
				var si: Vector2 = _fields[i].seed
				for j in near:
					if j != i and poly.size() >= 3:
						var sj: Vector2 = _fields[j].seed
						poly = _clip(poly, (si + sj) * 0.5, sj - si)
				if poly.size() < 3:
					continue
				polys.append([poly, i])
				for e in poly.size():
					var a := poly[e]
					var b := poly[(e + 1) % poly.size()]
					var on_x := is_equal_approx(a.x, b.x) and is_equal_approx(a.x, roundf(a.x))
					var on_y := is_equal_approx(a.y, b.y) and is_equal_approx(a.y, roundf(a.y))
					if on_x or on_y or a.distance_to(b) < 0.05:
						continue
					var j := _other_side(near, i, (a + b) * 0.5)
					if i < j:
						hedges.append([a, b, (i * 7 + j * 13) % 10 < 3])
			_field_polys[c] = polys
			_hedges[c] = hedges


func _other_side(candidates: Array, skip: int, p: Vector2) -> int:
	var best := -1
	for i in candidates:
		if i != skip and (best == -1 or p.distance_to(_fields[i].seed) < p.distance_to(_fields[best].seed)):
			best = i
	return best


# --- Towpath sides ----------------------------------------------------------

# Walks each stretch of canal from one end so the towpath can stay on the
# same bank all the way along it, bends included.
func _orient_towpaths() -> void:
	_tp_in.clear()
	var roots := []
	for p in world.portals:
		roots.append([p.cell, p.dir])
	var ends := []
	var rest := []
	for c in world.adj:
		var n := world.link_dirs(c, [L.CANAL]).size()
		if n == 1:
			ends.append([c, Vector2i.ZERO])
		elif n > 1:
			rest.append([c, Vector2i.ZERO])
	roots.append_array(ends)
	roots.append_array(rest)
	for root in roots:
		if _tp_in.has(root[0]):
			continue
		_tp_in[root[0]] = root[1]
		var queue: Array = [root[0]]
		var head := 0
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			for d in world.link_dirs(c, [L.CANAL]):
				if not _tp_in.has(c + d):
					_tp_in[c + d] = -d
					queue.append(c + d)


# --- Baking: terrain --------------------------------------------------------

func _emit_terrain(c: Vector2i, mb: Art.MB) -> void:
	var z := _zc(c)
	var o := Vector2(c)
	var lift := 0.045 * world.height(c)

	# Faces down to lower ground, or to the bottom of the slab at the map edge.
	for side in 2:
		var n := c + (Vector2i(0, 1) if side == 0 else Vector2i(1, 0))
		var edge := not world.in_bounds(n)
		var nz := -BASE if edge else _zc(n)
		if nz >= z:
			continue
		var a := o + (Vector2(0, 1) if side == 0 else Vector2(1, 0))
		var b := o + Vector2(1, 1)
		var shade := 0.0 if side == 1 else 0.14
		if edge:
			mb.quad(Art.iso(a, z), Art.iso(b, z), Art.iso(b, nz), Art.iso(a, nz), Art.EARTH.darkened(shade))
			mb.quad(Art.iso(a, nz + 6), Art.iso(b, nz + 6), Art.iso(b, nz), Art.iso(a, nz), Art.EARTH.darkened(shade + 0.18))
		else:
			mb.quad(Art.iso(a, z), Art.iso(b, z), Art.iso(b, nz), Art.iso(a, nz), Art.BANK.darkened(shade))
			for j in 2:
				var f := 0.2 + 0.5 * Art.rnd(c.x, c.y, 300 + side * 10 + j)
				var p := a.lerp(b, f)
				mb.quad(Art.iso(p, nz + 9), Art.iso(p + (b - a) * 0.16, nz + 9),
					Art.iso(p + (b - a) * 0.16, nz + 4), Art.iso(p, nz + 4), Art.STONE.darkened(0.15 + shade))
		mb.quad(Art.iso(a, z), Art.iso(b, z), Art.iso(b, z - 3.5), Art.iso(a, z - 3.5), Art.GRASS_LIP.darkened(shade))

	# Land: whichever fields cross this cell.
	var base_col: Color = _fields[_cell_field[c]].col
	mb.quad(Art.iso(o + Vector2(-0.01, -0.01), z), Art.iso(o + Vector2(1.01, -0.01), z),
		Art.iso(o + Vector2(1.01, 1.01), z), Art.iso(o + Vector2(-0.01, 1.01), z), base_col.lightened(lift))
	for entry in _field_polys[c]:
		var pts := PackedVector2Array()
		for q: Vector2 in entry[0]:
			pts.append(Art.iso(q, z))
		mb.fan(pts, (_fields[entry[1]].col as Color).lightened(lift))

	var field: Dictionary = _fields[_cell_field[c]]
	Art.field_detail(mb, o, z, field, c)

	if _river_dirs.has(c):
		var dirs: Array = _river_dirs[c]
		_stroke(mb, c, dirs, 0.36, Art.RIVER_BANK, false)
		_stroke(mb, c, dirs, 0.29, Art.RIVER_EDGE, false)
		_stroke(mb, c, dirs, 0.25, Art.RIVER, false)
		_stroke(mb, c, dirs, 0.07, Art.RIVER.lightened(0.18), false)
		Art.reeds(mb, o + Vector2(0.14 + 0.1 * Art.rnd(c.x, c.y, 8), 0.2), z, c.x)
		if Art.rnd(c.x, c.y, 9) > 0.5:
			Art.stone(mb, o + Vector2(0.5 + 0.1 * Art.rnd(c.x, c.y, 10), 0.55), z)
	else:
		for seg in _hedges[c]:
			if seg[2]:
				Art.stone_wall(mb, seg[0], seg[1], z)
			else:
				Art.hedge(mb, seg[0], seg[1], z, c.x * 31 + c.y)


# --- Baking: canals, paths and roads ----------------------------------------

## Ribbon along the curve p0 -> pc -> p1 (cell coordinates), between lateral
## offsets o0..o1 measured to the left of travel. z is given at each end and
## at the middle.
func _band(mb: Art.MB, p0: Vector2, pc: Vector2, p1: Vector2, o0: float, o1: float,
		z0: float, zm: float, z1: float, col: Color) -> void:
	var straight := ((p0 + p1) * 0.5).distance_to(pc) < 0.001
	var steps := 2 if straight else 7
	var pa := Vector2.ZERO
	var pb := Vector2.ZERO
	for i in steps + 1:
		var t := float(i) / steps
		var pos := p0.lerp(pc, t).lerp(pc.lerp(p1, t), t)
		var tan := (pc - p0).lerp(p1 - pc, t)
		if tan.length() < 0.0001:
			tan = p1 - p0
		var n := Vector2(tan.y, -tan.x).normalized()
		var z := lerpf(z0, zm, t * 2.0) if t < 0.5 else lerpf(zm, z1, (t - 0.5) * 2.0)
		var a := Art.iso(pos + n * o0, z)
		var b := Art.iso(pos + n * o1, z)
		if i > 0:
			mb.quad(pa, a, b, pb, col)
		pa = a
		pb = b


func _mid_z(c: Vector2i, d: Vector2, ramp: bool) -> float:
	var n := c + Vector2i(d)
	if ramp and world.in_bounds(n):
		return (_zc(c) + _zc(n)) * 0.5
	return _zc(c)


## Symmetric ribbon of half-width `hw` joining every direction in `dirs`
## through the cell centre. `ramp` lets it climb between levels.
func _stroke(mb: Art.MB, c: Vector2i, dirs: Array, hw: float, col: Color, ramp: bool) -> void:
	var centre := Vector2(c) + Vector2(0.5, 0.5)
	var z := _zc(c)
	if dirs.size() <= 1:
		mb.disc(Art.iso(centre, z), hw * 1.414 * HW, hw * 1.414 * HH, col, 14)
		if dirs.size() == 1:
			var d: Vector2 = dirs[0]
			var zm := _mid_z(c, d, ramp)
			_band(mb, centre, centre + d * 0.25, centre + d * 0.5, -hw, hw, z, (z + zm) * 0.5, zm, col)
		return
	for i in dirs.size():
		for j in range(i + 1, dirs.size()):
			var a: Vector2 = dirs[i]
			var b: Vector2 = dirs[j]
			_band(mb, centre + a * 0.5, centre, centre + b * 0.5, -hw, hw,
				_mid_z(c, a, ramp), z, _mid_z(c, b, ramp), col)


func _dirs(c: Vector2i, types: Array) -> Array:
	var out := []
	for d in world.link_dirs(c, types):
		out.append(Vector2(d))
	return out


func _portal_dir(c: Vector2i) -> Vector2i:
	for p in world.portals:
		if p.cell == c:
			return p.dir
	return Vector2i.ZERO


func _emit_links(c: Vector2i, mb: Art.MB) -> void:
	if not world.adj.has(c):
		return
	var z := _zc(c)
	var centre := Vector2(c) + Vector2(0.5, 0.5)

	var road := _dirs(c, [L.ROAD])
	if not road.is_empty():
		if world.open_ends.has(c) and not _river_dirs.has(c):
			road.append(Vector2(world.open_ends[c]))
		_stroke(mb, c, road, 0.175, Art.VERGE, true)
		_stroke(mb, c, road, 0.135, Art.ROAD, true)
	var path := _dirs(c, [L.PATH])
	if not path.is_empty():
		_stroke(mb, c, path, 0.085, Art.PATH_EDGE, true)
		_stroke(mb, c, path, 0.06, Art.PATH, true)

	var old := _dirs(c, [L.DERELICT])
	if not old.is_empty():
		_stroke(mb, c, old, 0.26, Art.MUD, false)
		_stroke(mb, c, old, 0.16, Art.MURK, false)
		Art.weeds(mb, Vector2(c), z, c.x * 17 + c.y * 5)

	var canal := _dirs(c, [L.CANAL])
	if canal.is_empty():
		return
	var portal := _portal_dir(c)
	if portal != Vector2i.ZERO:
		canal.append(Vector2(portal))

	# Towpath on one bank, on the same side all the way along.
	var from := Vector2(_tp_in.get(c, Vector2i.ZERO))
	var outs := []
	for d in canal:
		if d != from:
			outs.append(d)
	for layer in [[0.27, 0.45, Art.PATH_EDGE], [0.27, 0.42, Art.PATH]]:
		if from == Vector2.ZERO:
			for d: Vector2 in outs:
				_band(mb, centre, centre + d * 0.25, centre + d * 0.5, layer[0], layer[1], z, z, z, layer[2])
		elif outs.is_empty():
			_band(mb, centre + from * 0.5, centre + from * 0.25, centre, layer[0], layer[1], z, z, z, layer[2])
		else:
			for d: Vector2 in outs:
				_band(mb, centre + from * 0.5, centre, centre + d * 0.5, layer[0], layer[1], z, z, z, layer[2])

	_stroke(mb, c, canal, CANAL_W + 0.085, Art.COPING, false)
	_stroke(mb, c, canal, CANAL_W + 0.03, Art.WATER_EDGE, false)
	_stroke(mb, c, canal, CANAL_W, Art.WATER, false)
	_stroke(mb, c, canal, 0.06, Art.WATER.lightened(0.14), false)
	if Art.rnd(c.x, c.y, 44) > 0.72 and canal.size() == 2 and not world.is_bridge(c):
		Art.lilies(mb, centre, z, c.x + c.y * 3)

	# Where the canal leaves the map, show the cut end on the edge of the slab.
	if portal == Vector2i(1, 0) or portal == Vector2i(0, 1):
		var side := Vector2(portal.y, portal.x) * CANAL_W
		var e := centre + Vector2(portal) * 0.5
		mb.quad(Art.iso(e - side, z), Art.iso(e + side, z), Art.iso(e + side, z - 8), Art.iso(e - side, z - 8),
			Art.WATER_EDGE.darkened(0.1))


# --- Baking: standing objects -----------------------------------------------

# Queues a sprite with its anchor on the ground at `p` (cell coordinates).
func _put(sprites: Array, name: String, p: Vector2, z: float) -> void:
	if Sprites.has(name):
		sprites.append([Sprites.texture(name), Sprites.rect(name, Art.iso(p, z)), p.x + p.y])


func _emit_objects(c: Vector2i, mb: Art.MB, sprites: Array, smoke: Array) -> void:
	var z := _zc(c)
	var o := Vector2(c)
	var centre := o + Vector2(0.5, 0.5)
	var seed := c.x * 92821 + c.y * 68917
	var mine := []
	var kind := world.building(c)
	if kind != B.NONE:
		var name := Sprites.pick(BUILDING_SPRITE[kind], seed / 7)
		_put(sprites, name, centre, z)
		if Sprites.has(name):
			_place_top[c] = Sprites.height(name)
			var puff := Sprites.smoke(name)
			if puff != Vector2.ZERO:
				smoke.append(Art.iso(centre, z) + puff)
		return
	for p in world.portals:
		if p.cell == c:
			Art.signpost(mb, _label_anchor(p), z)
	match world.terrain_at(c):
		T.WOOD:
			Art.wood_floor(mb, o, z, seed)
			var by_water := false
			for d in World.DIRS4:
				by_water = by_water or world.has_water(c + d) or _river_dirs.has(c + d)
			for j in 2 + int(Art.rnd(seed, 0, 60) > 0.4):
				var p := o + Vector2(0.2 + 0.6 * Art.rnd(seed, j, 61), 0.2 + 0.6 * Art.rnd(seed, j, 71))
				var pick := int(Art.rnd(seed, j, 81) * TREES.size())
				_put(mine, "willow_a" if (by_water and j == 0) else TREES[pick], p, z)
		T.ROCK:
			_put(mine, Sprites.pick("rock", seed), centre, z)
		T.GRASS:
			if not world.adj.has(c):
				var field: Dictionary = _fields[_cell_field[c]]
				var roll := Art.rnd(c.x, c.y, 99)
				if field.kind == 0 and roll > 0.82:
					var animal := "cow" if roll > 0.93 else "sheep"
					for j in 1 + int(Art.rnd(seed, 2, 2) > 0.4):
						_put(mine, Sprites.pick(animal, seed + j), o + Vector2(0.3 + 0.4 * j, 0.35 + 0.3 * Art.rnd(seed, j, 4)), z)
				elif field.kind == 3 and roll > 0.6:
					_put(mine, "haybale_a", o + Vector2(0.3 + 0.4 * Art.rnd(c.x, c.y, 5), 0.3 + 0.4 * Art.rnd(c.x, c.y, 6)), z)
				elif roll < 0.035:
					_put(mine, Sprites.pick("oak", seed), centre, z)
				elif roll < 0.07:
					_put(mine, "bush_a", centre, z)
				for seg in _hedges[c]:
					if not seg[2] and Art.rnd(c.x, c.y, 77) > 0.78:
						_put(mine, "oak_d", (seg[0] as Vector2).lerp(seg[1], 0.5), z)
						break
	mine.sort_custom(func(a, b): return a[2] < b[2])
	sprites.append_array(mine)


func _label_anchor(p: Dictionary) -> Vector2:
	var d := Vector2(p.dir)
	var side := Vector2(-d.y, d.x) * 0.42
	if side.x + side.y > 0.0:
		side = -side
	return Vector2(p.cell) + Vector2(0.5, 0.5) + side + d * 0.2


# Things that must be drawn over a passing boat: bridges and lock gates.
func _emit_over(c: Vector2i, mb: Art.MB) -> void:
	var z := _zc(c)
	var centre := Vector2(c) + Vector2(0.5, 0.5)
	var land := world.link_dirs(c, [L.PATH, L.ROAD])
	var over_river := _river_dirs.has(c) and not land.is_empty()
	if world.is_bridge(c) or over_river:
		var a := Vector2(land[0])
		var b := Vector2(land[1]) if land.size() > 1 else -a
		var is_road := not world.link_dirs(c, [L.ROAD]).is_empty()
		Art.bridge(mb, centre + a * 0.5, centre + b * 0.5, z, is_road, over_river and not world.has_water(c))
	for pair in world.locks():
		if pair[1] == c:
			# The chamber is cut into the upper level, so it is drawn with this cell.
			var down := Vector2(pair[0] - pair[1])
			Art.lock(mb, centre + down * 0.5, -down.normalized(), _zc(pair[0]), z)


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if world == null:
		return
	var last := world.w + world.h - 1
	var slots := {}
	for boat in _boats:
		var st := _boat_state(boat)
		var c: Vector2i = st.cell
		var o: Vector2i = st.other
		var slot := clampi(maxi(c.x + c.y, o.x + o.y) + 1, 0, last)
		if not slots.has(slot):
			slots[slot] = []
		slots[slot].append(st)

	for d in last + 1:
		if _terrain[d] != null:
			draw_mesh(_terrain[d], null)
		if _linkm[d] != null:
			draw_mesh(_linkm[d], null)
		for c: Vector2i in (_water[d] if _water[d] != null else []):
			_glint(c)
		for st in slots.get(d, []):
			_draw_boat(st)
			for c: Vector2i in st.near:
				if _over.has(c):
					draw_mesh(_over[c], null)
		if _objm[d] != null:
			draw_mesh(_objm[d], null)
		for item in (_sprites[d] if _sprites[d] != null else []):
			draw_texture_rect(item[0], item[1], false)
		for c: Vector2i in (_over_cells[d] if _over_cells[d] != null else []):
			draw_mesh(_over[c], null)
		for p: Vector2 in (_smoke[d] if _smoke[d] != null else []):
			for j in 3:
				var f := fmod(_t * 0.3 + j / 3.0 + p.x * 0.01, 1.0)
				draw_circle(p + Vector2(sin(f * 5.0 + j) * 3.0 + f * 5.0, -f * 22.0), 2.2 + f * 3.5,
					Color(1, 1, 1, 0.5 * (1.0 - f)))
	_draw_overlays()


func _glint(c: Vector2i) -> void:
	var hsh := Art.rnd(c.x, c.y, 7)
	var ph := _t * 0.6 + hsh * TAU
	var a := 0.16 + 0.16 * sin(ph * 1.7)
	var p := Art.iso(Vector2(c) + Vector2(0.5 + 0.07 * sin(ph), 0.5 + 0.07 * cos(ph * 0.8)), _zc(c))
	draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), Color(1, 1, 1, a), 1.2)


func _draw_boat(st: Dictionary) -> void:
	var pos: Vector3 = st.pos
	var dir: Vector2 = st.dir
	var alpha: float = st.alpha
	if alpha <= 0.01:
		return
	var flat := Vector2(pos.x, pos.y)
	pos.z += sin(_t * 2.5 + st.look) * 0.3 - 1.0
	# Wake trailing from the stern.
	for j in 3:
		draw_circle(Art.iso(flat - dir * (0.6 + j * 0.12), pos.z + 1.0), 3.6 - j * 0.8, Color(1, 1, 1, (0.26 - j * 0.07) * alpha))
	# The sprite set has the boat drawn from a ring of headings; use the nearest.
	var heading := int(round(atan2(dir.y, dir.x) / TAU * Sprites.boat_directions))
	var name := Sprites.boat(st.look, heading)
	if Sprites.has(name):
		draw_texture_rect(Sprites.texture(name), Sprites.rect(name, Art.iso(flat, pos.z)), false, Color(1, 1, 1, alpha))


func _plaque(pos: Vector2, text: String, size: int, bg: Color, ink: Color) -> void:
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var rect := Rect2(pos + Vector2(-extent.x * 0.5 - 6, -size * 0.5 - 4), Vector2(extent.x + 12, size + 8))
	draw_rect(rect.grow(1.5), ink)
	draw_rect(rect, bg)
	draw_string(_font, rect.position + Vector2(6, size + 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


func _draw_overlays() -> void:
	if show_labels:
		for p in world.portals:
			_plaque(Art.iso(_label_anchor(p), _zc(p.cell) + 30.0), p.name, 12, Color("f6ecd4"), Color("4a3b2e"))
		for p in world.places:
			var top := cell_center(p.cell) + Vector2(0, -minf(_place_top.get(p.cell, 34.0), 62.0) - 2.0)
			var extent := _font.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			var at := top + Vector2(-extent.x * 0.5, 0)
			draw_string_outline(_font, at, p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 6, Color(0.98, 0.95, 0.86))
			draw_string(_font, at, p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("33281f"))
			# Badge: what the place still needs, or a tick once it has it.
			var badge := top + Vector2(0, -20.0 + (0.0 if p.ok else sin(_t * 3.0 + p.cell.x) * 2.0))
			draw_circle(badge, 9.5, Color("fbf3df"))
			draw_circle(badge, 8.0, Color("6fa35a") if p.ok else Color("e0863a"))
			if p.ok:
				draw_polyline(PackedVector2Array([badge + Vector2(-4, 0), badge + Vector2(-1, 3), badge + Vector2(4, -3)]), Color.WHITE, 2.0)
			elif p.need == L.ROAD:
				draw_rect(Rect2(badge + Vector2(-4.5, -2.5), Vector2(9, 5)), Color.WHITE)
				draw_circle(badge + Vector2(-2.5, 3), 1.6, Color.WHITE)
				draw_circle(badge + Vector2(2.5, 3), 1.6, Color.WHITE)
			else:
				draw_circle(badge + Vector2(0, -3.2), 1.9, Color.WHITE)
				draw_line(badge + Vector2(0, -1), badge + Vector2(0, 2.5), Color.WHITE, 2.0)
				draw_line(badge + Vector2(0, 2), badge + Vector2(-2.5, 5), Color.WHITE, 1.6)
				draw_line(badge + Vector2(0, 2), badge + Vector2(2.5, 5), Color.WHITE, 1.6)

	if world.in_bounds(hover):
		_ring(hover, 0.46, Color(1, 1, 1, 0.9) if hover_ok else Color(0.85, 0.3, 0.25, 0.9), 2.5)
	var alive := []
	for puff in _puffs:
		var age: float = (_t - puff.t) / 0.4
		if age < 1.0:
			alive.append(puff)
			_ring(puff.c, 0.35 + 0.4 * age, Color(1, 1, 1, 0.8 * (1.0 - age)), 2.5)
	_puffs = alive


func _ring(c: Vector2i, r: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		pts.append(Art.iso(Vector2(c) + Vector2(0.5 + cos(a) * r, 0.5 + sin(a) * r), _zc(c) + 1.0))
	draw_polyline(pts, col, width)
