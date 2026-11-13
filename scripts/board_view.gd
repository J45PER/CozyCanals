extends Node2D
## Draws the board in isometric projection. All art is drawn in code with
## flat-shaded polygons, so the project needs no image assets.
##
## The rules run on a grid, but the drawing hides it: waterways and lanes are
## curved strokes, the land is a patchwork of irregular fields with hedgerows,
## and towpaths hug one bank of the canal.

signal boat_arrived

const Board := preload("res://scripts/board.gd")
const K := Board.K

const HW := 48.0      # half tile width on screen
const HH := 24.0      # half tile height on screen
const HSTEP := 22.0   # screen pixels per terrain level
const BASE := 18.0    # thickness of the slab under the board

const GRASS_DARK := Color("86b868")
const HEDGE := Color("4f8443")
const HEDGE_TOP := Color("6da257")
const EARTH_L := Color("8f6b4a")
const EARTH_R := Color("ab835b")
const WATER := Color("62b6c9")
const WATER_WALL := Color("3d8799")
const RIVER := Color("8fd0d8")
const RIVER_WALL := Color("6fb7c2")
const RIVER_BANK := Color("cfe0b4")
const MURK := Color("8d9665")
const MURK_WALL := Color("6c6a47")
const MUD := Color("a8946c")
const STONE := Color("d3ccbb")
const PATH := Color("e6d2a2")
const LANE := Color("d6c8ae")
const LANE_VERGE := Color("b9ad8e")
const BRICK := Color("b9684c")
const WOOD := Color("4a3b2e")
const SHADOW := Color(0.1, 0.25, 0.1, 0.18)

const CANAL_W := 0.2          # half width of the channel, in tiles
const TOWPATH_IN := 0.25      # towpath band, measured from the centre line
const TOWPATH_OUT := 0.37

## Field types: pasture, meadow, crop, hay.
const FIELD_COLOURS := [Color("a6d285"), Color("b5db8e"), Color("e2d588"), Color("c3dc86")]
const BOAT_COLOURS := [
	[Color("2f6b55"), Color("b8483c")],
	[Color("34507a"), Color("d9a441")],
	[Color("8a3b3b"), Color("2f5d48")],
	[Color("444b52"), Color("b8483c")],
]

var board: Board
var hover := Vector2i(-1, -1)
var hover_ok := true

var _t := 0.0
var _ox := 0.0
var _oy := 0.0
var _oz := 0.0
var _font: Font
var _puffs: Array = []
var _boats: Array = []

var _fields: Array = []       # [{seed: Vector2, kind: int, col: Color}]
var _field_polys := {}        # cell -> [[PackedVector2Array, field index], ...]
var _hedges := {}             # cell -> [[Vector2, Vector2], ...]
var _cell_field := {}         # cell -> field index at the cell centre
var _tp_in := {}              # cell -> direction the towpath arrives from


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_board(b: Board) -> void:
	board = b
	_boats.clear()
	_puffs.clear()
	hover = Vector2i(-1, -1)
	_build_fields()
	refresh()


## Call after the board changes.
func refresh() -> void:
	_orient_towpaths()
	queue_redraw()


func add_puff(c: Vector2i) -> void:
	_puffs.append({"c": c, "t": _t})


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
	_boats.append({"cells": cells, "s": 0.0, "look": randi() % BOAT_COLOURS.size()})


func _process(delta: float) -> void:
	_t += delta
	var alive := []
	for boat in _boats:
		var cells: Array[Vector2i] = boat.cells
		var i := clampi(int(floor(boat.s)), 0, cells.size() - 1)
		boat.s += (0.4 if board.kind(cells[i]) == K.LOCK else 1.0) * delta
		if boat.s >= cells.size():
			boat_arrived.emit()
		else:
			alive.append(boat)
	_boats = alive
	queue_redraw()


# Where a boat is: {pos: Vector3 (tile x, tile y, screen z), dir, alpha, cell, other}.
func _boat_state(boat: Dictionary) -> Dictionary:
	var cells: Array[Vector2i] = boat.cells
	var n := cells.size()
	var i := clampi(int(floor(boat.s)), 0, n - 1)
	var f: float = boat.s - i
	var cell := cells[i]
	var a := Vector2(cells[i - 1] - cell) if i > 0 else Vector2(cell - cells[1])
	var b := Vector2(cells[i + 1] - cell) if i < n - 1 else Vector2(cell - cells[n - 2])
	var centre := Vector2(cell) + Vector2(0.5, 0.5)
	var p: Vector2
	var dir: Vector2
	if is_zero_approx(a.dot(b)):
		var th := f * PI * 0.5
		p = centre + 0.5 * (a + b) - 0.5 * (b * cos(th) + a * sin(th))
		dir = (b * sin(th) - a * cos(th)).normalized()
	else:
		p = centre + a.lerp(b, f) * 0.5
		dir = b
	# Keep to the right so boats can pass each other.
	p += Vector2(-dir.y, dir.x) * 0.085

	var lv := func(j: int) -> float: return float(board.height(cells[clampi(j, 1, n - 2)]))
	var z: float = lv.call(i)
	if f < 0.3:
		z = lerpf((lv.call(i - 1) + z) * 0.5, z, f / 0.3)
	elif f > 0.7:
		z = lerpf(z, (lv.call(i + 1) + z) * 0.5, (f - 0.7) / 0.3)

	var alpha := 1.0
	if i == 0:
		alpha = smoothstep(0.2, 0.9, f)
	elif i == n - 1:
		alpha = 1.0 - smoothstep(0.1, 0.8, f)
	var other := cells[i - 1] if (f < 0.5 and i > 0) else cells[mini(i + 1, n - 1)]
	return {"pos": Vector3(p.x, p.y, z * HSTEP), "dir": dir, "alpha": alpha, "cell": cell, "other": other}


# --- Projection helpers -----------------------------------------------------

static func iso(fx: float, fy: float, z: float) -> Vector2:
	return Vector2((fx - fy) * HW, (fx + fy) * HH - z)


func cell_center(c: Vector2i) -> Vector2:
	return iso(c.x + 0.5, c.y + 0.5, board.height(c) * HSTEP)


## Board-local position -> cell, taking terrain height into account.
func cell_at(p: Vector2) -> Vector2i:
	for lvl in range(board.max_height, -1, -1):
		var a := p.x / HW
		var b := (p.y + lvl * HSTEP) / HH
		var c := Vector2i(floori((a + b) * 0.5), floori((b - a) * 0.5))
		if board.in_bounds(c) and board.height(c) == lvl:
			return c
	return Vector2i(-1, -1)


func bounds() -> Rect2:
	var top := -board.max_height * HSTEP - 40.0
	return Rect2(-board.h * HW, top, (board.w + board.h) * HW, (board.w + board.h) * HH + BASE - top)


func _p(u: float, v: float, dz := 0.0) -> Vector2:
	return iso(_ox + u, _oy + v, _oz + dz)


# Point in tile space where `along` follows the canal axis.
func _pa(along: float, across: float, dz: float, axis_x: bool) -> Vector2:
	return _p(along, across, dz) if axis_x else _p(across, along, dz)


func _quad(x0: float, y0: float, x1: float, y1: float, col: Color, dz := 0.0) -> void:
	draw_colored_polygon(PackedVector2Array([_p(x0, y0, dz), _p(x1, y0, dz), _p(x1, y1, dz), _p(x0, y1, dz)]), col)


func _poly3(pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for q in pts:
		out.append(_p(q[0], q[1], q[2]))
	draw_colored_polygon(out, col)


func _face_y(x0: float, x1: float, y: float, z0: float, z1: float, col: Color) -> void:
	_poly3([[x0, y, z0], [x1, y, z0], [x1, y, z1], [x0, y, z1]], col)


func _face_x(x: float, y0: float, y1: float, z0: float, z1: float, col: Color) -> void:
	_poly3([[x, y0, z0], [x, y1, z0], [x, y1, z1], [x, y0, z1]], col)


func _ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


static func _hash(x: int, y: int, seed := 0) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


# --- Curved strokes ---------------------------------------------------------
# Waterways, lanes and towpaths are drawn as bands that enter a tile through
# the middle of one edge and leave through another: straight across, or
# round a quarter circle when they turn. Directions are unit vectors towards
# the neighbouring tile; ZERO means the band stops at the tile centre.

## Band between lateral offsets o0..o1, measured to the left of travel a -> b.
func _piece(a: Vector2, b: Vector2, o0: float, o1: float, col: Color, shift := 0.0) -> void:
	var c := Vector2(0.5 + shift, 0.5 + shift)
	# Shifted bands overlap the next tile a little so no seam shows between them.
	var ext := shift * 2.0
	var pts := PackedVector2Array()
	if a != Vector2.ZERO and b != Vector2.ZERO and is_zero_approx(a.dot(b)):
		var side := Vector2(-a.y, a.x).dot(b)   # +1 when "left" is the inside of the bend
		var corner := c + 0.5 * (a + b)
		var steps := 8
		var ring := []
		for o: float in [o0, o1]:
			var r := 0.5 - o * side
			var line := [corner - r * b + a * ext]
			for k in steps + 1:
				var th := PI * 0.5 * k / steps
				line.append(corner - r * (b * cos(th) + a * sin(th)))
			line.append(corner - r * a + b * ext)
			if o == o1:
				line.reverse()
			ring.append_array(line)
		for q: Vector2 in ring:
			pts.append(_p(q.x, q.y))
	else:
		var t := b if b != Vector2.ZERO else -a
		var n := Vector2(t.y, -t.x)
		var from := c + a * (0.5 + ext)
		var to := c + b * (0.5 + ext)
		for q: Vector2 in [from + n * o0, to + n * o0, to + n * o1, from + n * o1]:
			pts.append(_p(q.x, q.y))
	draw_colored_polygon(pts, col)


func _disc(r: float, col: Color, shift := 0.0) -> void:
	var pts := PackedVector2Array()
	for k in 12:
		var a := TAU * k / 12.0
		pts.append(_p(0.5 + shift + cos(a) * r, 0.5 + shift + sin(a) * r))
	draw_colored_polygon(pts, col)


## Symmetric band of half-width `hw` joining every connected edge.
func _stroke(conns: Array, hw: float, col: Color, shift := 0.0) -> void:
	if conns.size() <= 1:
		_disc(hw, col, shift)
		if conns.size() == 1:
			_piece(conns[0], Vector2.ZERO, -hw, hw, col, shift)
		return
	for i in conns.size():
		for j in range(i + 1, conns.size()):
			_piece(conns[i], conns[j], -hw, hw, col, shift)


func _water(conns: Array, hw: float, col: Color, wall: Color) -> void:
	_stroke(conns, hw, wall)
	_stroke(conns, hw - 0.02, col, 0.03)


func _water_conns(c: Vector2i) -> Array:
	var k := board.kind(c)
	var out := []
	for d in Board.DIRS:
		var n := c + d
		if Board.is_water(board.kind(n)) or (k == K.RIVER and not board.in_bounds(n)) \
				or (k == K.PORTAL and d == board.portal_dir(c)):
			out.append(Vector2(d))
	return out


func _lane_conns(c: Vector2i) -> Array:
	var out := []
	for d in Board.DIRS:
		var n := c + d
		var nk := board.kind(n)
		if nk == K.LANE or (nk == K.BRIDGE and board.was_lane(n)) or not board.in_bounds(n):
			out.append(Vector2(d))
	return out


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
# and cuts each field to the tiles it covers, so fields ignore the grid.
func _build_fields() -> void:
	_fields.clear()
	_field_polys.clear()
	_hedges.clear()
	_cell_field.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(board.title)
	var count := maxi(6, board.w * board.h / 10)
	for i in count:
		var pick := rng.randf()
		var kind := 0 if pick < 0.45 else (1 if pick < 0.7 else (2 if pick < 0.83 else 3))
		var col: Color = FIELD_COLOURS[kind]
		col = col.lightened(rng.randf_range(0.0, 0.08)).darkened(rng.randf_range(0.0, 0.05))
		_fields.append({
			"seed": Vector2(rng.randf_range(0, board.w), rng.randf_range(0, board.h)),
			"kind": kind, "col": col})

	for y in board.h:
		for x in board.w:
			var c := Vector2i(x, y)
			if not board.in_bounds(c):
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
				# Edges that are not on the tile border are field boundaries.
				for e in poly.size():
					var a := poly[e]
					var b := poly[(e + 1) % poly.size()]
					var on_x := is_equal_approx(a.x, b.x) and is_equal_approx(a.x, roundf(a.x))
					var on_y := is_equal_approx(a.y, b.y) and is_equal_approx(a.y, roundf(a.y))
					if not on_x and not on_y and a.distance_to(b) > 0.05 and i < _other_side(near, i, (a + b) * 0.5):
						hedges.append([a, b])
			_field_polys[c] = polys
			_hedges[c] = hedges


# Index of the nearest field seed to `p` other than `skip`.
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
	for i in board.portals.size():
		roots.append([board.portals[i], board.portal_dirs[i]])
	var ends := []
	var rest := []
	for y in board.h:
		for x in board.w:
			var c := Vector2i(x, y)
			if Board.is_navigable(board.kind(c)):
				(ends if _nav_dirs(c).size() == 1 else rest).append([c, Vector2i.ZERO])
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
			for d in _nav_dirs(c):
				if not _tp_in.has(c + d):
					_tp_in[c + d] = -d
					queue.append(c + d)


func _nav_dirs(c: Vector2i) -> Array:
	var out := []
	for d in Board.DIRS:
		if Board.is_navigable(board.kind(c + d)):
			out.append(d)
	return out


func _draw_towpath(c: Vector2i) -> void:
	var from: Vector2i = _tp_in.get(c, Vector2i.ZERO)
	var outs := []
	for d in _nav_dirs(c):
		if d != from:
			outs.append(d)
	if outs.is_empty():
		_piece(Vector2(from), Vector2.ZERO, TOWPATH_IN, TOWPATH_OUT, PATH)
	for d in outs:
		_piece(Vector2(from), Vector2(d), TOWPATH_IN, TOWPATH_OUT, PATH)


# --- Main draw --------------------------------------------------------------

func _draw() -> void:
	if board == null:
		return
	var last := board.w + board.h
	var slots := {}
	for boat in _boats:
		var st := _boat_state(boat)
		st["look"] = boat.look
		var c: Vector2i = st.cell
		var o: Vector2i = st.other
		st["behind"] = c if c.x + c.y < o.x + o.y else o
		var slot := clampi(maxi(c.x + c.y, o.x + o.y), 0, last)
		if not slots.has(slot):
			slots[slot] = []
		slots[slot].append(st)

	for d in last + 1:
		var x0 := maxi(0, d - board.h + 1)
		var x1 := mini(board.w, d + 1)
		for x in range(x0, x1):
			_ground(Vector2i(x, d - x))
		for st in slots.get(d, []):
			_draw_boat(st)
			_objects(st.behind)
		for x in range(x0, x1):
			_objects(Vector2i(x, d - x))

	_draw_markers()


func _nz(c: Vector2i) -> float:
	return board.height(c) * HSTEP if board.in_bounds(c) else -BASE


func _shimmer(c: Vector2i) -> void:
	var hsh := _hash(c.x, c.y, 7)
	for j in 2:
		var ph := _t * 0.7 + hsh * TAU + j * 2.4
		var u := 0.5 + 0.08 * sin(ph)
		var v := 0.5 + 0.08 * cos(ph * 0.8 + j)
		var a := 0.25 + 0.2 * sin(ph * 1.7)
		draw_line(_p(u - 0.05, v + 0.05, 0.0), _p(u + 0.05, v - 0.05, 0.0), Color(1, 1, 1, a), 1.5)


func _ground(c: Vector2i) -> void:
	if not board.in_bounds(c):
		return
	var k := board.kind(c)
	var z := board.height(c) * HSTEP
	_ox = c.x
	_oy = c.y
	_oz = z

	var zl := _nz(c + Vector2i(0, 1))
	if zl < z:
		_poly3([[0, 1, 0], [1, 1, 0], [1, 1, zl - z], [0, 1, zl - z]], EARTH_L)
		_poly3([[0, 1, 0], [1, 1, 0], [1, 1, -4], [0, 1, -4]], GRASS_DARK.darkened(0.12))
	var zr := _nz(c + Vector2i(1, 0))
	if zr < z:
		_poly3([[1, 0, 0], [1, 1, 0], [1, 1, zr - z], [1, 0, zr - z]], EARTH_R)
		_poly3([[1, 0, 0], [1, 1, 0], [1, 1, -4], [1, 0, -4]], GRASS_DARK)

	# Land: whichever fields cross this tile.
	var lift := 0.05 * board.height(c)
	_quad(-0.01, -0.01, 1.01, 1.01, (_fields[_cell_field[c]].col as Color).lightened(lift))
	for entry in _field_polys[c]:
		var pts := PackedVector2Array()
		for q: Vector2 in entry[0]:
			pts.append(iso(q.x, q.y, z))
		if pts.size() >= 3:
			draw_colored_polygon(pts, (_fields[entry[1]].col as Color).lightened(lift))
	if k == K.GRASS or k == K.TREE:
		for seg in _hedges[c]:
			var a := iso(seg[0].x, seg[0].y, z)
			var b := iso(seg[1].x, seg[1].y, z)
			draw_line(a, b, HEDGE, 5.0)
			draw_line(a + Vector2(0, -3), b + Vector2(0, -3), HEDGE_TOP, 4.0)

	var hsh := _hash(c.x, c.y)
	match k:
		K.GRASS:
			_meadow_details(c, hsh)
		K.RIVER:
			var conns := _water_conns(c)
			_stroke(conns, 0.3, RIVER_BANK)
			_water(conns, 0.23, RIVER, RIVER_WALL)
			if hsh > 0.4:
				_ellipse(_p(0.42 + 0.16 * hsh, 0.56), 5.0, 3.0, Color("a9a294"))
				_ellipse(_p(0.42 + 0.16 * hsh, 0.56, 1.5), 4.0, 2.2, STONE)
			_reeds(0.24 + 0.1 * hsh, 0.24)
			_shimmer(c)
		K.DERELICT:
			var conns := _water_conns(c)
			_stroke(conns, 0.25, MUD)
			_water(conns, CANAL_W, MURK, MURK_WALL)
			_ellipse(_p(0.44 + 0.12 * hsh, 0.5), 8.0, 4.0, Color("7fa35a"))
			_ellipse(_p(0.58 - 0.12 * hsh, 0.44), 5.0, 2.5, Color("6f9450"))
			_reeds(0.34, 0.36 + 0.2 * hsh)
			if hsh > 0.5:
				draw_arc(_p(0.52, 0.56, 1.0), 4.0, 0.0, TAU, 12, Color("3a3a3a"), 2.0)
		K.CANAL, K.BRIDGE, K.LOCK, K.PORTAL:
			var conns := _water_conns(c)
			_stroke(conns, CANAL_W + (0.1 if k == K.LOCK else 0.045), STONE)
			_water(conns, CANAL_W, WATER, WATER_WALL)
			_shimmer(c)
			if board.has_towpath(c):
				_draw_towpath(c)
			if k == K.PORTAL:
				_portal_mouth(c)
		K.LANE:
			var conns := _lane_conns(c)
			_stroke(conns, 0.13, LANE_VERGE)
			_stroke(conns, 0.1, LANE)
		K.COTTAGE, K.CAFE, K.PUB:
			_disc(0.42, GRASS_DARK.lightened(0.2))


func _meadow_details(c: Vector2i, hsh: float) -> void:
	match _fields[_cell_field[c]].kind:
		0:
			if hsh < 0.35:
				for j in 3:
					var u := 0.25 + 0.5 * _hash(c.x, c.y, j + 1)
					var v := 0.25 + 0.5 * _hash(c.x, c.y, j + 11)
					draw_line(_p(u, v), _p(u, v, 4.0), GRASS_DARK, 1.5)
		1:
			var cols := [Color("fff6d6"), Color("f7d86a"), Color("f2a7b8")]
			for j in 4:
				var u := 0.15 + 0.7 * _hash(c.x, c.y, j + 21)
				var v := 0.15 + 0.7 * _hash(c.x, c.y, j + 31)
				draw_circle(_p(u, v, 1.0), 1.8, cols[j % 3])
		2:
			for j in 4:
				var u := 0.15 + 0.7 * _hash(c.x, c.y, j + 41)
				var v := 0.15 + 0.7 * _hash(c.x, c.y, j + 51)
				draw_line(_p(u, v), _p(u, v, 5.0), Color("c9b45c"), 1.5)


# Where a canal leaves the map: show the cut end of the channel on the slab.
func _portal_mouth(c: Vector2i) -> void:
	var d := board.portal_dir(c)
	if d == Vector2i(1, 0):
		_face_x(1.0, 0.5 - CANAL_W, 0.5 + CANAL_W, -9.0, 0.0, WATER_WALL)
	elif d == Vector2i(0, 1):
		_face_y(0.5 - CANAL_W, 0.5 + CANAL_W, 1.0, -9.0, 0.0, WATER_WALL.darkened(0.1))


func _reeds(u: float, v: float) -> void:
	for j in 3:
		var sway := sin(_t * 1.5 + j) * 1.0
		var base := _p(u + j * 0.03, v + j * 0.02)
		draw_line(base, base + Vector2(sway, -9.0 - j), Color("5d8a48"), 1.5)


func _objects(c: Vector2i) -> void:
	if not board.in_bounds(c):
		return
	_ox = c.x
	_oy = c.y
	_oz = board.height(c) * HSTEP
	match board.kind(c):
		K.TREE: _copse(c)
		K.ROCK: _rock()
		K.LOCK: _lock_gates(_canal_axis_x(c))
		K.BRIDGE: _bridge(c)
		K.COTTAGE: _cottage()
		K.CAFE: _cafe()
		K.PUB: _pub()
		K.PORTAL: _fingerpost(c)
		K.GRASS:
			if _fields[_cell_field[c]].kind == 0 and _hash(c.x, c.y, 99) > 0.8:
				_sheep(c)


func _canal_axis_x(c: Vector2i) -> bool:
	if board.kind(c) == K.BRIDGE and board.was_lane(c):
		# The lane keeps its direction; the canal runs across it.
		var along_x := false
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
			var n := c + d
			along_x = along_x or board.kind(n) == K.LANE or not board.in_bounds(n)
		var along_y := false
		for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1)]:
			along_y = along_y or board.kind(c + d) == K.LANE
		return along_y or not along_x
	var wx := Board.is_water(board.kind(c + Vector2i(1, 0))) or Board.is_water(board.kind(c + Vector2i(-1, 0)))
	var wy := Board.is_water(board.kind(c + Vector2i(0, 1))) or Board.is_water(board.kind(c + Vector2i(0, -1)))
	return wx or not wy


func _tree(u: float, v: float, size: float, phase: float) -> void:
	var sway := sin(_t * 1.2 + phase) * 1.2
	_ellipse(_p(u + 0.05, v + 0.05), 17.0 * size, 8.0 * size, SHADOW)
	draw_line(_p(u, v), _p(u, v, 16.0 * size), Color("7a5a3c"), 4.0 * size)
	var top := _p(u, v, 26.0 * size) + Vector2(sway, 0)
	draw_circle(top + Vector2(-7, 5) * size, 11.0 * size, Color("5f9a4c"))
	draw_circle(top + Vector2(7, 4) * size, 11.0 * size, Color("6aa655"))
	draw_circle(top + Vector2(0, -5) * size, 13.0 * size, Color("78b560"))
	draw_circle(top + Vector2(-3, -9) * size, 6.0 * size, Color("8cc672"))


# A small clump of trees rather than one tree per tile.
func _copse(c: Vector2i) -> void:
	var spots := []
	for j in 2 + int(_hash(c.x, c.y, 60) > 0.45):
		spots.append(Vector3(0.2 + 0.6 * _hash(c.x, c.y, 61 + j), 0.2 + 0.6 * _hash(c.x, c.y, 71 + j),
			0.6 + 0.5 * _hash(c.x, c.y, 81 + j)))
	spots.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	for s: Vector3 in spots:
		_tree(s.x, s.y, s.z, s.x * 20.0)


func _rock() -> void:
	var p := _p(0.5, 0.55)
	_ellipse(p + Vector2(2, 3), 20.0, 8.0, SHADOW)
	var body := PackedVector2Array()
	for q: Vector2 in [Vector2(-17, 3), Vector2(-11, -13), Vector2(2, -20), Vector2(14, -9), Vector2(18, 3), Vector2(4, 8), Vector2(-8, 7)]:
		body.append(p + q)
	draw_colored_polygon(body, Color("a3a197"))
	var facet := PackedVector2Array()
	for q: Vector2 in [Vector2(-11, -13), Vector2(2, -20), Vector2(14, -9), Vector2(1, -5)]:
		facet.append(p + q)
	draw_colored_polygon(facet, Color("c4c2b8"))


func _sheep(c: Vector2i) -> void:
	var hsh := _hash(c.x, c.y, 5)
	for j in 1 + int(hsh > 0.5):
		var drift := sin(_t * 0.25 + hsh * TAU + j * 2.0) * 0.08
		var p := _p(0.35 + 0.3 * j + drift, 0.4 + 0.25 * j, 4.0)
		_ellipse(p + Vector2(1, 4), 7.0, 3.0, SHADOW)
		_ellipse(p, 6.5, 4.8, Color("fbf7ec"))
		draw_circle(p + Vector2(6.0 if j == 0 else -6.0, -1.5), 2.6, Color("3b3432"))


func _lock_gates(ax: bool) -> void:
	for along: float in [0.2, 0.8]:
		var a := _pa(along, 0.5 - CANAL_W, -2.0, ax)
		var b := _pa(along, 0.5 + CANAL_W, -2.0, ax)
		var up := Vector2(0, -9)
		draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), WOOD)
		var e0 := _pa(along, 0.1, 9.0, ax)
		var e1 := _pa(along, 0.9, 9.0, ax)
		draw_line(e0, e1, Color("2b2623"), 4.0)
		draw_line(e0, e0.lerp(e1, 0.14), Color("f6f0e2"), 4.0)
		draw_line(e1, e1.lerp(e0, 0.14), Color("f6f0e2"), 4.0)


# A humpback bridge. The deck runs across the canal.
func _bridge(c: Vector2i) -> void:
	var ax := _canal_axis_x(c)
	var lane := board.was_lane(c)
	var deck_col := LANE if lane else PATH
	var lo := 0.36 if lane else 0.4
	var hi := 1.0 - lo
	var s := [0.0, 0.2, 0.5, 0.8, 1.0] if lane else [0.1, 0.25, 0.5, 0.75, 0.9]
	var z := [0.0, 10.0, 13.0, 10.0, 0.0]
	var front := PackedVector2Array()
	for i in 5:
		front.append(_pa(hi, s[i], z[i] + 4.0, ax))
	for i in 4:
		var shade := deck_col.darkened(0.08) if i == 0 or i == 3 else deck_col
		draw_colored_polygon(PackedVector2Array([
			_pa(lo, s[i], z[i], ax), _pa(hi, s[i], z[i], ax),
			_pa(hi, s[i + 1], z[i + 1], ax), _pa(lo, s[i + 1], z[i + 1], ax)]), shade)
	var face := front.duplicate()
	face.append(_pa(hi, s[4], 0.0, ax))
	face.append(_pa(hi, s[0], 0.0, ax))
	draw_colored_polygon(face, BRICK if ax else BRICK.darkened(0.12))
	var w := CANAL_W + 0.02
	draw_colored_polygon(PackedVector2Array([
		_pa(hi, 0.5 - w, 0.0, ax), _pa(hi, 0.5 - w * 0.75, 6.5, ax), _pa(hi, 0.5, 9.5, ax),
		_pa(hi, 0.5 + w * 0.75, 6.5, ax), _pa(hi, 0.5 + w, 0.0, ax)]), Color("2c4a55"))
	draw_polyline(front, BRICK.lightened(0.25), 2.0)


func _house(x0: float, y0: float, x1: float, y1: float, wall_h: float, roof_h: float,
		wall: Color, roof: Color, ridge_x: bool) -> void:
	_ellipse(_p(x1 + 0.05, y1 + 0.05), 30.0, 12.0, SHADOW)
	_face_y(x0, x1, y1, 0.0, wall_h, wall.darkened(0.14))
	_face_x(x1, y0, y1, 0.0, wall_h, wall)
	var top := wall_h + roof_h
	var e := 0.04
	if ridge_x:
		var ym := (y0 + y1) * 0.5
		_poly3([[x0, y0, wall_h], [x1, y0, wall_h], [x1, ym, top], [x0, ym, top]], roof.darkened(0.25))
		_poly3([[x1, y0, wall_h], [x1, y1, wall_h], [x1, ym, top]], wall)
		_poly3([[x0 - e, y1 + e, wall_h - 2], [x1 + e, y1 + e, wall_h - 2], [x1 + e, ym, top], [x0 - e, ym, top]], roof)
	else:
		var xm := (x0 + x1) * 0.5
		_poly3([[x0, y0, wall_h], [x0, y1, wall_h], [xm, y1, top], [xm, y0, top]], roof.darkened(0.25))
		_poly3([[x0, y1, wall_h], [x1, y1, wall_h], [xm, y1, top]], wall.darkened(0.14))
		_poly3([[x1 + e, y0 - e, wall_h - 2], [x1 + e, y1 + e, wall_h - 2], [xm, y1 + e, top], [xm, y0 - e, top]], roof.lightened(0.08))


func _smoke(u: float, v: float, z: float) -> void:
	for j in 3:
		var f := fmod(_t * 0.35 + j / 3.0, 1.0)
		var p := _p(u, v, z + f * 26.0) + Vector2(sin(f * 5.0 + j) * 4.0, 0)
		draw_circle(p, 3.0 + f * 4.0, Color(1, 1, 1, 0.55 * (1.0 - f)))


func _chimney(u: float, v: float, z0: float, z1: float) -> void:
	_face_y(u - 0.05, u + 0.05, v + 0.05, z0, z1, BRICK.darkened(0.2))
	_face_x(u + 0.05, v - 0.05, v + 0.05, z0, z1, BRICK)
	_quad(u - 0.05, v - 0.05, u + 0.05, v + 0.05, BRICK.darkened(0.35), z1)
	_smoke(u, v, z1)


func _cottage() -> void:
	var wall := Color("ece0c4")
	_house(0.24, 0.26, 0.78, 0.76, 20.0, 16.0, wall, Color("b98a52"), false)
	_face_y(0.44, 0.56, 0.76, 0.0, 13.0, Color("5b7fa3"))
	_face_y(0.3, 0.39, 0.76, 7.0, 14.0, Color("fdf3c4"))
	_face_y(0.62, 0.71, 0.76, 7.0, 14.0, Color("fdf3c4"))
	_face_x(0.78, 0.42, 0.6, 7.0, 15.0, Color("fdf3c4"))
	_chimney(0.5, 0.36, 30.0, 42.0)


func _cafe() -> void:
	var wall := Color("f8eed6")
	_house(0.26, 0.24, 0.76, 0.7, 18.0, 10.0, wall, Color("4fa39a"), true)
	_face_y(0.34, 0.44, 0.7, 0.0, 12.0, Color("7a5a3c"))
	_face_y(0.5, 0.7, 0.7, 5.0, 13.0, Color("bfe3ea"))
	_face_x(0.76, 0.34, 0.6, 5.0, 13.0, Color("bfe3ea"))
	# Striped awning over the front.
	for j in 6:
		var a := 0.26 + j * 0.5 / 6.0
		var b := a + 0.5 / 6.0
		var col := Color("d9604c") if j % 2 == 0 else Color("fff8ea")
		_poly3([[a, 0.7, 16.0], [b, 0.7, 16.0], [b, 0.84, 11.0], [a, 0.84, 11.0]], col)
	# Tables outside.
	for q: Vector2 in [Vector2(0.36, 0.92), Vector2(0.64, 0.92)]:
		draw_line(_p(q.x, q.y), _p(q.x, q.y, 5.0), WOOD, 1.5)
		_ellipse(_p(q.x, q.y, 5.0), 5.0, 2.5, Color("fff8ea"))


func _pub() -> void:
	_house(0.16, 0.24, 0.84, 0.72, 24.0, 16.0, BRICK.lightened(0.1), Color("5d6470"), true)
	_face_y(0.44, 0.56, 0.72, 0.0, 14.0, Color("2f5d48"))
	for a: float in [0.22, 0.64]:
		_face_y(a, a + 0.14, 0.72, 6.0, 15.0, Color("fde9a8"))
	for a: float in [0.24, 0.44, 0.64]:
		_face_y(a, a + 0.1, 0.72, 17.0, 23.0, Color("fde9a8"))
	_face_x(0.84, 0.36, 0.6, 7.0, 16.0, Color("fde9a8"))
	_chimney(0.3, 0.42, 34.0, 46.0)
	# Hanging sign.
	draw_line(_p(0.9, 0.9), _p(0.9, 0.9, 24.0), WOOD, 2.5)
	var s := _p(0.9, 0.9, 22.0)
	draw_rect(Rect2(s + Vector2(-13, 0), Vector2(11, 10)), Color("2f5d48"))
	draw_rect(Rect2(s + Vector2(-11, 2), Vector2(7, 6)), Color("f4d35e"))


# Signpost naming the place this canal leads to.
func _fingerpost(c: Vector2i) -> void:
	var i := board.portals.find(c)
	var d := Vector2(board.portal_dirs[i])
	var side := Vector2(-d.y, d.x) * 0.4
	if side.x + side.y > 0.0:
		side = -side
	var base := _p(0.5 + side.x + d.x * 0.25, 0.5 + side.y + d.y * 0.25)
	var top := base + Vector2(0, -30)
	draw_line(base, top, WOOD, 3.0)
	var text: String = board.portal_names[i] if i < board.portal_names.size() else "Wharf"
	var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var rect := Rect2(top + Vector2(-size.x * 0.5 - 6, -9), Vector2(size.x + 12, 18))
	draw_rect(rect.grow(1.5), WOOD)
	draw_rect(rect, Color("fbf3df"))
	draw_string(_font, rect.position + Vector2(6, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, WOOD)


# --- Narrowboat -------------------------------------------------------------

func _prism(center: Vector3, dir: Vector2, pts: Array, z0: float, z1: float, side: Color, top: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var world: Array[Vector2] = []
	for q: Vector2 in pts:
		world.append(Vector2(center.x, center.y) + dir * q.x + perp * q.y)
	var edges := []
	for i in world.size():
		var a := world[i]
		var b := world[(i + 1) % world.size()]
		edges.append([a.x + a.y + b.x + b.y, a, b])
	edges.sort_custom(func(m, n): return m[0] < n[0])
	for e in edges:
		var a: Vector2 = e[1]
		var b: Vector2 = e[2]
		if absf((b.x - b.y) - (a.x - a.y)) * HW < 0.5:
			continue   # edge-on to the camera: nothing to draw
		var lum := absf((b - a).normalized().x)
		var shade := side.darkened(0.25 * lum)
		shade.a = side.a
		draw_colored_polygon(PackedVector2Array([
			iso(a.x, a.y, center.z + z0), iso(b.x, b.y, center.z + z0),
			iso(b.x, b.y, center.z + z1), iso(a.x, a.y, center.z + z1)]), shade)
	var cap := PackedVector2Array()
	for q in world:
		cap.append(iso(q.x, q.y, center.z + z1))
	draw_colored_polygon(cap, top)


func _draw_boat(st: Dictionary) -> void:
	var pos: Vector3 = st.pos
	var dir: Vector2 = st.dir
	var alpha: float = st.alpha
	if alpha <= 0.01:
		return
	var look: Array = BOAT_COLOURS[st.look]
	var fade := func(col: Color) -> Color: return Color(col, alpha)
	pos.z += sin(_t * 2.5 + st.look) * 0.6 - 2.0
	for j in 2:
		var w := pos - Vector3(dir.x, dir.y, 0) * (0.36 + j * 0.1)
		_ellipse(iso(w.x, w.y, pos.z), 6.0 - j * 2.0, 3.0 - j, Color(1, 1, 1, (0.3 - j * 0.1) * alpha))
	var hull := [Vector2(-0.3, -0.07), Vector2(0.2, -0.07), Vector2(0.32, 0.0), Vector2(0.2, 0.07), Vector2(-0.3, 0.07)]
	_prism(pos, dir, hull, 0.0, 5.0, fade.call(Color("23392f")), fade.call(look[1]))
	var cabin := [Vector2(-0.2, -0.05), Vector2(0.13, -0.05), Vector2(0.13, 0.05), Vector2(-0.2, 0.05)]
	_prism(pos, dir, cabin, 5.0, 10.5, fade.call(look[0]), fade.call(Color("f1e3bd")))
	var stack := Vector2(pos.x, pos.y) + dir * -0.13
	var sp := iso(stack.x, stack.y, pos.z + 10.5)
	draw_line(sp, sp + Vector2(0, -5), fade.call(Color("2b2623")), 2.5)
	draw_circle(sp + Vector2(0, -5), 1.6, fade.call(Color("d9a441")))


# --- Overlays ---------------------------------------------------------------

func _draw_markers() -> void:
	for pair in board.blocked_steps():
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var z := maxf(board.height(a), board.height(b)) * HSTEP
		var p := iso((a.x + b.x) * 0.5 + 0.5, (a.y + b.y) * 0.5 + 0.5, z) + Vector2(0, -20.0 + sin(_t * 4.0) * 2.5)
		draw_circle(p, 12.0, Color("fbf3df"))
		draw_circle(p, 10.0, Color("ef8a3c"))
		draw_string(_font, p + Vector2(-10, 6), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 17, Color.WHITE)

	if board.in_bounds(hover):
		_ox = hover.x
		_oy = hover.y
		_oz = board.height(hover) * HSTEP
		var col := Color(1, 1, 1, 0.9) if hover_ok else Color(0.9, 0.3, 0.25, 0.9)
		var ring := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			ring.append(_p(0.5 + cos(a) * 0.46, 0.5 + sin(a) * 0.46, 1.0))
		draw_polyline(ring, col, 2.5)

	var alive := []
	for puff in _puffs:
		var age: float = (_t - puff.t) / 0.45
		if age >= 1.0:
			continue
		alive.append(puff)
		var c: Vector2i = puff.c
		_ox = c.x
		_oy = c.y
		_oz = board.height(c) * HSTEP
		var r := 0.4 + 0.4 * age
		var ring := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			ring.append(_p(0.5 + cos(a) * r, 0.5 + sin(a) * r, 2.0))
		draw_polyline(ring, Color(1, 1, 1, 0.8 * (1.0 - age)), 3.0)
	_puffs = alive
