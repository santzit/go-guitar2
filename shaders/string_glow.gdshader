shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Base color of this string (set per-string instance from GDScript).
uniform vec4  string_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0.0 = resting dim glow (no note coming).
// 1.0 = full-intensity glow (note is at or past the strum line).
// Driven each frame by music_play.gd based on upcoming note timing.
uniform float glow_intensity  : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Strings are ALWAYS visible as colored neon lines (Rocksmith-style).
	// base_emit gives a constant moderate brightness so strings are always seen.
	// When a note is approaching (glow_intensity → 1.0) the string gets extra bright.
	float base_emit = 1.2;
	float peak_emit = 5.0;
	float emit      = mix(base_emit, peak_emit, glow_intensity);

	// Subtle depth fade: strings stay clearly visible along their full length,
	// but are very slightly dimmer in the far distance.
	float depth_fade = 1.0 - UV.y * 0.20;

	vec3 col = string_color.rgb * emit * depth_fade;

	ALBEDO   = col;
	EMISSION = col;
	// Strings are always opaque; alpha grows slightly when glowing.
	ALPHA    = mix(0.75, 0.95, glow_intensity) * depth_fade;
}
