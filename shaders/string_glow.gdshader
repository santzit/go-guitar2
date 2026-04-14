shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Base color of this string (set per-string instance from GDScript).
uniform vec4  string_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0.0 = resting (always colored).
// 1.0 = full-intensity glow (note is at or past the strum line).
// Driven each frame by music_play.gd based on upcoming note timing.
uniform float glow_intensity  : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Strings are ALWAYS colored.  glow_intensity adds emission brightness
	// as notes approach the strum line (lightened/delightened logic to come).
	float depth_fade = 1.0 - UV.y * 0.20;

	ALBEDO   = string_color.rgb;
	EMISSION = string_color.rgb * glow_intensity * 4.0 * depth_fade;
	ALPHA    = 1.0;
}
