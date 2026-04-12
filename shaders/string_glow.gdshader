shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Base color of this string (set per-string instance from GDScript).
uniform vec4  string_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0.0 = resting dim glow (no note coming).
// 1.0 = full-intensity glow (note is at or past the strum line).
// Driven each frame by music_play.gd based on upcoming note timing.
uniform float glow_intensity  : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Strings are DARK at rest (no note approaching) and glow brightly
	// as notes get close to the strum line (glow_intensity → 1.0).
	float peak_emit = 6.0;
	float emit      = glow_intensity * peak_emit;

	// Subtle depth fade along the highway length.
	float depth_fade = 1.0 - UV.y * 0.20;

	vec3 col = string_color.rgb * emit * depth_fade;

	ALBEDO   = col;
	EMISSION = col;
	// Fully transparent when no note, fully opaque when note is imminent.
	ALPHA    = glow_intensity * 0.95 * depth_fade;
}
