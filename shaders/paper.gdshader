shader_type canvas_item;
render_mode blend_mul, unshaded;
// Multiplied over the whole scene: paper grain, slow cloud shadows drifting
// across the land, a warm tint and a soft vignette.

uniform sampler2D noise : repeat_enable, filter_linear;

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 wide = vec2(uv.x * aspect, uv.y);
	float grain = texture(noise, wide * 2.6).r;
	float cloud = texture(noise, wide * 0.32 + vec2(TIME * 0.006, TIME * 0.003)).r;
	cloud = smoothstep(0.5, 0.72, cloud);
	vec3 tint = vec3(1.0, 0.985, 0.955);
	tint = mix(tint, vec3(0.80, 0.84, 0.90), cloud * 0.26);
	tint *= 0.965 + grain * 0.07;
	float edge = length((uv - 0.5) * vec2(1.0, 0.85));
	tint *= mix(1.0, 0.84, smoothstep(0.38, 0.8, edge));
	COLOR = vec4(tint, 1.0);
}
