shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never;

// 24 fret columns drawn across the highway width (X axis).
// Strings are NOT lanes on this surface — they are the Y (height) of each note.
uniform int   fret_count       : hint_range(1, 24) = 24;
uniform vec4  highway_color    : source_color = vec4(0.06, 0.06, 0.14, 1.0);
uniform vec4  fret_line_color  : source_color = vec4(0.45, 0.45, 0.80, 1.0);
// Alternating lane tint so individual fret columns are easy to count.
uniform vec4  lane_tint_a      : source_color = vec4(0.08, 0.08, 0.18, 1.0);
uniform vec4  lane_tint_b      : source_color = vec4(0.06, 0.06, 0.12, 1.0);
uniform vec4  strum_glow_color : source_color = vec4(0.90, 0.90, 1.00, 1.0);
uniform float fret_line_width  : hint_range(0.005, 0.10) = 0.035;
uniform float glow_strength    : hint_range(0.0,   3.0)  = 0.40;

void fragment() {
	vec2  uv       = UV;

	// ── Fret-column index (0 … fret_count-1) along the X axis ────────────
	float fret_uv   = uv.x * float(fret_count);
	float fret_idx  = floor(fret_uv);        // which fret column we are in
	float fret_frac = fract(fret_uv);        // 0…1 within that column
	bool  on_line   = fret_frac < fret_line_width || fret_frac > 1.0 - fret_line_width;

	// ── Alternating lane background (makes all 24 lanes easy to see) ──────
	float checker   = mod(fret_idx, 2.0);
	vec4  lane_col  = mix(lane_tint_a, lane_tint_b, checker);

	// ── Blend: line > lane colour ─────────────────────────────────────────
	vec4  col = on_line ? mix(lane_col, fret_line_color, 0.90) : lane_col;

	// ── Soft glow along each lane centre ─────────────────────────────────
	float lane_centre = 1.0 - abs(fret_frac * 2.0 - 1.0);
	col.rgb += fret_line_color.rgb * lane_centre * glow_strength * 0.10;

	// ── Depth fade: brighter near the strum line (uv.y → 0) ──────────────
	float depth_fade = 1.0 - uv.y * 0.55;
	col.rgb *= depth_fade;

	// ── Strum-line edge glow at the near edge (uv.y ≈ 0) ─────────────────
	float strum_glow = smoothstep(0.04, 0.0, uv.y);
	col.rgb += strum_glow_color.rgb * strum_glow * glow_strength;

	ALBEDO   = col.rgb;
	EMISSION = col.rgb * glow_strength * 0.5;
	ALPHA    = col.a;
}
