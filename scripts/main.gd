extends Node2D
## Game controller: menu and modes, touch/mouse input, boat traffic and the HUD.

const World := preload("res://scripts/world.gd")
const WorldView := preload("res://scripts/world_view.gd")
const MapGen := preload("res://scripts/mapgen.gd")
const AutoBuild := preload("res://scripts/autobuild.gd")
const Levels := preload("res://scripts/levels.gd")
const ToolButton := preload("res://scripts/tool_button.gd")
const T := World.Tool

const INK := Color("4a3b2e")
const MUTED := Color("85735c")
const CREAM := Color("f8efd9")
const EDGE := Color("d2bd92")
const GOLD := Color("e8ad2e")
const SAVE_PATH := "user://save.cfg"

const MAX_BOATS := 3
const BOAT_GAP := 4.0   # seconds between boats setting off
const TOOLS := [
	[T.PAN, "Move", "drag map"],
	[T.CANAL, "Canal", "12 a step"],
	[T.PATH, "Path", "2 a step"],
	[T.ROAD, "Road", "6 a step"],
	[T.TREE, "Trees", "2"],
	[T.COTTAGE, "Cottage", "25"],
	[T.CAFE, "Cafe", "35"],
	[T.PUB, "Pub", "50"],
	[T.ERASE, "Erase", "refunds"],
]


class StarRow extends Control:
	var filled := 0:
		set(v):
			filled = v
			queue_redraw()
	var count := 3
	var px := 20.0

	func _init(star_px: float, stars := 3) -> void:
		px = star_px
		count = stars
		custom_minimum_size = Vector2(px * count + 4.0 * (count - 1), px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for s in count:
			var c := Vector2(px * 0.5 + s * (px + 4.0), px * 0.5)
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + TAU * i / 10.0
				pts.append(c + Vector2(cos(a), sin(a)) * (px * 0.5 if i % 2 == 0 else px * 0.22))
			draw_colored_polygon(pts, Color("e8ad2e") if s < filled else Color("d6c9ab"))


class CoinIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, 11, Color("c98f2a"))
		draw_circle(size * 0.5, 8, Color("f1c84b"))


var world: World
var view: WorldView
var mode := "menu"          # menu, journey, daily or free
var level_idx := 0
var tool: int = T.CANAL

var _save := ConfigFile.new()
var _font: Font
var _touches := {}
var _painting := false
var _last_cell := Vector2i(-1, -1)
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _was_joined := false
var _celebrated := false
var _net_version := -1
var _next_boat := 0.0
var _free_seed := 1

var _hud: Control
var _game_ui: Array[Control] = []
var _title: Label
var _blurb: Label
var _coins: Label
var _coin_icon: CoinIcon
var _goal_stars: Array[StarRow] = []
var _goal_labels: Array[Label] = []
var _new_land: Button
var _tool_buttons: Array[ToolButton] = []
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _done: PanelContainer
var _done_title: Label
var _done_text: Label
var _done_stars: StarRow
var _done_next: Button
var _menu: PanelContainer
var _menu_home: Control
var _menu_levels: Control
var _level_stars: Array[StarRow] = []
var _daily_best: Label


func _ready() -> void:
	_save.load(SAVE_PATH)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Noto Serif", "DejaVu Serif", "serif"])
	_font = serif
	view = WorldView.new()
	add_child(view)
	view.boat_arrived.connect(_on_boat_arrived)
	_build_overlay()
	_build_hud()
	view._font = _font
	get_viewport().size_changed.connect(_fit_view)
	show_menu()


# --- Modes ------------------------------------------------------------------

func show_menu() -> void:
	mode = "menu"
	# A finished map with boats running makes the backdrop.
	var params := Levels.free_build(int(Time.get_unix_time_from_system()) % 1000)
	params.merge({"w": 24, "h": 17, "portals": 3}, true)
	var backdrop := MapGen.generate(params)
	AutoBuild.run(backdrop)
	_use_world(backdrop)
	view.show_labels = false
	for c in _game_ui:
		c.hide()
	_done.hide()
	_toast.hide()
	_refresh_menu()
	_menu_home.show()
	_menu_levels.hide()
	_menu.show()


func start_journey(idx: int) -> void:
	mode = "journey"
	level_idx = posmod(idx, Levels.JOURNEY.size())
	var params: Dictionary = Levels.JOURNEY[level_idx]
	_start(MapGen.generate(params), "%d. %s" % [level_idx + 1, params.name])


func start_daily() -> void:
	mode = "daily"
	_start(MapGen.generate(Levels.daily(Time.get_date_dict_from_system())), "")


func start_free(seed_: int) -> void:
	mode = "free"
	_free_seed = seed_
	_start(MapGen.generate(Levels.free_build(seed_)), "")


func _start(wd: World, heading: String) -> void:
	_use_world(wd)
	view.show_labels = true
	_menu.hide()
	_done.hide()
	for c in _game_ui:
		c.show()
	_toast.hide()
	_title.text = heading if heading != "" else world.title
	_blurb.text = world.blurb
	_new_land.visible = mode == "free"
	_coins.visible = not world.unlimited
	_coin_icon.visible = not world.unlimited
	for b in _tool_buttons:
		if b.tool_id == T.ROAD:
			b.visible = world.allow_roads
	_select_tool(T.CANAL)
	_refresh()


func _use_world(wd: World) -> void:
	world = wd
	world.changed.connect(_refresh)
	view.set_world(world)
	_was_joined = world.linked > 1
	_celebrated = false
	_net_version = world.net_version
	_next_boat = 0.5
	_fit_view()


func _fit_view() -> void:
	if world == null:
		return
	var vp := get_viewport_rect().size
	var area := Rect2(24, 50, vp.x - 48, vp.y - 50 - 118)
	if mode == "menu":
		area = Rect2(0, 0, vp.x, vp.y)
	var b := view.bounds()
	var s := minf(minf(area.size.x / b.size.x, area.size.y / b.size.y), 1.6)
	if mode == "menu":
		s *= 1.25
	view.scale = Vector2(s, s)
	view.position = area.get_center() - b.get_center() * s


func _zoom_at(point: Vector2, factor: float) -> void:
	var old := view.scale.x
	var s := clampf(old * factor, 0.35, 3.0)
	var local := (point - view.position) / old
	view.scale = Vector2(s, s)
	view.position = point - local * s


func _process(delta: float) -> void:
	if world == null:
		return
	view.refresh(Vector2i(-1, -1))   # catches changes not made through the tools
	# Keep a little traffic moving between any portals that are joined up.
	_next_boat -= delta
	if _next_boat > 0.0 or world.pairs.is_empty() or view.boat_count() >= MAX_BOATS:
		return
	_next_boat = BOAT_GAP
	var pair: Array = world.pairs.pick_random()
	if randf() < 0.5:
		pair = [pair[1], pair[0]]
	var from: Dictionary = world.portals[pair[0]]
	var to: Dictionary = world.portals[pair[1]]
	var path := world.path_between(from.cell, to.cell)
	if path.size() >= 2:
		view.spawn_boat(path, from.dir, to.dir)


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if mode == "menu":
		return
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
		elif _touches.size() == 1:
			view.position += event.relative
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.1)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			view.position += event.relative
		var c := _cell_under(event.position)
		view.hover = c if tool != T.PAN else Vector2i(-1, -1)
		view.hover_ok = true


func _cell_under(screen_pos: Vector2) -> Vector2i:
	return view.cell_at((screen_pos - view.position) / view.scale.x)


func _use_tool(screen_pos: Vector2, first: bool) -> void:
	var c := _cell_under(screen_pos)
	if not world.in_bounds(c) or c == _last_cell:
		return
	if World.TOOL_LINK.has(tool):
		# Lines are drawn cell to cell: the first touch only picks the start.
		if first or _last_cell.x < 0:
			_last_cell = c
			view.add_puff(c)
			return
		while _last_cell != c:
			var step := _last_cell + (c - _last_cell).sign()
			if not _draw_link(_last_cell, step):
				_painting = false
				return
			_last_cell = step
		return
	_last_cell = c
	if tool == T.ERASE:
		if world.erase(c):
			view.add_puff(c)
			view.refresh(c)
		elif first:
			_show_toast("Nothing of yours to erase here")
		return
	if not first and tool != T.TREE:
		return
	var err := world.place(tool, c)
	if err == "":
		view.add_puff(c)
		view.refresh(c)
	elif first:
		_show_toast(err)


func _draw_link(a: Vector2i, b: Vector2i) -> bool:
	var type: int = World.TOOL_LINK[tool]
	var plan := world.check_link(a, b, type)
	if plan.err == "same":
		return true
	if plan.err != "":
		_show_toast(plan.err)
		return false
	world.add_link(a, b, type)
	view.add_puff(b)
	view.refresh(b)
	if plan.lock:
		_show_toast("Lock built to climb the hill")
	elif plan.cost >= World.BRIDGE_COST + World.LINK_COST[type] and not plan.restore:
		_show_toast("Bridge built")
	return true


# --- Game events ------------------------------------------------------------

func _refresh() -> void:
	if mode == "menu":
		return
	_coins.text = str(world.coins)
	var open := world.all_linked()
	var n_places := world.places.size()
	_set_goal(0, open, "Canals linked %d / %d" % [world.linked if world.linked > 1 else 0, world.portals.size()])
	_set_goal(1, open and world.places_ok == n_places, "Places connected %d / %d" % [world.places_ok, n_places])
	_set_goal(2, open and world.charm >= world.charm_goal, "Charm %d / %d" % [world.charm, world.charm_goal])
	for i in 3:
		_goal_stars[i].get_parent().visible = not world.unlimited
	if world.net_version != _net_version:
		# The water changed, so boats in transit may no longer have a route.
		_net_version = world.net_version
		view.clear_boats()
		_next_boat = 0.8
	var joined := world.linked > 1
	if joined and not _was_joined:
		_show_toast("Boats are coming through!")
	_was_joined = joined
	if _done.visible:
		_fill_done_panel()


func _set_goal(i: int, done: bool, text: String) -> void:
	_goal_stars[i].filled = int(done)
	_goal_labels[i].text = text


func _on_boat_arrived() -> void:
	if mode == "menu":
		return
	world.boat_arrived()
	_coins.modulate = GOLD
	create_tween().tween_property(_coins, "modulate", Color.WHITE, 0.8)
	if not _celebrated and world.all_linked() and not world.unlimited:
		_celebrated = true
		_fill_done_panel()
		_done.show()


func _fill_done_panel() -> void:
	var stars := world.stars()
	_done_stars.filled = stars
	_done_title.text = "A perfect waterway!" if stars == 3 else "The canal is open!"
	var lines := []
	if world.places_ok < world.places.size():
		lines.append("Connect every place for another star.")
	if world.charm < world.charm_goal:
		lines.append("Add pubs, cafes, cottages and trees for charm.")
	if lines.is_empty():
		lines.append("Every canal linked, every place connected, and charming with it.")
	if mode == "daily":
		lines.append("Today's score: %d   (best %d)" % [world.score(), maxi(world.score(), _daily_score())])
	_done_text.text = "\n".join(lines)
	_done_next.text = "Next level" if mode == "journey" and level_idx < Levels.JOURNEY.size() - 1 else "Menu"
	_record_result()


func _daily_key() -> String:
	return Time.get_date_string_from_system()


func _daily_score() -> int:
	return _save.get_value("daily", _daily_key(), 0)


func _record_result() -> void:
	if mode == "journey":
		var k := str(level_idx)
		_save.set_value("journey", k, maxi(_save.get_value("journey", k, 0), world.stars()))
	elif mode == "daily":
		_save.set_value("daily", _daily_key(), maxi(_daily_score(), world.score()))
	_save.save(SAVE_PATH)


func _on_done_next() -> void:
	if mode == "journey" and level_idx < Levels.JOURNEY.size() - 1:
		start_journey(level_idx + 1)
	else:
		show_menu()


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


func _refresh_menu() -> void:
	for i in _level_stars.size():
		_level_stars[i].filled = _save.get_value("journey", str(i), 0)
	var best := _daily_score()
	_daily_best.text = "Today's best: %d" % best if best > 0 else "A new map every day"


# --- HUD construction -------------------------------------------------------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/paper.gdshader")
	mat.set_shader_parameter("noise", tex)
	rect.material = mat
	layer.add_child(rect)


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
	th.default_font = _font
	th.default_font_size = 17
	th.set_color("font_color", "Label", INK)
	var panel := _box(CREAM, EDGE, 16, 12)
	panel.shadow_color = Color(0.2, 0.15, 0.05, 0.2)
	panel.shadow_size = 6
	panel.shadow_offset = Vector2(0, 3)
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("normal", "Button", _box(Color("efe1bd"), EDGE, 12, 8))
	th.set_stylebox("hover", "Button", _box(Color("f4e9cc"), EDGE, 12, 8))
	th.set_stylebox("pressed", "Button", _box(Color("cfe0b8"), Color("7c9f62"), 12, 8))
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


func _button(text: String, on_press: Callable, min_size := Vector2(44, 40)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.pressed.connect(on_press)
	return b


func _vbox(parent: Control, gap := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	parent.add_child(v)
	return v


func _hbox(parent: Control, gap := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	parent.add_child(h)
	return h


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
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
	var info_box := _vbox(info)
	var title_row := _hbox(info_box)
	title_row.add_child(_button("Menu", show_menu))
	_title = _label("", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	_new_land = _button("New land", func(): start_free(_free_seed + 1))
	title_row.add_child(_new_land)
	_blurb = _label("", 14, MUTED)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(340, 0)
	info_box.add_child(_blurb)

	# Coins and goals, top right.
	var stats := PanelContainer.new()
	_hud.add_child(stats)
	_pin(stats, 1, 0, Vector2(-12, 12))
	var stats_box := _vbox(stats, 4)
	var coin_row := _hbox(stats_box)
	_coin_icon = CoinIcon.new()
	coin_row.add_child(_coin_icon)
	_coins = _label("0", 22)
	_coins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coin_row.add_child(_coins)
	coin_row.add_child(_button("Restart", _restart))
	for i in 3:
		var row := _hbox(stats_box)
		var star := StarRow.new(18, 1)
		row.add_child(star)
		var lbl := _label("", 15)
		lbl.custom_minimum_size = Vector2(190, 0)
		row.add_child(lbl)
		_goal_stars.append(star)
		_goal_labels.append(lbl)

	# Toolbar, bottom centre.
	var bar := PanelContainer.new()
	_hud.add_child(bar)
	_pin(bar, 0.5, 1, Vector2(0, -10))
	var bar_box := _hbox(bar, 6)
	var clear_style := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12, 4)
	var hover_style := _box(Color("efe1bd"), Color(0, 0, 0, 0), 12, 4)
	var on_style := _box(Color("cfe0b8"), Color("7c9f62"), 12, 4)
	for def in TOOLS:
		var b := ToolButton.new(def[0], def[1], def[2])
		b.add_theme_stylebox_override("normal", clear_style)
		b.add_theme_stylebox_override("hover", hover_style)
		b.add_theme_stylebox_override("pressed", on_style)
		b.add_theme_stylebox_override("hover_pressed", on_style)
		b.pressed.connect(_select_tool.bind(def[0]))
		bar_box.add_child(b)
		_tool_buttons.append(b)

	# Toast, just above the toolbar.
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_toast)
	_pin(_toast, 0.5, 1, Vector2(0, -136))
	_toast_label = _label("", 17)
	_toast.add_child(_toast_label)
	_toast.hide()
	_game_ui = [info, stats, bar]

	# Level complete panel, centre.
	_done = PanelContainer.new()
	_hud.add_child(_done)
	_pin(_done, 0.5, 0.5, Vector2.ZERO)
	var done_box := _vbox(_done, 12)
	_done_title = _label("", 28)
	_done_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	done_box.add_child(_done_title)
	_done_stars = StarRow.new(50)
	_done_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done_box.add_child(_done_stars)
	_done_text = _label("", 16, MUTED)
	_done_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done_text.custom_minimum_size = Vector2(400, 0)
	done_box.add_child(_done_text)
	var btn_row := _hbox(done_box, 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_child(_button("Keep building", func(): _done.hide()))
	_done_next = _button("Next level", _on_done_next)
	btn_row.add_child(_done_next)

	_build_menu()


func _restart() -> void:
	match mode:
		"journey": start_journey(level_idx)
		"daily": start_daily()
		"free": start_free(_free_seed)


func _build_menu() -> void:
	_menu = PanelContainer.new()
	var style := _box(Color(0.97, 0.94, 0.85, 0.95), EDGE, 22, 28)
	style.shadow_color = Color(0.2, 0.15, 0.05, 0.25)
	style.shadow_size = 12
	_menu.add_theme_stylebox_override("panel", style)
	_hud.add_child(_menu)
	_pin(_menu, 0.5, 0.5, Vector2.ZERO)
	var stack := _vbox(_menu, 0)

	_menu_home = _vbox(stack, 12)
	var name_label := _label("Cozy Canals", 54)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_home.add_child(name_label)
	var strap := _label("Restore the waterways of the English countryside", 16, MUTED)
	strap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_home.add_child(strap)
	_menu_home.add_child(Control.new())
	var big := Vector2(380, 58)
	_menu_home.add_child(_mode_button("Journey", "Ten waterways to restore, three stars each", big,
		func(): _menu_home.hide(); _menu_levels.show()))
	_menu_home.add_child(_mode_button("Daily Cut", "", big, start_daily))
	_daily_best = _menu_home.get_child(_menu_home.get_child_count() - 1).get_meta("sub")
	_menu_home.add_child(_mode_button("Free Build", "A wide open map, no budget, no goals", big,
		func(): start_free(randi() % 100000)))

	_menu_levels = _vbox(stack, 14)
	var heading := _label("Journey", 34)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_levels.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_menu_levels.add_child(grid)
	for i in Levels.JOURNEY.size():
		var b := _button("", start_journey.bind(i), Vector2(150, 96))
		var inner := _vbox(b, 4)
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var num := _label(str(i + 1), 24)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(num)
		var nm := _label(Levels.JOURNEY[i].name, 13, MUTED)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(nm)
		var stars := StarRow.new(15)
		stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		inner.add_child(stars)
		_level_stars.append(stars)
		grid.add_child(b)
	var back := _button("Back", func(): _menu_levels.hide(); _menu_home.show())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_levels.add_child(back)


func _mode_button(text: String, sub: String, min_size: Vector2, on_press: Callable) -> Button:
	var b := _button("", on_press, min_size)
	var inner := _vbox(b, 0)
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := _label(text, 22)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(head)
	var sub_label := _label(sub, 13, MUTED)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(sub_label)
	b.set_meta("sub", sub_label)
	return b
