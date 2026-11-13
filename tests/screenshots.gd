extends SceneTree
## Renders each level (untouched and with a solved route) to PNG files.
## Run with: godot -s tests/screenshots.gd -- <output_dir>

const Solver := preload("res://tests/test_levels.gd")
const Levels := preload("res://scripts/levels.gd")
const T := preload("res://scripts/board.gd").Tool


func _init() -> void:
	_run.call_deferred()


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "."
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in Levels.LEVELS.size():
		main.load_level(i)
		await create_timer(0.3).timeout
		await _snap("%s/level%d_start.png" % [out, i + 1])
		var board = main.board
		Solver.build(board, Solver.solve(board))
		# Decorate a little so buildings and towpaths show up.
		board.coins += 400
		var built := {T.PUB: 0, T.CAFE: 0, T.COTTAGE: 0}
		for c in board.route:
			for d in board.DIRS:
				board.apply(T.TOWPATH, c + d)
		for y in board.h:
			for x in board.w:
				for tool in built:
					if built[tool] < 1 and (x + y) % 3 == tool % 3 and board.apply(tool, Vector2i(x, y)) == "":
						built[tool] += 1
		await create_timer(4.0).timeout
		await _snap("%s/level%d_built.png" % [out, i + 1])
	quit()
