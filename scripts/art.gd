extends RefCounted
## Artwork that has to follow what the player draws, generated in code: the
## palette, a small triangle batcher, ground details, hedges, bridges and
## locks. Standing objects (buildings, trees, animals, boats) are sprites;
## see sprites.gd. Everything here is in cell coordinates, projected by iso().

const World := preload("res://scripts/world.gd")
const B := World.B

const HW := 36.0      # half cell width on screen
const HH := 18.0      # half cell height on screen
const HSTEP := 26.0   # screen pixels per terrain level

# Fields: pasture, meadow, wheat, cut hay, ploughed.
const FIELD := [Color("9cbb6f"), Color("a9c47a"), Color("d6c27c"), Color("bfc883"), Color("b39672")]
const MIST := Color("dde2c9")         # the haze the countryside fades into
const GRASS_LIP := Color("7ea05a")
const BANK := Color("7c9a5c")
const EARTH := Color("9a7b56")
const STONE := Color("c9bea4")
const HEDGE := Color("557c45")
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
const TIMBER := Color("3a2f27")
const SHADOW := Color(0.12, 0.2, 0.1, 0.18)


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

	## Convex polygon with a colour at each point, blended across it.
	func fan_shaded(pts: PackedVector2Array, cols: PackedColorArray) -> void:
		for i in range(1, pts.size() - 1):
			v.append(pts[0])
			v.append(pts[i])
			v.append(pts[i + 1])
			c.append(cols[0])
			c.append(cols[i])
			c.append(cols[i + 1])

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
# Flat colours and simple shapes only. `fade` (0..1) hazes a colour into the
# distance, for the countryside beyond the playable map.

static func hazed(col: Color, fade: float) -> Color:
	return col if fade <= 0.0 else col.lerp(MIST, fade)


static func field_detail(mb: MB, o: Vector2, ground: Callable, field: Dictionary, fade: float) -> void:
	# Crops and plough lines run in straight rows across the field.
	if field.kind != 2 and field.kind != 4:
		return
	var col: Color = field.col
	var dir := Vector2.from_angle(field.angle)
	var across := Vector2(-dir.y, dir.x)
	var tone := hazed(col.darkened(0.1), fade)
	for j in 3:
		var p := o + Vector2(0.5, 0.5) + across * (j - 1) * 0.3
		var a := p - dir * 0.34
		var b := p + dir * 0.34
		mb.line(iso(a, ground.call(a) + 0.3), iso(b, ground.call(b) + 0.3), 1.2, tone)


static func hedge(mb: MB, a: Vector2, b: Vector2, za: float, zb: float, fade: float) -> void:
	var pa := iso(a, za)
	var pb := iso(b, zb)
	var up := Vector2(0, -5.0)
	var side := (pb - pa).orthogonal().normalized() * 1.6
	if side.y < 0.0:
		side = -side
	mb.quad(pa - side, pb - side, pb + side + up, pa + side + up, hazed(HEDGE, fade))
	mb.quad(pa - side + up, pb - side + up, pb + side + up, pa + side + up, hazed(HEDGE_LIGHT, fade))
	mb.disc(pa + up * 0.5, 2.6, 3.4, hazed(HEDGE, fade), 8)
	mb.disc(pb + up * 0.5, 2.6, 3.4, hazed(HEDGE, fade), 8)


static func stone_wall(mb: MB, a: Vector2, b: Vector2, za: float, zb: float, fade: float, col := STONE) -> void:
	var pa := iso(a, za)
	var pb := iso(b, zb)
	var up := Vector2(0, -4.0)
	mb.quad(pa, pb, pb + up, pa + up, hazed(col.darkened(0.2), fade))
	mb.line(pa + up, pb + up, 2.0, hazed(col, fade))


## A pub-garden table with benches and a parasol, at screen point `p`.
static func picnic_table(mb: MB, p: Vector2, parasol: Color) -> void:
	mb.disc(p + Vector2(1, 1), 7.0, 3.0, SHADOW, 10)
	mb.quad(p + Vector2(-6, -1), p + Vector2(4, -4), p + Vector2(6, -3), p + Vector2(-4, 0), Color("8a6a45"))
	mb.quad(p + Vector2(-5, -4), p + Vector2(3, -7), p + Vector2(5, -6), p + Vector2(-3, -3), Color("a8865a"))
	mb.quad(p + Vector2(-4, 2), p + Vector2(6, -1), p + Vector2(7, 0), p + Vector2(-3, 3), Color("8a6a45"))
	mb.line(p + Vector2(0, -5), p + Vector2(0, -16), 1.0, TIMBER)
	mb.fan(PackedVector2Array([p + Vector2(-8, -14), p + Vector2(0, -19), p + Vector2(8, -14), p + Vector2(0, -12)]), parasol)


## Post-and-rail or picket fence.
static func fence(mb: MB, a: Vector2, b: Vector2, za: float, zb: float, col: Color, first_post: bool) -> void:
	var pa := iso(a, za)
	var pb := iso(b, zb)
	for h: float in [2.2, 4.4]:
		mb.line(pa + Vector2(0, -h), pb + Vector2(0, -h), 0.9, col.darkened(0.1))
	var n := maxi(1, int(a.distance_to(b) * 5.0))
	for i in range(0 if first_post else 1, n + 1):
		var p := pa.lerp(pb, float(i) / n)
		mb.line(p, p + Vector2(0, -5.6), 1.3, col)


static func reeds(mb: MB, p: Vector2, z: float) -> void:
	for j in 3:
		var base := iso(p + Vector2(j * 0.04, j * 0.02), z)
		mb.tri(base + Vector2(-1.0, 0), base + Vector2(1.0, 0), base + Vector2(0.5 * (j - 1), -7.0 - j), Color("5c8246"))


static func stone(mb: MB, p: Vector2, z: float) -> void:
	mb.disc(iso(p, z), 4.0, 2.4, STONE.darkened(0.15), 8)


static func lilies(mb: MB, p: Vector2, z: float, seed: int) -> void:
	for j in 2:
		var q := iso(p + Vector2(rnd(seed, j, 1) - 0.5, rnd(seed, j, 2) - 0.5) * 0.2, z)
		mb.disc(q, 2.8, 1.6, Color("6f9a55"), 8)


static func weeds(mb: MB, p: Vector2, z: float) -> void:
	mb.disc(iso(p, z), 6.5, 3.2, Color("7c9a55"), 10)
	reeds(mb, p + Vector2(0.06, 0.08), z)


static func signpost(mb: MB, p: Vector2, z: float) -> void:
	mb.line(iso(p, z), iso(p, z + 30.0), 2.6, TIMBER)


# --- Canal structures -------------------------------------------------------

## A bridge from p0 to p1 (where the path or road meets the water's banks).
## style: "brick" humpback, "stone" arch, or "wood" plank footbridge.
static func bridge(mb: MB, p0: Vector2, p1: Vector2, z: float, is_road: bool, style: String) -> void:
	var along := (p1 - p0).normalized()
	var side := Vector2(-along.y, along.x) * (0.17 if is_road else 0.11)
	if side.x + side.y < 0.0:
		side = -side          # `side` now points towards the camera
	var wooden := style == "wood"
	var wall: Color = {"brick": BRICK, "stone": Color("c3b8a0"), "wood": Color("8a6a45")}[style]
	var deck := Color("b08a5c") if wooden else (ROAD if is_road else PATH)
	var hump := 3.0 if wooden else (9.0 if style == "brick" else 7.0)
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
			iso(b + side, z + prof[i + 1][1]), iso(a + side, z + prof[i][1]), deck)
	for i in steps:
		var a: Vector2 = prof[i][0] + side
		var b: Vector2 = prof[i + 1][0] + side
		var top_a: float = prof[i][1] + 3.5
		var top_b: float = prof[i + 1][1] + 3.5
		if wooden:
			mb.line(iso(a, z + top_a), iso(b, z + top_b), 1.4, wall)
			mb.line(iso(a, z), iso(a, z + top_a), 1.4, wall.darkened(0.2))
			continue
		# The near wall, with an open arch over the water: below the arch's
		# curve there is nothing, so a boat underneath shows through.
		var rise_a := 0.0
		var rise_b := 0.0
		if i >= 2 and i <= 5:
			rise_a = sin((i - 2) / 4.0 * PI) * 6.0
			rise_b = sin((i - 1) / 4.0 * PI) * 6.0
		mb.quad(iso(a, z + rise_a), iso(b, z + rise_b), iso(b, z + top_b), iso(a, z + top_a), wall)
		if i >= 2 and i <= 5:
			mb.line(iso(a, z + rise_a), iso(b, z + rise_b), 1.2, wall.darkened(0.3))
		mb.line(iso(a, z + top_a), iso(b, z + top_b), 1.6, STONE if style == "brick" else wall.lightened(0.2))


## A lock between two levels, in "stone" or Victorian "brick". `mid` is the
## point where the levels meet and `dir` points uphill. The chamber is cut into the upper level: a stone-edged
## basin of deep water with tall bottom gates on the drop and top gates above.
static func lock(mb: MB, mid: Vector2, dir: Vector2, z_low: float, z_high: float, style := "stone") -> void:
	var edge := STONE if style == "stone" else Color("a8604a")
	var side := Vector2(-dir.y, dir.x)
	if side.x + side.y < 0.0:
		side = -side
	var head := mid + dir * 0.44
	var hw := 0.2
	var rim := hw + 0.075
	# Stone surround, then the chamber: far wall in shadow and water well below.
	mb.quad(iso(mid - side * rim, z_high), iso(head - side * rim, z_high),
		iso(head + side * rim, z_high), iso(mid + side * rim, z_high), edge)
	mb.quad(iso(mid - side * hw, z_high), iso(head - side * hw, z_high),
		iso(head + side * hw, z_high), iso(mid + side * hw, z_high), edge.darkened(0.45))
	var sink := minf(z_high - z_low, 7.0)
	mb.quad(iso(mid - side * hw * 0.55, z_high - sink), iso(head - side * hw * 0.55, z_high - sink),
		iso(head + side * hw, z_high - sink), iso(mid + side * hw, z_high - sink), WATER_EDGE.darkened(0.1))
	# The drop itself: a stone face with the tall bottom gates closed across it.
	mb.quad(iso(mid - side * rim, z_low), iso(mid + side * rim, z_low),
		iso(mid + side * rim, z_high), iso(mid - side * rim, z_high), edge.darkened(0.2))
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
