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
	# A sensible solution fits the budget and earns the first two stars.
	ok = ok and AutoBuild.run(world) and world.all_linked() and world.stars() >= 2 and world.coins >= 0
	var n := world.portals.size()
	ok = ok and world.pairs.size() == n * (n - 1) / 2
	var left := world.coins
	var locks := world.locks().size()
	# Erasing everything the player built refunds every coin.
	for y in world.h:
		for x in world.w:
			world.erase(Vector2i(x, y))
	ok = ok and world.coins == budget and world.linked == 1 and world.links == again.links
	print("%-16s %s  %dx%d portals=%d places=%d locks=%d budget=%d left=%d  (%d ms)" % [
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
	quit(0 if ok else 1)
