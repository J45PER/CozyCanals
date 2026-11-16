extends RefCounted
## Artwork that has to follow what the player draws, generated in code: the
## palette, a small triangle batcher, ground details, hedges, bridges and
## locks. Standing objects (buildings, trees, animals, boats) are sprites;
## see sprites.gd. Everything here is in cell coordinates, projected by iso().

const World := preload("res://scripts/world.gd")
const B := World.B

const HW := 36.0      # half cell width on screen
const HH := 18.0      # half cell height on screen
const HSTEP := 9.0    # screen pixels per terrain level: a low bank

# Fields: pasture, meadow, wheat, cut hay, ploughed.
const FIELD := [Color("9cbb6f"), Color("a9c47a"), Color("d6c27c"), Color("bfc883"), Color("b39672")]
const MIST := Color("dde2c9")         # the haze the countryside fades into
const GRASS_LIP := Color("7ea05a")
const BANK := Color("7c9a5c")
const EARTH := Color("9a7b56")
const STONE := Color("c9bea4")
const HEDGE := Color("557c45")
const HEDGE_LIGHT := Color("6f9450")
const RIVER := Color("86b9b0")           # a touch lighter and greener than canal water
const RIVER_EDGE := Color("64998f")
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

	## A four-cornered patch with a colour at each corner, blended across it.
	func quad_shaded(a: Vector2, b: Vector2, d: Vector2, e: Vector2, ca: Color, cb: Color, cd: Color, ce: Color) -> void:
		v.append(a); v.append(b); v.append(d)
		c.append(ca); c.append(cb); c.append(cd)
		v.append(a); v.append(d); v.append(e)
		c.append(ca); c.append(cd); c.append(ce)

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


static func hedge(mb: MB, a: Vector2, b: Vector2, za: float, zb: float, fade: float) -> void:
	var pa := iso(a, za)
	var pb := iso(b, zb)
	var up := Vector2(0, -5.0)
	var side := (pb - pa).orthogonal().normalized() * 1.6
	if side.y < 0.0:
		side = -side
	mb.quad(pa - side, pb - side, pb + side + up, pa + side + up, hazed(HEDGE, fade))
	mb.quad(pa - side + up, pb - side + up, pb + side + up, pa + side + up, hazed(HEDGE_LIGHT, fade))


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


static func signpost(mb: MB, p: Vector2, z: float) -> void:
	mb.line(iso(p, z), iso(p, z + 30.0), 2.6, TIMBER)


# --- Canal structures -------------------------------------------------------

## Height of a bridge deck above the water at `u` (0..1 along it), in pixels:
## arches rise to a crown, a concrete bridge is a level slab on its abutments.
static func deck_z(style: String, span: float, u: float) -> float:
	var scale := clampf(span / 0.7, 0.85, 1.6)
	if style == "concrete":
		return 12.0 * smoothstep(0.0, 0.18, minf(u, 1.0 - u))
	return (12.0 if style == "brick" else 11.0) * scale * sin(clampf(u, 0.0, 1.0) * PI)


## A bridge from p0 to p1: a brick or stone arch, or a modern concrete beam
## bridge. The deck follows the road in any direction (so it may cross the
## water at a slant); `open_frac` is the part of its length that is over the
## water. Under it there is nothing, so boats pass beneath.
static func bridge(mb: MB, p0: Vector2, p1: Vector2, z: float, is_road: bool, style: String, span := 0.7,
		half_width := -1.0, open_frac := 0.55) -> void:
	var along := (p1 - p0).normalized()
	var side := Vector2(-along.y, along.x) * (half_width if half_width > 0.0 else (0.17 if is_road else 0.11))
	if side.x + side.y < 0.0:
		side = -side          # `side` now points towards the camera
	var concrete := style == "concrete"
	var wall: Color = {"brick": BRICK, "stone": Color("c3b8a0"), "concrete": Color("bdbcb6")}[style]
	var deck := ROAD if is_road else PATH
	var steps := 14
	var lo := int(round(steps * (1.0 - open_frac) * 0.5))
	var hi := steps - lo
	var beam := 3.5 if not concrete else 4.0
	var prof := []
	for i in steps + 1:
		var t := float(i) / steps
		prof.append([p0.lerp(p1, 0.04 + t * 0.92), deck_z(style, span, t)])
	# How high the opening reaches under the deck at each point.
	var rise := []
	for i in steps + 1:
		var r := 0.0
		if i >= lo and i <= hi:
			if concrete:
				r = prof[i][1] - beam
			else:
				r = deck_z(style, span, float(i - lo) / maxf(hi - lo, 1)) * 0.8
		rise.append(maxf(r, 0.0))
	# Far parapet, then the deck, then the near wall with the opening.
	for i in steps:
		var a: Vector2 = prof[i][0] - side
		var b: Vector2 = prof[i + 1][0] - side
		mb.quad(iso(a, z + prof[i][1]), iso(b, z + prof[i + 1][1]),
			iso(b, z + prof[i + 1][1] + 3.0), iso(a, z + prof[i][1] + 3.0), wall.darkened(0.25))
	for i in steps:
		var a: Vector2 = prof[i][0]
		var b: Vector2 = prof[i + 1][0]
		mb.quad(iso(a - side, z + prof[i][1]), iso(b - side, z + prof[i + 1][1]),
			iso(b + side, z + prof[i + 1][1]), iso(a + side, z + prof[i][1]), deck)
	for i in steps:
		var a: Vector2 = prof[i][0] + side
		var b: Vector2 = prof[i + 1][0] + side
		var top_a: float = prof[i][1] + (3.0 if not concrete else 4.0)
		var top_b: float = prof[i + 1][1] + (3.0 if not concrete else 4.0)
		mb.quad(iso(a, z + rise[i]), iso(b, z + rise[i + 1]), iso(b, z + top_b), iso(a, z + top_a), wall)
		if i >= lo and i < hi:
			mb.line(iso(a, z + rise[i]), iso(b, z + rise[i + 1]), 1.2, wall.darkened(0.32))
		mb.line(iso(a, z + top_a), iso(b, z + top_b), 1.6, wall.lightened(0.18))
	if concrete:
		# Slim railings along both edges of the slab.
		for sd: float in [-1.0, 1.0]:
			for i in range(0, steps + 1, 2):
				var q: Vector2 = prof[i][0] + side * sd
				mb.line(iso(q, z + prof[i][1] + 4.0), iso(q, z + prof[i][1] + 7.0), 1.0, Color("e8e6df"))
			var qa: Vector2 = prof[0][0] + side * sd
			var qb: Vector2 = prof[steps][0] + side * sd
			mb.line(iso(qa, z + prof[0][1] + 7.0), iso(qb, z + prof[steps][1] + 7.0), 1.0, Color("e8e6df"))


## A lock, as decoration on level ground: stone or Victorian-brick walls along
## both sides of the canal for a short length, with open gates against them.
static func lock_rim(mb: MB, node: Vector2, t: Vector2, z: float, style: String) -> void:
	var wall := Color("9b5a47") if style == "brick" else Color("9d9684")
	var edge := wall.darkened(0.32)
	var n := Vector2(-t.y, t.x)
	var half := 0.4
	for s: float in [-1.0, 1.0]:
		var a0 := node - t * half + n * s * 0.19
		var a1 := node + t * half + n * s * 0.19
		var b0 := node - t * half + n * s * 0.37
		var b1 := node + t * half + n * s * 0.37
		mb.quad(iso(a0, z + 0.4), iso(a1, z + 0.4), iso(b1, z + 0.4), iso(b0, z + 0.4), wall)
		mb.line(iso(b0, z + 0.5), iso(b1, z + 0.5), 1.4, edge)
		# Gates standing open against the wall at each end.
		for e: float in [-1.0, 1.0]:
			var g0 := node + t * half * e + n * s * 0.2
			var g1 := node + t * (half * e - e * 0.2) + n * s * 0.215
			mb.line(iso(g0, z + 1.0), iso(g1, z + 1.0), 3.0, TIMBER)
	# Cross-ties at each end.
	for e: float in [-1.0, 1.0]:
		var c0 := node + t * half * e + n * 0.19
		var c1 := node + t * half * e - n * 0.19
		mb.line(iso(c0, z + 0.5), iso(c1, z + 0.5), 1.4, edge)


## Balance beams on the lock gates, drawn over passing boats.
static func lock_beams(mb: MB, node: Vector2, t: Vector2, z: float) -> void:
	var n := Vector2(-t.y, t.x)
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			var base := node + t * 0.38 * e + n * s * 0.27
			var tip := base + t * 0.16 * e + n * s * 0.1
			var a := iso(base, z + 3.5)
			var b := iso(tip, z + 3.5)
			mb.line(a, b, 2.4, Color("26211e"))
			mb.line(b, b.lerp(a, 0.3), 2.4, Color("f4efe2"))
