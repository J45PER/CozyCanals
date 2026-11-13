extends Node2D
## Draws the board in isometric projection. All art is drawn in code with
## flat-shaded polygons, so the project needs no image assets.

signal boat_arrived

const Board := preload("res://scripts/board.gd")
const K := Board.K

const HW := 48.0      # half tile width on screen
const HH := 24.0      # half tile height on screen
const HSTEP := 22.0   # screen pixels per terrain level
const BASE := 18.0    # thickness of the slab under the board

const GRASS_A := Color("a9d488")
const GRASS_B := Color("a0cc7f")
const GRASS_DARK := Color("86b868")
const EARTH_L := Color("8f6b4a")
const EARTH_R := Color("ab835b")
const WATER := Color("62b6c9")
const WATER_WALL := Color("3d8799")
const RIVER := Color("8fd0d8")
const RIVER_WALL := Color("6fb7c2")
const RIVER_BANK := Color("c4e3c0")
const MURK := Color("8d9665")
const MURK_WALL := Color("6c6a47")
const MUD := Color("a8946c")
const STONE := Color("d3ccbb")
const STONE_D := Color("a9a294")
const PATH := Color("e6d2a2")
const LANE := Color("cfc1a8")
const BRICK := Color("b9684c")
const WOOD := Color("4a3b2e")
const SHADOW := Color(0.1, 0.25, 0.1, 0.18)

var board: Board
var hover := Vector2i(-1, -1)
var hover_ok := true

var _t := 0.0
var _ox := 0.0
var _oy := 0.0
var _oz := 0.0
var _font: Font
var _puffs: Array = []

var _boat_path: Array[Vector2i] = []
var _boat_s := 0.0
var _boat_dir := 1
var _boat_wait := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_board(b: Board) -> void:
	board = b
	_boat_path = []
	_puffs.clear()
	hover = Vector2i(-1, -1)
	queue_redraw()


## Starts (or restarts) the narrowboat when the navigable route changes.
func set_route(route: Array[Vector2i]) -> void:
	if route == _boat_path:
		return
	_boat_path = route.duplicate()
	_boat_s = 0.0
	_boat_dir = 1
	_boat_wait = 0.8


func add_puff(c: Vector2i) -> void:
	_puffs.append({"c": c, "t": _t})


func _process(delta: float) -> void:
	_t += delta
	var n := _boat_path.size()
	if n >= 2:
		if _boat_wait > 0.0:
			_boat_wait -= delta
		else:
			var i := clampi(int(floor(_boat_s)), 0, n - 2)
			var stepped := board.height(_boat_path[i]) != board.height(_boat_path[i + 1])
			_boat_s += _boat_dir * (0.4 if stepped else 1.1) * delta
			if _boat_s >= n - 1 or _boat_s <= 0.0:
				_boat_s = clampf(_boat_s, 0.0, n - 1)
				_boat_dir = -_boat_dir
				_boat_wait = 1.6
				boat_arrived.emit()
	queue_redraw()


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


# --- Main draw --------------------------------------------------------------

func _draw() -> void:
	if board == null:
		return
	var boat_slot := -1
	var boat_behind := Vector2i(-1, -1)
	var n := _boat_path.size()
	if n >= 2:
		var i := clampi(int(floor(_boat_s)), 0, n - 2)
		var a := _boat_path[i]
		var b := _boat_path[i + 1]
		boat_slot = maxi(a.x + a.y, b.x + b.y)
		boat_behind = a if a.x + a.y < b.x + b.y else b

	for d in board.w + board.h - 1:
		var x0 := maxi(0, d - board.h + 1)
		var x1 := mini(board.w, d + 1)
		for x in range(x0, x1):
			_ground(Vector2i(x, d - x))
		if d == boat_slot:
			_draw_boat()
			_objects(boat_behind)
		for x in range(x0, x1):
			_objects(Vector2i(x, d - x))

	_draw_markers()


func _nz(c: Vector2i) -> float:
	return board.height(c) * HSTEP if board.in_bounds(c) else -BASE


func _water_conn(c: Vector2i, open_edges: bool) -> Array:
	var conn := []
	for d in Board.DIRS:
		var n := c + d
		conn.append(Board.is_water(board.kind(n)) or (open_edges and not board.in_bounds(n)))
	return conn


func _kind_conn(c: Vector2i, allowed: Array, open_edges: bool) -> Array:
	var conn := []
	for d in Board.DIRS:
		var n := c + d
		conn.append(board.kind(n) in allowed or (open_edges and not board.in_bounds(n)))
	return conn


# Flat cross-shaped strip (centre square plus arms to connected neighbours).
func _arms(mc: float, ma: float, col: Color, conn: Array) -> void:
	_quad(mc, mc, 1.0 - mc, 1.0 - mc, col)
	if conn[0]: _quad(1.0 - mc, ma, 1.0, 1.0 - ma, col)
	if conn[1]: _quad(ma, 1.0 - mc, 1.0 - ma, 1.0, col)
	if conn[2]: _quad(0.0, ma, mc, 1.0 - ma, col)
	if conn[3]: _quad(ma, 0.0, 1.0 - ma, mc, col)


# Like _arms, but with a darker strip on the far edges to suggest depth.
func _water(mc: float, ma: float, col: Color, wall: Color, conn: Array) -> void:
	var d := 0.05
	_arms(mc, ma, wall, conn)
	_quad(mc + d, mc + d, 1.0 - mc, 1.0 - mc, col)
	if conn[0]: _quad(1.0 - mc, ma + d, 1.0, 1.0 - ma, col)
	if conn[1]: _quad(ma + d, 1.0 - mc, 1.0 - ma, 1.0, col)
	if conn[2]: _quad(0.0, ma + d, mc + d, 1.0 - ma, col)
	if conn[3]: _quad(ma + d, 0.0, 1.0 - ma, mc + d, col)


func _shimmer(c: Vector2i) -> void:
	var hsh := _hash(c.x, c.y, 7)
	for j in 2:
		var ph := _t * 0.7 + hsh * TAU + j * 2.4
		var u := 0.5 + 0.13 * sin(ph)
		var v := 0.5 + 0.13 * cos(ph * 0.8 + j)
		var a := 0.25 + 0.2 * sin(ph * 1.7)
		draw_line(_p(u - 0.06, v + 0.06, 0.0), _p(u + 0.06, v - 0.06, 0.0), Color(1, 1, 1, a), 1.5)


func _ground(c: Vector2i) -> void:
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

	var grass := GRASS_A if (c.x + c.y) % 2 == 0 else GRASS_B
	grass = grass.lightened(0.05 * board.height(c))
	_quad(-0.01, -0.01, 1.01, 1.01, grass)

	var hsh := _hash(c.x, c.y)
	match k:
		K.GRASS:
			if hsh < 0.3:
				for j in 3:
					var u := 0.25 + 0.5 * _hash(c.x, c.y, j + 1)
					var v := 0.25 + 0.5 * _hash(c.x, c.y, j + 11)
					draw_line(_p(u, v), _p(u, v, 4.0), GRASS_DARK, 1.5)
			elif hsh > 0.82:
				var cols := [Color("fff6d6"), Color("f7d86a"), Color("f2a7b8")]
				for j in 3:
					var u := 0.2 + 0.6 * _hash(c.x, c.y, j + 21)
					var v := 0.2 + 0.6 * _hash(c.x, c.y, j + 31)
					draw_circle(_p(u, v, 1.0), 1.8, cols[j])
		K.RIVER:
			var conn := _water_conn(c, true)
			_arms(0.1, 0.1, RIVER_BANK, conn)
			_water(0.17, 0.17, RIVER, RIVER_WALL, conn)
			if hsh > 0.4:
				_ellipse(_p(0.3 + 0.4 * hsh, 0.62), 5.0, 3.0, STONE_D)
				_ellipse(_p(0.3 + 0.4 * hsh, 0.62, 1.5), 4.0, 2.2, STONE)
			_reeds(0.2 + 0.2 * hsh, 0.2)
			_shimmer(c)
		K.DERELICT:
			var conn := _water_conn(c, false)
			_arms(0.2, 0.2, MUD, conn)
			_water(0.24, 0.24, MURK, MURK_WALL, conn)
			_ellipse(_p(0.42 + 0.2 * hsh, 0.5), 9.0, 4.5, Color("7fa35a"))
			_ellipse(_p(0.62 - 0.2 * hsh, 0.42), 6.0, 3.0, Color("6f9450"))
			_reeds(0.3, 0.3 + 0.3 * hsh)
			if hsh > 0.5:
				draw_arc(_p(0.55, 0.62, 1.0), 4.5, 0.0, TAU, 12, Color("3a3a3a"), 2.0)
		K.CANAL, K.BRIDGE:
			var conn := _water_conn(c, false)
			_arms(0.2, 0.2, STONE, conn)
			_water(0.24, 0.24, WATER, WATER_WALL, conn)
			_shimmer(c)
		K.LOCK:
			var conn := _water_conn(c, false)
			_arms(0.13, 0.13, STONE, conn)
			_water(0.24, 0.24, WATER, WATER_WALL, conn)
			_shimmer(c)
		K.START, K.END:
			var conn := _water_conn(c, false)
			_arms(0.06, 0.2, STONE, conn)
			_water(0.14, 0.24, WATER, WATER_WALL, conn)
			_shimmer(c)
		K.TOWPATH:
			var conn := _kind_conn(c, [K.TOWPATH, K.LANE, K.BRIDGE, K.COTTAGE, K.CAFE, K.PUB], false)
			_arms(0.35, 0.35, PATH, conn)
		K.LANE:
			var conn := _kind_conn(c, [K.LANE, K.BRIDGE, K.TOWPATH], true)
			_arms(0.3, 0.3, LANE, conn)
		K.COTTAGE, K.CAFE, K.PUB:
			_quad(0.12, 0.12, 0.9, 0.9, GRASS_DARK.lightened(0.15))


func _reeds(u: float, v: float) -> void:
	for j in 3:
		var sway := sin(_t * 1.5 + j) * 1.0
		var base := _p(u + j * 0.03, v + j * 0.02)
		draw_line(base, base + Vector2(sway, -9.0 - j), Color("5d8a48"), 1.5)


func _objects(c: Vector2i) -> void:
	_ox = c.x
	_oy = c.y
	_oz = board.height(c) * HSTEP
	match board.kind(c):
		K.TREE: _tree(c)
		K.ROCK: _rock()
		K.LOCK: _lock_gates(_canal_axis_x(c))
		K.BRIDGE: _bridge(c)
		K.COTTAGE: _cottage()
		K.CAFE: _cafe()
		K.PUB: _pub()
		K.START: _wharf("START", Color("4f9d5b"))
		K.END: _wharf("END", Color("d0553f"))
		K.GRASS:
			if _hash(c.x, c.y, 99) > 0.93:
				_sheep(c)


func _canal_axis_x(c: Vector2i) -> bool:
	if board.kind(c) == K.BRIDGE and board.was_lane(c):
		# The lane keeps its direction; the canal runs across it.
		var lx := board.orig[c.y * board.w + mini(c.x + 1, board.w - 1)] == K.LANE
		lx = lx or board.orig[c.y * board.w + maxi(c.x - 1, 0)] == K.LANE
		return not lx
	var wx := Board.is_water(board.kind(c + Vector2i(1, 0))) or Board.is_water(board.kind(c + Vector2i(-1, 0)))
	var wy := Board.is_water(board.kind(c + Vector2i(0, 1))) or Board.is_water(board.kind(c + Vector2i(0, -1)))
	return wx or not wy


func _tree(c: Vector2i) -> void:
	var hsh := _hash(c.x, c.y, 3)
	var u := 0.4 + 0.2 * hsh
	var v := 0.4 + 0.2 * _hash(c.x, c.y, 4)
	var size := 0.85 + 0.35 * hsh
	var sway := sin(_t * 1.2 + hsh * TAU) * 1.2
	_ellipse(_p(u + 0.05, v + 0.05), 17.0 * size, 8.0 * size, SHADOW)
	draw_line(_p(u, v), _p(u, v, 16.0), Color("7a5a3c"), 4.0)
	var top := _p(u, v, 26.0 * size) + Vector2(sway, 0)
	draw_circle(top + Vector2(-7, 5) * size, 11.0 * size, Color("5f9a4c"))
	draw_circle(top + Vector2(7, 4) * size, 11.0 * size, Color("6aa655"))
	draw_circle(top + Vector2(0, -5) * size, 13.0 * size, Color("78b560"))
	draw_circle(top + Vector2(-3, -9) * size, 6.0 * size, Color("8cc672"))


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
		var a := _pa(along, 0.24, -2.0, ax)
		var b := _pa(along, 0.76, -2.0, ax)
		var up := Vector2(0, -9)
		draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), WOOD)
		var e0 := _pa(along, 0.02, 9.0, ax)
		var e1 := _pa(along, 0.98, 9.0, ax)
		draw_line(e0, e1, Color("2b2623"), 4.0)
		draw_line(e0, e0.lerp(e1, 0.14), Color("f6f0e2"), 4.0)
		draw_line(e1, e1.lerp(e0, 0.14), Color("f6f0e2"), 4.0)


func _bridge(c: Vector2i) -> void:
	var ax := _canal_axis_x(c)
	var deck_col := LANE if board.was_lane(c) else PATH
	var s := [0.0, 0.2, 0.5, 0.8, 1.0]
	var z := [0.0, 10.0, 13.0, 10.0, 0.0]
	var back := PackedVector2Array()
	var front := PackedVector2Array()
	for i in 5:
		back.append(_pa(0.3, s[i], z[i] + 4.0, ax))
		front.append(_pa(0.7, s[i], z[i] + 4.0, ax))
	draw_polyline(back, BRICK.darkened(0.2), 3.0)
	for i in 4:
		var shade := deck_col.darkened(0.08) if i == 0 or i == 3 else deck_col
		draw_colored_polygon(PackedVector2Array([
			_pa(0.3, s[i], z[i], ax), _pa(0.7, s[i], z[i], ax),
			_pa(0.7, s[i + 1], z[i + 1], ax), _pa(0.3, s[i + 1], z[i + 1], ax)]), shade)
	var face := front.duplicate()
	face.append(_pa(0.7, 1.0, 0.0, ax))
	face.append(_pa(0.7, 0.0, 0.0, ax))
	draw_colored_polygon(face, BRICK if ax else BRICK.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([
		_pa(0.7, 0.28, 0.0, ax), _pa(0.7, 0.33, 6.5, ax), _pa(0.7, 0.5, 9.5, ax),
		_pa(0.7, 0.67, 6.5, ax), _pa(0.7, 0.72, 0.0, ax)]), Color("2c4a55"))
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


func _wharf(label: String, flag: Color) -> void:
	for q: Vector2 in [Vector2(0.9, 0.3), Vector2(0.9, 0.7)]:
		draw_line(_p(q.x, q.y), _p(q.x, q.y, 5.0), Color("2b2623"), 4.0)
	var base := _p(0.08, 0.08)
	var top := _p(0.08, 0.08, 38.0)
	draw_line(base, top, WOOD, 2.5)
	var wave := sin(_t * 3.0) * 2.0
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(20, 5 + wave), top + Vector2(0, 11)]), flag)
	var pos := top + Vector2(-40, -6)
	draw_string_outline(_font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, 4, Color("fbf3df"))
	draw_string(_font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color("4a3b2e"))


# --- Narrowboat -------------------------------------------------------------

func _boat_pos(s: float) -> Vector3:
	var n := _boat_path.size()
	s = clampf(s, 0.0, n - 1)
	var i := clampi(int(floor(s)), 0, n - 2)
	var f := s - i
	var a := _boat_path[i]
	var b := _boat_path[i + 1]
	var z := lerpf(board.height(a), board.height(b), smoothstep(0.3, 0.7, f)) * HSTEP
	return Vector3(lerpf(a.x, b.x, f) + 0.5, lerpf(a.y, b.y, f) + 0.5, z)


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
		var lum := absf((b - a).normalized().x)
		draw_colored_polygon(PackedVector2Array([
			iso(a.x, a.y, center.z + z0), iso(b.x, b.y, center.z + z0),
			iso(b.x, b.y, center.z + z1), iso(a.x, a.y, center.z + z1)]), side.darkened(0.25 * lum))
	var cap := PackedVector2Array()
	for q in world:
		cap.append(iso(q.x, q.y, center.z + z1))
	draw_colored_polygon(cap, top)


func _draw_boat() -> void:
	var pos := _boat_pos(_boat_s)
	var ahead := _boat_pos(_boat_s + 0.3)
	var behind := _boat_pos(_boat_s - 0.3)
	var dir := Vector2(ahead.x - behind.x, ahead.y - behind.y)
	dir = Vector2(1, 0) if dir.length() < 0.001 else dir.normalized()
	dir *= _boat_dir
	pos.z += sin(_t * 2.5) * 0.6 - 2.0
	if _boat_wait <= 0.0:
		for j in 2:
			var w := pos - Vector3(dir.x, dir.y, 0) * (0.42 + j * 0.12)
			_ellipse(iso(w.x, w.y, pos.z), 7.0 - j * 2.0, 3.5 - j, Color(1, 1, 1, 0.3 - j * 0.1))
	var hull := [Vector2(-0.36, -0.085), Vector2(0.24, -0.085), Vector2(0.38, 0.0), Vector2(0.24, 0.085), Vector2(-0.36, 0.085)]
	_prism(pos, dir, hull, 0.0, 5.0, Color("23392f"), Color("b8483c"))
	var cabin := [Vector2(-0.24, -0.062), Vector2(0.16, -0.062), Vector2(0.16, 0.062), Vector2(-0.24, 0.062)]
	_prism(pos, dir, cabin, 5.0, 11.0, Color("2f6b55"), Color("f1e3bd"))
	var stack := Vector2(pos.x, pos.y) + dir * -0.16
	var sp := iso(stack.x, stack.y, pos.z + 11.0)
	draw_line(sp, sp + Vector2(0, -6), Color("2b2623"), 2.5)
	draw_circle(sp + Vector2(0, -6), 1.6, Color("d9a441"))


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
		draw_polyline(PackedVector2Array([_p(0, 0, 1), _p(1, 0, 1), _p(1, 1, 1), _p(0, 1, 1), _p(0, 0, 1)]), col, 2.5)

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
		var g := 0.5 * age
		draw_polyline(PackedVector2Array([
			_p(-g, -g, 2), _p(1 + g, -g, 2), _p(1 + g, 1 + g, 2), _p(-g, 1 + g, 2), _p(-g, -g, 2)]),
			Color(1, 1, 1, 0.8 * (1.0 - age)), 3.0)
	_puffs = alive
