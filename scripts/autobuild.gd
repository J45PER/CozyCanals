extends RefCounted
## Builds a sensible solution on a World using the same rules as the player.
## The map generator uses it to set budgets, and the tests use it to prove
## every map can be finished.

const World := preload("res://scripts/world.gd")
const L := World.L


## Cheapest chain of links of `type` from `start` to any cell accepted by
## `is_goal`, as a list of cells. Existing links of that type are free.
static func route(world: World, start: Vector2i, is_goal: Callable, type: int) -> Array[Vector2i]:
	var dist := {start: 0.0}
	var prev := {}
	var open: Array[Vector2i] = [start]
	var done := {}
	var found := Vector2i(-1, -1)
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
		if c != start and is_goal.call(c):
			found = c
			break
		for d in World.DIRS8:
			var n := c + d
			if done.has(n) or not world.in_bounds(n):
				continue
			var r := world.check_link(c, n, type)
			var cost := 0.01
			if r.err == "":
				cost = r.cost + 0.01
			elif r.err != "same":
				continue
			if not dist.has(n) or dist[c] + cost < dist[n]:
				dist[n] = dist[c] + cost
				prev[n] = c
				open.append(n)
	var path: Array[Vector2i] = []
	if found.x < 0:
		return path
	var cur := found
	while cur != start:
		path.append(cur)
		cur = prev[cur]
	path.append(start)
	path.reverse()
	return path


static func build(world: World, path: Array[Vector2i], type: int) -> bool:
	for i in range(1, path.size()):
		var err := world.add_link(path[i - 1], path[i], type)
		if err != "" and err != "same":
			return false
	return not path.is_empty()


## Joins every portal with canal. Returns false if any could not be reached.
static func link_portals(world: World) -> bool:
	for i in range(1, world.portals.size()):
		var target: Vector2i = world.portals[i].cell
		var path := route(world, world.portals[0].cell, func(c): return c == target, L.CANAL)
		if not build(world, path, L.CANAL):
			return false
	return true


## Gives every place the path or road it wants.
static func connect_places(world: World) -> bool:
	var ok := true
	for p in world.places:
		if p.ok:
			continue
		var path: Array[Vector2i]
		if p.need == L.ROAD:
			path = route(world, p.cell, func(c): return _on_fixed_road(world, c), L.ROAD)
		else:
			path = route(world, p.cell, func(c): return world.has_canal(c), L.PATH)
		ok = build(world, path, p.need) and ok
	return ok


static func _on_fixed_road(world: World, c: Vector2i) -> bool:
	for e in world.adj.get(c, []):
		if e[1] == L.ROAD and world.fixed.has(world.key(c, e[0])):
			return true
	return false


static func run(world: World) -> bool:
	return link_portals(world) and connect_places(world)
