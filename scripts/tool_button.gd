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
		T.PATH_TARMAC:
			_curve(c, Color("a7a39a"), 7.0)
			_curve(c, Color("8b8882"), 5.0)
		T.PATH_DIRT:
			_curve(c, Color("8f7656"), 8.0)
			_curve(c, Color("b39672"), 6.0)
			_curve(c, Color("8fae62"), 1.5)
		T.ROAD:
			_curve(c, Color("8f9a6a"), 12.0)
			_curve(c, Color("a29e95"), 9.0)
		T.ROAD_WIDE:
			_curve(c, Color("8f9a6a"), 17.0)
			_curve(c, Color("7f7d79"), 14.0)
			for i in range(0, 12, 3):
				var t0 := i / 12.0
				var t1 := (i + 1.4) / 12.0
				var p0 := c + Vector2(-24 + 48 * t0, sin(t0 * TAU) * 7.0 - 2.0 + t0 * 6.0)
				var p1 := c + Vector2(-24 + 48 * t1, sin(t1 * TAU) * 7.0 - 2.0 + t1 * 6.0)
				draw_line(p0, p1, Color("f1ece0"), 1.6)
		T.ROUNDABOUT:
			draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), Color("7f7d79"), 9.0)
			draw_line(c + Vector2(0, -18), c + Vector2(0, 18), Color("7f7d79"), 9.0)
			draw_circle(c, 15.0, Color("7f7d79"))
			draw_circle(c, 7.5, Color("f1ece0"))
			draw_circle(c, 6.0, Color("8fb36a"))
		T.CARPARK:
			draw_rect(Rect2(c + Vector2(-24, -14), Vector2(48, 28)), Color("8b8882"))
			for x in range(-16, 17, 11):
				draw_line(c + Vector2(x, -14), c + Vector2(x, -4), Color("f1ece0"), 1.5)
				draw_line(c + Vector2(x, 4), c + Vector2(x, 14), Color("f1ece0"), 1.5)
			draw_rect(Rect2(c + Vector2(-13, -12), Vector2(9, 7)), Color("c0392b"))
			draw_rect(Rect2(c + Vector2(6, 6), Vector2(9, 7)), Color("2c4466"))
		T.GARDEN:
			draw_rect(Rect2(c + Vector2(-24, -6), Vector2(48, 20)), Color("a9c97b"))
			for x: float in [-11.0, 11.0]:
				draw_rect(Rect2(c + Vector2(x - 6, 4), Vector2(12, 4)), Color("8a6a45"))
				draw_line(c + Vector2(x, 4), c + Vector2(x, -10), Color("3a2f27"), 1.5)
				draw_colored_polygon(PackedVector2Array([c + Vector2(x - 9, -9), c + Vector2(x, -16), c + Vector2(x + 9, -9)]),
					Color("d4604c") if x < 0 else Color("3f7a55"))
		T.MOORINGS:
			draw_rect(Rect2(c + Vector2(-26, -4), Vector2(52, 16)), Color("6aa3a8"))
			draw_rect(Rect2(c + Vector2(-26, -12), Vector2(52, 8)), Color("e2cfa3"))
			for x: float in [-16.0, 0.0, 16.0]:
				draw_rect(Rect2(c + Vector2(x - 2, -13), Vector2(4, 6)), Color("26211e"))
			draw_rect(Rect2(c + Vector2(-18, -1), Vector2(36, 8)), Color("2f5a48"))
			draw_rect(Rect2(c + Vector2(-14, -4), Vector2(26, 4)), Color("e6d6a4"))
		T.BASIN:
			draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), Color("cfc3a6"), 14.0)
			draw_circle(c, 15.0, Color("cfc3a6"))
			draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), Color("6aa3a8"), 9.0)
			draw_circle(c, 12.0, Color("6aa3a8"))
		T.HEDGE_ROW, T.WALL_ROW, T.FENCE_ROW:
			draw_line(c + Vector2(-26, 2), c + Vector2(26, 2), Color("e2cfa3"), 7.0)
			for y: float in [-8.0, 11.0]:
				match tool_id:
					T.HEDGE_ROW:
						draw_line(c + Vector2(-24, y), c + Vector2(24, y), Color("557c45"), 7.0)
						draw_line(c + Vector2(-24, y - 2), c + Vector2(24, y - 2), Color("6f9450"), 3.0)
					T.WALL_ROW:
						draw_line(c + Vector2(-24, y), c + Vector2(24, y), Color("a59a82"), 6.0)
						draw_line(c + Vector2(-24, y - 2.5), c + Vector2(24, y - 2.5), Color("c9bea4"), 2.0)
					T.FENCE_ROW:
						draw_line(c + Vector2(-24, y - 1), c + Vector2(24, y - 1), Color("8a6a45"), 1.5)
						draw_line(c + Vector2(-24, y + 2), c + Vector2(24, y + 2), Color("8a6a45"), 1.5)
						for x in range(-24, 25, 8):
							draw_line(c + Vector2(x, y - 4), c + Vector2(x, y + 4), Color("6b5138"), 2.0)
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
		T.BRIDGE_BRICK, T.BRIDGE_STONE, T.BRIDGE_CONCRETE:
			var wall: Color = {T.BRIDGE_BRICK: Color("ab5a43"), T.BRIDGE_STONE: Color("c3b8a0"), T.BRIDGE_CONCRETE: Color("bdbcb6")}[tool_id]
			draw_rect(Rect2(c + Vector2(-24, 6), Vector2(48, 8)), Color("6aa3a8"))
			if tool_id == T.BRIDGE_CONCRETE:
				draw_rect(Rect2(c + Vector2(-26, -6), Vector2(52, 7)), wall)
				draw_rect(Rect2(c + Vector2(-26, -6), Vector2(8, 20)), wall)
				draw_rect(Rect2(c + Vector2(18, -6), Vector2(8, 20)), wall)
				draw_line(c + Vector2(-26, -9), c + Vector2(26, -9), Color("e8e6df"), 1.5)
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
