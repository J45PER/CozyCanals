extends Node2D
## Game controller: owns the board, handles touch/mouse input and the HUD.

const Board := preload("res://scripts/board.gd")
const BoardView := preload("res://scripts/board_view.gd")
const Levels := preload("res://scripts/levels.gd")
const ToolButton := preload("res://scripts/tool_button.gd")
const T := Board.Tool

const INK := Color("4a3b2e")
const MUTED := Color("8a7860")
const CREAM := Color("fbf3df")
const EDGE := Color("d8c49a")
const GOLD := Color("f2b632")

## Tools that keep building as you drag across tiles.
const DRAG_TOOLS := [T.CANAL, T.TOWPATH, T.TREE, T.CLEAR]
const TOOLS := [
	[T.PAN, "Move", "drag map"],
	[T.CANAL, "Canal", "5 / 15"],
	[T.LOCK, "Lock", "25 - 40"],
	[T.BRIDGE, "Bridge", "20 / 35"],
	[T.TOWPATH, "Towpath", "3"],
	[T.TREE, "Tree", "2"],
	[T.COTTAGE, "Cottage", "25"],
	[T.CAFE, "Cafe", "35"],
	[T.PUB, "Pub", "50"],
	[T.CLEAR, "Clear", "refunds"],
]


class StarIcon extends Control:
	var on := false:
		set(v):
			on = v
			queue_redraw()

	func _init(px: float) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + TAU * i / 10.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, Color("f2b632") if on else Color("d9ceb4"))


class CoinIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, 11, Color("d9982b"))
		draw_circle(size * 0.5, 8, Color("f6c94c"))


var board: Board
var view: BoardView
var level_idx := 0
var tool: int = T.CANAL

var _touches := {}
var _painting := false
var _last_cell := Vector2i(-1, -1)
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _was_open := false
var _celebrated := false

var _hud: Control
var _title: Label
var _blurb: Label
var _coins: Label
var _goal_stars: Array[StarIcon] = []
var _goal_labels: Array[Label] = []
var _tool_buttons: Array[ToolButton] = []
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _done: PanelContainer
var _done_title: Label
var _done_text: Label
var _done_stars: Array[StarIcon] = []
var _done_next: Button


func _ready() -> void:
	view = BoardView.new()
	add_child(view)
	view.boat_arrived.connect(_on_boat_arrived)
	_build_hud()
	get_viewport().size_changed.connect(_fit_view)
	load_level(0)


func load_level(idx: int) -> void:
	level_idx = posmod(idx, Levels.LEVELS.size())
	board = Board.new()
	board.load_level(Levels.LEVELS[level_idx])
	board.changed.connect(_refresh)
	view.set_board(board)
	_was_open = false
	_celebrated = false
	_done.hide()
	_title.text = "%d. %s" % [level_idx + 1, board.title]
	_blurb.text = board.blurb
	_fit_view()
	_refresh()


func _fit_view() -> void:
	if board == null:
		return
	var vp := get_viewport_rect().size
	var area := Rect2(24, 56, vp.x - 48, vp.y - 56 - 124)
	var b := view.bounds()
	var s := minf(minf(area.size.x / b.size.x, area.size.y / b.size.y), 1.5)
	view.scale = Vector2(s, s)
	view.position = area.get_center() - b.get_center() * s


func _zoom_at(point: Vector2, factor: float) -> void:
	var old := view.scale.x
	var s := clampf(old * factor, 0.4, 2.5)
	var local := (point - view.position) / old
	view.scale = Vector2(s, s)
	view.position = point - local * s


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_pinch_dist = 0.0
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1 and tool != T.PAN:
				_painting = true
				_last_cell = Vector2i(-1, -1)
				_use_tool(event.position, true)
			else:
				_painting = false
		else:
			_touches.erase(event.index)
			_painting = false
			view.hover = Vector2i(-1, -1)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var pts := _touches.values()
			var mid: Vector2 = (pts[0] + pts[1]) * 0.5
			var dist: float = pts[0].distance_to(pts[1])
			if _pinch_dist > 0.0:
				view.position += mid - _pinch_mid
				_zoom_at(mid, dist / _pinch_dist)
			_pinch_dist = dist
			_pinch_mid = mid
		elif _painting:
			_use_tool(event.position, false)
		else:
			view.position += event.relative
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.1)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			view.position += event.relative
		_update_hover(event.position)


func _cell_under(screen_pos: Vector2) -> Vector2i:
	return view.cell_at((screen_pos - view.position) / view.scale.x)


func _update_hover(screen_pos: Vector2) -> void:
	var c := _cell_under(screen_pos)
	if tool == T.PAN or not board.in_bounds(c):
		view.hover = Vector2i(-1, -1)
		return
	view.hover = c
	view.hover_ok = board.check(tool, c) == ""


func _use_tool(screen_pos: Vector2, first: bool) -> void:
	var c := _cell_under(screen_pos)
	if not board.in_bounds(c) or c == _last_cell:
		return
	_last_cell = c
	if not first and tool not in DRAG_TOOLS:
		return
	if board.kind(c) == Board.result_kind(tool):
		return
	var err := board.apply(tool, c)
	if err != "":
		if first:
			_show_toast(err)
		return
	view.add_puff(c)
	if tool == T.CANAL or tool == T.BRIDGE:
		for pair in board.blocked_steps():
			if c in pair:
				_show_toast("Different levels here - add a lock to join them")


# --- Game events ------------------------------------------------------------

func _refresh() -> void:
	_coins.text = str(board.coins)
	var open := not board.route.is_empty()
	_set_goal(0, open, "Route open" if open else "Join START to END")
	_set_goal(1, open and board.towpath_pct >= Board.TOWPATH_GOAL,
		"Towpath %d%% / %d%%" % [board.towpath_pct, Board.TOWPATH_GOAL])
	_set_goal(2, open and board.charm >= board.charm_goal,
		"Charm %d / %d" % [board.charm, board.charm_goal])
	view.set_route(board.route)
	if open and not _was_open:
		_show_toast("The cut is open - the first boat is away!")
	_was_open = open
	if _done.visible:
		_fill_done_panel()


func _set_goal(i: int, done: bool, text: String) -> void:
	_goal_stars[i].on = done
	_goal_labels[i].text = text


func _on_boat_arrived() -> void:
	board.boat_arrived()
	_coins.modulate = GOLD
	create_tween().tween_property(_coins, "modulate", Color.WHITE, 0.8)
	if not _celebrated:
		_celebrated = true
		_fill_done_panel()
		_done.show()


func _fill_done_panel() -> void:
	var stars := board.stars()
	for i in 3:
		_done_stars[i].on = i < stars
	_done_title.text = "A perfect waterway!" if stars == 3 else "The cut is open!"
	var lines := ["Every boat that arrives earns %d coins." % board.boat_income()]
	if board.towpath_pct < Board.TOWPATH_GOAL:
		lines.append("Lay towpath beside the route for another star.")
	if board.charm < board.charm_goal:
		lines.append("Add pubs, cafes, cottages and trees for charm.")
	_done_text.text = "\n".join(lines)
	_done_next.text = "Next level" if level_idx < Levels.LEVELS.size() - 1 else "Back to level 1"


func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.modulate.a = 1.0
	_toast.show()
	_toast.reset_size()
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(_toast.hide)


func _select_tool(id: int) -> void:
	tool = id
	view.hover = Vector2i(-1, -1)
	for b in _tool_buttons:
		b.set_pressed_no_signal(b.tool_id == id)


# --- HUD construction -------------------------------------------------------

func _box(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 17
	th.set_color("font_color", "Label", INK)
	var panel := _box(CREAM, EDGE, 16, 12)
	panel.shadow_color = Color(0.2, 0.15, 0.05, 0.18)
	panel.shadow_size = 6
	panel.shadow_offset = Vector2(0, 3)
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("normal", "Button", _box(Color("f3e6c4"), EDGE, 12, 8))
	th.set_stylebox("hover", "Button", _box(Color("f7edd2"), EDGE, 12, 8))
	th.set_stylebox("pressed", "Button", _box(Color("cfe6c0"), Color("7fb069"), 12, 8))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(c, "Button", INK)
	return th


## Pins a control to a point of the screen (ax, ay in 0..1) and lets it grow
## away from that point as its contents change.
func _pin(ctrl: Control, ax: float, ay: float, offset: Vector2) -> void:
	ctrl.anchor_left = ax
	ctrl.anchor_right = ax
	ctrl.anchor_top = ay
	ctrl.anchor_bottom = ay
	ctrl.offset_left = offset.x
	ctrl.offset_right = offset.x
	ctrl.offset_top = offset.y
	ctrl.offset_bottom = offset.y
	var grow := [Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN]
	ctrl.grow_horizontal = grow[int(round(ax * 2))]
	ctrl.grow_vertical = grow[int(round(ay * 2))]


func _label(text: String, font_size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 40)
	b.pressed.connect(on_press)
	return b


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = _make_theme()
	layer.add_child(_hud)

	# Level title, top left.
	var info := PanelContainer.new()
	_hud.add_child(info)
	_pin(info, 0, 0, Vector2(12, 12))
	var info_box := VBoxContainer.new()
	info.add_child(info_box)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	info_box.add_child(title_row)
	title_row.add_child(_button("<", func(): load_level(level_idx - 1)))
	_title = _label("", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	title_row.add_child(_button(">", func(): load_level(level_idx + 1)))
	_blurb = _label("", 14, MUTED)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(330, 0)
	info_box.add_child(_blurb)

	# Coins and goals, top right.
	var stats := PanelContainer.new()
	_hud.add_child(stats)
	_pin(stats, 1, 0, Vector2(-12, 12))
	var stats_box := VBoxContainer.new()
	stats.add_child(stats_box)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 8)
	stats_box.add_child(coin_row)
	coin_row.add_child(CoinIcon.new())
	_coins = _label("0", 22)
	_coins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coin_row.add_child(_coins)
	coin_row.add_child(_button("Restart", func(): load_level(level_idx)))
	for i in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		stats_box.add_child(row)
		var star := StarIcon.new(20)
		row.add_child(star)
		var lbl := _label("", 15)
		lbl.custom_minimum_size = Vector2(170, 0)
		row.add_child(lbl)
		_goal_stars.append(star)
		_goal_labels.append(lbl)

	# Toolbar, bottom centre.
	var bar := PanelContainer.new()
	_hud.add_child(bar)
	_pin(bar, 0.5, 1, Vector2(0, -10))
	var bar_box := HBoxContainer.new()
	bar_box.add_theme_constant_override("separation", 6)
	bar.add_child(bar_box)
	var clear_style := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12, 4)
	var hover_style := _box(Color("f3e6c4"), Color(0, 0, 0, 0), 12, 4)
	var on_style := _box(Color("cfe6c0"), Color("7fb069"), 12, 4)
	for def in TOOLS:
		var b := ToolButton.new(def[0], def[1], def[2])
		b.add_theme_stylebox_override("normal", clear_style)
		b.add_theme_stylebox_override("hover", hover_style)
		b.add_theme_stylebox_override("pressed", on_style)
		b.add_theme_stylebox_override("hover_pressed", on_style)
		b.pressed.connect(_select_tool.bind(def[0]))
		bar_box.add_child(b)
		_tool_buttons.append(b)
	_select_tool(tool)

	# Toast, just above the toolbar.
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_toast)
	_pin(_toast, 0.5, 1, Vector2(0, -136))
	_toast_label = _label("", 17)
	_toast.add_child(_toast_label)
	_toast.hide()

	# Level complete panel, centre.
	_done = PanelContainer.new()
	_hud.add_child(_done)
	_pin(_done, 0.5, 0.5, Vector2.ZERO)
	var done_box := VBoxContainer.new()
	done_box.add_theme_constant_override("separation", 12)
	_done.add_child(done_box)
	_done_title = _label("", 28)
	_done_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	done_box.add_child(_done_title)
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	done_box.add_child(star_row)
	for i in 3:
		var s := StarIcon.new(52)
		star_row.add_child(s)
		_done_stars.append(s)
	_done_text = _label("", 16, MUTED)
	_done_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done_text.custom_minimum_size = Vector2(380, 0)
	done_box.add_child(_done_text)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	done_box.add_child(btn_row)
	btn_row.add_child(_button("Keep building", func(): _done.hide()))
	_done_next = _button("Next level", func(): load_level(level_idx + 1))
	btn_row.add_child(_done_next)
	_done.hide()
