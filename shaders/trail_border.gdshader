shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 base_color : source_color = vec4(1.0, 0.5, 0.1, 0.4);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.6);
uniform float mesh_width : hint_range(0.05, 4.0) = 0.5;
uniform float mesh_length : hint_range(0.05, 20.0) = 1.0;
uniform float border_width : hint_range(0.005, 0.45) = 0.06;
uniform float edge_softness : hint_range(0.001, 0.08) = 0.02;
uniform float corner_radius : hint_range(0.0, 0.5) = 0.2;
uniform float glow_energy : hint_range(0.0, 8.0) = 2.4;
uniform float border_glow_boost : hint_range(0.0, 6.0) = 1.6;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float half_width = max(mesh_width * 0.5, 0.0001);
	float half_length = max(mesh_length * 0.5, 0.0001);
	float border_world = clamp(border_width, 0.005, 0.45) * half_width;
	float border_softness = max(edge_softness * half_width, 0.0005);
	float shape_softness = max(edge_softness * min(half_width, half_length), 0.0005);
	float edge_dist = half_width - abs(local_pos.x);
	float border = 1.0 - smoothstep(border_world, border_world + border_softness, edge_dist);
	float radius = clamp(corner_radius, 0.0, 0.5) * min(half_width, half_length);
	vec2 corner_pos = vec2(abs(local_pos.x), abs(local_pos.z));
	vec2 corner_box = vec2(half_width - radius, half_length - radius);
	vec2 corner_offset = corner_pos - corner_box;
	float corner_dist = length(max(corner_offset, vec2(0.0))) + min(max(corner_offset.x, corner_offset.y), 0.0) - radius;
	float shape_alpha = 1.0 - smoothstep(0.0, shape_softness, corner_dist);

	vec3 color = mix(base_color.rgb, border_color.rgb, border);
	ALBEDO = color;
	EMISSION = ((base_color.rgb * glow_energy) + (border_color.rgb * glow_energy * border_glow_boost * border)) * shape_alpha;
	ALPHA = mix(base_color.a, border_color.a, border) * shape_alpha;
}
