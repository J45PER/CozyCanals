extends Button
## Toolbar button with a small code-drawn icon, a name and a cost line.

const Board := preload("res://scripts/board.gd")
const T := Board.Tool

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


func _diamond(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -ry), c + Vector2(rx, 0), c + Vector2(0, ry), c + Vector2(-rx, 0)]), col)


func _house(c: Vector2, wall: Color, roof: Color) -> void:
	draw_rect(Rect2(c + Vector2(-13, -4), Vector2(26, 18)), wall)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-17, -4), c + Vector2(0, -18), c + Vector2(17, -4)]), roof)
	draw_rect(Rect2(c + Vector2(-3, 4), Vector2(6, 10)), INK)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var c := Vector2(size.x * 0.5, 30)
	match tool_id:
		T.PAN:
			for d: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				draw_line(c + d * 4, c + d * 15, INK, 3.0)
				var side := Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([c + d * 19, c + d * 12 + side * 5, c + d * 12 - side * 5]), INK)
		T.CANAL:
			_diamond(c, 26, 14, Color("d3ccbb"))
			_diamond(c, 21, 10, Color("62b6c9"))
		T.LOCK:
			_diamond(c, 26, 14, Color("d3ccbb"))
			_diamond(c, 21, 10, Color("62b6c9"))
			draw_line(c + Vector2(-16, 6), c + Vector2(16, -8), Color("2b2623"), 4.0)
			draw_line(c + Vector2(-16, 6), c + Vector2(-10, 3.4), Color.WHITE, 4.0)
			draw_line(c + Vector2(16, -8), c + Vector2(10, -5.4), Color.WHITE, 4.0)
		T.BRIDGE:
			draw_rect(Rect2(c + Vector2(-24, 6), Vector2(48, 8)), Color("62b6c9"))
			draw_arc(c + Vector2(0, 10), 15, PI, TAU, 16, Color("b9684c"), 7.0)
			draw_line(c + Vector2(-25, 9), c + Vector2(-13, 0), Color("b9684c"), 5.0)
			draw_line(c + Vector2(25, 9), c + Vector2(13, 0), Color("b9684c"), 5.0)
		T.TOWPATH:
			_diamond(c, 26, 14, Color("a9d488"))
			draw_line(c + Vector2(-13, 3), c + Vector2(9, -8), Color("62b6c9"), 7.0)
			draw_line(c + Vector2(-8, 9), c + Vector2(14, -2), Color("e6d2a2"), 5.0)
		T.TREE:
			draw_line(c + Vector2(0, 4), c + Vector2(0, 16), Color("7a5a3c"), 4.0)
			draw_circle(c + Vector2(-6, 2), 9, Color("5f9a4c"))
			draw_circle(c + Vector2(6, 2), 9, Color("6aa655"))
			draw_circle(c + Vector2(0, -7), 11, Color("78b560"))
		T.COTTAGE:
			_house(c, Color("ece0c4"), Color("b98a52"))
		T.CAFE:
			_house(c, Color("f8eed6"), Color("4fa39a"))
			for j in 4:
				draw_rect(Rect2(c + Vector2(-13 + j * 6.5, -4), Vector2(6.5, 5)), Color("d9604c") if j % 2 == 0 else Color.WHITE)
		T.PUB:
			_house(c, Color("c47a5f"), Color("5d6470"))
			draw_rect(Rect2(c + Vector2(15, -2), Vector2(9, 8)), Color("2f5d48"))
			draw_rect(Rect2(c + Vector2(17, 0), Vector2(5, 4)), Color("f4d35e"))
		T.CLEAR:
			draw_line(c + Vector2(-11, -11), c + Vector2(11, 11), Color("c9553f"), 5.0)
			draw_line(c + Vector2(11, -11), c + Vector2(-11, 11), Color("c9553f"), 5.0)
	draw_string(font, Vector2(0, 66), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, INK)
	draw_string(font, Vector2(0, 81), cost, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, MUTED)
