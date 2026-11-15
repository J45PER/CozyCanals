extends Button
## Toolbar button with a small code-drawn icon, a name and a cost line.

const World := preload("res://scripts/world.gd")
const Sprites := preload("res://scripts/sprites.gd")
const View := preload("res://scripts/world_view.gd")
const T := World.Tool

const INK := Color("4a3b2e")
const MUTED := Color("8a7860")

var tool_id := 0
var title := ""
var cost := ""


func _init(p_tool: int, p_title: String, p_cost: String) -> void:
	tool_id = p_tool
	title = p_title
	cost = p_cost
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	Sprites.ensure_loaded()
	custom_minimum_size = Vector2(82, 88)


func _curve(c: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		pts.append(c + Vector2(-24 + 48 * t, sin(t * TAU) * 7.0 - 2.0 + t * 6.0))
	draw_polyline(pts, col, width, true)


func _draw() -> void:
	var font := get_theme_default_font()
	var c := Vector2(size.x * 0.5, 30)
	match tool_id:
		T.PAN:
			for d: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				draw_line(c + d * 4, c + d * 15, INK, 3.0)
				var side := Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([c + d * 19, c + d * 12 + side * 5, c + d * 12 - side * 5]), INK)
		T.CANAL:
			_curve(c, Color("cfc3a6"), 15.0)
			_curve(c, Color("6aa3a8"), 10.0)
		T.PATH:
			_curve(c, Color("c2ab7c"), 7.0)
			_curve(c, Color("e2cfa3"), 4.5)
		T.ROAD:
			_curve(c, Color("8f9a6a"), 14.0)
			_curve(c, Color("b8ad9c"), 10.0)
		T.ERASE:
			draw_line(c + Vector2(-11, -11), c + Vector2(11, 11), Color("c0553f"), 5.0)
			draw_line(c + Vector2(11, -11), c + Vector2(-11, 11), Color("c0553f"), 5.0)
		T.RESTORE:
			# Silted canal on the left, clear water on the right.
			_curve(c, Color("9a6a55"), 15.0)
			var pts := PackedVector2Array()
			for i in 7:
				var t := i / 12.0
				pts.append(c + Vector2(-24 + 48 * t, sin(t * TAU) * 7.0 - 2.0 + t * 6.0))
			draw_polyline(pts, Color("7c8a62"), 10.0, true)
			var rest := PackedVector2Array()
			for i in range(6, 13):
				var t := i / 12.0
				rest.append(c + Vector2(-24 + 48 * t, sin(t * TAU) * 7.0 - 2.0 + t * 6.0))
			draw_polyline(rest, Color("6aa3a8"), 10.0, true)
			draw_circle(c + Vector2(-8, -10), 2.5, Color("f1c84b"))
			draw_circle(c + Vector2(12, -12), 1.8, Color("f1c84b"))
		T.LOCK_BRICK, T.LOCK_STONE:
			var edge := Color("a8604a") if tool_id == T.LOCK_BRICK else Color("c9bea4")
			draw_rect(Rect2(c + Vector2(-20, -10), Vector2(40, 22)), edge)
			draw_rect(Rect2(c + Vector2(-15, -6), Vector2(30, 14)), Color("6aa3a8"))
			for x: float in [-9.0, 9.0]:
				draw_rect(Rect2(c + Vector2(x - 2, -8), Vector2(4, 18)), Color("3a2f27"))
				draw_line(c + Vector2(x, -12), c + Vector2(x - 12, -16), Color("26211e"), 3.0)
				draw_line(c + Vector2(x - 9, -15.3), c + Vector2(x - 12, -16), Color("f4efe2"), 3.0)
		T.BRIDGE_BRICK, T.BRIDGE_STONE, T.BRIDGE_WOOD:
			var wall: Color = {T.BRIDGE_BRICK: Color("ab5a43"), T.BRIDGE_STONE: Color("c3b8a0"), T.BRIDGE_WOOD: Color("8a6a45")}[tool_id]
			draw_rect(Rect2(c + Vector2(-24, 6), Vector2(48, 8)), Color("6aa3a8"))
			if tool_id == T.BRIDGE_WOOD:
				draw_line(c + Vector2(-24, 3), c + Vector2(24, 3), wall, 4.0)
				draw_line(c + Vector2(-22, -5), c + Vector2(22, -5), wall, 2.0)
				for x: float in [-18.0, 0.0, 18.0]:
					draw_line(c + Vector2(x, -5), c + Vector2(x, 12), wall.darkened(0.2), 2.0)
			else:
				var arch := PackedVector2Array([c + Vector2(-26, 12), c + Vector2(-16, -4), c + Vector2(0, -9),
					c + Vector2(16, -4), c + Vector2(26, 12), c + Vector2(13, 12), c + Vector2(9, 5),
					c + Vector2(0, 2), c + Vector2(-9, 5), c + Vector2(-13, 12)])
				draw_colored_polygon(arch, wall)
	if World.TOOL_BUILDING.has(tool_id) or tool_id == T.TREE:
		# Building and planting tools show the sprite itself.
		var name := "oak_a" if tool_id == T.TREE else Sprites.pick(View.BUILDING_SPRITE[World.TOOL_BUILDING[tool_id]], 0)
		if Sprites.has(name):
			var r := Sprites.rect(name, Vector2.ZERO)
			var zoom := minf(72.0 / r.size.x, 50.0 / r.size.y)
			draw_texture_rect(Sprites.texture(name), Rect2(Vector2(size.x * 0.5 - r.size.x * zoom * 0.5, 54.0 - r.size.y * zoom), r.size * zoom), false)
	draw_string(font, Vector2(0, 66), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, INK)
	draw_string(font, Vector2(0, 81), cost, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, MUTED)
