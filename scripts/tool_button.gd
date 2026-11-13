extends Button
## Toolbar button with a small code-drawn icon, a name and a cost line.

const World := preload("res://scripts/world.gd")
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
	custom_minimum_size = Vector2(92, 88)


func _curve(c: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		pts.append(c + Vector2(-24 + 48 * t, sin(t * TAU) * 7.0 - 2.0 + t * 6.0))
	draw_polyline(pts, col, width, true)


func _house(c: Vector2, wall: Color, roof: Color) -> void:
	draw_rect(Rect2(c + Vector2(-13, -4), Vector2(26, 18)), wall)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-17, -4), c + Vector2(0, -18), c + Vector2(17, -4)]), roof)
	draw_rect(Rect2(c + Vector2(-3, 4), Vector2(6, 10)), INK)


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
		T.TREE:
			draw_line(c + Vector2(0, 4), c + Vector2(0, 16), Color("6b5138"), 4.0)
			draw_circle(c + Vector2(-6, 2), 9, Color("4f7b45"))
			draw_circle(c + Vector2(6, 2), 9, Color("6a9a52"))
			draw_circle(c + Vector2(0, -7), 11, Color("8ab868"))
		T.COTTAGE:
			_house(c, Color("dcc79a"), Color("c2a05c"))
		T.CAFE:
			_house(c, Color("f3ead2"), Color("4d9a90"))
			for j in 4:
				draw_rect(Rect2(c + Vector2(-13 + j * 6.5, -4), Vector2(6.5, 5)), Color("d4604c") if j % 2 == 0 else Color.WHITE)
		T.PUB:
			_house(c, Color("efe8d8"), Color("5b6470"))
			draw_rect(Rect2(c + Vector2(15, -2), Vector2(9, 8)), Color("2d5443"))
			draw_rect(Rect2(c + Vector2(17, 0), Vector2(5, 4)), Color("f1c84b"))
		T.ERASE:
			draw_line(c + Vector2(-11, -11), c + Vector2(11, 11), Color("c0553f"), 5.0)
			draw_line(c + Vector2(11, -11), c + Vector2(-11, 11), Color("c0553f"), 5.0)
	draw_string(font, Vector2(0, 66), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, INK)
	draw_string(font, Vector2(0, 81), cost, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, MUTED)
