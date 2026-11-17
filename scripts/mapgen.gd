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
##   roads     pairs of road ends for the player to join (the roads themselves are not built)
##   farms     farms wanting a road to an existing road
##   woods     0..1 woodland cover
##   budget    starting coins as a multiple of a sensible solution's cost
##   unlimited true for free building with no budget
##   cosy      [moorings, buildings, trees and hedges] the third star asks for

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
	var cosy: Array = p.get("cosy", [0, 0, 0])
	world.cosy = [int(cosy[0]), int(cosy[1]), int(cosy[2])]
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
	var hills := 0   # the land is flat; locks are decoration
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

	var placed := {}   # cells whose node has been set by a smoothed line

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
				_smooth(world, course, placed)
				for c in course:
					world.terrain[world.idx(c)] = T.RIVER
				world.rivers.append(course)
				world.open_ends[a.cell] = a.dir
				world.open_ends[b.cell] = b.dir

	# Road ends, for the player to join. Only the two ends are built: a short
	# stub at each edge. The line that would have joined them is remembered, so
	# farms can be sited along it.
	var road_line := {}
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
		if line.size() < 6:
			continue
		for e: Dictionary in [a, b]:
			var inner: Vector2i = e.cell - e.dir
			for cell: Vector2i in [e.cell, inner, inner - e.dir]:
				if world.in_bounds(cell) and world.terrain[world.idx(cell)] != T.RIVER:
					world.terrain[world.idx(cell)] = T.GRASS
			world.add_fixed_link(e.cell, inner, L.ROAD, "carriageway")
			world.open_ends[e.cell] = e.dir
		for c in line:
			road_line[c] = true
		world.road_sets.append({"a": {"cell": a.cell, "dir": a.dir}, "b": {"cell": b.cell, "dir": b.dir},
			"name": "%s road" % names[(count + i) % names.size()], "ok": false})
	world.recompute()

	# The "obvious" canal line between the portals; parts of it survive as
	# derelict canal, and places are sited a short walk away from it.
	var ideal := {}
	var share: float = p.get("derelict", 0.0)
	for i in range(1, count):
		var line := _wander(world, world.portals[0].cell - world.portals[0].dir,
			world.portals[i].cell - world.portals[i].dir, noise, 700.0, false, true)
		_smooth(world, line, placed)
		for c in line:
			ideal[c] = true
		_age_canal(world, line, share, rng)
	world.recompute()

	_site_places(world, rng, int(p.get("places", 0)), ideal.keys(), 2, 4, L.PATH)
	var road_cells := road_line.keys()
	if not road_cells.is_empty():
		_site_places(world, rng, int(p.get("farms", 0)), road_cells, 2, 4, L.ROAD, ideal)
	world.recompute()
	# Nodes only matter where a line passes.
	for c in world.offsets.keys():
		if not world.adj.has(c) and not world.river_next.has(c):
			world.offsets.erase(c)
	return world


# The original canal ran along `line`. Over time stretches of it were filled in
# or built over (gaps) and others silted up but survived (derelict): the
# surviving stretches are long and continuous, start and end at a break in the
# route, and never short stubs. Where the route meets a road or a river there
# is always a break, as the canal was culverted or bridged there.
static func _age_canal(world: World, line: Array[Vector2i], share: float, rng: RandomNumberGenerator) -> void:
	var n := line.size() - 1
	if n < 6 or share <= 0.0:
		return
	# Which links of the route could survive at all.
	var fine := []
	for j in n:
		var a := line[j]
		var b := line[j + 1]
		var ok := world.link(a, b) == -1 and world.land_links(a) == 0 and world.land_links(b) == 0
		ok = ok and world.terrain_at(a) != T.RIVER and world.terrain_at(b) != T.RIVER
		var d := b - a
		if d.x != 0 and d.y != 0 and world.link(Vector2i(a.x + d.x, a.y), Vector2i(a.x, a.y + d.y)) != -1:
			ok = false
		fine.append(ok)
	# Lay surviving stretches along the route until about `share` of it is old.
	var target := int(round(n * share))
	var chosen := PackedByteArray()
	chosen.resize(n)
	var covered := 0
	var tries := 0
	while covered < target and tries < 40:
		tries += 1
		var length := rng.randi_range(4, 9)
		var at := rng.randi_range(0, maxi(n - length, 0))
		var ok := true
		for j in range(at, mini(at + length, n)):
			ok = ok and fine[j]
		if ok and at + length <= n:
			var overlap := false
			for j in range(maxi(at - 1, 0), mini(at + length + 1, n)):
				overlap = overlap or chosen[j] == 1
			if not overlap:
				for j in range(at, at + length):
					chosen[j] = 1
				covered += length
	for j in n:
		if chosen[j] == 1:
			world.add_fixed_link(line[j], line[j + 1], L.DERELICT)
			for c: Vector2i in [line[j], line[j + 1]]:
				world.terrain[world.idx(c)] = T.GRASS


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
## A min-heap of (cost, state) pairs, for the route finder.
class Heap:
	var keys := PackedInt32Array()
	var costs := PackedFloat64Array()

	func is_empty() -> bool:
		return keys.is_empty()

	func push(key: int, cost: float) -> void:
		keys.append(key)
		costs.append(cost)
		var i := keys.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if costs[parent] <= costs[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> int:
		var top := keys[0]
		var last := keys.size() - 1
		keys[0] = keys[last]
		costs[0] = costs[last]
		keys.resize(last)
		costs.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < last and costs[l] < costs[m]:
				m = l
			if r < last and costs[r] < costs[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var k := keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var c := costs[a]
		costs[a] = costs[b]
		costs[b] = c


## Extra cost of turning by `k` eighth-turns: straight is free, a gentle bend
## is cheap, a sharp turn is very expensive. Real waterways and roads curve.
const TURN_COST := [0.0, 0.5, 3.0, 12.0, 40.0]


## A meandering route of cells from a to b. Moves are in eight directions and
## turning is penalised, so routes run in long gentle curves instead of
## stair-stepping. `river` and `canal` change what the ground costs.
static func _wander(world: World, a: Vector2i, b: Vector2i, noise: FastNoiseLite, offset: float,
		river: bool, canal := false) -> Array[Vector2i]:
	var w := world.w
	var h := world.h
	var states := w * h * 9
	var dist := PackedFloat32Array()
	dist.resize(states)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(states)
	prev.fill(-1)
	# Per-cell costs that don't depend on the direction of travel.
	var cell_cost := PackedFloat32Array()
	cell_cost.resize(w * h)
	var blocked := PackedByteArray()
	blocked.resize(w * h)
	for y in h:
		for x in w:
			var n := Vector2i(x, y)
			var i := y * w + x
			if not world.in_bounds(n) or world.building(n) != B.NONE:
				blocked[i] = 1
				continue
			var cost := (noise.get_noise_2d(x * 0.25 + offset, y * 0.25) + 1.0) * 1.6
			if world.terrain_at(n) == T.ROCK:
				if canal:
					blocked[i] = 1
				cost += 4.0
			if river and (world.adj.has(n) or _near_portal(world, n)):
				cost += 8.0
			if canal and n != b and _near_portal(world, n, 0):
				blocked[i] = 1
			cell_cost[i] = cost
	var heap := Heap.new()
	var start := (a.y * w + a.x) * 9 + 8
	dist[start] = 0.0
	heap.push(start, 0.0)
	var goal := -1
	while not heap.is_empty():
		var key := heap.pop()
		var cost_here := dist[key]
		var cell_i := key / 9
		var cx := cell_i % w
		var cy := cell_i / w
		var d0 := key % 9
		if cx == b.x and cy == b.y:
			goal = key
			break
		for di in 8:
			var d := World.DIRS8[di]
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h or blocked[ny * w + nx] == 1:
				continue
			var diagonal := d.x != 0 and d.y != 0
			if diagonal and world.link(Vector2i(cx + d.x, cy), Vector2i(cx, cy + d.y)) != -1:
				continue
			var step := (1.4 if diagonal else 1.0) + cell_cost[ny * w + nx]
			if d0 < 8:
				var k := absi(d0 - di)
				step += TURN_COST[mini(k, 8 - k)]
			var nk := (ny * w + nx) * 9 + di
			var nc := cost_here + step
			if nc < dist[nk]:
				dist[nk] = nc
				prev[nk] = key
				heap.push(nk, nc)
	var path: Array[Vector2i] = []
	if goal < 0:
		return path
	var cur := goal
	while cur >= 0:
		var ci := cur / 9
		path.append(Vector2i(ci % w, ci / w))
		cur = prev[cur]
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


## Smooths a route: each cell's node (where the line passes through it) moves
## towards the middle of its neighbours' nodes, so corners round off into
## curves. Nodes stay inside their own cells. Cells already placed by an
## earlier line keep their node, so lines crossing share one.
static func _smooth(world: World, line: Array[Vector2i], placed: Dictionary) -> void:
	if line.size() < 3:
		return
	var pts: Array[Vector2] = []
	for c in line:
		pts.append(Vector2(c) + Vector2(0.5, 0.5))
	for it in 12:
		var next := pts.duplicate()
		for i in range(1, pts.size() - 1):
			next[i] = pts[i] * 0.5 + (pts[i - 1] + pts[i + 1]) * 0.25
		pts = next
	for i in line.size():
		var c := line[i]
		if placed.has(c) or i == 0 or i == line.size() - 1:
			continue
		world.offsets[c] = (pts[i] - Vector2(c)).clamp(Vector2(0.12, 0.12), Vector2(0.88, 0.88))
		placed[c] = true
