extends SceneTree
## Renders the menu and some levels (untouched and built) to PNG files.
## Run with: godot -s tests/screenshots.gd -- <output_dir> [level numbers...]

const AutoBuild := preload("res://scripts/autobuild.gd")
const T := preload("res://scripts/world.gd").Tool


func _init() -> void:
	_run.call_deferred()


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "."
	var picks := []
	for i in range(1, args.size()):
		picks.append(int(args[i]) - 1)
	if picks.is_empty():
		picks = [0, 3, 6]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(6.0).timeout
	await _snap("%s/menu.png" % out)
	for i in picks:
		main.start_journey(i)
		await create_timer(0.5).timeout
		await _snap("%s/level%d_start.png" % [out, i + 1])
		var world = main.world
		world.coins += 500
		AutoBuild.run(world)
		# Decorate a little so the player's buildings show up too.
		var built := {T.PUB: 0, T.CAFE: 0, T.COTTAGE: 0, T.TREE: 0, T.TERRACE: 0, T.SHOP: 0, T.BOATYARD: 0, T.WINDMILL: 0}
		for y in world.h:
			for x in world.w:
				for tool in built:
					if built[tool] < 2 and (x * 3 + y) % 5 == tool % 5 and world.place(tool, Vector2i(x, y)) == "":
						built[tool] += 1
		await create_timer(9.0).timeout
		main._done.hide()
		await _snap("%s/level%d_built.png" % [out, i + 1])
	quit()
