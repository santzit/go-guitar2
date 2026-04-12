shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Base color of this string (set per-string instance from GDScript).
uniform vec4  string_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0.0 = resting dim glow (no note coming).
// 1.0 = full-intensity glow (note is at or past the strum line).
// Driven each frame by music_play.gd based on upcoming note timing.
uniform float glow_intensity  : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Emission ramps from nearly invisible at rest up to a bright peak as the note approaches.
	float base_emit = 0.05;
	float peak_emit = 8.0;
	float emit      = mix(base_emit, peak_emit, glow_intensity);

	// Soft depth fade: strings are brightest near the strum line (uv.y ≈ 0)
	// and fade gently into the distance (uv.y → 1).
	float depth_fade = 1.0 - UV.y * 0.55;

	vec3 col = string_color.rgb * emit * depth_fade;

	ALBEDO   = col;
	EMISSION = col;
	// Alpha also increases with glow so the string "appears" as a note arrives.
	ALPHA    = mix(0.05, 0.85, glow_intensity) * depth_fade;
}
