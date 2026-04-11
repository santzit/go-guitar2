shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Per-instance colour set by note.gd (string colour palette).
uniform vec4  note_color      : source_color         = vec4(1.0, 0.3, 0.3, 1.0);
uniform float pulse_speed     : hint_range(0.5, 10.0) = 3.0;
uniform float glow_intensity  : hint_range(0.0,  5.0) = 1.5;
uniform float metallic_value  : hint_range(0.0,  1.0) = 0.60;
uniform float roughness_value : hint_range(0.0,  1.0) = 0.15;

// Rounded-box vertex deformation.
// Projects each subdivided box vertex onto the surface of a rounded box
// using the standard SDF formula: length(max(abs(p)-b, 0)) = r
void vertex() {
	float r   = 0.05;                         // corner radius
	vec3  h   = vec3(0.45, 0.25, 0.15);       // half-extents of note (0.90, 0.50, 0.30) / 2
	vec3  q   = abs(VERTEX) - (h - r);
	// Clamp the interior part and project the corner onto a sphere of radius r.
	vec3  rounded = sign(VERTEX) * (min(abs(VERTEX), h - r) + normalize(max(q, vec3(0.0001))) * r);
	// Recompute surface normal from the rounded-box gradient before assigning VERTEX.
	NORMAL = sign(rounded) * normalize(max(abs(rounded) - (h - r), vec3(0.0001)));
	VERTEX = rounded;
}

void fragment() {
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	vec3  color = note_color.rgb;
	float glow  = glow_intensity * (0.70 + pulse * 0.30);

	ALBEDO    = color;
	EMISSION  = color * glow;
	METALLIC  = metallic_value;
	ROUGHNESS = roughness_value;
	ALPHA     = note_color.a;
}
