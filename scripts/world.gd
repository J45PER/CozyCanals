extends RefCounted
## Game state and rules for one map. No rendering in here, so it can be
## driven from tests, the map generator and the game alike.
##
## The land is a grid of cells. Canals, paths and roads are "links" between
## neighbouring cells in any of 8 directions, drawn by dragging. Canals leave
## the map through portals on the edge; the aim is to join every portal into
## one navigable network and give every place a way to reach it.

signal changed

enum T { GRASS, WOOD, ROCK, RIVER, VOID }
enum L { CANAL, DERELICT, PATH, ROAD }
enum B { NONE, COTTAGE, CAFE, PUB, CHURCH, FARM }
enum Tool { PAN, CANAL, PATH, ROAD, TREE, COTTAGE, CAFE, PUB, ERASE }

const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

const LINK_COST := {L.CANAL: 12, L.PATH: 2, L.ROAD: 6}
const DREDGE_COST := 4      # restoring derelict canal, or canalising a river
const LOCK_COST := 25
const BRIDGE_COST := 20
const TREE_COST := 2
const BUILD_COST := {Tool.COTTAGE: 25, Tool.CAFE: 35, Tool.PUB: 50}
const TOOL_BUILDING := {Tool.COTTAGE: B.COTTAGE, Tool.CAFE: B.CAFE, Tool.PUB: B.PUB}
const TOOL_LINK := {Tool.CANAL: L.CANAL, Tool.PATH: L.PATH, Tool.ROAD: L.ROAD}
const CHARM := {B.COTTAGE: 4, B.CAFE: 6, B.PUB: 8}
const LOCK_CHARM := 2
const BRIDGE_CHARM := 3

var title := ""
var blurb := ""
var w := 0
var h := 0
var terrain := PackedInt32Array()
var heights := PackedInt32Array()
var bld := PackedInt32Array()
var bld_fixed := PackedByteArray()     # 1 where the building came with the map
var planted := PackedByteArray()       # 1 where the player planted trees
var cell_paid := PackedInt32Array()
var max_height := 0

var links := {}       # edge key -> L
var fixed := {}       # edge key -> true for links that came with the map
var paid := {}        # edge key -> coins spent on it
var restored := {}    # edge key -> true where derelict canal was restored

var portals: Array = []     # [{cell, dir, name}] canals running off the map
var places: Array = []      # [{cell, kind, need, name, ok}] to be connected
var rivers: Array = []      # [Array[Vector2i]] river courses, for drawing
var open_ends := {}         # cell -> direction a road or river runs off the map

var coins := 0
var spent := 0
var par := 0            # what a sensible solution spends; beat it for the medal
var unlimited := false
var allow_roads := false
var charm_goal := 0

# Derived state, refreshed by recompute().
var adj := {}               # cell -> [[neighbour cell, L], ...]
var pairs: Array = []       # [i, j] portal indices joined by navigable water
var linked := 1             # size of the largest group of joined portals
var network := {}           # cells on the routes between joined portals
var places_ok := 0
var charm := 0
var version := 0            # bumped on every change
var net_version := 0        # bumped when navigable water changes


func setup(width: int, height_: int) -> void:
	w = width
	h = height_
	terrain.resize(w * h)
	heights.resize(w * h)
	heights.fill(0)
	bld.resize(w * h)
	bld.fill(0)
	cell_paid.resize(w * h)
	cell_paid.fill(0)
	bld_fixed.resize(w * h)
	bld_fixed.fill(0)
	planted.resize(w * h)
	planted.fill(0)
	terrain.fill(T.VOID)


# --- Cells ------------------------------------------------------------------

func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


## True for cells that are part of the land.
func in_bounds(c: Vector2i) -> bool:
	return inside(c) and terrain[c.y * w + c.x] != T.VOID


func terrain_at(c: Vector2i) -> int:
	return terrain[c.y * w + c.x] if inside(c) else T.VOID


func height(c: Vector2i) -> int:
	return heights[c.y * w + c.x] if in_bounds(c) else 0


func building(c: Vector2i) -> int:
	return bld[c.y * w + c.x] if inside(c) else B.NONE


# --- Links ------------------------------------------------------------------

func key(a: Vector2i, b: Vector2i) -> int:
	var ia := idx(a)
	var ib := idx(b)
	return mini(ia, ib) * w * h + maxi(ia, ib)


func key_cells(k: int) -> Array[Vector2i]:
	var n := w * h
	var ia := k / n
	var ib := k % n
	return [Vector2i(ia % w, ia / w), Vector2i(ib % w, ib / w)]


func link(a: Vector2i, b: Vector2i) -> int:
	return links.get(key(a, b), -1) if inside(a) and inside(b) else -1


## Directions from `c` along links of any of the given types.
func link_dirs(c: Vector2i, types: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in adj.get(c, []):
		if e[1] in types:
			out.append(e[0] - c)
	return out


func has_water(c: Vector2i) -> bool:
	for e in adj.get(c, []):
		if e[1] == L.CANAL or e[1] == L.DERELICT:
			return true
	return false


func has_canal(c: Vector2i) -> bool:
	for e in adj.get(c, []):
		if e[1] == L.CANAL:
			return true
	return false


func land_links(c: Vector2i) -> int:
	var n := 0
	for e in adj.get(c, []):
		n += int(e[1] == L.PATH or e[1] == L.ROAD)
	return n


## A path or road crossing over a canal.
func is_bridge(c: Vector2i) -> bool:
	return has_water(c) and land_links(c) >= 2


## What adding a link would involve: {err, cost, lock, restore}.
## err is "" if allowed, "same" if the link already exists.
func check_link(a: Vector2i, b: Vector2i, type: int) -> Dictionary:
	var r := {"err": "", "cost": 0, "lock": false, "restore": false}
	if not in_bounds(a) or not in_bounds(b):
		r.err = "That's off the map"
		return r
	var d := b - a
	if maxi(absi(d.x), absi(d.y)) != 1:
		r.err = "Too far"
		return r
	var diagonal := d.x != 0 and d.y != 0
	var cur: int = links.get(key(a, b), -1)
	if cur == type:
		r.err = "same"
		return r
	if cur == L.DERELICT and type == L.CANAL:
		r.restore = true
		r.cost = _scaled(DREDGE_COST, diagonal)
	elif cur != -1:
		r.err = "Something already runs along here"
		return r
	else:
		if diagonal and link(Vector2i(a.x + d.x, a.y), Vector2i(a.x, a.y + d.y)) != -1:
			r.err = "Can't cross mid-way - meet at a point instead"
			return r
		var dh := absi(height(a) - height(b))
		if dh > 1:
			r.err = "Too steep here"
			return r
		for c: Vector2i in [a, b]:
			if terrain_at(c) == T.ROCK:
				r.err = "Solid rock - go around"
				return r
			if type == L.CANAL and building(c) != B.NONE:
				r.err = "There's a building in the way"
				return r
		var both_river := terrain_at(a) == T.RIVER and terrain_at(b) == T.RIVER
		var base: int = DREDGE_COST + 1 if (type == L.CANAL and both_river) else LINK_COST[type]
		r.cost = _scaled(base, diagonal)
		if type == L.CANAL and dh == 1:
			r.lock = true
			r.cost += LOCK_COST
		for c: Vector2i in [a, b]:
			if type == L.CANAL:
				if not has_water(c) and land_links(c) >= 2:
					r.cost += BRIDGE_COST
			else:
				if has_water(c) and land_links(c) == 1:
					r.cost += BRIDGE_COST
				if terrain_at(c) == T.RIVER and land_links(c) == 0:
					r.cost += BRIDGE_COST
	if not unlimited and r.cost > coins:
		r.err = "Not enough coins (%d needed)" % r.cost
	return r


static func _scaled(cost: int, diagonal: bool) -> int:
	return int(round(cost * 1.4)) if diagonal else cost


## Adds a link. Returns "" on success, "same" if already there, or a reason.
func add_link(a: Vector2i, b: Vector2i, type: int) -> String:
	var r := check_link(a, b, type)
	if r.err != "":
		return r.err
	var k := key(a, b)
	links[k] = type
	paid[k] = paid.get(k, 0) + r.cost
	if r.restore:
		restored[k] = true
	_spend(r.cost)
	for c: Vector2i in [a, b]:
		if terrain[idx(c)] == T.WOOD:
			terrain[idx(c)] = T.GRASS
			planted[idx(c)] = 0
	if type == L.CANAL:
		net_version += 1
	recompute()
	return ""


func _spend(cost: int) -> void:
	spent += cost
	if not unlimited:
		coins -= cost


func _refund(amount: int) -> void:
	spent -= amount
	if not unlimited:
		coins += amount


## Adds a link that is part of the map itself (cannot be erased).
func add_fixed_link(a: Vector2i, b: Vector2i, type: int) -> void:
	var k := key(a, b)
	links[k] = type
	fixed[k] = true


## Why a building or tree can't go here, or "".
func check_place(tool: int, c: Vector2i) -> String:
	if not in_bounds(c):
		return "That's off the map"
	if terrain_at(c) != T.GRASS or building(c) != B.NONE or adj.has(c):
		return "Needs open grass"
	var cost: int = TREE_COST if tool == Tool.TREE else BUILD_COST[tool]
	if tool != Tool.TREE:
		var beside := false
		for d in DIRS8:
			beside = beside or adj.has(c + d)
		if not beside:
			return "Build beside a canal, path or road"
	if not unlimited and cost > coins:
		return "Not enough coins (%d needed)" % cost
	return ""


func place(tool: int, c: Vector2i) -> String:
	var err := check_place(tool, c)
	if err != "":
		return err
	var i := idx(c)
	var cost: int = TREE_COST if tool == Tool.TREE else BUILD_COST[tool]
	if tool == Tool.TREE:
		terrain[i] = T.WOOD
		planted[i] = 1
	else:
		bld[i] = TOOL_BUILDING[tool]
	cell_paid[i] = cost
	_spend(cost)
	recompute()
	return ""


## Removes everything the player built on a cell, refunding it in full.
func erase(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var removed := false
	for e in adj.get(c, []).duplicate():
		var k := key(c, e[0])
		if fixed.has(k) and not restored.has(k):
			continue
		_refund(paid.get(k, 0))
		paid.erase(k)
		if restored.has(k):
			restored.erase(k)
			links[k] = L.DERELICT
		else:
			links.erase(k)
		if e[1] == L.CANAL:
			net_version += 1
		removed = true
	var i := idx(c)
	if (bld[i] != B.NONE and bld_fixed[i] == 0) or planted[i] == 1:
		_refund(cell_paid[i])
		cell_paid[i] = 0
		if planted[i] == 1:
			terrain[i] = T.GRASS
			planted[i] = 0
		bld[i] = B.NONE
		removed = true
	if removed:
		recompute()
	return removed


## Canal links that step between levels: [[lower cell, upper cell], ...].
func locks() -> Array:
	var out := []
	for k in links:
		if links[k] != L.CANAL:
			continue
		var cells := key_cells(k)
		var dh := height(cells[0]) - height(cells[1])
		if dh != 0:
			out.append([cells[1], cells[0]] if dh > 0 else cells)
	return out


# --- Goals ------------------------------------------------------------------

func boat_income() -> int:
	return 6 + maxi(charm, 0) / 3


func boat_arrived() -> int:
	var income := boat_income()
	if not unlimited:
		coins += income
	changed.emit()
	return income


func all_linked() -> bool:
	return linked == portals.size()


func stars() -> int:
	if not all_linked():
		return 0
	return 1 + int(places_ok == places.size()) + int(charm >= charm_goal)


## True once the map is finished without spending more than par.
func under_par() -> bool:
	return stars() >= 2 and par > 0 and spent <= par


func score() -> int:
	return stars() * 1000 + maxi(0, par * 2 - spent) + charm * 5


func recompute() -> void:
	version += 1
	adj.clear()
	for k in links:
		var cells := key_cells(k)
		for i in 2:
			if not adj.has(cells[i]):
				adj[cells[i]] = []
			adj[cells[i]].append([cells[1 - i], links[k]])

	pairs.clear()
	network.clear()
	var group_of := []
	for i in portals.size():
		group_of.append(i)
	for i in portals.size():
		for j in range(i + 1, portals.size()):
			var path := path_between(portals[i].cell, portals[j].cell)
			if path.is_empty():
				continue
			pairs.append([i, j])
			group_of[j] = group_of[i]
			for c in path:
				network[c] = true
	linked = 1
	var sizes := {}
	for g in group_of:
		sizes[g] = sizes.get(g, 0) + 1
		linked = maxi(linked, sizes[g])

	places_ok = 0
	for p in places:
		p.ok = _place_connected(p)
		places_ok += int(p.ok)

	charm = 0
	for i in w * h:
		if bld_fixed[i] == 0:
			charm += CHARM.get(bld[i], 0)
		charm += int(planted[i])
	for pair in locks():
		if not fixed.has(key(pair[0], pair[1])):
			charm += LOCK_CHARM
	for c in adj:
		if is_bridge(c):
			for e in adj[c]:
				if not fixed.has(key(c, e[0])):
					charm += BRIDGE_CHARM
					break
	changed.emit()


# A place wanting a PATH needs a walk (path or road) to working canal.
# A place wanting a ROAD needs a road to one of the map's own roads.
func _place_connected(p: Dictionary) -> bool:
	var allowed := [L.ROAD] if p.need == L.ROAD else [L.PATH, L.ROAD]
	var seen := {p.cell: true}
	var queue: Array = [p.cell]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c != p.cell:
			if p.need == L.PATH and has_canal(c):
				return true
			if p.need == L.ROAD:
				for e in adj.get(c, []):
					if e[1] == L.ROAD and fixed.has(key(c, e[0])):
						return true
		for e in adj.get(c, []):
			if e[1] in allowed and not seen.has(e[0]):
				seen[e[0]] = true
				queue.append(e[0])
	return false


## Shortest navigable route between two cells, or [] if there is none.
func path_between(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == to:
			break
		for e in adj.get(c, []):
			if e[1] == L.CANAL and not prev.has(e[0]):
				prev[e[0]] = c
				queue.append(e[0])
	var path: Array[Vector2i] = []
	if not prev.has(to):
		return path
	var cur := to
	while cur != from:
		path.append(cur)
		cur = prev[cur]
	path.append(from)
	path.reverse()
	return path
