shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform sampler2D albedo_tex : source_color;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float border_width : hint_range(0.01, 0.40) = 0.16;
uniform float corner_radius : hint_range(0.02, 0.45) = 0.34;
uniform float edge_softness : hint_range(0.001, 0.05) = 0.008;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.8;
uniform float border_emission_energy : hint_range(0.0, 12.0) = 3.6;
uniform float side_brightness : hint_range(0.1, 1.0) = 0.30;
uniform float side_emission_factor : hint_range(0.0, 1.0) = 0.08;

float rounded_rect_sdf(vec2 p, float radius) {
	vec2 q = abs(p) - vec2(0.5 - radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec2 p = UV - vec2(0.5);
	float dist = rounded_rect_sdf(p, corner_radius);

	float front_face = step(0.9, NORMAL.z);
	float rounded_mask = 1.0 - smoothstep(0.0, edge_softness, dist);
	float inner_mask = 1.0 - smoothstep(0.0, edge_softness, dist + border_width);
	float border_mask = rounded_mask - inner_mask;
	border_mask = clamp(border_mask, 0.0, 1.0) * front_face;

	vec4 base = tex * tint_color;
	vec3 front_rgb = mix(base.rgb, border_color.rgb, border_mask);
	vec3 side_rgb = base.rgb * side_brightness;
	vec3 rgb = mix(side_rgb, front_rgb, front_face);
	float alpha_mask = mix(1.0, rounded_mask, front_face);
	float alpha = base.a * alpha_mask;
	float border_emission = border_mask * border_emission_energy;

	ALBEDO = rgb;
	vec3 front_emission = base.rgb * emission_energy + border_color.rgb * border_emission;
	vec3 side_emission = base.rgb * emission_energy * side_emission_factor;
	EMISSION = mix(side_emission, front_emission, front_face);
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.05;
}
