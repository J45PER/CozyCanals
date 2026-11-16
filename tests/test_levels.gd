extends SceneTree
## Headless check of the map generator and the rules.
## Run with: godot --headless -s tests/test_levels.gd

const World := preload("res://scripts/world.gd")
const MapGen := preload("res://scripts/mapgen.gd")
const AutoBuild := preload("res://scripts/autobuild.gd")
const Levels := preload("res://scripts/levels.gd")
const L := World.L


func _check(label: String, params: Dictionary) -> bool:
	var t0 := Time.get_ticks_msec()
	var world := MapGen.generate(params)
	var ms := Time.get_ticks_msec() - t0
	var again := MapGen.generate(params)
	var ok: bool = world.portals.size() == params.portals
	# Same seed, same map.
	ok = ok and again.terrain == world.terrain and again.coins == world.coins and again.links == world.links
	var wanted: int = params.get("places", 0) + params.get("farms", 0)
	ok = ok and world.places.size() <= wanted and world.places.size() >= mini(wanted, 1)
	ok = ok and world.linked == 1 and world.places_ok == 0 and world.charm == 0
	var budget := world.coins
	# Tapping old canal restores the whole unbroken stretch, and erasing puts it back.
	for k in world.links.keys():
		if world.links[k] == L.DERELICT:
			var cell := world.key_cells(k)[0]
			var run := world.derelict_run(cell).size()
			var result := world.restore_run(cell)
			ok = ok and run > 0 and result.err == "" and result.count == run and world.coins == budget - result.cost
			ok = ok and world.derelict_run(cell).is_empty() and world.is_old(world.key_cells(k)[0], world.key_cells(k)[1])
			for y in world.h:
				for x in world.w:
					world.erase(Vector2i(x, y))
			# Bulldozing gives back half.
			ok = ok and world.coins < budget and world.coins >= budget - result.cost and world.links == again.links
			break
	# Old canal only exists as long, continuous stretches of one route.
	var stubs := 0
	var seen_runs := {}
	for k in world.links:
		if world.links[k] == L.DERELICT:
			var cell := world.key_cells(k)[0]
			var run := world.derelict_run(cell)
			var id := world.key(run[0][0], run[0][1])
			if not seen_runs.has(id):
				seen_runs[id] = true
				if run.size() < 4:
					stubs += 1
	ok = ok and stubs == 0
	if stubs > 0:
		print("  short stubs of old canal: ", stubs)
	# A sensible solution fits the budget and earns the first two stars.
	ok = ok and AutoBuild.run(world) and world.all_linked() and world.stars() >= 2 and world.coins >= 0
	var wanted_roads: int = params.get("roads", 0)
	ok = ok and world.roads_ok == world.road_sets.size() and world.road_sets.size() <= wanted_roads
	# Roads are only ends: nothing joins them until the player builds it.
	ok = ok and world.finish() and world.stars() >= 2 and world.finished_stars == world.stars()
	var n := world.portals.size()
	ok = ok and world.pairs.size() == n * (n - 1) / 2
	var left := world.coins
	var locks := world.traffic.size()
	# Bulldozing everything the player built gives some coins back and
	# leaves the map as it started; the map's own places can't be knocked down.
	for y in world.h:
		for x in world.w:
			world.erase(Vector2i(x, y))
	ok = ok and world.coins > left and world.coins < budget and world.linked == 1 and world.links == again.links
	# The map's own buildings can come down too, at a price, and stop being goals.
	var place_cell: Vector2i = world.places[0].cell
	var n_places := world.places.size()
	var coins_before := world.coins
	ok = ok and world.bulldoze(place_cell) == "" and world.building(place_cell) == World.B.NONE
	ok = ok and world.places.size() == n_places - 1 and world.coins == coins_before - World.PLACE_DEMOLISH_COST
	# Where the canals start can never be cleared.
	ok = ok and world.check_bulldoze(world.portals[0].cell).what != "place"
	# Nothing can be built through woodland until it is cleared, which costs.
	var wood := Vector2i(-1, -1)
	for y in world.h:
		for x in world.w:
			if world.terrain_at(Vector2i(x, y)) == World.T.WOOD and wood.x < 0:
				wood = Vector2i(x, y)
	if wood.x >= 0:
		var n2: Vector2i = wood + Vector2i(1, 0)
		ok = ok and world.check_link(wood, n2, L.PATH).err.begins_with("Trees")
		var before := world.coins
		ok = ok and world.bulldoze(wood) == "" and world.coins == before - World.CLEAR_TREES_COST
	print("%-16s %s  %dx%d portals=%d places=%d boat routes=%d budget=%d left=%d  (%d ms)" % [
		label, "ok" if ok else "FAIL", world.w, world.h, n, world.places.size(),
		locks, budget, left, ms])
	return ok


func _init() -> void:
	var ok := true
	for params in Levels.JOURNEY:
		ok = _check(params.name, params) and ok
	for day in [1, 2, 3, 4, 5]:
		ok = _check("daily %d" % day, Levels.daily({"year": 2026, "month": 11, "day": day})) and ok

	# Free build: no budget, nothing is ever refused for lack of coins.
	var free := MapGen.generate(Levels.free_build(5))
	var built := free.unlimited and AutoBuild.run(free) and free.coins == 0
	ok = ok and built
	print("free build       %s  %dx%d" % ["ok" if free.all_linked() else "FAIL", free.w, free.h])
	ok = ok and free.all_linked()

	# Hedges along a road, a roundabout at a junction, and a road leading off the map.
	var extras := true
	var road_cell := Vector2i(-1, -1)
	for k in free.links:
		if free.links[k] == L.ROAD:
			var cells := free.key_cells(k)
			var e1: String = free.add_verge(cells[0], cells[1], "hedge")
			if e1 != "":
				print("  hedge: ", e1)
			extras = extras and e1 == ""
			extras = extras and free.add_verge(cells[0], cells[1], "wall") != ""
			for c in cells:
				if road_cell.x < 0 and free.link_dirs(c, [L.ROAD]).size() == 2 and not free.has_water(c):
					road_cell = c
			break
	if road_cell.x >= 0:
		var spur := false
		for d in World.DIRS8:
			var n := road_cell + d
			if not spur and free.in_bounds(n) and not free.adj.has(n) and free.terrain_at(n) == World.T.GRASS and free.building(n) == World.B.NONE:
				if free.add_link(road_cell, n, L.ROAD, "lane") == "":
					spur = true
		extras = extras and spur
		var e3: String = free.add_roundabout(road_cell)
		if e3 != "":
			print("  roundabout: ", e3)
		extras = extras and e3 == "" and free.roundabouts.has(road_cell)
	var edge_done := false
	for y in free.h:
		for x in free.w:
			var c := Vector2i(x, y)
			if edge_done or not free.in_bounds(c) or free.terrain_at(c) != World.T.GRASS or free.open_ends.has(c):
				continue
			for d in World.DIRS4:
				if not free.in_bounds(c + d) and free.in_bounds(c - d):
					var portal := false
					for p in free.portals:
						portal = portal or p.cell == c
					if not portal and not edge_done:
						extras = extras and free.add_exit(c, d, L.ROAD, "carriageway") == "" and free.exits.has(c)
						extras = extras and free.bulldoze(c) == "" and not free.exits.has(c)
						edge_done = true
	print("roads extras     %s  roundabout=%s exit=%s" % ["ok" if extras else "FAIL", road_cell.x >= 0, edge_done])
	ok = ok and extras and edge_done
	# Crossing water: a road may meet a canal squarely or at 45 degrees, never along it.
	var tiny := World.new()
	tiny.setup(9, 9)
	tiny.terrain.fill(World.T.GRASS)
	tiny.unlimited = true
	for x in range(1, 7):
		tiny.add_fixed_link(Vector2i(x, 4), Vector2i(x + 1, 4), L.CANAL)
	tiny.recompute()
	var angles := true
	angles = angles and tiny.add_link(Vector2i(3, 3), Vector2i(3, 4), L.ROAD) == ""
	angles = angles and tiny.add_link(Vector2i(3, 4), Vector2i(3, 5), L.ROAD) == ""
	angles = angles and tiny.add_link(Vector2i(5, 3), Vector2i(6, 4), L.PATH) == ""
	angles = angles and tiny.add_link(Vector2i(6, 4), Vector2i(7, 5), L.PATH) == ""
	var junction := tiny.add_link(Vector2i(2, 3), Vector2i(3, 4), L.PATH)
	angles = angles and junction != "" and junction != "same"
	var along := tiny.add_link(Vector2i(0, 4), Vector2i(1, 4), L.PATH)
	var along_land := tiny.add_link(Vector2i(2, 3), Vector2i(2, 4), L.CANAL)
	angles = angles and along != "" and along != "same"
	print("crossing angles  %s  (%s)" % ["ok" if angles else "FAIL", along])
	ok = ok and angles
	quit(0 if ok else 1)
