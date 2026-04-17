shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix;

// Fixed highway mesh. Visual effects are currently disabled for a flat base look.
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
uniform sampler2D fret_glow_map : hint_default_black;
uniform float vertical_line_width : hint_range(0.001, 0.05) = 0.008;
uniform float vertical_line_strength : hint_range(0.0, 2.0) = 0.55;
uniform float separator_base_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float separator_glow_strength  : hint_range(0.0, 6.0) = 2.2;
uniform vec4 separator_glow_color : source_color = vec4(0.40, 0.85, 1.00, 1.0);
uniform float highway_alpha : hint_range(0.0, 1.0) = 0.5;

const int MAX_SHADER_LANES = 6; // lane_intensity uniforms are packed for 6 lanes.
const int MAX_FRET_LINES = 25;
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
	return fret_num;
}

float vertical_fret_line_alpha(vec2 uv) {
	float max_pos = max(chart_fret_pos(float(fret_count)), MIN_FRET_POS);
	int fret_limit = min(fret_count, MAX_FRET_LINES - 1);
	float half_width = vertical_line_width * 0.5;
	float alpha = 0.0;
	for (int i = 0; i < MAX_FRET_LINES; i++) {
		// MAX_FRET_LINES=25 lets fret_count=24 draw boundaries for fret 0..24.
		if (i > fret_limit) {
			break;
		}
		float fret_x = chart_fret_pos(float(i)) / max_pos;
		if (abs(uv.x - fret_x) > half_width) {
			continue;
		}
		float local_u = (uv.x - fret_x) / vertical_line_width + 0.5;
		float line_sample = texture(vertical_fret_line_tex, vec2(local_u, uv.y)).a;
		alpha = max(alpha, line_sample);
	}
	return alpha * vertical_line_strength;
}

float separator_glow(vec2 uv) {
	float x_f = uv.x * float(fret_count);
	float boundary_idx = clamp(round(x_f), 0.0, float(fret_count));
	float u = (boundary_idx + 0.5) / float(fret_count + 1);
	return texture(fret_glow_map, vec2(u, uv.y)).r;
}

void fragment() {
	ALBEDO = base_color.rgb;
	float separator_mask = vertical_fret_line_alpha(UV);
	float glow = separator_glow(UV);
	float emission_strength = separator_base_intensity + glow * separator_glow_strength;
	EMISSION = separator_glow_color.rgb * separator_mask * emission_strength;
	ALPHA    = highway_alpha;
}
