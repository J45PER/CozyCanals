extends RefCounted
## The sprite set: every standing object on the map is a PNG in
## assets/sprites, described by sprites.json (see tools/make_sprites.js).
##
## Names end in a variant letter (cottage_a, cottage_b, ...); ask for the base
## name and a seed to get one of them. Sizes and anchors are in game pixels at
## 1x zoom, whatever resolution the PNG itself is.

const DIR := "res://assets/sprites/"

static var _meta := {}
static var _tex := {}
static var _variants := {}
static var _loaded := false
static var boat_directions := 16
static var boat_liveries := 0


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data = JSON.parse_string(FileAccess.get_file_as_string(DIR + "sprites.json"))
	if data == null:
		push_error("Could not read sprites.json")
		return
	boat_directions = int(data.get("boat_directions", 16))
	for name: String in data.sprites:
		var tex: Texture2D = load(DIR + name + ".png")
		if tex == null:
			push_warning("Missing sprite: " + name)
			continue
		_meta[name] = data.sprites[name]
		_tex[name] = tex
		if name.begins_with("boat_"):
			boat_liveries = maxi(boat_liveries, int(name.get_slice("_", 1)) + 1)
		else:
			var base := name.get_slice("_", 0)
			if not _variants.has(base):
				_variants[base] = []
			_variants[base].append(name)


static func has(name: String) -> bool:
	return _tex.has(name)


## One of the variants of `base` ("cottage" -> "cottage_c"), chosen by seed.
static func pick(base: String, seed: int) -> String:
	var options: Array = _variants.get(base, [])
	return "" if options.is_empty() else options[posmod(seed, options.size())]


static func boat(livery: int, direction: int) -> String:
	return "boat_%d_%02d" % [posmod(livery, maxi(boat_liveries, 1)), posmod(direction, boat_directions)]


static func texture(name: String) -> Texture2D:
	return _tex.get(name)


## Where to draw the sprite so its anchor sits at `pos`.
static func rect(name: String, pos: Vector2, zoom := 1.0) -> Rect2:
	var m: Dictionary = _meta[name]
	return Rect2(pos - Vector2(m.ax, m.ay) * zoom, Vector2(m.w, m.h) * zoom)


static func height(name: String) -> float:
	return _meta[name].ay if _meta.has(name) else 30.0


## Chimney top relative to the anchor, or ZERO if the sprite has none.
static func smoke(name: String) -> Vector2:
	var m: Dictionary = _meta.get(name, {})
	return Vector2(m.smoke[0], m.smoke[1]) if m.has("smoke") else Vector2.ZERO
