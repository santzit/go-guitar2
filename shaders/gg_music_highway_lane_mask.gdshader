shader_type spatial;
render_mode cull_disabled, unshaded, depth_prepass_alpha;

uniform float side_margin_units : hint_range(0.0, 8.0) = 2.0;
uniform float lit_width_units   : hint_range(1.0, 64.0) = 24.0;
uniform float lane_softness     : hint_range(0.001, 0.25) = 0.035;
uniform float lane_width_scale  : hint_range(0.2, 1.0) = 0.90;
uniform vec4 base_color         : source_color = vec4(0.035, 0.04, 0.055, 1.0);

uniform vec4 lane_color_0 : source_color = vec4(1.00, 0.30, 0.25, 1.0); // red
uniform vec4 lane_color_1 : source_color = vec4(1.00, 0.88, 0.20, 1.0); // yellow
uniform vec4 lane_color_2 : source_color = vec4(0.20, 0.90, 1.00, 1.0); // cyan
uniform vec4 lane_color_3 : source_color = vec4(1.00, 0.65, 0.20, 1.0); // orange
uniform vec4 lane_color_4 : source_color = vec4(0.30, 1.00, 0.50, 1.0); // green
uniform vec4 lane_color_5 : source_color = vec4(0.85, 0.25, 1.00, 1.0); // purple

uniform float lane_intensity_0 : hint_range(0.0, 2.0) = 0.18;
uniform float lane_intensity_1 : hint_range(0.0, 2.0) = 0.18;
uniform float lane_intensity_2 : hint_range(0.0, 2.0) = 0.18;
uniform float lane_intensity_3 : hint_range(0.0, 2.0) = 0.18;
uniform float lane_intensity_4 : hint_range(0.0, 2.0) = 0.18;
uniform float lane_intensity_5 : hint_range(0.0, 2.0) = 0.18;

float lane_band(float lane_uv, float lane_center, float lane_half_width, float softness) {
	float d = abs(lane_uv - lane_center);
	return 1.0 - smoothstep(lane_half_width, lane_half_width + softness, d);
}

void fragment() {
	float total_units = lit_width_units + side_margin_units * 2.0;
	float x_units = UV.x * total_units;
	float side_mask_left = smoothstep(side_margin_units - 0.2, side_margin_units + 0.2, x_units);
	float side_mask_right = 1.0 - smoothstep(side_margin_units + lit_width_units - 0.2, side_margin_units + lit_width_units + 0.2, x_units);
	float side_mask = clamp(side_mask_left * side_mask_right, 0.0, 1.0);

	float lane_uv = clamp(UV.y, 0.0, 1.0);
	float lane_step = 1.0 / 6.0;
	float lane_half_width = lane_step * 0.5 * lane_width_scale;

	vec3 color = base_color.rgb;

	float m0 = lane_band(lane_uv, lane_step * 0.5, lane_half_width, lane_softness);
	float m1 = lane_band(lane_uv, lane_step * 1.5, lane_half_width, lane_softness);
	float m2 = lane_band(lane_uv, lane_step * 2.5, lane_half_width, lane_softness);
	float m3 = lane_band(lane_uv, lane_step * 3.5, lane_half_width, lane_softness);
	float m4 = lane_band(lane_uv, lane_step * 4.5, lane_half_width, lane_softness);
	float m5 = lane_band(lane_uv, lane_step * 5.5, lane_half_width, lane_softness);

	color += lane_color_0.rgb * m0 * lane_intensity_0 * side_mask;
	color += lane_color_1.rgb * m1 * lane_intensity_1 * side_mask;
	color += lane_color_2.rgb * m2 * lane_intensity_2 * side_mask;
	color += lane_color_3.rgb * m3 * lane_intensity_3 * side_mask;
	color += lane_color_4.rgb * m4 * lane_intensity_4 * side_mask;
	color += lane_color_5.rgb * m5 * lane_intensity_5 * side_mask;

	float horizon_fade = mix(1.2, 0.55, UV.y);
	color *= horizon_fade;
	color += vec3(0.55, 0.58, 0.68) * smoothstep(0.08, 0.0, abs(UV.x - 0.5));

	ALBEDO = color;
	EMISSION = color * 1.2;
	ALPHA = 1.0;
}
