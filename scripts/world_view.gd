extends Node2D
## Draws a World in isometric projection.
##
## The map is surrounded by an apron of countryside that is not part of the
## game: fields, hedges and trees fading into haze, with the canals, roads and
## rivers carrying on into the distance. Only the land inside it can be built on.
##
## Drawing happens in two passes so standing things are never cut off:
##   1. everything flat (ground, water, paths, roads), for the whole map;
##   2. standing things (hedges, trees, buildings, bridges, locks, boats),
##      one diagonal row at a time from back to front. Raised ground is drawn
##      again in this pass so a hill still hides what is behind it.
## Each row's geometry is baked into meshes and only rebuilt when it changes.

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
## Cells of countryside drawn around the map: wide enough to fill the screen
## at any allowed zoom, fading fully into the background before its edge.
var APRON := 10
var _full_fade := 8            # distance from the land where the haze is complete
const BOAT_RUN := 6            # cells a boat travels through the countryside

const CANAL_W := 0.2
const BRICK_OLD := Color("9a6a55")       # Victorian engineering brick
const BRICK_MOSSY := Color("857a5c")
const STONE_NEW := Color("e2dccb")       # freshly laid coping
const CINDER := Color("b9ab92")          # old towpath
const CINDER_EDGE := Color("8f826b")
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
var show_derelict := false     # highlight silted canal (while restoring)

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
var _apron_h := {}             # apron cell -> ground level, carried on from the nearest land
var _apron_d := {}             # apron cell -> distance from the land, in cells
var _cont := {}                # apron cell -> [kind, dirs]: canals, roads, rivers carrying on
var _edge_lines: Array = []    # [[a, b, z], ...] the edge of the playable land
var _corner_z := {}            # cell corner -> ground height in pixels (slopes join the levels)
var _ground := {}              # cell -> [[screen points, colours], ...] lit ground pieces
var _relief: FastNoiseLite

var _flat_terrain: Array = []  # per row: ArrayMesh
var _flat_links: Array = []
var _raised: Array = []        # per row: raised ground drawn again over what is behind it
var _standing: Array = []      # per row: hedges, walls, signposts, reeds
var _sprites: Array = []       # per row: [[Texture2D, Rect2, depth, Color], ...]
var _place_top := {}           # cell -> height of the building sprite on it
var _smoke: Array = []         # per row: [Vector2] chimney tops
var _water: Array = []         # per row: [Vector2i] canal cells
var _over := {}                # cell -> ArrayMesh drawn above boats (bridges, locks)
var _over_cells: Array = []    # per row: [Vector2i]
var _dirty := {}
var _focus := 0
var _seen_version := -1
var _seen_net := -1


## Labels, badges and highlights: drawn on their own layer above the map so
## the haze never touches them.
class Overlay extends Node2D:
	var view: Node2D

	func _draw() -> void:
		view._draw_overlays(self)


var _overlay: Overlay


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_overlay = Overlay.new()
	_overlay.view = self
	add_child(_overlay)
	Sprites.ensure_loaded()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


# --- Cells and rows -----------------------------------------------------------

func _rows() -> int:
	return world.w + world.h + 4 * APRON - 1


func _ri(c: Vector2i) -> int:
	return c.x + c.y + 2 * APRON


func _in_range(c: Vector2i) -> bool:
	return c.x >= -APRON and c.y >= -APRON and c.x < world.w + APRON and c.y < world.h + APRON


## All cells (land and apron) on diagonal row `r`.
func _row(r: int) -> Array[Vector2i]:
	var d := r - 2 * APRON
	var out: Array[Vector2i] = []
	for x in range(maxi(-APRON, d - (world.h + APRON - 1)), mini(world.w + APRON, d + APRON + 1)):
		out.append(Vector2i(x, d - x))
	return out


func _h(c: Vector2i) -> int:
	return world.height(c) if world.in_bounds(c) else _apron_h.get(c, 0)


func _zc(c: Vector2i) -> float:
	return _h(c) * HSTEP


## True for countryside so far out that the haze hides it completely.
func _hidden(c: Vector2i) -> bool:
	return not world.in_bounds(c) and _apron_d.get(c, APRON) > _full_fade


## Haze is applied by a shader (see _build_haze); colours here stay plain.
func _fade(_c: Vector2i) -> float:
	return 0.0


# One value per cell, sampled smoothly by shaders/haze.gdshader.
func _build_haze() -> void:
	var size := Vector2i(world.w + 2 * APRON, world.h + 2 * APRON)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x - APRON, y - APRON)
			var f := 0.0
			if not world.in_bounds(c):
				var d: int = _apron_d.get(c, APRON)
				f = 0.3 + 0.7 * smoothstep(1.0, float(_full_fade), float(d))
			img.set_pixel(x, y, Color(f, f, f))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/haze.gdshader")
	mat.set_shader_parameter("fade_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("map_origin", Vector2(-APRON, -APRON) + Vector2(-0.5, -0.5) + Vector2(0.5, 0.5))
	mat.set_shader_parameter("map_size", Vector2(size))
	mat.set_shader_parameter("half_cell", Vector2(HW, HH))
	mat.set_shader_parameter("mist", Art.MIST)
	material = mat


# --- Setup ----------------------------------------------------------------------

func set_world(wd: World) -> void:
	world = wd
	APRON = clampi((world.w + world.h) / 3, 11, 16)
	_full_fade = APRON - 2
	_boats.clear()
	_puffs.clear()
	_place_top.clear()
	hover = Vector2i(-1, -1)
	var rows := _rows()
	for arr in [_flat_terrain, _flat_links, _raised, _standing, _sprites, _smoke, _water, _over_cells]:
		arr.clear()
		arr.resize(rows)
	_over.clear()
	_build_apron()
	_build_haze()
	_build_corners()
	_build_fields()
	_build_ground()
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
	_build_continuations()
	_build_edge()
	_seen_version = -1
	_seen_net = -1
	refresh(Vector2i(-1, -1))
	_rebuild(9999)


# Gives each apron cell the level of the nearest land, so hills carry on.
func _build_apron() -> void:
	_apron_h.clear()
	_apron_d.clear()
	var queue: Array[Vector2i] = []
	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			if world.in_bounds(c):
				queue.append(c)
	var dist := {}
	for c in queue:
		dist[c] = 0
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in World.DIRS4:
			var n := c + d
			if _in_range(n) and not dist.has(n) and not world.in_bounds(n):
				dist[n] = dist[c] + 1
				_apron_d[n] = dist[n]
				_apron_h[n] = _h(c)
				queue.append(n)


# Canals, roads and rivers carry on straight out across the apron.
func _build_continuations() -> void:
	_cont.clear()
	var starts := []
	for p in world.portals:
		starts.append([p.cell, p.dir, "canal"])
	for c in world.open_ends:
		starts.append([c, world.open_ends[c], "river" if _river_dirs.has(c) else "road"])
	for s in starts:
		var d: Vector2i = s[1]
		for k in range(1, APRON * 2 + 2):
			var c: Vector2i = s[0] + d * k
			if not _in_range(c):
				break
			if world.in_bounds(c):
				break
			_cont[c] = [s[2], [Vector2(-d), Vector2(d)]]


# The outline of the playable land, drawn as a soft line.
func _build_edge() -> void:
	_edge_lines.clear()
	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			if not world.in_bounds(c):
				continue
			var o := Vector2(c)
			if not world.in_bounds(c + Vector2i(0, -1)):
				_edge_lines.append([o, o + Vector2(1, 0)])
			if not world.in_bounds(c + Vector2i(-1, 0)):
				_edge_lines.append([o, o + Vector2(0, 1)])
			if not world.in_bounds(c + Vector2i(0, 1)):
				_edge_lines.append([o + Vector2(0, 1), o + Vector2(1, 1)])
			if not world.in_bounds(c + Vector2i(1, 0)):
				_edge_lines.append([o + Vector2(1, 0), o + Vector2(1, 1)])


## Call after the world changes. `near` is the cell that was edited, if known.
func refresh(near: Vector2i) -> void:
	if world.version == _seen_version:
		return
	_seen_version = world.version
	var rows := _rows()
	if world.net_version != _seen_net or near.x < 0:
		_seen_net = world.net_version
		_orient_towpaths()
		for r in rows:
			_dirty[r] = true
	if near.x >= 0:
		_focus = _ri(near)
		for r in range(_focus - 2, _focus + 4):
			if r >= 0 and r < rows:
				_dirty[r] = true
		_rebuild(6)


func add_puff(c: Vector2i) -> void:
	_puffs.append({"c": c, "t": _t})


# Re-bakes up to `budget` dirty rows, nearest the last edit first.
func _rebuild(budget: int) -> void:
	if _dirty.is_empty():
		return
	var rows := _dirty.keys()
	rows.sort_custom(func(a, b): return absi(a - _focus) < absi(b - _focus))
	for r in rows.slice(0, budget):
		_dirty.erase(r)
		var cells := _row(r)
		var terrain := Art.MB.new()
		var links := Art.MB.new()
		var raised := Art.MB.new()
		var standing := Art.MB.new()
		var sprites := []
		var smoke := []
		var water := []
		for c in cells:
			if _hidden(c):
				continue
			_emit_terrain(c, terrain)
			_emit_links(c, links)
			if _is_raised(c):
				_emit_terrain(c, raised)
				_emit_links(c, raised)
			_emit_standing(c, standing, sprites, smoke)
			if world.in_bounds(c) and world.has_canal(c):
				water.append(c)
		_flat_terrain[r] = terrain.mesh()
		_flat_links[r] = links.mesh()
		_raised[r] = raised.mesh()
		_standing[r] = standing.mesh()
		_sprites[r] = sprites
		_smoke[r] = smoke
		_water[r] = water
		for c in (_over_cells[r] if _over_cells[r] != null else []):
			_over.erase(c)
		var over := []
		for c in cells:
			if not world.in_bounds(c):
				continue
			var mb := Art.MB.new()
			_emit_over(c, mb)
			var mesh := mb.mesh()
			if mesh != null:
				_over[c] = mesh
				over.append(c)
		_over_cells[r] = over
	queue_redraw()


# Ground that stands above something behind it, so it must be drawn again
# after the things on the lower ground.
func _is_raised(c: Vector2i) -> bool:
	var h := _h(c)
	if h == 0:
		return false
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		if _in_range(c + d) and _h(c + d) < h:
			return true
	return false


# --- Boats ------------------------------------------------------------------

func boat_count() -> int:
	return _boats.size()


func clear_boats() -> void:
	_boats.clear()


## Sends a boat along `path`, arriving from the distance and leaving the same way.
func spawn_boat(path: Array[Vector2i], dir_in: Vector2i, dir_out: Vector2i) -> void:
	var cells: Array[Vector2i] = []
	for k in range(BOAT_RUN, 0, -1):
		cells.append(path[0] + dir_in * k)
	cells.append_array(path)
	for k in range(1, BOAT_RUN + 1):
		cells.append(path[path.size() - 1] + dir_out * k)
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
		var here := _h(cells[i])
		var slow := here != _h(cells[maxi(i - 1, 0)]) or here != _h(cells[mini(i + 1, n - 1)])
		boat.s += (0.5 if slow else BOAT_SPEED) * delta
		if boat.s >= n:
			boat_arrived.emit()
		else:
			alive.append(boat)
	_boats = alive
	queue_redraw()
	_overlay.queue_redraw()


func _boat_state(boat: Dictionary) -> Dictionary:
	var cells: Array[Vector2i] = boat.cells
	var n := cells.size()
	var i := clampi(int(floor(boat.s)), 0, n - 1)
	var f: float = boat.s - i
	var cell := cells[i]
	var back := cells[i - 1] - cell if i > 0 else cell - cells[1]
	var ahead := cells[i + 1] - cell if i < n - 1 else cell - cells[n - 2]
	var p0 := _join(cell, back)
	var pc := _node(cell)
	var p1 := _join(cell, ahead)
	var p := p0.lerp(pc, f).lerp(pc.lerp(p1, f), f)
	var dir := (pc - p0).lerp(p1 - pc, f)
	dir = (p1 - p0).normalized() if dir.length() < 0.001 else dir.normalized()
	p += Vector2(-dir.y, dir.x) * 0.075

	var z := float(_h(cell))
	if f < 0.3:
		z = lerpf((_h(cell + back) + z) * 0.5, z, f / 0.3)
	elif f > 0.7:
		z = lerpf(z, (_h(cell + ahead) + z) * 0.5, (f - 0.7) / 0.3)
	var s: float = boat.s
	var alpha := smoothstep(0.0, 2.0, s) * (1.0 - smoothstep(n - 2.0, float(n), s))
	var other := cell + back if f < 0.5 else cell + ahead
	return {"pos": Vector3(p.x, p.y, z * HSTEP), "dir": dir, "alpha": alpha, "cell": cell, "other": other,
		"near": [cell + back, cell, cell + ahead], "look": boat.look}


# --- Projection -------------------------------------------------------------

func cell_center(c: Vector2i) -> Vector2:
	return Art.iso(Vector2(c) + Vector2(0.5, 0.5), _zc(c))


## View-local position -> cell, taking terrain height into account.
func cell_at(p: Vector2) -> Vector2i:
	var m := map_at(p)
	var c := Vector2i(floori(m.x), floori(m.y))
	return c if world.in_bounds(c) else Vector2i(-1, -1)


## The playable land, in view-local coordinates.
func bounds() -> Rect2:
	var top := -world.max_height * HSTEP - 50.0
	return Rect2(-world.h * HW, top, (world.w + world.h) * HW, (world.w + world.h) * HH - top)


# --- Height surface -----------------------------------------------------------
# Each cell is four triangles meeting at its centre. The centre sits at the
# cell's own level (where canals, locks and buildings stand); each corner is
# the average of the cells around it, so levels join with slopes, not cliffs.

func _build_corners() -> void:
	_corner_z.clear()
	_relief = FastNoiseLite.new()
	_relief.seed = hash(world.title)
	_relief.frequency = 0.12
	for y in range(-APRON, world.h + APRON + 1):
		for x in range(-APRON, world.w + APRON + 1):
			var sum := 0.0
			var apron := 0
			for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var c := Vector2i(x, y) + d
				var cc := Vector2i(clampi(c.x, -APRON, world.w + APRON - 1), clampi(c.y, -APRON, world.h + APRON - 1))
				sum += _h(cc)
				apron += int(not world.in_bounds(cc))
			var z := sum / 4.0 * HSTEP
			if apron == 4:
				# Rolling country in the distance.
				z += (_relief.get_noise_2d(x, y) * 0.5 + 0.5) * HSTEP * 1.4
			_corner_z[Vector2i(x, y)] = z


func _cz(corner: Vector2i) -> float:
	return _corner_z.get(corner, 0.0)


# Height at the middle of a cell: its own level on the map, smooth beyond it.
func _centre_z(c: Vector2i) -> float:
	if world.in_bounds(c):
		return world.height(c) * HSTEP
	return (_cz(c) + _cz(c + Vector2i(1, 0)) + _cz(c + Vector2i(0, 1)) + _cz(c + Vector2i(1, 1))) * 0.25


# The four triangles of a cell: [[a, b], ...] corners in cell space, each
# joined to the centre (0.5, 0.5).
const FAN := [[Vector2(0, 0), Vector2(1, 0)], [Vector2(1, 0), Vector2(1, 1)],
	[Vector2(1, 1), Vector2(0, 1)], [Vector2(0, 1), Vector2(0, 0)]]


func _fan_index(u: float, v: float) -> int:
	if v <= u and v <= 1.0 - u:
		return 0
	if u >= v and u >= 1.0 - v:
		return 1
	if v >= u and v >= 1.0 - u:
		return 2
	return 3


## Ground height (screen pixels) at a point in map coordinates.
func ground_z(p: Vector2) -> float:
	var c := Vector2i(floori(p.x), floori(p.y))
	var l := p - Vector2(c)
	var tri: Array = FAN[_fan_index(l.x, l.y)]
	var a: Vector2 = tri[0]
	var b: Vector2 = tri[1]
	var m := Vector2(0.5, 0.5)
	var w := _bary(l, a, b, m)
	return w.x * _cz(c + Vector2i(a)) + w.y * _cz(c + Vector2i(b)) + w.z * _centre_z(c)


static func _bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-6:
		return Vector3(1, 0, 0)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)


## Map coordinates under a view-local point, following the ground's height.
func map_at(local: Vector2) -> Vector2:
	var z := 0.0
	var m := Vector2.ZERO
	for i in 6:
		var a := local.x / HW
		var b := (local.y + z) / HH
		m = Vector2((a + b) * 0.5, (b - a) * 0.5)
		z = ground_z(m)
	return m


# Light falls from the upper left; slopes facing it are brighter. Shading is
# worked out at each corner and centre and blended, so hills look smooth.
const LIGHT := Vector3(-0.55, -0.35, 0.76)


func _light(dzdx: float, dzdy: float) -> float:
	var s := 1.0 / (2.0 * HH)   # pixels of height per cell -> slope
	var n := Vector3(-dzdx * s, -dzdy * s, 1.0).normalized()
	return 1.0 + (n.dot(LIGHT) - LIGHT.z) * 1.1


func _corner_light(k: Vector2i) -> float:
	return _light((_cz(k + Vector2i(1, 0)) - _cz(k - Vector2i(1, 0))) * 0.5,
		(_cz(k + Vector2i(0, 1)) - _cz(k - Vector2i(0, 1))) * 0.5)


func _centre_light(c: Vector2i) -> float:
	var z00 := _cz(c)
	var z10 := _cz(c + Vector2i(1, 0))
	var z01 := _cz(c + Vector2i(0, 1))
	var z11 := _cz(c + Vector2i(1, 1))
	return _light((z10 + z11 - z00 - z01) * 0.5, (z01 + z11 - z00 - z10) * 0.5)


static func _lit(col: Color, light: float) -> Color:
	return Color(col.r * light, col.g * light, col.b * light, col.a)


# Cuts each field piece of each cell into the cell's four triangles, so every
# piece lies on one triangle, then gives each point its height and light.
func _build_ground() -> void:
	_ground.clear()
	var m := Vector2(0.5, 0.5)
	var corner_light := {}
	for k in _corner_z:
		corner_light[k] = _corner_light(k)
	for y in range(-APRON, world.h + APRON):
		for x in range(-APRON, world.w + APRON):
			var c := Vector2i(x, y)
			if _hidden(c):
				continue
			var o := Vector2(c)
			var pieces := []
			var zm := _centre_z(c)
			var lm := _centre_light(c)
			var lift := 0.03 * zm / HSTEP
			for tri: Array in FAN:
				var a: Vector2 = tri[0]
				var b: Vector2 = tri[1]
				var za := _cz(c + Vector2i(a))
				var zb := _cz(c + Vector2i(b))
				var la: float = corner_light.get(c + Vector2i(a), 1.0)
				var lb: float = corner_light.get(c + Vector2i(b), 1.0)
				for entry in _field_polys[c]:
					var poly: PackedVector2Array = entry[0]
					for edge in [[a, b, m], [b, m, a], [m, a, b]]:
						var p: Vector2 = o + edge[0]
						var q: Vector2 = o + edge[1]
						var r: Vector2 = o + edge[2]
						var nrm := (q - p).orthogonal()
						if (r - p).dot(nrm) > 0.0:
							nrm = -nrm
						poly = _clip(poly, p, nrm)
						if poly.size() < 3:
							break
					if poly.size() < 3:
						continue
					var col: Color = (_fields[entry[1]].col as Color).lightened(lift)
					var pts := PackedVector2Array()
					var cols := PackedColorArray()
					for q: Vector2 in poly:
						var w := _bary(q - o, a, b, m)
						pts.append(Art.iso(q, w.x * za + w.y * zb + w.z * zm))
						cols.append(_lit(col, w.x * la + w.y * lb + w.z * lm))
					pieces.append([pts, cols])
			_ground[c] = pieces


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
	var span := Vector2(world.w + 2 * APRON, world.h + 2 * APRON)
	var count := maxi(12, int(span.x * span.y / 16.0))
	for i in count:
		var pick := rng.randf()
		var kind := 0 if pick < 0.46 else (1 if pick < 0.66 else (2 if pick < 0.8 else (3 if pick < 0.92 else 4)))
		var col: Color = Art.FIELD[kind]
		col = col.lightened(rng.randf_range(0.0, 0.03))
		_fields.append({
			"seed": Vector2(rng.randf_range(-APRON, world.w + APRON), rng.randf_range(-APRON, world.h + APRON)),
			"kind": kind, "col": col, "angle": rng.randf() * PI})

	for y in range(-APRON, world.h + APRON):
		for x in range(-APRON, world.w + APRON):
			var c := Vector2i(x, y)
			if _hidden(c):
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


# --- Baking: flat ground ----------------------------------------------------

func _emit_terrain(c: Vector2i, mb: Art.MB) -> void:
	var z := _zc(c)
	var o := Vector2(c)
	var fade := _fade(c)
	for piece in _ground.get(c, []):
		mb.fan_shaded(piece[0], piece[1])
	if not _busy(c):
		Art.field_detail(mb, o, ground_z, _fields[_cell_field[c]], fade)

	var river: Array = _river_dirs.get(c, [])
	if _cont.has(c) and _cont[c][0] == "river":
		river = _cont[c][1]
	if not river.is_empty():
		_stroke(mb, c, river, 0.36, Art.hazed(Art.RIVER_BANK, fade), true, true)
		_stroke(mb, c, river, 0.29, Art.hazed(Art.RIVER_EDGE, fade), true, true)
		_stroke(mb, c, river, 0.25, Art.hazed(Art.RIVER, fade), true, true)
		if fade == 0.0 and Art.rnd(c.x, c.y, 9) > 0.6:
			Art.stone(mb, _node(c, true) + Vector2(0.08, 0.1), z)


# A cell with a line or building on it, where field details and hedges stop.
func _busy(c: Vector2i) -> bool:
	if world.in_bounds(c):
		return world.adj.has(c) or _river_dirs.has(c) or world.building(c) != B.NONE
	return _cont.has(c)


# --- Baking: canals, paths and roads ----------------------------------------

## Ribbon along the curve p0 -> pc -> p1 (cell coordinates), between lateral
## offsets o0..o1 measured to the left of travel. z is given at each end and
## at the middle.
func _band(mb: Art.MB, p0: Vector2, pc: Vector2, p1: Vector2, o0: float, o1: float,
		z0: float, zm: float, z1: float, col: Color, drape := false) -> void:
	# Overlap the neighbouring cell's part by a hair so no crack shows at the join.
	if p0.distance_to(pc) > 0.001 and p1.distance_to(pc) > 0.001:
		p0 += (p0 - pc).normalized() * 0.02
		p1 += (p1 - pc).normalized() * 0.02
	var straight := ((p0 + p1) * 0.5).distance_to(pc) < 0.001
	var steps := 2 if straight else 8
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
		var a := Art.iso(pos + n * o0, ground_z(pos + n * o0) + 0.6 if drape else z)
		var b := Art.iso(pos + n * o1, ground_z(pos + n * o1) + 0.6 if drape else z)
		if i > 0:
			mb.quad(pa, a, b, pb, col)
		pa = a
		pb = b


func _mid_z(c: Vector2i, d: Vector2, ramp: bool) -> float:
	var n := c + Vector2i(d)
	if ramp and _in_range(n):
		return (_zc(c) + _zc(n)) * 0.5
	return _zc(c)


# Where the lines through a cell meet. Rivers wander on their own course.
func _node(c: Vector2i, river := false) -> Vector2:
	if river:
		if _river_dirs.has(c):
			return Vector2(c) + Vector2(0.3 + 0.4 * Art.rnd(c.x, c.y, 301), 0.3 + 0.4 * Art.rnd(c.x, c.y, 302))
		return Vector2(c) + Vector2(0.5, 0.5)
	return world.node(c) if world.inside(c) else Vector2(c) + Vector2(0.5, 0.5)


# Where the line from cell `c` towards its neighbour in direction `d` leaves
# the cell. Each cell draws its own part of a line up to this point.
func _join(c: Vector2i, d: Vector2i, river := false) -> Vector2:
	var a := _node(c, river)
	var b := _node(c + d, river)
	var corner := Vector2(c) + Vector2(1.0 if d.x > 0 else 0.0, 1.0 if d.y > 0 else 0.0)
	var axis := Vector2(d)
	var span := (b - a).dot(axis)
	if absf(span) < 0.0001:
		return a
	return a.lerp(b, clampf((corner - a).dot(axis) / span, 0.0, 1.0))


## Symmetric ribbon of half-width `hw` joining every direction in `dirs`
## through the cell's node. `ramp` lets it climb between levels. With `flags`
## (one per direction), a stretch between two flagged directions uses `alt`.
func _stroke(mb: Art.MB, c: Vector2i, dirs: Array, hw: float, col: Color, ramp: bool,
		river := false, flags := [], alt := Color.WHITE) -> void:
	var node := _node(c, river)
	var z := _zc(c)
	if dirs.size() <= 1:
		var tone := alt if (not flags.is_empty() and flags[0]) else col
		var zn := ground_z(node) + 0.6 if ramp else z
		mb.disc(Art.iso(node, zn), hw * 1.414 * HW, hw * 1.414 * HH, tone, 18)
		if dirs.size() == 1:
			var d: Vector2 = dirs[0]
			var zm := _mid_z(c, d, ramp)
			var j := _join(c, Vector2i(d), river)
			_band(mb, node, (node + j) * 0.5, j, -hw, hw, z, (z + zm) * 0.5, zm, tone, ramp)
		return
	for i in dirs.size():
		for k in range(i + 1, dirs.size()):
			var a: Vector2 = dirs[i]
			var b: Vector2 = dirs[k]
			var tone := alt if (not flags.is_empty() and flags[i] and flags[k]) else col
			_band(mb, _join(c, Vector2i(a), river), node, _join(c, Vector2i(b), river), -hw, hw,
				_mid_z(c, a, ramp), z, _mid_z(c, b, ramp), tone, ramp)


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
	if not world.in_bounds(c):
		_emit_continuation(c, mb)
		return
	if not world.adj.has(c):
		return
	var z := _zc(c)
	var node := _node(c)

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

	var canal := _dirs(c, [L.CANAL])

	# Silted old canal: the brick edging still shows through mud and weeds.
	# Where it meets working canal, the working canal is drawn over it.
	var old := _dirs(c, [L.DERELICT])
	if not old.is_empty() and canal.is_empty():
		_stroke(mb, c, old, CANAL_W + 0.09, BRICK_MOSSY, false)
		_stroke(mb, c, old, CANAL_W + 0.035, Art.MUD, false)
		_stroke(mb, c, old, 0.12, Art.MURK, false)
		if Art.rnd(c.x, c.y, 17) > 0.5:
			Art.weeds(mb, node + Vector2(0.06, -0.04), z)

	if canal.is_empty():
		return
	# Old canal (the map's own, or restored) keeps its Victorian brick edge and
	# cinder towpath; newly dug cut has pale stone and fresh gravel.
	var aged := []
	for d: Vector2 in canal:
		aged.append(world.is_old(c, c + Vector2i(d)))
	var portal := _portal_dir(c)
	if portal != Vector2i.ZERO:
		canal.append(Vector2(portal))
		aged.append(true)

	# Towpath on one bank, on the same side all the way along.
	var from := Vector2(_tp_in.get(c, Vector2i.ZERO))
	var from_aged := true
	var outs := []
	var outs_aged := []
	for i in canal.size():
		if canal[i] == from:
			from_aged = aged[i]
		else:
			outs.append(canal[i])
			outs_aged.append(aged[i])
	for layer in [[0.27, 0.45, Art.PATH_EDGE, CINDER_EDGE], [0.27, 0.42, Art.PATH, CINDER]]:
		if from == Vector2.ZERO:
			for i in outs.size():
				var j := _join(c, Vector2i(outs[i]))
				_band(mb, node, (node + j) * 0.5, j, layer[0], layer[1], z, z, z, layer[3] if outs_aged[i] else layer[2])
		elif outs.is_empty():
			var j := _join(c, Vector2i(from))
			_band(mb, j, (node + j) * 0.5, node, layer[0], layer[1], z, z, z, layer[3] if from_aged else layer[2])
		else:
			for i in outs.size():
				_band(mb, _join(c, Vector2i(from)), node, _join(c, Vector2i(outs[i])), layer[0], layer[1], z, z, z,
					layer[3] if (from_aged and outs_aged[i]) else layer[2])

	_stroke(mb, c, canal, CANAL_W + 0.09, STONE_NEW, false, false, aged, BRICK_OLD)
	_stroke(mb, c, canal, CANAL_W + 0.05, STONE_NEW.darkened(0.08), false, false, aged, Art.COPING)
	_stroke(mb, c, canal, CANAL_W + 0.03, Art.WATER_EDGE, false)
	_stroke(mb, c, canal, CANAL_W, Art.WATER, false)
	if Art.rnd(c.x, c.y, 44) > 0.75 and canal.size() == 2 and not world.is_bridge(c):
		Art.lilies(mb, node, z, c.x + c.y * 3)


# Canals and roads carrying on into the distance, hazed like the land.
func _emit_continuation(c: Vector2i, mb: Art.MB) -> void:
	if not _cont.has(c):
		return
	var kind: String = _cont[c][0]
	var dirs: Array = _cont[c][1]
	var fade := _fade(c)
	var z := _zc(c)
	var node := _node(c)
	match kind:
		"road":
			_stroke(mb, c, dirs, 0.175, Art.hazed(Art.VERGE, fade), true)
			_stroke(mb, c, dirs, 0.135, Art.hazed(Art.ROAD, fade), true)
		"canal":
			# Towpath on the same bank as the map's side of the canal.
			var j0 := _join(c, Vector2i(dirs[1]))
			var j1 := _join(c, Vector2i(dirs[0]))
			_band(mb, j0, node, j1, 0.27, 0.45, z, z, z, Art.hazed(CINDER_EDGE, fade))
			_band(mb, j0, node, j1, 0.27, 0.42, z, z, z, Art.hazed(CINDER, fade))
			_stroke(mb, c, dirs, CANAL_W + 0.09, Art.hazed(BRICK_OLD, fade), false)
			_stroke(mb, c, dirs, CANAL_W + 0.05, Art.hazed(Art.COPING, fade), false)
			_stroke(mb, c, dirs, CANAL_W + 0.03, Art.hazed(Art.WATER_EDGE, fade), false)
			_stroke(mb, c, dirs, CANAL_W, Art.hazed(Art.WATER, fade), false)


# --- Baking: standing things ------------------------------------------------

# Queues a sprite with its anchor on the ground at `p` (cell coordinates).
func _put(sprites: Array, name: String, p: Vector2, z: float, fade := 0.0) -> void:
	z = ground_z(p)
	if Sprites.has(name):
		var tint := Color.WHITE.lerp(Art.MIST, fade)
		tint.a = 1.0 - fade * 0.25
		sprites.append([Sprites.texture(name), Sprites.rect(name, Art.iso(p, z)), p.x + p.y, tint])


func _emit_standing(c: Vector2i, mb: Art.MB, sprites: Array, smoke: Array) -> void:
	var z := _zc(c)
	var o := Vector2(c)
	var centre := o + Vector2(0.5, 0.5)
	var seed := c.x * 92821 + c.y * 68917
	var fade := _fade(c)
	var mine := []

	if not _busy(c):
		for seg in _hedges[c]:
			var za := ground_z(seg[0])
			var zb := ground_z(seg[1])
			if seg[2]:
				Art.stone_wall(mb, seg[0], seg[1], za, zb, fade)
			else:
				Art.hedge(mb, seg[0], seg[1], za, zb, fade)
	if _river_dirs.has(c) and Art.rnd(c.x, c.y, 8) > 0.4:
		Art.reeds(mb, _node(c, true) + Vector2(-0.2, -0.18), z)

	if not world.in_bounds(c):
		_emit_scenery(c, mine, fade)
	else:
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
					_emit_field_life(c, mine, 0.0)
	mine.sort_custom(func(a, b): return a[2] < b[2])
	sprites.append_array(mine)


# Animals, bales and the odd tree in the fields.
func _emit_field_life(c: Vector2i, mine: Array, fade: float) -> void:
	var o := Vector2(c)
	var z := _zc(c)
	var seed := c.x * 92821 + c.y * 68917
	var field: Dictionary = _fields[_cell_field[c]]
	var roll := Art.rnd(c.x, c.y, 99)
	if field.kind == 0 and roll > 0.84:
		var animal := "cow" if roll > 0.94 else "sheep"
		for j in 1 + int(Art.rnd(seed, 2, 2) > 0.4):
			_put(mine, Sprites.pick(animal, seed + j), o + Vector2(0.3 + 0.4 * j, 0.35 + 0.3 * Art.rnd(seed, j, 4)), z, fade)
	elif field.kind == 3 and roll > 0.65:
		_put(mine, "haybale_a", o + Vector2(0.3 + 0.4 * Art.rnd(c.x, c.y, 5), 0.3 + 0.4 * Art.rnd(c.x, c.y, 6)), z, fade)
	elif roll < 0.03:
		_put(mine, Sprites.pick("oak", seed), o + Vector2(0.5, 0.5), z, fade)
	for seg in _hedges[c]:
		if not seg[2] and Art.rnd(c.x, c.y, 77) > 0.8:
			_put(mine, "oak_d", (seg[0] as Vector2).lerp(seg[1], 0.5), z, fade)
			break


# The countryside beyond the map: woods, fields and the odd distant farm.
func _emit_scenery(c: Vector2i, mine: Array, fade: float) -> void:
	if _cont.has(c):
		return
	var o := Vector2(c)
	var z := _zc(c)
	var seed := c.x * 92821 + c.y * 68917
	var woods := sin(c.x * 0.55 + world.w) * cos(c.y * 0.45 + world.h * 0.3)
	if woods > 0.62:
		for j in 2 + int(Art.rnd(seed, 0, 60) > 0.5):
			var p := o + Vector2(0.2 + 0.6 * Art.rnd(seed, j, 61), 0.2 + 0.6 * Art.rnd(seed, j, 71))
			_put(mine, TREES[int(Art.rnd(seed, j, 81) * TREES.size())], p, z, fade)
	elif Art.rnd(c.x, c.y, 404) > 0.985:
		_put(mine, Sprites.pick(["cottage", "farm", "church", "windmill"][int(Art.rnd(c.x, c.y, 405) * 4.0)], seed),
			o + Vector2(0.5, 0.5), z, fade)
	elif Art.rnd(c.x, c.y, 406) > 0.45:
		_emit_field_life(c, mine, fade)


func _label_anchor(p: Dictionary) -> Vector2:
	var d := Vector2(p.dir)
	var side := Vector2(-d.y, d.x) * 0.42
	if side.x + side.y > 0.0:
		side = -side
	return Vector2(p.cell) + Vector2(0.5, 0.5) + side + d * 0.2


# Things that must be drawn over a passing boat: bridges and lock gates.
func _emit_over(c: Vector2i, mb: Art.MB) -> void:
	var z := _zc(c)
	var land := world.link_dirs(c, [L.PATH, L.ROAD])
	var over_river := _river_dirs.has(c) and not land.is_empty()
	if world.is_bridge(c) or over_river:
		var p0 := _join(c, land[0])
		var p1 := _join(c, land[1]) if land.size() > 1 else _node(c) * 2.0 - p0
		var is_road := not world.link_dirs(c, [L.ROAD]).is_empty()
		var plain := "wood" if (over_river and not world.has_water(c)) else "brick"
		Art.bridge(mb, p0, p1, z, is_road, world.styles.get(c, plain))
	for pair in world.locks():
		if pair[1] == c:
			# The chamber is cut into the upper level, so it is drawn with this cell.
			var uphill := (_node(c) - _node(pair[0])).normalized()
			Art.lock(mb, _join(c, pair[0] - c), uphill, _zc(pair[0]), z, world.styles.get(c, "stone"))


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if world == null:
		return
	var rows := _rows()
	var slots := {}
	for boat in _boats:
		var st := _boat_state(boat)
		var c: Vector2i = st.cell
		var o: Vector2i = st.other
		var slot := clampi(maxi(_ri(c), _ri(o)) + 1, 0, rows - 1)
		if not slots.has(slot):
			slots[slot] = []
		slots[slot].append(st)

	# Pass 1: everything flat.
	for r in rows:
		if _flat_terrain[r] != null:
			draw_mesh(_flat_terrain[r], null)
	for r in rows:
		if _flat_links[r] != null:
			draw_mesh(_flat_links[r], null)
		for c: Vector2i in (_water[r] if _water[r] != null else []):
			_glint(c)
	for seg in _edge_lines:
		var pts := PackedVector2Array()
		for k in 5:
			var q: Vector2 = (seg[0] as Vector2).lerp(seg[1], k / 4.0)
			pts.append(Art.iso(q, ground_z(q) + 0.5))
		draw_polyline(pts, Color(1, 1, 1, 0.7), 2.0, true)

	# Pass 2: standing things, back to front.
	for r in rows:
		if _raised[r] != null:
			draw_mesh(_raised[r], null)
		for st in slots.get(r, []):
			_draw_boat(st)
			for c: Vector2i in st.near:
				if _over.has(c):
					draw_mesh(_over[c], null)
		if _standing[r] != null:
			draw_mesh(_standing[r], null)
		for item in (_sprites[r] if _sprites[r] != null else []):
			draw_texture_rect(item[0], item[1], false, item[3])
		for c: Vector2i in (_over_cells[r] if _over_cells[r] != null else []):
			draw_mesh(_over[c], null)
		for p: Vector2 in (_smoke[r] if _smoke[r] != null else []):
			for j in 3:
				var f := fmod(_t * 0.3 + j / 3.0 + p.x * 0.01, 1.0)
				draw_circle(p + Vector2(sin(f * 5.0 + j) * 3.0 + f * 5.0, -f * 22.0), 2.2 + f * 3.5,
					Color(1, 1, 1, 0.5 * (1.0 - f)))


func _glint(c: Vector2i) -> void:
	var hsh := Art.rnd(c.x, c.y, 7)
	var ph := _t * 0.6 + hsh * TAU
	var a := 0.16 + 0.16 * sin(ph * 1.7)
	var p := Art.iso(_node(c) + Vector2(0.07 * sin(ph), 0.07 * cos(ph * 0.8)), _zc(c))
	draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), Color(1, 1, 1, a), 1.2)


func _draw_boat(st: Dictionary) -> void:
	var pos: Vector3 = st.pos
	var dir: Vector2 = st.dir
	var alpha: float = st.alpha
	if alpha <= 0.01:
		return
	var flat := Vector2(pos.x, pos.y)
	pos.z += sin(_t * 2.5 + st.look) * 0.3 - 1.0
	var fade := maxf(_fade(st.cell), 0.0)
	# Wake trailing from the stern.
	for j in 3:
		draw_circle(Art.iso(flat - dir * (0.6 + j * 0.12), pos.z + 1.0), 3.6 - j * 0.8, Color(1, 1, 1, (0.26 - j * 0.07) * alpha))
	# The sprite set has the boat drawn from a ring of headings; use the nearest.
	var heading := int(round(atan2(dir.y, dir.x) / TAU * Sprites.boat_directions))
	var name := Sprites.boat(st.look, heading)
	if Sprites.has(name):
		var tint := Color.WHITE.lerp(Art.MIST, fade * 0.8)
		tint.a = alpha
		draw_texture_rect(Sprites.texture(name), Sprites.rect(name, Art.iso(flat, pos.z)), false, tint)


func _plaque(ci: CanvasItem, pos: Vector2, text: String, size: int, bg: Color, ink: Color) -> void:
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var rect := Rect2(pos + Vector2(-extent.x * 0.5 - 6, -size * 0.5 - 4), Vector2(extent.x + 12, size + 8))
	ci.draw_rect(rect.grow(1.5), ink)
	ci.draw_rect(rect, bg)
	ci.draw_string(_font, rect.position + Vector2(6, size + 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


func _draw_overlays(ci: CanvasItem) -> void:
	if show_derelict:
		# Silted canal glows so it is easy to find and tap.
		var a := 0.45 + 0.25 * sin(_t * 4.0)
		for k in world.links:
			if world.links[k] == L.DERELICT:
				var cells := world.key_cells(k)
				ci.draw_line(Art.iso(_node(cells[0]), _zc(cells[0]) + 1.0), Art.iso(_node(cells[1]), _zc(cells[1]) + 1.0),
					Color(1.0, 0.86, 0.45, a), 5.0, true)
	if show_labels:
		for p in world.portals:
			_plaque(ci, Art.iso(_label_anchor(p), _zc(p.cell) + 30.0), p.name, 12, Color("f6ecd4"), Color("4a3b2e"))
		for p in world.places:
			var top := cell_center(p.cell) + Vector2(0, -minf(_place_top.get(p.cell, 34.0), 62.0) - 2.0)
			var extent := _font.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			var at := top + Vector2(-extent.x * 0.5, 0)
			ci.draw_string_outline(_font, at, p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 6, Color(0.98, 0.95, 0.86))
			ci.draw_string(_font, at, p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("33281f"))
			# Badge: what the place still needs, or a tick once it has it.
			var badge := top + Vector2(0, -20.0 + (0.0 if p.ok else sin(_t * 3.0 + p.cell.x) * 2.0))
			ci.draw_circle(badge, 9.5, Color("fbf3df"))
			ci.draw_circle(badge, 8.0, Color("6fa35a") if p.ok else Color("e0863a"))
			if p.ok:
				ci.draw_polyline(PackedVector2Array([badge + Vector2(-4, 0), badge + Vector2(-1, 3), badge + Vector2(4, -3)]), Color.WHITE, 2.0)
			elif p.need == L.ROAD:
				ci.draw_rect(Rect2(badge + Vector2(-4.5, -2.5), Vector2(9, 5)), Color.WHITE)
				ci.draw_circle(badge + Vector2(-2.5, 3), 1.6, Color.WHITE)
				ci.draw_circle(badge + Vector2(2.5, 3), 1.6, Color.WHITE)
			else:
				ci.draw_circle(badge + Vector2(0, -3.2), 1.9, Color.WHITE)
				ci.draw_line(badge + Vector2(0, -1), badge + Vector2(0, 2.5), Color.WHITE, 2.0)
				ci.draw_line(badge + Vector2(0, 2), badge + Vector2(-2.5, 5), Color.WHITE, 1.6)
				ci.draw_line(badge + Vector2(0, 2), badge + Vector2(2.5, 5), Color.WHITE, 1.6)

	if world.in_bounds(hover):
		_ring(ci, hover, 0.46, Color(1, 1, 1, 0.9) if hover_ok else Color(0.85, 0.3, 0.25, 0.9), 2.5)
	var alive := []
	for puff in _puffs:
		var age: float = (_t - puff.t) / 0.4
		if age < 1.0:
			alive.append(puff)
			_ring(ci, puff.c, 0.35 + 0.4 * age, Color(1, 1, 1, 0.8 * (1.0 - age)), 2.5)
	_puffs = alive


func _ring(ci: CanvasItem, c: Vector2i, r: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		var q := Vector2(c) + Vector2(0.5 + cos(a) * r, 0.5 + sin(a) * r)
		pts.append(Art.iso(q, ground_z(q) + 1.0))
	ci.draw_polyline(pts, col, width, true)
