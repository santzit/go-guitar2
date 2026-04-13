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
uniform sampler2D vertical_fret_line_tex : source_color;
uniform float vertical_line_width : hint_range(0.001, 0.05) = 0.008;
uniform float vertical_line_strength : hint_range(0.0, 2.0) = 0.55;

const int MAX_SHADER_LANES = 6; // lane_intensity uniforms are packed for 6 lanes.
const int MAX_FRET_LINES = 24;
const float SCALE_LENGTH = 300.0;
const float MIN_FRET_POS = 0.0001;

float lane_intensity(int lane) {
	if (lane < 0 || lane >= string_count || lane >= MAX_SHADER_LANES) return 0.0;
	if (lane == 0) return lane_intensity_0_3.x;
	if (lane == 1) return lane_intensity_0_3.y;
	if (lane == 2) return lane_intensity_0_3.z;
	if (lane == 3) return lane_intensity_0_3.w;
	if (lane == 4) return lane_intensity_4_5.x;
	return lane_intensity_4_5.y;
}

float chart_fret_pos(float fret_num) {
	return SCALE_LENGTH - (SCALE_LENGTH / pow(2.0, fret_num / 12.0));
}

float vertical_fret_line_alpha(vec2 uv) {
	float max_pos = max(chart_fret_pos(float(fret_count)), MIN_FRET_POS);
	int fret_limit = min(fret_count, MAX_FRET_LINES);
	float half_width = vertical_line_width * 0.5;
	float alpha = 0.0;
	for (int i = 0; i <= MAX_FRET_LINES; i++) {
		// Intentional <=: fret_count=24 means we draw boundaries for fret 0..24.
		if (i > fret_limit) {
			break;
		}
		float fret_x = chart_fret_pos(float(i)) / max_pos;
		if (abs(uv.x - fret_x) > half_width) {
			continue;
		}
		float local_u = (uv.x - fret_x) / vertical_line_width + 0.5;
		if (local_u < 0.0 || local_u > 1.0) {
			continue;
		}
		float line_sample = texture(vertical_fret_line_tex, vec2(local_u, uv.y)).a;
		alpha = max(alpha, line_sample);
	}
	return alpha * vertical_line_strength;
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
	float fret_line = vertical_fret_line_alpha(uv);

	vec3 col = base_color.rgb;
	col += lane_glow_color.rgb * lane_energy * depth_fade * glow_strength;
	col += range_glow_color.rgb * in_fret_range * 0.22 * depth_fade;
	col += strum_glow_color.rgb * strum_glow * glow_strength;
	col += vec3(fret_line) * depth_fade;

	ALBEDO = col;
	EMISSION = col * (0.50 + lane_energy + fret_line * 0.35);
	ALPHA    = 1.0;
}
