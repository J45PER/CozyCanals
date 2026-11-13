extends RefCounted
## The game's artwork, generated in code: palette, a small triangle batcher,
## and one function per thing that appears on the map. Everything is drawn in
## cell coordinates and projected with iso().

const World := preload("res://scripts/world.gd")
const B := World.B

const HW := 36.0      # half cell width on screen
const HH := 18.0      # half cell height on screen
const HSTEP := 16.0   # screen pixels per terrain level

# Fields: pasture, wildflower meadow, wheat, cut hay, ploughed.
const FIELD := [Color("9fbc72"), Color("adc47e"), Color("dcc57c"), Color("c9cc86"), Color("b0926b")]
const GRASS_LIP := Color("7ea05a")
const BANK := Color("7c9a5c")
const EARTH := Color("9a7b56")
const STONE := Color("c9bea4")
const HEDGE := Color("4f7340")
const HEDGE_LIGHT := Color("6f9450")
const RIVER := Color("7fb4bd")
const RIVER_EDGE := Color("5f98a3")
const RIVER_BANK := Color("c6c79a")
const WATER := Color("6aa3a8")
const WATER_EDGE := Color("47767e")
const COPING := Color("cfc3a6")
const MUD := Color("9c8a66")
const MURK := Color("7c8a62")
const PATH := Color("e2cfa3")
const PATH_EDGE := Color("c2ab7c")
const ROAD := Color("b8ad9c")
const VERGE := Color("8f9a6a")
const BRICK := Color("ab5a43")
const HONEY := Color("dcc79a")
const WHITEWASH := Color("efe8d8")
const SLATE := Color("5b6470")
const THATCH := Color("c2a05c")
const TIMBER := Color("3a2f27")
const SHADOW := Color(0.12, 0.2, 0.1, 0.2)


## Collects coloured triangles and turns them into one mesh.
class MB:
	var v := PackedVector2Array()
	var c := PackedColorArray()

	func tri(a: Vector2, b: Vector2, d: Vector2, col: Color) -> void:
		v.append(a)
		v.append(b)
		v.append(d)
		c.append(col)
		c.append(col)
		c.append(col)

	func quad(a: Vector2, b: Vector2, d: Vector2, e: Vector2, col: Color) -> void:
		tri(a, b, d, col)
		tri(a, d, e, col)

	func fan(pts: PackedVector2Array, col: Color) -> void:
		for i in range(1, pts.size() - 1):
			tri(pts[0], pts[i], pts[i + 1], col)

	func disc(o: Vector2, rx: float, ry: float, col: Color, n := 10) -> void:
		var prev := o + Vector2(rx, 0)
		for i in range(1, n + 1):
			var a := TAU * i / n
			var next := o + Vector2(cos(a) * rx, sin(a) * ry)
			tri(o, prev, next, col)
			prev = next

	func line(a: Vector2, b: Vector2, width: float, col: Color) -> void:
		var n := (b - a).orthogonal().normalized() * width * 0.5
		quad(a + n, b + n, b - n, a - n, col)

	func mesh() -> ArrayMesh:
		if v.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_COLOR] = c
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


static func iso(p: Vector2, z: float) -> Vector2:
	return Vector2((p.x - p.y) * HW, (p.x + p.y) * HH - z)


## Repeatable pseudo-random number in 0..1.
static func rnd(x: int, y: int, seed := 0) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


# --- Building blocks --------------------------------------------------------

# A box seen from the front: left wall, right wall and top.
static func box(mb: MB, o: Vector2, z: float, x0: float, y0: float, x1: float, y1: float,
		z0: float, z1: float, col: Color, top := Color(0, 0, 0, 0)) -> void:
	mb.quad(iso(o + Vector2(x0, y1), z + z0), iso(o + Vector2(x1, y1), z + z0),
		iso(o + Vector2(x1, y1), z + z1), iso(o + Vector2(x0, y1), z + z1), col.darkened(0.17))
	mb.quad(iso(o + Vector2(x1, y0), z + z0), iso(o + Vector2(x1, y1), z + z0),
		iso(o + Vector2(x1, y1), z + z1), iso(o + Vector2(x1, y0), z + z1), col)
	mb.quad(iso(o + Vector2(x0, y0), z + z1), iso(o + Vector2(x1, y0), z + z1),
		iso(o + Vector2(x1, y1), z + z1), iso(o + Vector2(x0, y1), z + z1),
		col.lightened(0.12) if top.a == 0.0 else top)


# A pitched roof over the same footprint, with the gable end filled in.
static func roof(mb: MB, o: Vector2, z: float, x0: float, y0: float, x1: float, y1: float,
		zw: float, zt: float, ridge_x: bool, col: Color, wall: Color) -> void:
	var e := 0.05
	if ridge_x:
		var ym := (y0 + y1) * 0.5
		mb.quad(iso(o + Vector2(x0, y0), z + zw), iso(o + Vector2(x1, y0), z + zw),
			iso(o + Vector2(x1, ym), z + zt), iso(o + Vector2(x0, ym), z + zt), col.darkened(0.28))
		mb.tri(iso(o + Vector2(x1, y0), z + zw), iso(o + Vector2(x1, y1), z + zw), iso(o + Vector2(x1, ym), z + zt), wall)
		mb.quad(iso(o + Vector2(x0 - e, y1 + e), z + zw - 2), iso(o + Vector2(x1 + e, y1 + e), z + zw - 2),
			iso(o + Vector2(x1 + e, ym), z + zt), iso(o + Vector2(x0 - e, ym), z + zt), col)
		mb.line(iso(o + Vector2(x0 - e, ym), z + zt), iso(o + Vector2(x1 + e, ym), z + zt), 2.0, col.darkened(0.3))
	else:
		var xm := (x0 + x1) * 0.5
		mb.quad(iso(o + Vector2(x0, y0), z + zw), iso(o + Vector2(x0, y1), z + zw),
			iso(o + Vector2(xm, y1), z + zt), iso(o + Vector2(xm, y0), z + zt), col.darkened(0.28))
		mb.tri(iso(o + Vector2(x0, y1), z + zw), iso(o + Vector2(x1, y1), z + zw), iso(o + Vector2(xm, y1), z + zt),
			wall.darkened(0.17))
		mb.quad(iso(o + Vector2(x1 + e, y0 - e), z + zw - 2), iso(o + Vector2(x1 + e, y1 + e), z + zw - 2),
			iso(o + Vector2(xm, y1 + e), z + zt), iso(o + Vector2(xm, y0 - e), z + zt), col.lightened(0.07))
		mb.line(iso(o + Vector2(xm, y0 - e), z + zt), iso(o + Vector2(xm, y1 + e), z + zt), 2.0, col.darkened(0.3))


# Panel on the left-hand wall (the one at y = `y`).
static func on_left(mb: MB, o: Vector2, z: float, xa: float, xb: float, y: float, za: float, zb: float, col: Color) -> void:
	mb.quad(iso(o + Vector2(xa, y), z + za), iso(o + Vector2(xb, y), z + za),
		iso(o + Vector2(xb, y), z + zb), iso(o + Vector2(xa, y), z + zb), col)


# Panel on the right-hand wall (the one at x = `x`).
static func on_right(mb: MB, o: Vector2, z: float, x: float, ya: float, yb: float, za: float, zb: float, col: Color) -> void:
	mb.quad(iso(o + Vector2(x, ya), z + za), iso(o + Vector2(x, yb), z + za),
		iso(o + Vector2(x, yb), z + zb), iso(o + Vector2(x, ya), z + zb), col)


static func window_left(mb: MB, o: Vector2, z: float, x: float, y: float, za: float, lit := Color("f7e7a6")) -> void:
	on_left(mb, o, z, x - 0.012, x + 0.092, y, za - 0.8, za + 6.3, Color("f4efe2"))
	on_left(mb, o, z, x, x + 0.08, y, za, za + 5.5, lit)
	on_left(mb, o, z, x + 0.036, x + 0.044, y, za, za + 5.5, Color("f4efe2"))


static func window_right(mb: MB, o: Vector2, z: float, x: float, y: float, za: float, lit := Color("f7e7a6")) -> void:
	on_right(mb, o, z, x, y - 0.012, y + 0.092, za - 0.8, za + 6.3, Color("f4efe2"))
	on_right(mb, o, z, x, y, y + 0.08, za, za + 5.5, lit)
	on_right(mb, o, z, x, y + 0.036, y + 0.044, za, za + 5.5, Color("f4efe2"))


static func chimney(mb: MB, o: Vector2, z: float, x: float, y: float, z0: float, z1: float) -> Vector2:
	box(mb, o, z, x - 0.04, y - 0.04, x + 0.04, y + 0.04, z0, z1, BRICK.darkened(0.1))
	box(mb, o, z, x - 0.02, y - 0.02, x + 0.02, y + 0.02, z1, z1 + 2.0, Color("c98f5f"))
	return iso(o + Vector2(x, y), z + z1 + 3.0)


static func shadow(mb: MB, o: Vector2, z: float, x: float, y: float, rx: float, ry: float) -> void:
	mb.disc(iso(o + Vector2(x, y), z), rx, ry, SHADOW)


static func flowerbed(mb: MB, o: Vector2, z: float, x0: float, x1: float, y: float, seed: int) -> void:
	mb.quad(iso(o + Vector2(x0, y), z), iso(o + Vector2(x1, y), z), iso(o + Vector2(x1, y + 0.07), z),
		iso(o + Vector2(x0, y + 0.07), z), HEDGE_LIGHT)
	var cols := [Color("e98bb0"), Color("f1c84b"), Color("f4efe2"), Color("c58ad6"), Color("e2604e")]
	for j in 6:
		var p := iso(o + Vector2(lerpf(x0, x1, (j + 0.5) / 6.0), y + 0.035), z + 2.0)
		mb.disc(p, 1.7, 1.5, cols[(seed + j) % cols.size()], 6)


# --- Ground details ---------------------------------------------------------

static func field_detail(mb: MB, o: Vector2, z: float, field: Dictionary, c: Vector2i) -> void:
	var col: Color = field.col
	# Soft blotches so no field is a flat colour.
	for j in 3:
		# Kept well inside the cell so the next cell never cuts one off.
		var p := o + Vector2(0.32 + 0.36 * rnd(c.x, c.y, 200 + j), 0.32 + 0.36 * rnd(c.x, c.y, 210 + j))
		var tone := col.darkened(0.05) if j % 2 == 0 else col.lightened(0.05)
		tone.a = 0.5
		mb.disc(iso(p, z), 6.0 + 5.0 * rnd(c.x, c.y, 220 + j), 3.0 + 2.5 * rnd(c.x, c.y, 230 + j), tone, 8)
	var dir := Vector2.from_angle(field.angle)
	match field.kind:
		0:
			for j in 5:
				var p := iso(o + Vector2(0.1 + 0.8 * rnd(c.x, c.y, j + 1), 0.1 + 0.8 * rnd(c.x, c.y, j + 11)), z)
				mb.tri(p + Vector2(-1.5, 0), p + Vector2(1.5, 0), p + Vector2(0.5, -4.0), col.darkened(0.16))
			if rnd(c.x, c.y, 50) > 0.6:
				for j in 4:
					var p := iso(o + Vector2(0.1 + 0.8 * rnd(c.x, c.y, j + 61), 0.1 + 0.8 * rnd(c.x, c.y, j + 71)), z + 1.5)
					mb.disc(p, 1.3, 1.1, Color("f3d552"), 5)
		1:
			var cols := [Color("f6f0df"), Color("f3d552"), Color("e79ab5"), Color("b58bd0"), Color("d9604c")]
			for j in 9:
				var p := iso(o + Vector2(0.05 + 0.9 * rnd(c.x, c.y, j + 21), 0.05 + 0.9 * rnd(c.x, c.y, j + 31)), z + 1.5)
				mb.disc(p, 1.5, 1.3, cols[j % cols.size()], 5)
		2, 3, 4:
			# Rows running the way the field was drilled, cut or ploughed.
			var tone := col.darkened(0.12) if field.kind != 3 else col.lightened(0.1)
			for j in 6:
				var p := o + Vector2(0.12 + 0.76 * rnd(c.x, c.y, j + 41), 0.12 + 0.76 * rnd(c.x, c.y, j + 51))
				mb.line(iso(p - dir * 0.11, z), iso(p + dir * 0.11, z), 1.3, tone)


static func hedge(mb: MB, a: Vector2, b: Vector2, z: float, seed: int) -> void:
	var n := maxi(2, int(a.distance_to(b) * 7.0))
	for i in n + 1:
		var p := iso(a.lerp(b, float(i) / n), z)
		mb.disc(p + Vector2(0, 0.5), 5.2, 3.4, HEDGE.darkened(0.12), 7)
	for i in n + 1:
		var p := iso(a.lerp(b, float(i) / n), z)
		var wob := rnd(seed, i, 3)
		mb.disc(p + Vector2(0, -3.0 - wob), 4.6, 3.6, HEDGE, 7)
		mb.disc(p + Vector2(1.2, -4.6 - wob), 2.6, 2.0, HEDGE_LIGHT, 6)


static func stone_wall(mb: MB, a: Vector2, b: Vector2, z: float) -> void:
	var pa := iso(a, z)
	var pb := iso(b, z)
	var up := Vector2(0, -4.5)
	mb.quad(pa, pb, pb + up, pa + up, STONE.darkened(0.22))
	mb.line(pa + up, pb + up, 2.2, STONE.lightened(0.05))
	var n := maxi(2, int(a.distance_to(b) * 6.0))
	for i in range(1, n):
		var p := pa.lerp(pb, float(i) / n)
		mb.line(p, p + up, 0.8, STONE.darkened(0.4))


static func reeds(mb: MB, p: Vector2, z: float, seed: int) -> void:
	for j in 4:
		var base := iso(p + Vector2(j * 0.035, j * 0.02), z)
		var lean := (rnd(seed, j, 1) - 0.5) * 4.0
		mb.tri(base + Vector2(-0.9, 0), base + Vector2(0.9, 0), base + Vector2(lean, -8.0 - j), Color("5c8246"))
	var head := iso(p + Vector2(0.035, 0.02), z + 9.0)
	mb.disc(head, 1.2, 2.4, Color("6b4a2f"), 5)


static func stone(mb: MB, p: Vector2, z: float) -> void:
	mb.disc(iso(p, z), 5.0, 3.0, STONE.darkened(0.25), 7)
	mb.disc(iso(p, z + 1.5), 3.8, 2.2, STONE, 7)


static func lilies(mb: MB, p: Vector2, z: float, seed: int) -> void:
	for j in 3:
		var q := iso(p + Vector2(rnd(seed, j, 1) - 0.5, rnd(seed, j, 2) - 0.5) * 0.2, z)
		mb.disc(q, 3.0, 1.7, Color("6f9a55"), 7)
		if j == 0:
			mb.disc(q + Vector2(0, -0.8), 1.2, 1.0, Color("f4efe2"), 5)


static func weeds(mb: MB, o: Vector2, z: float, seed: int) -> void:
	for j in 3:
		var p := o + Vector2(0.3 + 0.4 * rnd(seed, j, 1), 0.3 + 0.4 * rnd(seed, j, 2))
		mb.disc(iso(p, z), 6.0, 3.0, Color("7c9a55"), 7)
		mb.disc(iso(p, z + 2.0), 3.5, 2.6, Color("8fae62"), 6)
	reeds(mb, o + Vector2(0.4, 0.55), z, seed)
	if rnd(seed, 9, 9) > 0.55:
		# Something dumped in the cut.
		var q := iso(o + Vector2(0.55, 0.45), z + 1.0)
		mb.disc(q, 4.0, 2.2, Color("34312e"), 8)
		mb.disc(q, 2.2, 1.2, MURK, 8)


# --- Trees and rocks --------------------------------------------------------

static func oak(mb: MB, p: Vector2, z: float, size: float, seed: int) -> void:
	var tone := rnd(seed, 1, 1)
	var dark := Color("4f7b45").lerp(Color("5f8a3e"), tone)
	var mid := Color("6a9a52").lerp(Color("7fa64a"), tone)
	var light := Color("8ab868").lerp(Color("9fc060"), tone)
	mb.disc(iso(p + Vector2(0.06, 0.06), z), 15.0 * size, 7.0 * size, SHADOW)
	var base := iso(p, z)
	mb.quad(base + Vector2(-2.0, 0) * size, base + Vector2(2.0, 0) * size,
		base + Vector2(1.4, -13.0) * size, base + Vector2(-1.4, -13.0) * size, Color("6b5138"))
	var top := base + Vector2(0, -21.0 * size)
	mb.disc(top + Vector2(-6, 5) * size, 9.5 * size, 8.0 * size, dark)
	mb.disc(top + Vector2(7, 4) * size, 9.0 * size, 7.5 * size, dark)
	mb.disc(top + Vector2(0, 1) * size, 11.5 * size, 9.5 * size, mid)
	mb.disc(top + Vector2(-5, -4) * size, 7.5 * size, 6.5 * size, mid)
	mb.disc(top + Vector2(4, -5) * size, 7.5 * size, 6.5 * size, light)
	mb.disc(top + Vector2(1, -9) * size, 4.5 * size, 3.8 * size, light.lightened(0.1))


static func poplar(mb: MB, p: Vector2, z: float, size: float) -> void:
	mb.disc(iso(p + Vector2(0.04, 0.04), z), 8.0 * size, 4.0 * size, SHADOW)
	var base := iso(p, z)
	mb.quad(base + Vector2(-1.3, 0), base + Vector2(1.3, 0), base + Vector2(1.0, -8.0), base + Vector2(-1.0, -8.0), Color("6b5138"))
	mb.disc(base + Vector2(0, -20.0 * size), 5.5 * size, 15.0 * size, Color("55803f"))
	mb.disc(base + Vector2(1.5, -23.0 * size), 3.2 * size, 11.0 * size, Color("73a052"))


static func pine(mb: MB, p: Vector2, z: float, size: float) -> void:
	mb.disc(iso(p + Vector2(0.04, 0.04), z), 9.0 * size, 4.5 * size, SHADOW)
	var base := iso(p, z)
	mb.quad(base + Vector2(-1.3, 0), base + Vector2(1.3, 0), base + Vector2(1.0, -6.0), base + Vector2(-1.0, -6.0), Color("5e4630"))
	for j in 3:
		var y := -5.0 - j * 8.0 * size
		var half := (9.0 - j * 2.2) * size
		mb.tri(base + Vector2(-half, y), base + Vector2(half, y), base + Vector2(0, y - 13.0 * size), Color("3f6b47").lightened(j * 0.05))
		mb.tri(base + Vector2(0, y), base + Vector2(half, y), base + Vector2(0, y - 13.0 * size), Color("4f7d55").lightened(j * 0.05))


# A clump of mixed trees over a carpet of bluebells.
static func copse(mb: MB, o: Vector2, z: float, seed: int) -> void:
	mb.disc(iso(o + Vector2(0.5, 0.5), z), 24.0, 12.0, Color(0.36, 0.5, 0.3, 0.5), 12)
	for j in 5:
		var q := iso(o + Vector2(0.2 + 0.6 * rnd(seed, j, 5), 0.2 + 0.6 * rnd(seed, j, 6)), z + 1.0)
		mb.disc(q, 1.4, 1.1, Color("7f8fd6"), 5)
	var spots := []
	for j in 2 + int(rnd(seed, 0, 60) > 0.4):
		spots.append(Vector3(0.2 + 0.6 * rnd(seed, j, 61), 0.2 + 0.6 * rnd(seed, j, 71), rnd(seed, j, 81)))
	spots.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	for s: Vector3 in spots:
		var p := o + Vector2(s.x, s.y)
		if s.z > 0.86:
			pine(mb, p, z, 0.9)
		elif s.z > 0.74:
			poplar(mb, p, z, 0.9)
		else:
			oak(mb, p, z, 0.65 + 0.45 * s.z, seed + int(s.z * 100.0))


static func outcrop(mb: MB, o: Vector2, z: float, seed: int) -> void:
	var p := iso(o + Vector2(0.5, 0.55), z)
	mb.disc(p + Vector2(2, 3), 17.0, 7.0, SHADOW)
	var flip := -1.0 if rnd(seed, 1, 1) > 0.5 else 1.0
	var body := PackedVector2Array()
	for q: Vector2 in [Vector2(-14, 3), Vector2(-10, -9), Vector2(-1, -15), Vector2(10, -8), Vector2(15, 3), Vector2(3, 7), Vector2(-7, 6)]:
		body.append(p + Vector2(q.x * flip, q.y))
	mb.fan(body, Color("9a968a"))
	mb.fan(PackedVector2Array([p + Vector2(-10 * flip, -9), p + Vector2(-1 * flip, -15), p + Vector2(10 * flip, -8), p + Vector2(0, -4)]),
		Color("bcb8ab"))
	mb.disc(p + Vector2(-9 * flip, 5), 5.0, 2.5, Color("7f9a5c"), 6)


static func livestock(mb: MB, o: Vector2, z: float, seed: int, cows: bool) -> void:
	for j in 1 + int(rnd(seed, 2, 2) > 0.4):
		var p := iso(o + Vector2(0.3 + 0.4 * j, 0.35 + 0.3 * rnd(seed, j, 4)), z + 3.5)
		var face := 1.0 if rnd(seed, j, 5) > 0.5 else -1.0
		mb.disc(p + Vector2(1, 4), 6.5, 2.6, SHADOW, 8)
		if cows:
			mb.disc(p + Vector2(0, -1), 7.0, 4.4, Color("f3efe6"), 9)
			mb.disc(p + Vector2(-2.0 * face, -2.0), 3.0, 2.4, Color("2f2b29"), 7)
			mb.disc(p + Vector2(3.0 * face, 0.0), 2.0, 1.8, Color("2f2b29"), 6)
			mb.disc(p + Vector2(7.0 * face, -2.0), 2.6, 2.3, Color("2f2b29"), 7)
		else:
			mb.disc(p, 5.2, 3.9, Color("f6f1e4"), 9)
			mb.disc(p + Vector2(0, -2), 4.0, 2.8, Color("fffaf0"), 8)
			mb.disc(p + Vector2(5.0 * face, -1.5), 2.1, 2.0, Color("3b3432"), 7)


static func hay_bale(mb: MB, p: Vector2, z: float) -> void:
	var q := iso(p, z)
	mb.disc(q + Vector2(1, 2), 7.0, 3.0, SHADOW, 8)
	mb.quad(q + Vector2(-5, -8), q + Vector2(4, -6), q + Vector2(4, 1), q + Vector2(-5, -1), Color("cdb163"))
	mb.disc(q + Vector2(4, -2.5), 3.0, 4.0, Color("e2c877"), 9)
	mb.disc(q + Vector2(4, -2.5), 1.2, 1.6, Color("c9ac5e"), 6)


# --- Buildings --------------------------------------------------------------

## Draws a building and returns where its chimney smoke should rise from
## (screen position), or ZERO if it has none.
static func building(mb: MB, kind: int, o: Vector2, z: float, seed: int) -> Vector2:
	mb.disc(iso(o + Vector2(0.5, 0.5), z), 24.0, 12.0, Color(0.55, 0.66, 0.4, 0.5), 12)
	match kind:
		B.COTTAGE: return _cottage(mb, o, z, seed)
		B.CAFE: return _cafe(mb, o, z)
		B.PUB: return _pub(mb, o, z)
		B.CHURCH: return _church(mb, o, z)
		B.FARM: return _farm(mb, o, z)
	return Vector2.ZERO


static func _cottage(mb: MB, o: Vector2, z: float, seed: int) -> Vector2:
	var style := int(rnd(seed, 3, 3) * 3.0)
	var wall: Color = [HONEY, WHITEWASH, HONEY.darkened(0.06)][style]
	var top: Color = [THATCH, THATCH.darkened(0.08), SLATE][style]
	shadow(mb, o, z, 0.62, 0.66, 24.0, 10.0)
	box(mb, o, z, 0.24, 0.3, 0.76, 0.7, 0.0, 12.0, wall)
	on_left(mb, o, z, 0.46, 0.56, 0.7, 0.0, 9.0, [Color("5d7f9a"), Color("5f8a5a"), Color("a8493a")][style])
	window_left(mb, o, z, 0.29, 0.7, 4.0)
	window_left(mb, o, z, 0.63, 0.7, 4.0)
	window_right(mb, o, z, 0.76, 0.46, 4.5)
	roof(mb, o, z, 0.24, 0.3, 0.76, 0.7, 12.0, 23.0, false, top, wall)
	var smoke := chimney(mb, o, z, 0.4, 0.4, 17.0, 26.0)
	flowerbed(mb, o, z, 0.24, 0.44, 0.71, seed)
	flowerbed(mb, o, z, 0.58, 0.76, 0.71, seed + 2)
	return smoke


static func _cafe(mb: MB, o: Vector2, z: float) -> Vector2:
	shadow(mb, o, z, 0.62, 0.64, 23.0, 10.0)
	box(mb, o, z, 0.26, 0.26, 0.74, 0.66, 0.0, 12.0, Color("f3ead2"))
	on_left(mb, o, z, 0.32, 0.42, 0.66, 0.0, 9.0, Color("6b5138"))
	on_left(mb, o, z, 0.47, 0.7, 0.66, 3.0, 9.5, Color("f4efe2"))
	on_left(mb, o, z, 0.485, 0.685, 0.66, 3.8, 8.8, Color("b9dbe0"))
	window_right(mb, o, z, 0.74, 0.4, 4.0, Color("b9dbe0"))
	roof(mb, o, z, 0.26, 0.26, 0.74, 0.66, 12.0, 19.0, true, Color("4d9a90"), Color("f3ead2"))
	for j in 6:
		var a := 0.26 + j * 0.08
		var col := Color("d4604c") if j % 2 == 0 else Color("fbf6e8")
		mb.quad(iso(o + Vector2(a, 0.66), z + 11.5), iso(o + Vector2(a + 0.08, 0.66), z + 11.5),
			iso(o + Vector2(a + 0.08, 0.8), z + 8.0), iso(o + Vector2(a, 0.8), z + 8.0), col)
	for q: Vector2 in [Vector2(0.36, 0.9), Vector2(0.62, 0.9)]:
		mb.line(iso(o + q, z), iso(o + q, z + 4.0), 1.3, TIMBER)
		mb.disc(iso(o + q, z + 4.0), 4.2, 2.1, Color("fbf6e8"), 8)
	return Vector2.ZERO


static func _pub(mb: MB, o: Vector2, z: float) -> Vector2:
	shadow(mb, o, z, 0.66, 0.68, 30.0, 12.0)
	box(mb, o, z, 0.14, 0.24, 0.84, 0.68, 0.0, 16.0, WHITEWASH)
	# Black timber framing on the upper floor.
	on_left(mb, o, z, 0.14, 0.84, 0.68, 8.2, 9.2, TIMBER)
	on_right(mb, o, z, 0.84, 0.24, 0.68, 8.2, 9.2, TIMBER)
	for a: float in [0.14, 0.31, 0.49, 0.67, 0.825]:
		on_left(mb, o, z, a, a + 0.015, 0.68, 9.2, 16.0, TIMBER)
	for a: float in [0.24, 0.45, 0.665]:
		on_right(mb, o, z, 0.84, a, a + 0.015, 9.2, 16.0, TIMBER)
	on_left(mb, o, z, 0.44, 0.55, 0.68, 0.0, 7.6, Color("2d5443"))
	window_left(mb, o, z, 0.2, 0.68, 2.0)
	window_left(mb, o, z, 0.64, 0.68, 2.0)
	window_left(mb, o, z, 0.36, 0.68, 10.0)
	window_left(mb, o, z, 0.54, 0.68, 10.0)
	window_right(mb, o, z, 0.84, 0.32, 2.2)
	window_right(mb, o, z, 0.84, 0.5, 10.0)
	roof(mb, o, z, 0.14, 0.24, 0.84, 0.68, 16.0, 28.0, true, SLATE, WHITEWASH)
	var smoke := chimney(mb, o, z, 0.28, 0.4, 22.0, 32.0)
	# Hanging sign, a bench with a parasol, and a telephone box.
	var post := o + Vector2(0.93, 0.86)
	mb.line(iso(post, z), iso(post, z + 20.0), 2.0, TIMBER)
	var sign := iso(post, z + 19.0)
	mb.quad(sign + Vector2(-11, 0), sign + Vector2(-1, 0), sign + Vector2(-1, 9), sign + Vector2(-11, 9), Color("2d5443"))
	mb.disc(sign + Vector2(-6, 4.5), 2.6, 2.6, Color("f1c84b"), 8)
	box(mb, o, z, 0.24, 0.84, 0.4, 0.9, 0.0, 2.5, Color("8a6a45"))
	var pole := o + Vector2(0.32, 0.87)
	mb.line(iso(pole, z + 2.0), iso(pole, z + 13.0), 1.2, TIMBER)
	mb.disc(iso(pole, z + 12.0), 9.0, 4.0, Color("d4604c"), 10)
	mb.disc(iso(pole, z + 13.5), 4.5, 2.0, Color("fbf6e8"), 8)
	box(mb, o, z, 0.62, 0.86, 0.69, 0.93, 0.0, 12.0, Color("c0392b"))
	on_left(mb, o, z, 0.635, 0.675, 0.93, 3.0, 10.0, Color("f0d9d0"))
	return smoke


static func _church(mb: MB, o: Vector2, z: float) -> Vector2:
	var wall := Color("cdbf9f")
	shadow(mb, o, z, 0.64, 0.68, 30.0, 12.0)
	# Nave.
	box(mb, o, z, 0.38, 0.32, 0.88, 0.66, 0.0, 14.0, wall)
	for a: float in [0.46, 0.6, 0.74]:
		on_left(mb, o, z, a, a + 0.06, 0.66, 3.0, 10.0, Color("3f5873"))
		mb.disc(iso(o + Vector2(a + 0.03, 0.66), z + 10.0), 1.9, 2.2, Color("3f5873"), 6)
	on_right(mb, o, z, 0.88, 0.44, 0.54, 4.0, 11.0, Color("7fa2c4"))
	roof(mb, o, z, 0.38, 0.32, 0.88, 0.66, 14.0, 24.0, true, SLATE, wall)
	# Tower with battlements and a little spire.
	box(mb, o, z, 0.14, 0.34, 0.4, 0.64, 0.0, 34.0, wall.darkened(0.04))
	on_left(mb, o, z, 0.23, 0.31, 0.64, 0.0, 8.0, Color("5a4632"))
	on_left(mb, o, z, 0.24, 0.3, 0.64, 20.0, 27.0, Color("3a3f48"))
	on_right(mb, o, z, 0.4, 0.45, 0.53, 20.0, 27.0, Color("3a3f48"))
	mb.disc(iso(o + Vector2(0.27, 0.64), z + 14.5), 2.6, 2.6, Color("f4efe2"), 8)
	for q: Vector2 in [Vector2(0.14, 0.34), Vector2(0.34, 0.34), Vector2(0.14, 0.58), Vector2(0.34, 0.58)]:
		box(mb, o, z, q.x, q.y, q.x + 0.06, q.y + 0.06, 34.0, 37.5, wall)
	var tip := iso(o + Vector2(0.27, 0.49), z + 52.0)
	mb.tri(iso(o + Vector2(0.2, 0.56), z + 34.0), iso(o + Vector2(0.34, 0.56), z + 34.0), tip, SLATE.darkened(0.15))
	mb.tri(iso(o + Vector2(0.34, 0.42), z + 34.0), iso(o + Vector2(0.34, 0.56), z + 34.0), tip, SLATE.lightened(0.08))
	# Churchyard: headstones and a yew.
	for q: Vector2 in [Vector2(0.5, 0.82), Vector2(0.62, 0.86), Vector2(0.74, 0.8)]:
		var g := iso(o + q, z)
		mb.quad(g + Vector2(-1.8, 0), g + Vector2(1.8, 0), g + Vector2(1.8, -4.5), g + Vector2(-1.8, -4.5), Color("a9a89f"))
		mb.disc(g + Vector2(0, -4.5), 1.8, 1.6, Color("a9a89f"), 6)
	pine(mb, o + Vector2(0.18, 0.86), z, 0.75)
	return Vector2.ZERO


static func _farm(mb: MB, o: Vector2, z: float) -> Vector2:
	shadow(mb, o, z, 0.64, 0.7, 30.0, 12.0)
	# Barn: black weatherboard with a rust-red roof.
	box(mb, o, z, 0.12, 0.16, 0.56, 0.52, 0.0, 15.0, Color("4a3f38"))
	on_left(mb, o, z, 0.26, 0.42, 0.52, 0.0, 11.0, Color("7a5a3c"))
	on_left(mb, o, z, 0.335, 0.345, 0.52, 0.0, 11.0, Color("4a3f38"))
	roof(mb, o, z, 0.12, 0.16, 0.56, 0.52, 15.0, 25.0, false, Color("a2533d"), Color("4a3f38"))
	# Farmhouse in brick.
	box(mb, o, z, 0.56, 0.42, 0.9, 0.74, 0.0, 12.0, BRICK.lightened(0.12))
	on_left(mb, o, z, 0.7, 0.78, 0.74, 0.0, 8.5, Color("f4efe2"))
	window_left(mb, o, z, 0.6, 0.74, 4.0)
	window_left(mb, o, z, 0.8, 0.74, 4.0)
	window_right(mb, o, z, 0.9, 0.54, 4.0)
	roof(mb, o, z, 0.56, 0.42, 0.9, 0.74, 12.0, 21.0, true, SLATE, BRICK.lightened(0.12))
	var smoke := chimney(mb, o, z, 0.66, 0.5, 16.0, 24.0)
	hay_bale(mb, o + Vector2(0.22, 0.78), z)
	hay_bale(mb, o + Vector2(0.38, 0.86), z)
	# Post-and-rail fence along the yard.
	var a := o + Vector2(0.08, 0.62)
	var b := o + Vector2(0.08, 0.96)
	mb.line(iso(a, z + 4.0), iso(b, z + 4.0), 1.2, Color("8a6a45"))
	mb.line(iso(a, z + 2.0), iso(b, z + 2.0), 1.2, Color("8a6a45"))
	for j in 4:
		var p := a.lerp(b, j / 3.0)
		mb.line(iso(p, z), iso(p, z + 5.5), 1.6, Color("6b5138"))
	return smoke


static func signpost(mb: MB, p: Vector2, z: float) -> void:
	mb.disc(iso(p, z), 3.0, 1.5, SHADOW, 6)
	mb.line(iso(p, z), iso(p, z + 30.0), 2.6, TIMBER)


# --- Canal structures -------------------------------------------------------

## A bridge from p0 to p1 (the middles of two cell edges) over the water in
## between: a brick humpback for canals, a plank footbridge for rivers.
static func bridge(mb: MB, p0: Vector2, p1: Vector2, z: float, is_road: bool, wooden: bool) -> void:
	var along := (p1 - p0).normalized()
	var side := Vector2(-along.y, along.x) * (0.17 if is_road else 0.11)
	if side.x + side.y < 0.0:
		side = -side          # `side` now points towards the camera
	var wall := Color("8a6a45") if wooden else BRICK
	var deck := Color("b08a5c") if wooden else (ROAD if is_road else PATH)
	var hump := 3.0 if wooden else 9.0
	var steps := 8
	var prof := []
	for i in steps + 1:
		var t := float(i) / steps
		prof.append([p0.lerp(p1, 0.08 + t * 0.84), sin(t * PI) * hump])
	# Far parapet, deck, then the near wall with its arch.
	for i in steps:
		var a: Vector2 = prof[i][0] - side
		var b: Vector2 = prof[i + 1][0] - side
		mb.quad(iso(a, z + prof[i][1]), iso(b, z + prof[i + 1][1]),
			iso(b, z + prof[i + 1][1] + 3.5), iso(a, z + prof[i][1] + 3.5), wall.darkened(0.25))
	for i in steps:
		var a: Vector2 = prof[i][0]
		var b: Vector2 = prof[i + 1][0]
		mb.quad(iso(a - side, z + prof[i][1]), iso(b - side, z + prof[i + 1][1]),
			iso(b + side, z + prof[i + 1][1]), iso(a + side, z + prof[i][1]), deck.darkened(0.04 * absf(i - 3.5)))
	for i in steps:
		var a: Vector2 = prof[i][0] + side
		var b: Vector2 = prof[i + 1][0] + side
		var top_a: float = prof[i][1] + 3.5
		var top_b: float = prof[i + 1][1] + 3.5
		if wooden:
			mb.line(iso(a, z + top_a), iso(b, z + top_b), 1.4, wall)
			mb.line(iso(a, z), iso(a, z + top_a), 1.4, wall.darkened(0.2))
			mb.line(iso(a, z + prof[i][1]), iso(b, z + prof[i + 1][1]), 2.0, wall.darkened(0.1))
			continue
		mb.quad(iso(a, z), iso(b, z), iso(b, z + top_b), iso(a, z + top_a), wall)
		if i >= 2 and i <= 5:
			# The arch opening over the water.
			var rise_a := sin((i - 2) / 4.0 * PI) * 5.0
			var rise_b := sin((i - 1) / 4.0 * PI) * 5.0
			mb.quad(iso(a, z), iso(b, z), iso(b, z + rise_b), iso(a, z + rise_a), Color("243c44"))
		mb.line(iso(a, z + top_a), iso(b, z + top_b), 1.6, STONE)


## A lock between two levels. `mid` is the point where the levels meet and
## `dir` points uphill; the chamber sits on the lower side.
static func lock(mb: MB, mid: Vector2, dir: Vector2, z_low: float, z_high: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	if side.x + side.y < 0.0:
		side = -side
	var tail := mid - dir * 0.46
	var hw := 0.2
	# Chamber walls rising to the upper level, far side first.
	for s: float in [-1.0, 1.0]:
		var a: Vector2 = tail + side * hw * s
		var b: Vector2 = mid + side * hw * s
		var a2: Vector2 = tail + side * (hw + 0.09) * s
		var b2: Vector2 = mid + side * (hw + 0.09) * s
		if s < 0.0:
			mb.quad(iso(a, z_low), iso(b, z_low), iso(b, z_high + 1.0), iso(a, z_high + 1.0), STONE.darkened(0.3))
		else:
			mb.quad(iso(a2, z_low), iso(b2, z_low), iso(b2, z_high + 1.0), iso(a2, z_high + 1.0), STONE.darkened(0.12))
		mb.quad(iso(a, z_high + 1.0), iso(b, z_high + 1.0), iso(b2, z_high + 1.0), iso(a2, z_high + 1.0), STONE.lightened(0.06))
	# Top gate holding back the upper water, bottom gate at the tail.
	for gate in [[mid, z_high + 4.0], [tail, z_low + 9.0]]:
		var g: Vector2 = gate[0]
		var top: float = gate[1]
		mb.quad(iso(g - side * hw, z_low), iso(g + side * hw, z_low), iso(g + side * hw, top), iso(g - side * hw, top), TIMBER)
		mb.line(iso(g - side * hw * 0.3, z_low), iso(g - side * hw * 0.3, top), 1.0, Color("5a4a3e"))
		mb.line(iso(g + side * hw * 0.4, z_low), iso(g + side * hw * 0.4, top), 1.0, Color("5a4a3e"))
		# Balance beams: black with white ends.
		var e0 := iso(g - side * 0.47, top + 2.0)
		var e1 := iso(g + side * 0.47, top + 2.0)
		mb.line(e0, e1, 3.2, Color("26211e"))
		mb.line(e0, e0.lerp(e1, 0.13), 3.2, Color("f4efe2"))
		mb.line(e1, e1.lerp(e0, 0.13), 3.2, Color("f4efe2"))
	# Water spilling through the top gate.
	mb.line(iso(mid - dir * 0.02, z_high - 1.0), iso(mid - dir * 0.02, z_low + 1.0), 2.0, Color(1, 1, 1, 0.55))
