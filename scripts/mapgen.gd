extends RefCounted
## Builds a World from a seed and a few parameters. The same seed always
## gives the same map, which is what makes Journey levels and the Daily map
## repeatable.
##
## Parameters (all optional except seed):
##   seed, name, blurb, w, h
##   portals   number of canals running off the map (2+)
##   hills     0 flat, 1 one terrace, 2 two terraces
##   river     true to add a river
##   derelict  0..1 share of the obvious route that survives as silted canal
##   places    villages, pubs and churches wanting a path to the canal
##   roads     existing roads crossing the map
##   farms     farms wanting a road to an existing road
##   woods     0..1 woodland cover
##   budget    starting coins as a multiple of a sensible solution's cost
##   unlimited true for free building with no budget
##   charm_goal

const World := preload("res://scripts/world.gd")
const AutoBuild := preload("res://scripts/autobuild.gd")
const T := World.T
const L := World.L
const B := World.B

const TOWNS := ["Ambleford", "Thistlewick", "Marlow Wharf", "Hartley Top", "Coombe Basin",
	"Nettlebank", "Oxley Lock", "Fenny Bridge", "Wrenhope", "Saltersford"]
const PUBS := ["The Navigation", "The Boat Inn", "The Anchor", "The Swan", "The Barge & Bottle"]
const CHURCHES := ["St Mary's", "St Giles'", "All Saints"]
const HAMLETS := ["Rose Cottage", "Lock Cottage", "Bramble End", "Orchard Row"]
const FARMS := ["Home Farm", "Brook Farm", "Hilltop Farm", "Manor Farm"]
const MILLS := ["Hartley Mill", "Ambleford Mill", "Tower Mill"]
const MANORS := ["Coombe Hall", "Thistlewick Manor", "The Grange"]
const SHOPS := ["Village Stores", "The Post Office", "Wharf Stores"]
## Places that want a footpath, in the order they are handed out.
const PATH_PLACES := [[B.PUB, PUBS], [B.CHURCH, CHURCHES], [B.COTTAGE, HAMLETS], [B.WINDMILL, MILLS],
	[B.MANOR, MANORS], [B.SHOP, SHOPS]]


## Generates a finished, solvable map with its starting budget.
static func generate(params: Dictionary) -> World:
	var p := params.duplicate()
	for attempt in 30:
		var world := _make(p)
		if world != null:
			if p.get("unlimited", false):
				world.unlimited = true
				world.recompute()
				return world
			var trial := _make(p)
			trial.unlimited = true
			trial.recompute()
			if AutoBuild.run(trial):
				world.coins = int(ceil(trial.spent * float(p.get("budget", 1.5)) / 10.0)) * 10 + 10
				world.recompute()
				return world
		p.seed = int(p.seed) + 7919
	push_error("Could not generate a solvable map")
	return _make(p)


static func _make(p: Dictionary) -> World:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.seed)
	var world := World.new()
	var w: int = p.get("w", 22)
	var h: int = p.get("h", 16)
	world.setup(w, h)
	world.title = p.get("name", "Open Country")
	world.blurb = p.get("blurb", "")
	world.charm_goal = p.get("charm_goal", 20)
	world.allow_roads = p.get("roads", 0) > 0 or p.get("unlimited", false)

	var noise := FastNoiseLite.new()
	noise.seed = int(p.seed)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0

	# Land: a rounded shape with a ragged coastline, kept in one piece.
	var centre := Vector2((w - 1) * 0.5, (h - 1) * 0.5)
	for y in h:
		for x in w:
			var n := Vector2((x - centre.x) / (w * 0.5), (y - centre.y) / (h * 0.5))
			var r := pow(absf(n.x), 3.0) + pow(absf(n.y), 3.0)
			if r + noise.get_noise_2d(x * 0.16, y * 0.16) * 0.3 < 0.8:
				world.terrain[y * w + x] = T.GRASS
	_keep_connected(world, Vector2i(centre))

	# Hills as terraces, never stepping more than one level at a time.
	# The ground climbs across the map, so a canal has to gain height somewhere.
	var hills: int = p.get("hills", 0)
	var slope := Vector2.from_angle(rng.randf() * TAU)
	for y in h:
		for x in w:
			var n := Vector2((x - centre.x) / (w * 0.5), (y - centre.y) / (h * 0.5))
			var v := n.dot(slope) * 0.8 + noise.get_noise_2d(x * 0.075 + 40.0, y * 0.075 + 40.0) * 0.6
			var lvl := 0
			if hills == 1:
				lvl = int(v > 0.05)
			elif hills >= 2:
				lvl = int(v > -0.2) + int(v > 0.3)
			world.heights[y * w + x] = lvl
	_relax_heights(world)
	for i in w * h:
		world.max_height = maxi(world.max_height, world.heights[i])

	# Woods and rocky outcrops.
	var woods: float = p.get("woods", 0.5)
	for y in h:
		for x in w:
			var i := y * w + x
			if world.terrain[i] != T.GRASS:
				continue
			if noise.get_noise_2d(x * 0.13 + 90.0, y * 0.13) > 0.52 - woods * 0.5:
				world.terrain[i] = T.WOOD
			if noise.get_noise_2d(x * 0.3, y * 0.3 + 170.0) > 0.6:
				world.terrain[i] = T.ROCK

	var edge := _edge_cells(world)
	if edge.size() < 8:
		return null

	# Canal portals, spread around the edge.
	var names := TOWNS.duplicate()
	_shuffle(names, rng)
	var count: int = p.get("portals", 2)
	var base := rng.randf() * TAU
	var taken: Array[Vector2i] = []
	for i in count:
		var ang := base + TAU * i / count + rng.randf_range(-0.25, 0.25)
		var e := _edge_at_angle(world, edge, ang, centre, taken, 5)
		if e.is_empty():
			return null
		var c: Vector2i = e.cell
		var inner: Vector2i = c - e.dir
		taken.append(c)
		for cell: Vector2i in [c, inner, inner - e.dir]:
			if world.in_bounds(cell):
				world.terrain[world.idx(cell)] = T.GRASS
		world.heights[world.idx(c)] = world.heights[world.idx(inner)]
		world.add_fixed_link(c, inner, L.CANAL)
		world.portals.append({"cell": c, "dir": e.dir, "name": names[i % names.size()]})

	# A river winding across the map.
	if p.get("river", false):
		var a := _edge_at_angle(world, edge, base + 0.9, centre, taken, 4)
		if not a.is_empty():
			taken.append(a.cell)
		var b := _edge_at_angle(world, edge, base + 0.9 + PI + rng.randf_range(-0.5, 0.5), centre, taken, 4)
		if not a.is_empty() and not b.is_empty():
			taken.append(b.cell)
			var course := _wander(world, a.cell, b.cell, noise, 300.0, true)
			if course.size() > 3:
				for c in course:
					world.terrain[world.idx(c)] = T.RIVER
				world.rivers.append(course)
				world.open_ends[a.cell] = a.dir
				world.open_ends[b.cell] = b.dir

	# Existing roads.
	for i in int(p.get("roads", 0)):
		var ang := base + 1.9 + i * 1.3
		var a := _edge_at_angle(world, edge, ang, centre, taken, 4)
		if a.is_empty():
			continue
		taken.append(a.cell)
		var b := _edge_at_angle(world, edge, ang + PI + rng.randf_range(-0.6, 0.6), centre, taken, 4)
		if b.is_empty():
			continue
		taken.append(b.cell)
		var line := _wander(world, a.cell, b.cell, noise, 500.0 + i * 50.0, false)
		for j in range(1, line.size()):
			world.add_fixed_link(line[j - 1], line[j], L.ROAD)
		for c in line:
			if world.terrain[world.idx(c)] != T.RIVER:
				world.terrain[world.idx(c)] = T.GRASS
		if line.size() > 1:
			world.open_ends[a.cell] = a.dir
			world.open_ends[b.cell] = b.dir
	world.recompute()

	# The "obvious" canal line between the portals; parts of it survive as
	# derelict canal, and places are sited a short walk away from it.
	var ideal := {}
	var share: float = p.get("derelict", 0.0)
	for i in range(1, count):
		var line := _wander(world, world.portals[0].cell - world.portals[0].dir,
			world.portals[i].cell - world.portals[i].dir, noise, 700.0, false, true)
		var run_left := 0
		var run_on := false
		for j in range(1, line.size()):
			ideal[line[j]] = true
			# Alternate surviving stretches with gaps, in proportion to `share`.
			if run_left <= 0:
				run_on = not run_on
				var stretch := rng.randi_range(4, 7)
				var kept := int(round(stretch * share))
				run_left = kept if run_on else stretch - kept
				if run_left <= 0:
					run_on = not run_on
					run_left = stretch
			run_left -= 1
			var a := line[j - 1]
			var b := line[j]
			if not run_on or world.height(a) != world.height(b) or world.link(a, b) != -1:
				continue
			if world.land_links(a) > 0 or world.land_links(b) > 0:
				continue
			if world.terrain_at(a) == T.RIVER or world.terrain_at(b) == T.RIVER:
				continue
			var d := b - a
			if d.x != 0 and d.y != 0 and world.link(Vector2i(a.x + d.x, a.y), Vector2i(a.x, a.y + d.y)) != -1:
				continue
			world.add_fixed_link(a, b, L.DERELICT)
			for c: Vector2i in [a, b]:
				world.terrain[world.idx(c)] = T.GRASS
		if not line.is_empty():
			ideal[line[0]] = true
	world.recompute()

	_site_places(world, rng, int(p.get("places", 0)), ideal.keys(), 2, 4, L.PATH)
	var road_cells := []
	for c in world.adj:
		if world.land_links(c) > 0:
			road_cells.append(c)
	if not road_cells.is_empty():
		_site_places(world, rng, int(p.get("farms", 0)), road_cells, 2, 4, L.ROAD, ideal)
	world.recompute()
	return world


# --- Helpers ----------------------------------------------------------------

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _keep_connected(world: World, from: Vector2i) -> void:
	var seen := {}
	var queue: Array[Vector2i] = []
	if world.in_bounds(from):
		seen[from] = true
		queue.append(from)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in World.DIRS4:
			if world.in_bounds(c + d) and not seen.has(c + d):
				seen[c + d] = true
				queue.append(c + d)
	for y in world.h:
		for x in world.w:
			if not seen.has(Vector2i(x, y)):
				world.terrain[y * world.w + x] = T.VOID


static func _relax_heights(world: World) -> void:
	var changed := true
	while changed:
		changed = false
		for y in world.h:
			for x in world.w:
				var c := Vector2i(x, y)
				if not world.in_bounds(c):
					continue
				for d in World.DIRS8:
					if world.in_bounds(c + d) and world.height(c) - world.height(c + d) > 1:
						world.heights[world.idx(c)] -= 1
						changed = true


# Land cells with the open edge of the map on one side: [{cell, dir}].
static func _edge_cells(world: World) -> Array:
	var out := []
	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			if not world.in_bounds(c):
				continue
			for d in World.DIRS4:
				if not world.in_bounds(c + d) and world.in_bounds(c - d) and world.in_bounds(c - d * 2):
					out.append({"cell": c, "dir": d})
					break
	return out


static func _edge_at_angle(world: World, edge: Array, ang: float, centre: Vector2,
		taken: Array[Vector2i], min_gap: int) -> Dictionary:
	var best := {}
	var best_diff := 99.0
	for e in edge:
		var c: Vector2i = e.cell
		var clear := true
		for t in taken:
			if maxi(absi(t.x - c.x), absi(t.y - c.y)) < min_gap:
				clear = false
		if not clear:
			continue
		var v := Vector2(c) - centre
		var diff := absf(angle_difference(ang, atan2(v.y / world.h, v.x / world.w)))
		if diff < best_diff:
			best_diff = diff
			best = e
	return best


# A meandering line of cells from a to b. Rivers keep to 4 directions and
# low ground; canal and road lines may run diagonally.
static func _wander(world: World, a: Vector2i, b: Vector2i, noise: FastNoiseLite, offset: float,
		river: bool, canal := false) -> Array[Vector2i]:
	var dist := {a: 0.0}
	var prev := {}
	var open: Array[Vector2i] = [a]
	var done := {}
	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if dist[open[i]] < dist[open[best]]:
				best = i
		var c := open[best]
		open.remove_at(best)
		if done.has(c):
			continue
		done[c] = true
		if c == b:
			break
		for d in (World.DIRS4 if river else World.DIRS8):
			var n := c + d
			if done.has(n) or not world.in_bounds(n):
				continue
			var dh := absi(world.height(c) - world.height(n))
			if dh > 1 or world.building(n) != B.NONE:
				continue
			var diagonal := d.x != 0 and d.y != 0
			if diagonal and world.link(Vector2i(c.x + d.x, c.y), Vector2i(c.x, c.y + d.y)) != -1:
				continue
			var cost := (1.4 if diagonal else 1.0) + (noise.get_noise_2d(n.x * 0.25 + offset, n.y * 0.25) + 1.0) * 1.6
			if world.terrain_at(n) == T.ROCK:
				cost += 30.0 if canal else 4.0
			if river:
				cost += world.height(n) * 2.0 + (8.0 if world.adj.has(n) or _near_portal(world, n) else 0.0)
			if canal:
				cost += dh * 5.0
				if world.terrain_at(n) == T.ROCK:
					continue
				if n != b and _near_portal(world, n, 0):
					continue
			else:
				cost += dh * 1.5
			if not dist.has(n) or dist[c] + cost < dist[n]:
				dist[n] = dist[c] + cost
				prev[n] = c
				open.append(n)
	var path: Array[Vector2i] = []
	if not prev.has(b):
		return path
	var cur := b
	while cur != a:
		path.append(cur)
		cur = prev[cur]
	path.append(a)
	path.reverse()
	if not canal:
		for c in path:
			if world.terrain_at(c) == T.ROCK:
				world.terrain[world.idx(c)] = T.GRASS
	return path


static func _near_portal(world: World, c: Vector2i, reach := 1) -> bool:
	for p in world.portals:
		if maxi(absi(p.cell.x - c.x), absi(p.cell.y - c.y)) <= reach:
			return true
	return false


# Puts `count` places on open grass between `near` and `far` cells from the
# anchor cells, spaced apart from each other.
static func _site_places(world: World, rng: RandomNumberGenerator, count: int, anchors: Array,
		near: int, far: int, need: int, avoid := {}) -> void:
	if count <= 0 or anchors.is_empty():
		return
	var spots: Array[Vector2i] = []
	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			if world.terrain_at(c) != T.GRASS or world.adj.has(c) or avoid.has(c) or world.building(c) != B.NONE:
				continue
			var open_land := true
			for d in World.DIRS8:
				open_land = open_land and world.in_bounds(c + d)
			var nearest := 99
			for a: Vector2i in anchors:
				nearest = mini(nearest, maxi(absi(a.x - c.x), absi(a.y - c.y)))
			if open_land and nearest >= near and nearest <= far:
				spots.append(c)
	_shuffle(spots, rng)
	var placed := 0
	for c in spots:
		if placed >= count:
			break
		var clear := true
		for other in world.places:
			if maxi(absi(other.cell.x - c.x), absi(other.cell.y - c.y)) < 4:
				clear = false
		if not clear:
			continue
		var kind: int = B.FARM
		var label: String = FARMS[placed % FARMS.size()]
		if need == L.PATH:
			var choice: Array = PATH_PLACES[placed % PATH_PLACES.size()]
			kind = choice[0]
			label = choice[1][rng.randi_range(0, choice[1].size() - 1)]
		world.bld[world.idx(c)] = kind
		world.bld_fixed[world.idx(c)] = 1
		world.places.append({"cell": c, "kind": kind, "need": need, "name": label, "ok": false})
		placed += 1
