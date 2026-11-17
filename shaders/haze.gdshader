shader_type canvas_item;
// Fades the countryside beyond the playable map into haze. `fade_map` holds
// one value per map cell (0 on the land, rising away from it); sampling it
// with linear filtering gives a smooth gradient instead of stepped bands.

uniform sampler2D fade_map : filter_linear, repeat_disable;
uniform vec2 map_origin;      // cell coordinate of the map texture's corner
uniform vec2 map_size;        // texture size in cells
uniform vec2 half_cell;       // a cell on screen (width, height)
uniform vec4 mist : source_color;

varying vec2 cell;

void vertex() {
	cell = VERTEX / half_cell;
}

void fragment() {
	vec4 col = COLOR;   // already includes the texture
	float f = texture(fade_map, (cell - map_origin) / map_size).r;
	COLOR = vec4(mix(col.rgb, mist.rgb, f), col.a);
}
