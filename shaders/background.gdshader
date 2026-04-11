shader_type spatial;
render_mode cull_disabled, unshaded;

// ── Gradient backdrop colours ─────────────────────────────────────────────
uniform vec4  color_top      : source_color = vec4(0.05, 0.02, 0.18, 1.0);
uniform vec4  color_bottom   : source_color = vec4(0.00, 0.00, 0.04, 1.0);
// ── Central stage-spotlight oval ──────────────────────────────────────────
uniform vec4  glow_color     : source_color = vec4(0.18, 0.08, 0.40, 1.0);
uniform float glow_strength  : hint_range(0.0, 3.0) = 1.2;

void fragment() {
	// Vertical gradient (UV.y = 0 at bottom edge, 1 at top edge)
	vec4 grad = mix(color_bottom, color_top, UV.y);

	// Soft oval spotlight centred slightly below middle
	vec2  c    = UV - vec2(0.5, 0.30);
	float dist = length(c * vec2(0.7, 1.4));
	float glow = smoothstep(0.55, 0.0, dist) * glow_strength;

	ALBEDO = grad.rgb + glow_color.rgb * glow;
	ALPHA  = 1.0;
}
