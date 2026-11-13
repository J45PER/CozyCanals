extends RefCounted
## Artwork that has to follow what the player draws, generated in code: the
## palette, a small triangle batcher, ground details, hedges, bridges and
## locks. Standing objects (buildings, trees, animals, boats) are sprites;
## see sprites.gd. Everything here is in cell coordinates, projected by iso().

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


# --- Small ground-level props -------------------------------------------------

# Leaf litter and bluebells under a clump of trees.
static func wood_floor(mb: MB, o: Vector2, z: float, seed: int) -> void:
	mb.disc(iso(o + Vector2(0.5, 0.5), z), 24.0, 12.0, Color(0.36, 0.5, 0.3, 0.5), 12)
	for j in 5:
		var q := iso(o + Vector2(0.2 + 0.6 * rnd(seed, j, 5), 0.2 + 0.6 * rnd(seed, j, 6)), z + 1.0)
		mb.disc(q, 1.4, 1.1, Color("7f8fd6"), 5)


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
## `dir` points uphill. The chamber is cut into the upper level: a stone-edged
## basin of deep water with tall bottom gates on the drop and top gates above.
static func lock(mb: MB, mid: Vector2, dir: Vector2, z_low: float, z_high: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	if side.x + side.y < 0.0:
		side = -side
	var head := mid + dir * 0.44
	var hw := 0.2
	var rim := hw + 0.075
	# Stone surround, then the chamber: far wall in shadow and water well below.
	mb.quad(iso(mid - side * rim, z_high), iso(head - side * rim, z_high),
		iso(head + side * rim, z_high), iso(mid + side * rim, z_high), STONE)
	mb.quad(iso(mid - side * hw, z_high), iso(head - side * hw, z_high),
		iso(head + side * hw, z_high), iso(mid + side * hw, z_high), STONE.darkened(0.45))
	var sink := minf(z_high - z_low, 7.0)
	mb.quad(iso(mid - side * hw * 0.55, z_high - sink), iso(head - side * hw * 0.55, z_high - sink),
		iso(head + side * hw, z_high - sink), iso(mid + side * hw, z_high - sink), WATER_EDGE.darkened(0.1))
	# The drop itself: a stone face with the tall bottom gates closed across it.
	mb.quad(iso(mid - side * rim, z_low), iso(mid + side * rim, z_low),
		iso(mid + side * rim, z_high), iso(mid - side * rim, z_high), STONE.darkened(0.2))
	mb.quad(iso(mid - side * hw, z_low), iso(mid + side * hw, z_low),
		iso(mid + side * hw, z_high + 2.0), iso(mid - side * hw, z_high + 2.0), TIMBER)
	mb.line(iso(mid, z_low), iso(mid, z_high + 2.0), 1.0, Color("5a4a3e"))
	mb.line(iso(mid - side * hw * 0.5, z_high - 3.0), iso(mid - side * hw * 0.5, z_low + 1.0), 1.6, Color(1, 1, 1, 0.5))
	# Top gates at the head of the chamber.
	mb.quad(iso(head - side * hw, z_high - 1.0), iso(head + side * hw, z_high - 1.0),
		iso(head + side * hw, z_high + 3.0), iso(head - side * hw, z_high + 3.0), TIMBER)
	# Balance beams on both pairs: black with white ends, angled back along the lock side.
	for gate in [[mid, 1.0], [head, 1.0]]:
		var g: Vector2 = gate[0]
		for s: float in [-1.0, 1.0]:
			var a := iso(g + side * hw * 0.2 * s, z_high + 4.0)
			var b := iso(g + side * (rim + 0.13) * s + dir * 0.06, z_high + 4.0)
			mb.line(a, b, 2.6, Color("26211e"))
			mb.line(b, b.lerp(a, 0.28), 2.6, Color("f4efe2"))
	# Bollards on the lockside.
	for t: float in [0.12, 0.34]:
		var p := iso(mid + dir * t + side * (rim - 0.025), z_high)
		mb.line(p, p + Vector2(0, -3.0), 1.8, Color("26211e"))
