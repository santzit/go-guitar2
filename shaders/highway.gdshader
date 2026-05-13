shader_type spatial;
// Opaque, unlit highway floor with static separator lines.
render_mode cull_disabled, unshaded;

uniform int   fret_count       : hint_range(1, 24) = 24;
uniform vec4  base_color       : source_color = vec4(0.04, 0.04, 0.07, 1.0);
// Width of each separator line, in UV space (0-1 across the full highway).
uniform float vertical_line_width : hint_range(0.0005, 0.1) = 0.0015;
uniform float separator_base_intensity : hint_range(0.0, 4.0) = 2.0;
uniform vec4  separator_line_color  : source_color = vec4(0.55, 0.85, 1.00, 1.0);


// Procedural separator line mask using fract() - no loop required.
// UV.x spans fret 0 (left) -> fret 24 (right) linearly.
// Returns a smooth 0..1 weight that peaks at each integer fret boundary.
float separator_line_mask(vec2 uv) {
	float fc = max(float(fret_count), 1.0);
	float fret_u = uv.x * fc;
	float dist = min(fract(fret_u), 1.0 - fract(fret_u));
	float half_width = max(vertical_line_width * fc * 0.5, 0.001);
	return 1.0 - smoothstep(0.0, half_width, dist);
}


void fragment() {
	float sep_mask = separator_line_mask(UV);
	vec3 line_rgb = separator_line_color.rgb;

	vec3 col = mix(base_color.rgb, line_rgb, sep_mask);

	ALBEDO = col;
	EMISSION = line_rgb * sep_mask * separator_base_intensity;
}
