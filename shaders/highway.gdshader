shader_type spatial;
render_mode cull_disabled, unshaded, depth_prepass_alpha;

// Fixed highway mesh. The 6 string-lane look is fully shader-driven via UV masks.
uniform int   fret_count       : hint_range(1, 24) = 24;
uniform int   string_count     : hint_range(1, 6) = 6;
uniform int   active_fret_min  : hint_range(0, 24) = 0;
uniform int   active_fret_max  : hint_range(-1, 24) = -1;

uniform vec4  base_color       : source_color = vec4(0.01, 0.01, 0.02, 1.0);
uniform vec4  lane_glow_color  : source_color = vec4(0.30, 0.70, 1.00, 1.0);
uniform vec4  range_glow_color : source_color = vec4(0.95, 0.95, 1.00, 1.0);
uniform vec4  strum_glow_color : source_color = vec4(0.40, 0.80, 1.00, 1.0);
uniform vec4  lane_intensity_0_3 = vec4(0.0);
uniform vec2  lane_intensity_4_5 = vec2(0.0);
uniform float lane_width       : hint_range(0.05, 0.95) = 0.65;
uniform float lane_glow_power  : hint_range(0.1, 4.0) = 1.6;
uniform float pulse_speed      : hint_range(0.0, 10.0) = 3.0;
uniform float glow_strength    : hint_range(0.0, 3.0) = 1.2;

float lane_intensity(int lane) {
	if (lane == 0) return lane_intensity_0_3.x;
	if (lane == 1) return lane_intensity_0_3.y;
	if (lane == 2) return lane_intensity_0_3.z;
	if (lane == 3) return lane_intensity_0_3.w;
	if (lane == 4) return lane_intensity_4_5.x;
	return lane_intensity_4_5.y;
}

void fragment() {
	vec2 uv = UV;
	float lanes = float(string_count);
	float lane_pos = uv.x * lanes;
	int lane_idx = int(clamp(floor(lane_pos), 0.0, lanes - 1.0));
	float lane_frac = fract(lane_pos);
	float lane_core = 1.0 - smoothstep(lane_width, 1.0, abs(lane_frac * 2.0 - 1.0));

	float pulse = 0.86 + 0.14 * sin(TIME * pulse_speed + float(lane_idx));
	float lane_energy = pow(lane_core, lane_glow_power) * lane_intensity(lane_idx) * pulse;

	float fret = uv.x * float(fret_count);
	float min_f = float(active_fret_min);
	float max_f = float(active_fret_max);
	float active_ok = step(min_f, max_f);
	float in_fret_range = active_ok * step(min_f, fret) * step(fret, max_f);

	float depth_fade = 1.0 - uv.y * 0.55;
	float strum_glow = smoothstep(0.08, 0.0, uv.y);

	vec3 col = base_color.rgb;
	col += lane_glow_color.rgb * lane_energy * depth_fade * glow_strength;
	col += range_glow_color.rgb * in_fret_range * 0.22 * depth_fade;
	col += strum_glow_color.rgb * strum_glow * glow_strength;

	ALBEDO = col;
	EMISSION = col * (0.50 + lane_energy);
	ALPHA    = 1.0;
}
