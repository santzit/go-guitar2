shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix;

// Highway surface shader: draws fret-separator lines and dynamic glow map.
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
uniform sampler2D fret_glow_map : hint_default_black;
uniform float vertical_line_width : hint_range(0.001, 0.05) = 0.012;
uniform float separator_base_intensity : hint_range(0.0, 4.0) = 1.5;
uniform float separator_glow_strength  : hint_range(0.0, 8.0) = 3.5;
uniform vec4  separator_line_color  : source_color = vec4(0.55, 0.85, 1.00, 1.0);
uniform float separator_line_albedo : hint_range(0.0, 1.0) = 0.5;
uniform float highway_alpha : hint_range(0.0, 1.0) = 0.5;

const int MAX_SHADER_LANES = 6; // lane_intensity uniforms are packed for 6 lanes.
const int MAX_FRET_LINES = 25;

float lane_intensity(int lane) {
	if (lane < 0 || lane >= string_count || lane >= MAX_SHADER_LANES) return 0.0;
	if (lane == 0) return lane_intensity_0_3.x;
	if (lane == 1) return lane_intensity_0_3.y;
	if (lane == 2) return lane_intensity_0_3.z;
	if (lane == 3) return lane_intensity_0_3.w;
	if (lane == 4) return lane_intensity_4_5.x;
	return lane_intensity_4_5.y;
}

// Procedural separator line mask: returns 0..1 based on distance from nearest fret boundary.
// Uses pure math so there is no texture-loading dependency.
float separator_line_mask(vec2 uv) {
	float half_width = vertical_line_width * 0.5;
	float fc = max(float(fret_count), 0.0001);
	float best = 0.0;
	for (int i = 0; i < MAX_FRET_LINES; i++) {
		if (i > fret_count) {
			break;
		}
		float fret_x = float(i) / fc;
		float dist = abs(uv.x - fret_x);
		if (dist < half_width) {
			// Linear falloff from centre (1.0) to edge (0.0)
			best = max(best, 1.0 - dist / half_width);
		}
	}
	return best;
}

// Sample the dynamic glow map at the nearest fret boundary column.
float separator_glow(vec2 uv) {
	float x_f = uv.x * float(fret_count);
	float boundary_idx = clamp(round(x_f), 0.0, float(fret_count));
	float u = (boundary_idx + 0.5) / float(fret_count + 1);
	return texture(fret_glow_map, vec2(u, uv.y)).r;
}

void fragment() {
	float sep_mask = separator_line_mask(UV);
	float glow     = separator_glow(UV);
	float emission_strength = separator_base_intensity + glow * separator_glow_strength;

	vec3 line_rgb = separator_line_color.rgb;

	// Blend line colour into ALBEDO so lines are visible regardless of EMISSION behavior.
	ALBEDO  = mix(base_color.rgb, line_rgb * separator_line_albedo, sep_mask);
	// EMISSION drives HDR bloom; values >0.5 exceed the glow_hdr_threshold.
	EMISSION = line_rgb * sep_mask * emission_strength;
	ALPHA    = highway_alpha;
}
