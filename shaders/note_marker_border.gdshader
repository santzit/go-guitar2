shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform sampler2D albedo_tex : source_color;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float border_width : hint_range(0.01, 0.40) = 0.12;
uniform float corner_radius : hint_range(0.02, 0.45) = 0.26;
uniform float edge_softness : hint_range(0.001, 0.05) = 0.01;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.8;

float sd_rounded_rect(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - (half_size - vec2(radius));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec2 p = UV * 2.0 - vec2(1.0);
	float dist = sd_rounded_rect(p, vec2(1.0), corner_radius);

	float front_face = step(0.5, NORMAL.z);
	float rounded_mask = 1.0 - smoothstep(0.0, edge_softness, dist);
	float inner_mask = 1.0 - smoothstep(-border_width - edge_softness, -border_width + edge_softness, dist);
	float border_mask = rounded_mask - inner_mask;
	border_mask = clamp(border_mask, 0.0, 1.0) * front_face;

	vec4 base = tex * tint_color;
	vec3 rgb = mix(base.rgb, border_color.rgb, border_mask);
	float alpha_mask = mix(1.0, rounded_mask, front_face);
	float alpha = base.a * alpha_mask;

	ALBEDO = rgb;
	EMISSION = rgb * emission_energy;
	ALPHA = alpha;
}
