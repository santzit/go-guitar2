shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

// Base color of this string (set per-string instance from GDScript).
uniform vec4  string_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0.0 = resting (always colored).
// 1.0 = full-intensity glow (note is at or past the strum line).
// Driven each frame by music_play.gd based on upcoming note timing.
uniform float glow_intensity  : hint_range(0.0, 1.0) = 0.0;
// Resting brightness for fretboard strings before upcoming-note glow ramps in.
uniform float rest_brightness : hint_range(0.1, 1.0) = 0.34;
// Resting saturation for fretboard strings. 1.0 = full color, 0.0 = grayscale.
uniform float rest_saturation : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	// Strings stay opaque and slightly dim at rest, then brighten toward full
	// color as upcoming-note glow increases.
	float depth_fade = 1.0 - UV.y * 0.20;
	float ramp = clamp(glow_intensity, 0.0, 1.0);
	float lit = mix(rest_brightness, 1.0, ramp);
	float sat = mix(rest_saturation, 1.0, ramp);
	float luma = dot(string_color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rest_color = mix(vec3(luma), string_color.rgb, sat);

	ALBEDO   = rest_color * lit;
	EMISSION = string_color.rgb * ramp * 3.0 * depth_fade;
	ALPHA    = 1.0;
}
