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
uniform sampler2D fret_glow_map : hint_default_black;
// Width of each separator line, in UV space (0–1 across all 24 frets).
// 0.003 ≈ 0.07 world-units per line — thin crisp line visible from the play camera.
uniform float vertical_line_width : hint_range(0.001, 0.1) = 0.003;
uniform float separator_base_intensity : hint_range(0.0, 4.0) = 0.5;
// Glow map R channel = note-start intensity (bright flash at note head).
// Glow map G channel = sustain intensity (soft persistent glow along sustain tail).
uniform float note_start_glow_strength : hint_range(0.0, 30.0) = 20.0;
uniform float sustain_glow_strength    : hint_range(0.0, 10.0)  = 5.0;
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

// Sample per-boundary glow data from a 1D RGBA8 texture (single row):
//   R = note-start peak intensity  [0..1]
//   G = note-head UV.y position    [0 = far end, 1 = strum line]
//   B = sustain peak intensity     [0..1]
//   A = sustain-tail UV.y position [0..1, always <= G]
// Returns vec2(note_start_glow, sustain_glow) by computing a Gaussian in UV.y space
// so the mark tracks the note regardless of texture resolution or V-axis direction.
vec2 separator_glow(vec2 uv) {
	float x_f      = uv.x * float(fret_count);
	float boundary = clamp(round(x_f), 0.0, float(fret_count));
	float tex_u    = (boundary + 0.5) / float(fret_count + 1);

	// Always sample the single row of the 1D texture (V = 0.5).
	vec4 data    = texture(fret_glow_map, vec2(tex_u, 0.5));
	float peak   = data.r;   // note-start peak intensity
	float note_v = data.g;   // UV.y of note head (0=far, 1=strum)
	float sus_p  = data.b;   // sustain peak intensity
	float sus_v  = data.a;   // UV.y of sustain tail (farther from strum ⟹ smaller)

	// Gaussian mark centred at the note head's UV.y position (σ ≈ 0.10 UV units).
	float dv   = uv.y - note_v;
	float mark = peak * exp(-dv * dv * 100.0);

	// Sustain fill: from sus_v (tail) up to note_v (head), inclusive.
	float in_s    = step(sus_v, uv.y) * (1.0 - step(note_v + 0.005, uv.y));
	float sustain = sus_p * in_s;

	return vec2(mark, sustain);
}

void fragment() {
	float mask = separator_line_mask(UV);
	vec2  glow = separator_glow(UV);

	// Only the separator line pixels glow. The emission scales from the dim base
	// to a very bright flash at note-start and a softer glow along sustains.
	// The contrast (dim base vs bright note mark) is what makes the moving mark
	// clearly visible against the thin quiescent lines.
	float emission_strength = separator_base_intensity
		+ glow.r * note_start_glow_strength
		+ glow.g * sustain_glow_strength;

	vec3 line_rgb = separator_line_color.rgb;

	// Full-brightness ALBEDO on separator line pixels; base floor elsewhere.
	ALBEDO   = mix(base_color.rgb, line_rgb, mask);
	// EMISSION only on line pixels — creates a bright mark that follows the note.
	EMISSION = line_rgb * mask * emission_strength;
	// ALPHA is implicitly 1.0 in the opaque render_mode (no blend_mix).
}
