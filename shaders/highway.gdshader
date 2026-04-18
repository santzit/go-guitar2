shader_type spatial;
// Opaque, unlit highway floor. Notes, strings, and fret markers are rendered
// above Y=0, so the highway can be fully opaque without hiding any game objects.
render_mode cull_disabled, unshaded;

uniform int   fret_count       : hint_range(1, 24) = 24;
uniform int   string_count     : hint_range(1, 6) = 6;
uniform int   active_fret_min  : hint_range(0, 24) = 0;
uniform int   active_fret_max  : hint_range(-1, 24) = -1;

uniform vec4  base_color       : source_color = vec4(0.04, 0.04, 0.07, 1.0);
uniform vec4  lane_glow_color  : source_color = vec4(0.30, 0.70, 1.00, 1.0);
uniform vec4  range_glow_color : source_color = vec4(0.95, 0.95, 1.00, 1.0);
uniform vec4  strum_glow_color : source_color = vec4(0.40, 0.80, 1.00, 1.0);
uniform vec4  lane_intensity_0_3 = vec4(0.0);
uniform vec2  lane_intensity_4_5 = vec2(0.0);
uniform float lane_width       : hint_range(0.05, 0.95) = 0.65;
uniform float lane_glow_power  : hint_range(0.1, 4.0) = 1.6;
uniform float pulse_speed      : hint_range(0.0, 10.0) = 3.0;
uniform float glow_strength    : hint_range(0.0, 3.0) = 1.2;
// Width of each separator line, in UV space (0–1 across the full highway).
// half_width_world = vertical_line_width × highway_width × 0.5
// 0.0015 × 48 × 0.5 = 0.036 world-unit half-width → ~0.07 world-unit full line.
uniform float vertical_line_width : hint_range(0.0005, 0.1) = 0.0015;
uniform float separator_base_intensity : hint_range(0.0, 4.0) = 2.0;
uniform vec4  separator_line_color  : source_color = vec4(0.55, 0.85, 1.00, 1.0);

const int MAX_SHADER_LANES = 6;

float lane_intensity(int lane) {
	if (lane < 0 || lane >= string_count || lane >= MAX_SHADER_LANES) return 0.0;
	if (lane == 0) return lane_intensity_0_3.x;
	if (lane == 1) return lane_intensity_0_3.y;
	if (lane == 2) return lane_intensity_0_3.z;
	if (lane == 3) return lane_intensity_0_3.w;
	if (lane == 4) return lane_intensity_4_5.x;
	return lane_intensity_4_5.y;
}

// Procedural separator line mask using fract() – no loop required.
// UV.x spans fret 0 (left) → fret 24 (right) linearly.
// Returns a smooth 0..1 weight that peaks at each integer fret boundary.
float separator_line_mask(vec2 uv) {
	float fc = max(float(fret_count), 1.0);
	// Map UV.x into fret-coordinate space so each fret occupies [0,1].
	float fret_u = uv.x * fc;
	// Distance from the nearest integer boundary (0 at boundary, 0.5 at fret centre).
	float dist = min(fract(fret_u), 1.0 - fract(fret_u));
	// Half-width in fret-coordinate units (clamped to avoid smoothstep(a,a,x)).
	float half_width = max(vertical_line_width * fc * 0.5, 0.001);
	// Smooth falloff: 1 at boundary centre, 0 at half_width away.
	return 1.0 - smoothstep(0.0, half_width, dist);
}

void fragment() {
	float fc       = max(float(fret_count), 1.0);
	float sc       = max(float(string_count), 1.0);
	// fret_u: 0.0 at fret 0 (X=0), fc at fret 24 (X=48).
	// Each unit of fret_u = FRET_SPACING (2 world-units) on the highway.
	float fret_u   = UV.x * fc;

	// ── Active fret-range highlight ───────────────────────────────────────────
	// Smooth ramp in/out at range edges (±0.5 fret = ±1 world-unit fade).
	float range_mask = 0.0;
	if (active_fret_max >= active_fret_min && active_fret_min >= 0) {
		float fmin = float(active_fret_min);
		float fmax = float(active_fret_max);
		range_mask = smoothstep(fmin - 0.5, fmin + 0.5, fret_u)
		           * (1.0 - smoothstep(fmax - 0.5, fmax + 0.5, fret_u));
	}

	// ── Lane glow ─────────────────────────────────────────────────────────────
	// The fretboard is divided into string_count (6) lanes, each spanning
	// fret_count / string_count = 4 frets = 8 world-units (the 2 unit/m grid).
	// lane_intensity(N) carries the per-lane brightness set by set_lane_intensities().
	float frets_per_lane = max(fc / sc, 0.001);   // guard against degenerate fret_count/string_count
	int   lane_idx  = clamp(int(fret_u / frets_per_lane), 0, int(sc) - 1);
	float lint      = lane_intensity(lane_idx);

	// Fractional position within the lane slot [0, 1].
	float lane_u      = mod(fret_u, frets_per_lane) / frets_per_lane;
	// Distance from the slot centre (0 = centre, 0.5 = edge).
	float center_dist = abs(lane_u - 0.5);
	float glow_half   = clamp(lane_width * 0.5, 0.01, 0.49);
	float lane_mask   = lint * (1.0 - smoothstep(0.0, glow_half, center_dist));
	// Apply glow power directly: higher values = sharper, more concentrated glow.
	lane_mask = pow(clamp(lane_mask, 0.0, 1.0), max(lane_glow_power, 0.1));
	// Subtle pulse animation.
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
	lane_mask  *= (1.0 + pulse * 0.15);

	// ── Fret separator lines ──────────────────────────────────────────────────
	float sep_mask = separator_line_mask(UV);
	vec3  line_rgb = separator_line_color.rgb;

	// ── Compose final colour ──────────────────────────────────────────────────
	float lane_contrib = clamp(lane_mask * glow_strength, 0.0, 1.0);
	vec3  col = base_color.rgb;
	col = mix(col, range_glow_color.rgb, range_mask * 0.15);
	col = mix(col, lane_glow_color.rgb,  lane_contrib);
	col = mix(col, line_rgb,             sep_mask);

	ALBEDO   = col;
	// EMISSION: separator lines glow at full intensity; lane glow adds softer fill.
	EMISSION = line_rgb * sep_mask * separator_base_intensity
	         + lane_glow_color.rgb * lane_contrib;
	// ALPHA is implicitly 1.0 in the opaque render_mode (no blend_mix).
}
