shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 base_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 corner_glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 marker_size = vec2(0.78, 0.34);
uniform float corner_radius_uv : hint_range(0.02, 0.49) = 0.24;
uniform float corner_glow_width : hint_range(0.02, 0.40) = 0.14;
uniform float edge_softness : hint_range(0.001, 0.05) = 0.01;
uniform float glow_energy : hint_range(0.0, 8.0) = 1.8;
uniform float corner_glow_boost : hint_range(0.0, 12.0) = 6.0;

varying vec3 local_pos;

float rounded_rect_sdf(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - (half_size - vec2(radius));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 half_size = max(marker_size * 0.5, vec2(0.0001));
	float min_half = min(half_size.x, half_size.y);
	float radius = clamp(corner_radius_uv, 0.02, 0.49) * min_half;
	float glow_width = clamp(corner_glow_width, 0.02, 0.40) * min_half;
	float softness = max(edge_softness * min_half, 0.0005);
	float dist = rounded_rect_sdf(local_pos.xy, half_size, radius);

	float outer = 1.0 - smoothstep(0.0, softness, dist);
	float inner = 1.0 - smoothstep(0.0, softness, dist + glow_width);
	float ring = clamp(outer - inner, 0.0, 1.0);
	float alpha_mask = outer;

	if (alpha_mask <= 0.001) {
		discard;
	}

	ALBEDO = base_color.rgb;
	EMISSION = (base_color.rgb * glow_energy) + (corner_glow_color.rgb * ring * glow_energy * corner_glow_boost);
	ALPHA = base_color.a * alpha_mask;
}
