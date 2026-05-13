shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform float glow_energy : hint_range(0.0, 8.0) = 2.4;
uniform float end_glow_boost : hint_range(0.0, 16.0) = 5.0;
uniform float edge_glow_boost : hint_range(0.0, 16.0) = 6.0;
uniform float connector_width : hint_range(0.001, 0.2) = 0.012;
uniform float connector_depth : hint_range(0.001, 0.2) = 0.012;
uniform float connector_height : hint_range(0.02, 8.0) = 0.02;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float half_h = max(connector_height * 0.5, 0.001);
	float y01 = clamp((local_pos.y + half_h) / (half_h * 2.0), 0.0, 1.0);
	float end_dist = min(y01, 1.0 - y01);
	float end_glow = 1.0 - smoothstep(0.0, 0.35, end_dist);

	float half_w = max(connector_width * 0.5, 0.0005);
	float half_d = max(connector_depth * 0.5, 0.0005);
	float x_edge = smoothstep(0.45, 1.0, abs(local_pos.x) / half_w);
	float z_edge = smoothstep(0.45, 1.0, abs(local_pos.z) / half_d);
	float edge_glow = max(x_edge, z_edge);

	float combined_glow = clamp(max(end_glow, edge_glow), 0.0, 1.0);
	float mid_alpha = 0.35;
	float alpha = mix(mid_alpha, 1.0, combined_glow) * line_color.a;

	ALBEDO = mix(line_color.rgb * 0.2, line_color.rgb, combined_glow);
	EMISSION = line_color.rgb * (
		glow_energy
		+ (end_glow * end_glow_boost)
		+ (edge_glow * edge_glow_boost)
	);
	ALPHA = alpha;
}
