extends SceneTree
## Drives the real scene with synthetic taps to check touch input and the HUD.
## Needs a display: xvfb-run godot -s tests/test_input.gd

const T := preload("res://scripts/board.gd").Tool
const K := preload("res://scripts/board.gd").K


func _init() -> void:
	_run.call_deferred()


func _tap(pos: Vector2, drag_to := Vector2.INF) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	Input.parse_input_event(down)
	await process_frame
	if drag_to != Vector2.INF:
		for i in range(1, 21):
			var move := InputEventMouseMotion.new()
			move.position = pos.lerp(drag_to, i / 20.0)
			move.global_position = move.position
			move.relative = (drag_to - pos) / 20.0
			move.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(move)
			await process_frame
		pos = drag_to
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)
	await process_frame
	await process_frame


func _screen(main: Node, c: Vector2i) -> Vector2:
	return main.view.position + main.view.cell_center(c) * main.view.scale.x


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	var board = main.board
	var ok := true

	# Drag the canal tool along the whole silted line of level 1.
	await _tap(_screen(main, Vector2i(1, 3)), _screen(main, Vector2i(5, 3)))
	ok = ok and board.kind(Vector2i(1, 3)) == K.CANAL and board.kind(Vector2i(4, 3)) == K.CANAL
	print("drag-dig: ", board.kind(Vector2i(1, 3)) == K.CANAL, " coins=", board.coins)

	# Pick the bridge tool from the toolbar, then tap the lane crossing.
	var bridge_btn: Control = main._tool_buttons[3]
	await _tap(bridge_btn.global_position + bridge_btn.size * 0.5)
	ok = ok and main.tool == T.BRIDGE
	print("toolbar select: ", main.tool == T.BRIDGE)
	await _tap(_screen(main, Vector2i(6, 3)))
	ok = ok and board.kind(Vector2i(6, 3)) == K.BRIDGE
	print("bridge placed: ", board.kind(Vector2i(6, 3)) == K.BRIDGE)

	# Taps on the HUD must not build on tiles hidden behind it.
	var before: int = board.coins
	await _tap(main._tool_buttons[1].global_position + Vector2(40, 40))
	ok = ok and board.coins == before

	await _tap(_screen(main, Vector2i(7, 3)), _screen(main, Vector2i(9, 3)))
	ok = ok and not board.route.is_empty()
	print("route open: ", not board.route.is_empty())
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
