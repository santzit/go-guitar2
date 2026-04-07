shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_opaque;

// Number of fret columns drawn across the highway width (X axis).
uniform int fret_count : hint_range(1, 24) = 24;
// Number of string lanes (visual guide depth lines along Z axis).
uniform int string_count : hint_range(1, 6) = 6;

uniform vec4 highway_color    : source_color = vec4(0.06, 0.06, 0.14, 1.0);
uniform vec4 fret_line_color  : source_color = vec4(0.40, 0.40, 0.75, 1.0);
uniform vec4 string_lane_color: source_color = vec4(0.15, 0.55, 0.15, 1.0);
uniform vec4 strum_glow_color : source_color = vec4(0.90, 0.90, 1.00, 1.0);

uniform float fret_line_width  : hint_range(0.001, 0.15) = 0.030;
uniform float string_lane_width: hint_range(0.001, 0.15) = 0.018;
uniform float glow_strength    : hint_range(0.0,  3.0)   = 0.40;

void fragment() {
	vec2 uv = UV;

	// ── Base highway colour ───────────────────────────────────────────────
	vec4 col = highway_color;

	// ── Fret lanes (vertical bands along X) ──────────────────────────────
	float fret_uv   = uv.x * float(fret_count);
	float fret_frac = fract(fret_uv);
	bool on_fret    = fret_frac < fret_line_width || fret_frac > 1.0 - fret_line_width;
	if (on_fret) {
		col = mix(col, fret_line_color, 0.9);
	}

	// ── String guide lanes (horizontal bands along Z / depth) ────────────
	float str_uv   = uv.y * float(string_count);
	float str_frac = fract(str_uv);
	bool on_string  = str_frac < string_lane_width || str_frac > 1.0 - string_lane_width;
	if (on_string && !on_fret) {
		col = mix(col, string_lane_color, 0.75);
	}

	// ── Fret centre soft glow ─────────────────────────────────────────────
	float fret_centre  = 1.0 - abs(fract(fret_uv + 0.5) * 2.0 - 1.0);
	col.rgb += fret_line_color.rgb * fret_centre * glow_strength * 0.12;

	// ── Depth fade: brighter near the strum line (uv.y → 0) ──────────────
	float depth_fade = 1.0 - uv.y * 0.55;
	col.rgb *= depth_fade;

	// ── Strum-line edge glow (very bottom of surface) ────────────────────
	float strum_glow = smoothstep(0.04, 0.0, uv.y);
	col.rgb += strum_glow_color.rgb * strum_glow * glow_strength;

	ALBEDO   = col.rgb;
	EMISSION = col.rgb * glow_strength * 0.5;
	ALPHA    = col.a;
}
