shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 base_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 corner_glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float corner_radius_uv : hint_range(0.02, 0.49) = 0.24;
uniform float corner_glow_width : hint_range(0.02, 0.40) = 0.14;
uniform float edge_softness : hint_range(0.001, 0.05) = 0.01;
uniform float glow_energy : hint_range(0.0, 8.0) = 1.8;
uniform float corner_glow_boost : hint_range(0.0, 12.0) = 6.0;

float rounded_rect_sdf(vec2 p, float radius) {
	vec2 half_size = vec2(0.5);
	vec2 q = abs(p) - (half_size - vec2(radius));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float radius = clamp(corner_radius_uv, 0.02, 0.49);
	float dist = rounded_rect_sdf(p, radius);

	float outer = 1.0 - smoothstep(0.0, edge_softness, dist);
	float inner = 1.0 - smoothstep(0.0, edge_softness, dist + corner_glow_width);
	float ring = clamp(outer - inner, 0.0, 1.0);

	float edge_x = smoothstep(0.05, 0.48, abs(p.x));
	float edge_y = smoothstep(0.05, 0.48, abs(p.y));
	float corner_mask = edge_x * edge_y;
	float face_mask = step(0.6, abs(NORMAL.z));
	float corner_glow = ring * corner_mask * face_mask;
	float alpha_mask = mix(1.0, outer, face_mask);

	ALBEDO = base_color.rgb;
	EMISSION = (base_color.rgb * glow_energy) + (corner_glow_color.rgb * corner_glow * glow_energy * corner_glow_boost);
	ALPHA = base_color.a * alpha_mask;
}
