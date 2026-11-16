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
enum B { NONE, COTTAGE, TERRACE, SHOP, CAFE, PUB, BOATYARD, WINDMILL, CHURCH, FARM, MANOR, CARPARK, GARDEN }
enum Tool { PAN, CANAL, PATH, ROAD, TREE, COTTAGE, TERRACE, SHOP, CAFE, PUB, BOATYARD, WINDMILL, ERASE,
	RESTORE, LOCK_BRICK, LOCK_STONE, BRIDGE_BRICK, BRIDGE_STONE, BRIDGE_WOOD,
	ROAD_WIDE, PATH_TARMAC, PATH_DIRT, ROUNDABOUT, HEDGE_ROW, WALL_ROW, FENCE_ROW,
	CARPARK, GARDEN, MOORINGS, BASIN }

const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

const LINK_COST := {L.CANAL: 12, L.PATH: 2, L.ROAD: 6}
const DREDGE_COST := 4      # restoring derelict canal, or canalising a river
const BRIDGE_COST := 20
const TREE_COST := 2
const BUILD_COST := {Tool.COTTAGE: 25, Tool.TERRACE: 40, Tool.SHOP: 45, Tool.CAFE: 35, Tool.PUB: 50,
	Tool.BOATYARD: 60, Tool.WINDMILL: 70, Tool.CARPARK: 15, Tool.GARDEN: 20}
## Add-ons that join the plot of the building beside them.
const ADDONS := [B.CARPARK, B.GARDEN]
const TOOL_BUILDING := {Tool.COTTAGE: B.COTTAGE, Tool.TERRACE: B.TERRACE, Tool.SHOP: B.SHOP, Tool.CAFE: B.CAFE,
	Tool.PUB: B.PUB, Tool.BOATYARD: B.BOATYARD, Tool.WINDMILL: B.WINDMILL, Tool.CARPARK: B.CARPARK, Tool.GARDEN: B.GARDEN}
const TOOL_LINK := {Tool.CANAL: L.CANAL, Tool.PATH: L.PATH, Tool.ROAD: L.ROAD,
	Tool.ROAD_WIDE: L.ROAD, Tool.PATH_TARMAC: L.PATH, Tool.PATH_DIRT: L.PATH}
## Surface of each path or road tool, and what one length of it costs.
const TOOL_STYLE := {Tool.PATH: "gravel", Tool.PATH_TARMAC: "tarmac", Tool.PATH_DIRT: "dirt",
	Tool.ROAD: "lane", Tool.ROAD_WIDE: "carriageway"}
const STYLE_LINK_COST := {"gravel": 2, "tarmac": 4, "dirt": 1, "lane": 6, "carriageway": 10}
const STYLE_NAME := {"gravel": "gravel path", "tarmac": "tarmac path", "dirt": "dirt track",
	"lane": "lane", "carriageway": "road"}
## Tools that line a path or road with a hedge, wall or fence, and their cost a length.
const VERGE_TOOLS := {Tool.HEDGE_ROW: "hedge", Tool.WALL_ROW: "wall", Tool.FENCE_ROW: "fence"}
const VERGE_COST := {"hedge": 3, "wall": 4, "fence": 2}
const VERGE_CHARM := {"hedge": 1, "wall": 1, "fence": 0}
const ROUNDABOUT_COST := 30
const EXIT_COST := 15
const CLEAR_TREES_COST := 6
## Share of the cost given back when the player demolishes their own work.
const DEMOLISH_REFUND := 0.5
const CHARM := {B.COTTAGE: 4, B.TERRACE: 6, B.SHOP: 7, B.CAFE: 6, B.PUB: 8, B.BOATYARD: 9, B.WINDMILL: 10,
	B.GARDEN: 3}
## Canal features: moorings with bollards, and wide water (a winding hole).
const CANAL_FEATURES := {Tool.MOORINGS: "moorings", Tool.BASIN: "basin",
	Tool.LOCK_STONE: "lock_stone", Tool.LOCK_BRICK: "lock_brick"}
## Locks are decoration only: the land is flat, so boats never need them.
const FEATURE_COST := {"moorings": 10, "basin": 25, "lock_stone": 15, "lock_brick": 15}
const FEATURE_CHARM := {"moorings": 2, "basin": 3, "lock_stone": 2, "lock_brick": 2}
const FEATURE_NAME := {"moorings": "moorings", "basin": "wide water", "lock_stone": "a lock", "lock_brick": "a lock"}
## Knocking down a building that came with the map costs this.
const PLACE_DEMOLISH_COST := 40
const STYLE_COST := 10
## Tools that rebuild an existing bridge in another style.
const STYLE_TOOLS := {
	Tool.BRIDGE_BRICK: ["bridge", "brick"], Tool.BRIDGE_STONE: ["bridge", "stone"], Tool.BRIDGE_WOOD: ["bridge", "wood"],
}
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
var offsets := {}     # cell -> where in the cell (0..1) its lines meet; centre if absent
var styles := {}      # cell -> "brick", "stone" or "wood" for a lock or bridge rebuilt by the player
var style_paid := {}  # cell -> coins spent restyling it
var link_style := {}  # edge key -> path or road surface ("gravel", "lane", ...)
var verges := {}      # edge key -> "hedge", "wall" or "fence" lining a path or road
var roundabouts := {} # cell -> true
var exits := {}       # edge cell -> [direction, L, style] for a path or road leaving the map
var features := {}    # canal cell -> "moorings", "basin", "lock_stone" or "lock_brick"
var river_next := {}  # river cell -> neighbouring cells along the river (boats can use them)
var river_ends: Array = []   # [{cell, dir}] where rivers run off the map
var traffic: Array = []      # [[from, to], ...] water ends (canal portals, then river ends) joined by navigable water

var portals: Array = []     # [{cell, dir, name}] canals running off the map
var places: Array = []      # [{cell, kind, need, name, ok}] to be connected
var rivers: Array = []      # [Array[Vector2i]] river courses, for drawing
var open_ends := {}         # cell -> direction a road or river runs off the map

var coins := 0
var spent := 0
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


## Where the lines through a cell meet, in map coordinates. Lines follow the
## player's finger, so this is rarely the exact centre of the cell.
func node(c: Vector2i) -> Vector2:
	return Vector2(c) + offsets.get(c, Vector2(0.5, 0.5))


## True if the cell has nothing on it yet, so a new line may place its node freely.
func can_move_node(c: Vector2i) -> bool:
	if not in_bounds(c) or building(c) != B.NONE or adj.has(c) or terrain_at(c) == T.RIVER:
		return false
	for p in portals:
		if p.cell == c:
			return false
	return true


func set_offset(c: Vector2i, off: Vector2) -> void:
	offsets[c] = off.clamp(Vector2(0.2, 0.2), Vector2(0.8, 0.8))
	version += 1


## True for canal that predates the player: the map's own, or restored derelict.
func is_old(a: Vector2i, b: Vector2i) -> bool:
	var k := key(a, b)
	return fixed.has(k) or restored.has(k)


## Every derelict link joined to `c` in one unbroken stretch: [[a, b], ...].
func derelict_run(c: Vector2i) -> Array:
	var out := []
	var seen := {}
	var queue: Array = [c]
	var visited := {c: true}
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for e in adj.get(cur, []):
			if e[1] != L.DERELICT:
				continue
			var k := key(cur, e[0])
			if not seen.has(k):
				seen[k] = true
				out.append([cur, e[0]])
			if not visited.has(e[0]):
				visited[e[0]] = true
				queue.append(e[0])
	return out


## Restores the old, silted canal that runs through cell `c` (each length
## that touches it). Returns {count, cost, err}.
func restore_at(c: Vector2i) -> Dictionary:
	var todo := []
	var total := 0
	for e in adj.get(c, []):
		if e[1] == L.DERELICT:
			todo.append(e[0])
			total += _scaled(DREDGE_COST, e[0].x != c.x and e[0].y != c.y)
	if todo.is_empty():
		return {"count": 0, "cost": 0, "err": "No silted canal here"}
	if not unlimited and total > coins:
		return {"count": 0, "cost": total, "err": "Restoring this needs %d coins" % total}
	for n in todo:
		add_link(c, n, L.CANAL)
	return {"count": todo.size(), "cost": total, "err": ""}


## True if a path or road crosses water (canal or river) at `c`.
func has_bridge(c: Vector2i) -> bool:
	return is_bridge(c) or (terrain_at(c) == T.RIVER and land_links(c) > 0)


## Rebuilds the bridge at `c` in the tool's style. Returns "" or why not.
func restyle(tool: int, c: Vector2i) -> String:
	var style: String = STYLE_TOOLS[tool][1]
	if not has_bridge(c):
		return "Tap a bridge to rebuild it"
	if styles.get(c, "") == style:
		return "It's already built like that"
	if not unlimited and STYLE_COST > coins:
		return "Not enough coins (%d needed)" % STYLE_COST
	styles[c] = style
	style_paid[c] = style_paid.get(c, 0) + STYLE_COST
	_spend(STYLE_COST)
	recompute()
	return ""


## Restores the whole derelict stretch through `c`. Returns {count, cost, err}.
func restore_run(c: Vector2i) -> Dictionary:
	var run := derelict_run(c)
	var total := 0
	for pair in run:
		total += _scaled(DREDGE_COST, pair[0].x != pair[1].x and pair[0].y != pair[1].y)
	if run.is_empty():
		return {"count": 0, "cost": 0, "err": "No old canal here to restore"}
	if not unlimited and total > coins:
		return {"count": 0, "cost": total, "err": "Restoring this stretch needs %d coins" % total}
	for pair in run:
		add_link(pair[0], pair[1], L.CANAL)
	return {"count": run.size(), "cost": total, "err": ""}


## A path or road crossing over a canal.
func is_bridge(c: Vector2i) -> bool:
	return has_water(c) and land_links(c) >= 2


## What adding a link would involve: {err, cost, lock, restore}.
## err is "" if allowed, "same" if the link already exists.
func check_link(a: Vector2i, b: Vector2i, type: int, style := "") -> Dictionary:
	var r := {"err": "", "cost": 0, "restore": false}
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
		var have: String = link_style.get(key(a, b), "")
		if type == L.CANAL or style == "" or have == "" or have == style:
			r.err = "same"
		else:
			r.err = "There's a %s here - bulldoze it first" % STYLE_NAME.get(have, "path")
		return r
	if cur == L.DERELICT and type == L.CANAL:
		r.restore = true
		r.cost = _scaled(DREDGE_COST, diagonal)
	elif cur != -1:
		r.err = "Something already runs along here - bulldoze it first"
		return r
	else:
		if diagonal and link(Vector2i(a.x + d.x, a.y), Vector2i(a.x, a.y + d.y)) != -1:
			r.err = "Can't cross mid-way - meet at a point instead"
			return r
		for c: Vector2i in [a, b]:
			if terrain_at(c) == T.ROCK:
				r.err = "Solid rock - go around"
				return r
			if terrain_at(c) == T.WOOD:
				r.err = "Trees in the way - bulldoze them first"
				return r
			if type == L.CANAL and building(c) != B.NONE:
				r.err = "There's a building in the way"
				return r
		var both_river := terrain_at(a) == T.RIVER and terrain_at(b) == T.RIVER
		var base: int = DREDGE_COST + 1 if (type == L.CANAL and both_river) else STYLE_LINK_COST.get(style, LINK_COST[type])
		r.cost = _scaled(base, diagonal)
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
func add_link(a: Vector2i, b: Vector2i, type: int, style := "") -> String:
	if style == "" and type == L.PATH:
		style = "gravel"
	elif style == "" and type == L.ROAD:
		style = "lane"
	var r := check_link(a, b, type, style)
	if r.err != "":
		return r.err
	var k := key(a, b)
	links[k] = type
	if type == L.PATH or type == L.ROAD:
		link_style[k] = style
	paid[k] = paid.get(k, 0) + r.cost
	if r.restore:
		restored[k] = true
	_spend(r.cost)
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
func add_fixed_link(a: Vector2i, b: Vector2i, type: int, style := "") -> void:
	var k := key(a, b)
	links[k] = type
	fixed[k] = true
	if style != "":
		link_style[k] = style


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
		if tool == Tool.GARDEN or tool == Tool.CARPARK:
			var next_to := false
			for d in DIRS4:
				var k := building(c + d)
				next_to = next_to or (k != B.NONE and k not in ADDONS)
				if tool == Tool.CARPARK:
					next_to = next_to or not link_dirs(c + d, [L.ROAD]).is_empty()
			if not next_to:
				return "Put it next to a building%s" % (" or a road" if tool == Tool.CARPARK else "")
		elif not beside:
			return "Build beside a canal, path or road"
		if tool == Tool.BOATYARD:
			var waterside := false
			for d in DIRS8:
				waterside = waterside or has_canal(c + d)
			if not waterside:
				return "A boatyard needs working canal alongside"
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


## What bulldozing a cell would do: {what, coins} where coins is the refund
## (positive) or cost (negative), or what = "" if there is nothing to clear.
func check_bulldoze(c: Vector2i) -> Dictionary:
	if not in_bounds(c):
		return {"what": "", "coins": 0}
	var back := 0
	var any := false
	for e in adj.get(c, []):
		var k := key(c, e[0])
		if fixed.has(k) and not restored.has(k):
			continue
		back += paid.get(k, 0) + VERGE_COST.get(verges.get(k, ""), 0)
		any = true
	if styles.has(c):
		back += style_paid.get(c, 0)
		any = true
	if roundabouts.has(c):
		back += ROUNDABOUT_COST
		any = true
	if exits.has(c):
		back += EXIT_COST
		any = true
	if features.has(c):
		back += FEATURE_COST[features[c]]
		any = true
	var i := idx(c)
	if (bld[i] != B.NONE and bld_fixed[i] == 0) or planted[i] == 1:
		back += cell_paid[i]
		any = true
	if any:
		return {"what": "yours", "coins": int(back * DEMOLISH_REFUND)}
	if terrain[i] == T.WOOD:
		return {"what": "trees", "coins": -CLEAR_TREES_COST}
	if bld[i] != B.NONE:
		if _protected(c):
			return {"what": "protected", "coins": 0}
		return {"what": "place", "coins": -PLACE_DEMOLISH_COST}
	return {"what": "", "coins": 0}


# Where the map's canals, roads and rivers start and end: never cleared.
func _protected(c: Vector2i) -> bool:
	if open_ends.has(c):
		return true
	for p in portals:
		if p.cell == c:
			return true
	return false


## Clears a cell: the player's own work comes down for half its cost back;
## clearing woodland costs money. Returns "" or why not.
func bulldoze(c: Vector2i) -> String:
	var plan := check_bulldoze(c)
	match plan.what:
		"":
			return "Nothing here to bulldoze"
		"protected":
			return "The map's routes start here - it can't be knocked down"
		"place":
			if not unlimited and PLACE_DEMOLISH_COST > coins:
				return "Knocking down %s needs %d coins" % [_place_name(c), PLACE_DEMOLISH_COST]
			var gone := []
			for p in places:
				if p.cell == c:
					gone.append(p)
			for p in gone:
				places.erase(p)
			bld[idx(c)] = B.NONE
			bld_fixed[idx(c)] = 0
			_spend(PLACE_DEMOLISH_COST)
			recompute()
			return ""
		"trees":
			if not unlimited and CLEAR_TREES_COST > coins:
				return "Clearing trees needs %d coins" % CLEAR_TREES_COST
			terrain[idx(c)] = T.GRASS
			_spend(CLEAR_TREES_COST)
			recompute()
			return ""
	for e in adj.get(c, []).duplicate():
		var k := key(c, e[0])
		if fixed.has(k) and not restored.has(k):
			continue
		_refund_part(paid.get(k, 0) + VERGE_COST.get(verges.get(k, ""), 0))
		paid.erase(k)
		verges.erase(k)
		if restored.has(k):
			restored.erase(k)
			links[k] = L.DERELICT
		else:
			links.erase(k)
			link_style.erase(k)
		if e[1] == L.CANAL:
			net_version += 1
	if styles.has(c):
		_refund_part(style_paid.get(c, 0))
		styles.erase(c)
		style_paid.erase(c)
	if roundabouts.has(c):
		_refund_part(ROUNDABOUT_COST)
		roundabouts.erase(c)
	if exits.has(c):
		_refund_part(EXIT_COST)
		exits.erase(c)
	if features.has(c):
		_refund_part(FEATURE_COST[features[c]])
		if features[c].begins_with("lock_"):
			styles.erase(c)
		features.erase(c)
	var i := idx(c)
	if (bld[i] != B.NONE and bld_fixed[i] == 0) or planted[i] == 1:
		_refund_part(cell_paid[i])
		cell_paid[i] = 0
		if planted[i] == 1:
			terrain[i] = T.GRASS
			planted[i] = 0
		bld[i] = B.NONE
	recompute()
	for d in DIRS8 + [Vector2i.ZERO]:
		if not adj.has(c + d):
			offsets.erase(c + d)
	return ""


## Kept for older callers: bulldozes, returning whether anything came down.
func erase(c: Vector2i) -> bool:
	var plan := check_bulldoze(c)
	return plan.what == "yours" and bulldoze(c) == ""


func _refund_part(amount: int) -> void:
	# What was spent stays spent; only part of it comes back.
	if not unlimited:
		coins += int(amount * DEMOLISH_REFUND)


func _place_name(c: Vector2i) -> String:
	for p in places:
		if p.cell == c:
			return p.name
	return "This building"


## Lines a path or road with a hedge, wall or fence. Returns "", "same" or why not.
func add_verge(a: Vector2i, b: Vector2i, kind: String) -> String:
	var t := link(a, b)
	if t != L.PATH and t != L.ROAD:
		return "Hedges and walls go along a path or road"
	var k := key(a, b)
	if verges.get(k, "") == kind:
		return "same"
	if verges.has(k):
		return "There's already a %s here - bulldoze it first" % verges[k]
	if not unlimited and VERGE_COST[kind] > coins:
		return "Not enough coins (%d needed)" % VERGE_COST[kind]
	verges[k] = kind
	_spend(VERGE_COST[kind])
	recompute()
	return ""


## Adds moorings or wide water to a stretch of working canal.
func add_feature(c: Vector2i, kind: String) -> String:
	if not has_canal(c) or link_dirs(c, [L.CANAL]).size() + int(_portal_cell(c)) > 2:
		return "Moorings, locks and wide water go on a plain stretch of canal"
	if has_bridge(c):
		return "Not under a bridge"
	if features.has(c):
		return "There's already %s here - bulldoze it first" % FEATURE_NAME[features[c]]
	if not unlimited and FEATURE_COST[kind] > coins:
		return "Not enough coins (%d needed)" % FEATURE_COST[kind]
	features[c] = kind
	if kind.begins_with("lock_"):
		styles[c] = kind.trim_prefix("lock_")
	_spend(FEATURE_COST[kind])
	recompute()
	return ""


func _portal_cell(c: Vector2i) -> bool:
	for p in portals:
		if p.cell == c:
			return true
	return false


## Turns a road junction into a roundabout.
func add_roundabout(c: Vector2i) -> String:
	if link_dirs(c, [L.ROAD]).size() < 3:
		return "Roundabouts go where three or more roads meet"
	if roundabouts.has(c):
		return "There's already a roundabout here"
	if has_water(c):
		return "Not on a bridge"
	if not unlimited and ROUNDABOUT_COST > coins:
		return "Not enough coins (%d needed)" % ROUNDABOUT_COST
	roundabouts[c] = true
	_spend(ROUNDABOUT_COST)
	recompute()
	return ""


## Carries a path or road off the edge of the map from edge cell `c`.
func add_exit(c: Vector2i, d: Vector2i, type: int, style: String) -> String:
	if not in_bounds(c) or in_bounds(c + d) or maxi(absi(d.x), absi(d.y)) != 1 or (d.x != 0 and d.y != 0):
		return "Paths and roads leave the map from its edge"
	if exits.has(c) or open_ends.has(c):
		return "Something already leaves the map here"
	for p in portals:
		if p.cell == c:
			return "The canal leaves the map here"
	if terrain_at(c) == T.WOOD:
		return "Trees in the way - bulldoze them first"
	if not unlimited and EXIT_COST > coins:
		return "Not enough coins (%d needed)" % EXIT_COST
	exits[c] = [d, type, style]
	_spend(EXIT_COST)
	recompute()
	return ""


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


func score() -> int:
	return stars() * 1000 + coins + charm * 5


func _index_rivers() -> void:
	river_next.clear()
	river_ends.clear()
	for course in rivers:
		for i in course.size():
			var c: Vector2i = course[i]
			var next: Array[Vector2i] = []
			if i > 0:
				next.append(course[i - 1])
			if i < course.size() - 1:
				next.append(course[i + 1])
			river_next[c] = next
		for c: Vector2i in [course[0], course[course.size() - 1]]:
			if open_ends.has(c):
				river_ends.append({"cell": c, "dir": open_ends[c]})


## Every place boats enter and leave the map: the canals' portals, then rivers.
func water_ends() -> Array:
	var out := []
	for p in portals:
		out.append({"cell": p.cell, "dir": p.dir})
	out.append_array(river_ends)
	return out


func recompute() -> void:
	version += 1
	if river_next.is_empty() and not rivers.is_empty():
		_index_rivers()
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
	traffic.clear()
	var ends := water_ends()
	for i in ends.size():
		for j in range(i + 1, ends.size()):
			if not path_between(ends[i].cell, ends[j].cell).is_empty():
				traffic.append([i, j])
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
	for k in verges:
		charm += VERGE_CHARM.get(verges[k], 0)
	for c in features:
		charm += FEATURE_CHARM.get(features[c], 0)
	for c in adj:
		if is_bridge(c):
			for e in adj[c]:
				if not fixed.has(key(c, e[0])):
					charm += BRIDGE_CHARM
					break
	changed.emit()


# A place wanting a PATH needs a walk (path or road) to working canal.
# A place wanting a ROAD needs a road to one of the map's own roads, or a
# road the player has carried off the edge of the map.
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
				if exits.has(c) and exits[c][1] == L.ROAD:
					return true
				for e in adj.get(c, []):
					if e[1] == L.ROAD and fixed.has(key(c, e[0])):
						return true
		for e in adj.get(c, []):
			if e[1] in allowed and not seen.has(e[0]):
				seen[e[0]] = true
				queue.append(e[0])
	return false


## Cells a boat can move to from `c`: along canal, and along a river's course.
func water_next(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in adj.get(c, []):
		if e[1] == L.CANAL:
			out.append(e[0])
	for n in river_next.get(c, []):
		out.append(n)
	return out


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
		for n in water_next(c):
			if not prev.has(n):
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
