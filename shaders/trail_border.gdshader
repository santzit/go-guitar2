shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 base_color : source_color = vec4(1.0, 0.5, 0.1, 0.4);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.6);
uniform float border_width : hint_range(0.01, 0.45) = 0.12;
uniform float edge_softness : hint_range(0.001, 0.08) = 0.02;
uniform float glow_energy : hint_range(0.0, 8.0) = 2.4;
uniform float border_glow_boost : hint_range(0.0, 6.0) = 1.6;

void fragment() {
	float left_edge = 1.0 - smoothstep(border_width - edge_softness, border_width, UV.x);
	float right_edge = smoothstep(1.0 - border_width, 1.0 - border_width + edge_softness, UV.x);
	float border = clamp(left_edge + right_edge, 0.0, 1.0);

	vec3 color = mix(base_color.rgb, border_color.rgb, border);
	ALBEDO = color;
	EMISSION = (base_color.rgb * glow_energy) + (border_color.rgb * glow_energy * border_glow_boost * border);
	ALPHA = mix(base_color.a, border_color.a, border);
}
