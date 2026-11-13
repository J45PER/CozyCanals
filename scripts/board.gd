extends RefCounted
## Game state and rules for one level. No rendering in here, so it can be
## driven from tests as well as from the game.
##
## The map is a grid of cells, some of which are VOID (off the edge of the
## land). Canals leave the map through PORTAL cells on the edge; the aim is
## to link every portal into one navigable network.

signal changed

enum K { GRASS, TREE, ROCK, RIVER, DERELICT, LANE, CANAL, LOCK, BRIDGE, COTTAGE, CAFE, PUB, PORTAL, VOID }
enum Tool { PAN, CANAL, LOCK, BRIDGE, TOWPATH, TREE, COTTAGE, CAFE, PUB, CLEAR }

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const CHARM := {K.TREE: 1, K.LOCK: 2, K.BRIDGE: 3, K.COTTAGE: 4, K.CAFE: 6, K.PUB: 8}
const TOWPATH_GOAL := 80
const TOWPATH_COST := 3
const CHAR_KINDS := {
	".": K.GRASS, "t": K.TREE, "o": K.ROCK, "r": K.RIVER, "d": K.DERELICT,
	"l": K.LANE, "c": K.CANAL, "h": K.COTTAGE, "P": K.PORTAL, "#": K.VOID,
}

var title := ""
var blurb := ""
var w := 0
var h := 0
var kinds := PackedInt32Array()
var orig := PackedInt32Array()
var heights := PackedInt32Array()
var paid := PackedInt32Array()
var towpath := PackedByteArray()
var max_height := 0

var coins := 0
var charm_goal := 0
var base_charm := 0

## Where canals leave the map, the direction they leave in, and a place name.
var portals: Array[Vector2i] = []
var portal_dirs: Array[Vector2i] = []
var portal_names: Array = []

# Derived state, refreshed by recompute().
var pairs: Array = []            ## [i, j] portal indices joined by navigable water
var linked := 1                  ## size of the largest group of joined portals
var network := {}                ## cells on the routes between joined portals
var charm := 0
var towpath_pct := 0
## Bumped whenever the navigable water changes, so boats can be re-routed.
var net_version := 0


func load_level(data: Dictionary) -> void:
	title = data.name
	blurb = data.blurb
	coins = data.coins
	charm_goal = data.charm_goal
	portal_names = data.get("portals", [])
	var rows: Array = data.tiles
	h = rows.size()
	w = (rows[0] as String).length()
	kinds.resize(w * h)
	heights.resize(w * h)
	paid.resize(w * h)
	paid.fill(0)
	towpath.resize(w * h)
	towpath.fill(0)
	max_height = 0
	portals.clear()
	portal_dirs.clear()
	for y in h:
		for x in w:
			var i := y * w + x
			kinds[i] = CHAR_KINDS[(rows[y] as String)[x]]
			heights[i] = int((data.heights[y] as String)[x])
			max_height = maxi(max_height, heights[i])
			if kinds[i] == K.PORTAL:
				portals.append(Vector2i(x, y))
	for p in portals:
		portal_dirs.append(_edge_dir(p))
	orig = kinds.duplicate()
	base_charm = _total_charm()
	recompute()


# The direction in which a portal's canal runs off the map.
func _edge_dir(c: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	for d in DIRS:
		if in_bounds(c + d) or not in_bounds(c - d):
			continue
		if is_water(kind(c - d)):
			return d
		if best == Vector2i.ZERO:
			best = d
	return best


## True for cells that are part of the land (inside the grid and not VOID).
func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and kinds[c.y * w + c.x] != K.VOID


func kind(c: Vector2i) -> int:
	return kinds[c.y * w + c.x] if in_bounds(c) else K.VOID


func height(c: Vector2i) -> int:
	return heights[c.y * w + c.x] if in_bounds(c) else 0


func has_towpath(c: Vector2i) -> bool:
	return in_bounds(c) and towpath[c.y * w + c.x] == 1


func portal_dir(c: Vector2i) -> Vector2i:
	var i := portals.find(c)
	return portal_dirs[i] if i >= 0 else Vector2i.ZERO


static func is_navigable(k: int) -> bool:
	return k == K.CANAL or k == K.LOCK or k == K.BRIDGE or k == K.PORTAL


static func is_water(k: int) -> bool:
	return k == K.RIVER or k == K.DERELICT or is_navigable(k)


func is_player_built(c: Vector2i) -> bool:
	var i := c.y * w + c.x
	return kinds[i] != orig[i] or towpath[i] == 1


func was_lane(c: Vector2i) -> bool:
	return orig[c.y * w + c.x] == K.LANE


## True if a boat can move between two neighbouring cells.
func can_pass(a: Vector2i, b: Vector2i) -> bool:
	var ka := kind(a)
	var kb := kind(b)
	if not is_navigable(ka) or not is_navigable(kb):
		return false
	var dh := absi(height(a) - height(b))
	return dh == 0 or (dh == 1 and (ka == K.LOCK or kb == K.LOCK))


## Neighbouring navigable cells that sit on a different level with no lock
## joining them. Used to hint that a lock is needed.
func blocked_steps() -> Array:
	var out := []
	for y in h:
		for x in w:
			var a := Vector2i(x, y)
			if not is_navigable(kind(a)):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b := a + d
				if is_navigable(kind(b)) and height(a) != height(b) and not can_pass(a, b):
					out.append([a, b])
	return out


## Cost of using a tool on a tile of the given kind, or -1 if not allowed.
static func cost_for(tool: int, k: int) -> int:
	var soft := k == K.GRASS or k == K.TREE
	var silted := k == K.RIVER or k == K.DERELICT
	match tool:
		Tool.CANAL:
			return 5 if silted else (15 if soft else -1)
		Tool.LOCK:
			if k == K.CANAL:
				return 25
			return 30 if silted else (40 if soft else -1)
		Tool.BRIDGE:
			if k == K.CANAL:
				return 20
			return 35 if k == K.LANE else -1
		Tool.TOWPATH:
			return TOWPATH_COST if is_navigable(k) else -1
		Tool.TREE:
			return 2 if k == K.GRASS else -1
		Tool.COTTAGE:
			return 25 if k == K.GRASS else -1
		Tool.CAFE:
			return 35 if k == K.GRASS else -1
		Tool.PUB:
			return 50 if k == K.GRASS else -1
	return -1


static func result_kind(tool: int) -> int:
	match tool:
		Tool.CANAL: return K.CANAL
		Tool.LOCK: return K.LOCK
		Tool.BRIDGE: return K.BRIDGE
		Tool.TREE: return K.TREE
		Tool.COTTAGE: return K.COTTAGE
		Tool.CAFE: return K.CAFE
		Tool.PUB: return K.PUB
	return -1


## Returns "" if the tool can be used on the cell, otherwise a short reason.
func check(tool: int, c: Vector2i) -> String:
	if not in_bounds(c):
		return "Out of bounds"
	var k := kind(c)
	if tool == Tool.CLEAR:
		return "" if is_player_built(c) else "Nothing of yours to clear here"
	if k == K.ROCK:
		return "Solid rock - go around"
	var cost := cost_for(tool, k)
	if cost < 0:
		match tool:
			Tool.CANAL:
				return "Use a bridge to cross the lane" if k == K.LANE else "Can't dig here"
			Tool.LOCK:
				return "Locks go on the canal line"
			Tool.BRIDGE:
				return "Bridges go over a canal or lane"
			Tool.TOWPATH:
				return "Towpaths run beside a working canal"
			_:
				return "Needs open grass"
	if tool == Tool.TOWPATH and has_towpath(c):
		return "Already has a towpath"
	if tool == Tool.COTTAGE or tool == Tool.CAFE or tool == Tool.PUB:
		var beside := false
		for d in DIRS:
			var nk := kind(c + d)
			if is_navigable(nk) or nk == K.LANE:
				beside = true
		if not beside:
			return "Build beside the canal or a lane"
	if cost > coins:
		return "Not enough coins (%d needed)" % cost
	return ""


## Applies a tool. Returns "" on success or the reason it was refused.
func apply(tool: int, c: Vector2i) -> String:
	var err := check(tool, c)
	if err != "":
		return err
	var i := c.y * w + c.x
	var was_nav := is_navigable(kinds[i])
	var was_kind := kinds[i]
	if tool == Tool.CLEAR:
		coins += paid[i]
		paid[i] = 0
		kinds[i] = orig[i]
		towpath[i] = 0
	else:
		var cost := cost_for(tool, kinds[i])
		coins -= cost
		paid[i] += cost
		if tool == Tool.TOWPATH:
			towpath[i] = 1
		else:
			kinds[i] = result_kind(tool)
	if was_kind != kinds[i] and (was_nav or is_navigable(kinds[i])):
		net_version += 1
	recompute()
	return ""


func boat_income() -> int:
	return 8 + maxi(charm, 0) / 3


func boat_arrived() -> int:
	var income := boat_income()
	coins += income
	changed.emit()
	return income


func all_linked() -> bool:
	return linked == portals.size()


func stars() -> int:
	if not all_linked():
		return 0
	return 1 + int(towpath_pct >= TOWPATH_GOAL) + int(charm >= charm_goal)


func recompute() -> void:
	pairs.clear()
	network.clear()
	var group_size := {}
	var group_of := []
	for i in portals.size():
		group_of.append(i)
	for i in portals.size():
		for j in range(i + 1, portals.size()):
			var path := path_between(portals[i], portals[j])
			if path.is_empty():
				continue
			pairs.append([i, j])
			group_of[j] = group_of[i]
			for c in path:
				network[c] = true
	linked = 1
	for g in group_of:
		group_size[g] = group_size.get(g, 0) + 1
		linked = maxi(linked, group_size[g])
	charm = _total_charm() - base_charm
	var covered := 0
	for c in network:
		covered += int(has_towpath(c))
	towpath_pct = 0 if network.is_empty() else covered * 100 / network.size()
	changed.emit()


func _total_charm() -> int:
	var total := 0
	for k in kinds:
		total += CHARM.get(k, 0)
	return total


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
		for d in DIRS:
			var n := c + d
			if not prev.has(n) and can_pass(c, n):
				prev[n] = c
				queue.append(n)
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
