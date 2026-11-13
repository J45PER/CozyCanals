extends SceneTree
## Drives the real scene with synthetic taps to check the menu, touch
## drawing and the HUD. Needs a display: xvfb-run godot -s tests/test_input.gd

const World := preload("res://scripts/world.gd")
const AutoBuild := preload("res://scripts/autobuild.gd")
const T := World.Tool
const L := World.L

var main: Node
var ok := true


func _init() -> void:
	_run.call_deferred()


func _expect(label: String, cond: bool) -> void:
	print("%s: %s" % [label, "ok" if cond else "FAIL"])
	ok = ok and cond


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	await process_frame
	await process_frame


## Press at the first point, drag through the rest, release.
func _drag(points: Array) -> void:
	await _mouse(points[0], true)
	for i in range(1, points.size()):
		for j in range(1, 9):
			var move := InputEventMouseMotion.new()
			move.position = (points[i - 1] as Vector2).lerp(points[i], j / 8.0)
			move.global_position = move.position
			move.relative = (points[i] - points[i - 1]) / 8.0
			move.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(move)
			await process_frame
	await _mouse(points[points.size() - 1], false)


func _tap_control(c: Control) -> void:
	await _drag([c.global_position + c.size * 0.5])


func _screen(c: Vector2i) -> Vector2:
	return main.view.position + main.view.cell_center(c) * main.view.scale.x


func _tool(id: int) -> Control:
	for b in main._tool_buttons:
		if b.tool_id == id:
			return b
	return null


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	_expect("menu shown", main.mode == "menu" and main._menu.visible)

	# Menu -> Journey -> level 1, all by tapping.
	await _tap_control(main._menu_home.get_child(3))
	_expect("level list opens", main._menu_levels.visible)
	await _tap_control(main._level_stars[0].get_parent().get_parent())
	_expect("level 1 starts", main.mode == "journey" and main.level_idx == 0 and not main._menu.visible)
	var world: World = main.world
	var start_coins := world.coins

	# Draw the whole canal by dragging a finger along a route, bends included.
	var from: Vector2i = world.portals[0].cell
	var target: Vector2i = world.portals[1].cell
	var path := AutoBuild.route(world, from, func(c): return c == target, L.CANAL)
	var points := []
	for c in path:
		points.append(_screen(c))
	await _drag(points)
	_expect("canal drawn by dragging", world.all_linked())
	_expect("coins spent", world.coins < start_coins and world.spent == start_coins - world.coins)
	var diagonal := false
	for i in range(1, path.size()):
		var d := path[i] - path[i - 1]
		diagonal = diagonal or (d.x != 0 and d.y != 0)
	_expect("route used diagonals", diagonal)

	# Path tool: walk the pub (or church) to the towpath.
	await _tap_control(_tool(T.PATH))
	_expect("path tool selected", main.tool == T.PATH)
	var place: Dictionary = world.places[0]
	var walk := AutoBuild.route(world, place.cell, func(c): return world.has_canal(c), L.PATH)
	points = []
	for c in walk:
		points.append(_screen(c))
	await _drag(points)
	_expect("place connected by path", world.places_ok == world.places.size())

	# A tap on the toolbar must not build on the land behind it.
	var before := world.version
	await _tap_control(_tool(T.CANAL))
	_expect("toolbar tap builds nothing", world.version == before and main.tool == T.CANAL)

	# Erase refunds: rub out one canal cell in the middle and get coins back.
	await _tap_control(_tool(T.ERASE))
	var coins := world.coins
	var mid := path[path.size() / 2]
	if world.fixed.has(world.key(mid, path[path.size() / 2 + 1])) and not world.restored.has(world.key(mid, path[path.size() / 2 + 1])):
		mid = path[path.size() / 2 + 2]
	await _drag([_screen(mid)])
	_expect("erase refunds and breaks the route", world.coins > coins and not world.all_linked())
	world.coins += 200
	AutoBuild.run(world)
	_expect("route rebuilt", world.all_linked())

	# Boats pass through, pay out, and the level completes and is saved.
	coins = world.coins
	await create_timer(26.0).timeout
	_expect("boat passed through and paid", world.coins > coins)
	_expect("completion panel shown", main._done.visible)
	var saved := ConfigFile.new()
	saved.load("user://save.cfg")
	_expect("stars saved", saved.get_value("journey", "0", 0) >= 2)

	# Other modes start cleanly.
	main.start_daily()
	await create_timer(0.3).timeout
	_expect("daily starts with a budget", main.mode == "daily" and main.world.coins > 0 and main.world.par > 0)
	main.start_free(3)
	await create_timer(0.3).timeout
	_expect("free build is unlimited with roads", main.world.unlimited and _tool(T.ROAD).visible)
	main.show_menu()
	await create_timer(0.3).timeout
	_expect("back to menu", main._menu.visible and main._level_stars[0].filled >= 2)

	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
