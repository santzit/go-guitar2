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
uniform float separator_base_intensity : hint_range(0.0, 4.0) = 2.0;
// Glow map R channel = note-start intensity (bright flash at note head).
// Glow map G channel = sustain intensity (soft persistent glow along sustain tail).
uniform float note_start_glow_strength : hint_range(0.0, 12.0) = 8.0;
uniform float sustain_glow_strength    : hint_range(0.0, 6.0)  = 2.0;
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

// Sample the runtime glow texture at the nearest fret boundary column.
// Returns vec2(note_start_intensity, sustain_intensity) from the RG8 map.
vec2 separator_glow(vec2 uv) {
	float x_f      = uv.x * float(fret_count);
	float boundary = clamp(round(x_f), 0.0, float(fret_count));
	float u        = (boundary + 0.5) / float(fret_count + 1);
	return texture(fret_glow_map, vec2(u, uv.y)).rg;
}

// Sample both boundary columns that flank the current UV.x position and take
// the maximum. This spreads the glow across the entire fret lane rather than
// only on the thin separator line pixels — making the floor visibly glow near
// note positions even between the lines.
vec2 separator_glow_floor(vec2 uv) {
	float fc    = max(float(fret_count), 1.0);
	float x_f   = uv.x * fc;
	float left  = clamp(floor(x_f), 0.0, fc);
	float right  = clamp(ceil(x_f),  0.0, fc);
	float inv   = 1.0 / (fc + 1.0);
	vec2 gl = texture(fret_glow_map, vec2((left  + 0.5) * inv, uv.y)).rg;
	vec2 gr = texture(fret_glow_map, vec2((right + 0.5) * inv, uv.y)).rg;
	return max(gl, gr);
}

void fragment() {
	float mask       = separator_line_mask(UV);
	vec2  line_glow  = separator_glow(UV);
	vec2  floor_glow = separator_glow_floor(UV);

	// Separator line emission: base glow + note-start bright flash + sustain dim glow.
	float line_emission = separator_base_intensity
		+ line_glow.r * note_start_glow_strength
		+ line_glow.g * sustain_glow_strength;

	// Floor area glow: spreads across the full fret lane.
	// Note-start uses 25% of line strength (bright); sustain uses 40% of its own strength (dim).
	// This gives a clearly visible pool of light under note heads that fades along sustain tails.
	float floor_emission = floor_glow.r * note_start_glow_strength * 0.25
	                     + floor_glow.g * sustain_glow_strength * 0.40;

	vec3 line_rgb = separator_line_color.rgb;

	// ALBEDO: separator line colour on lines; floor tinted with note glow between lines.
	ALBEDO = mix(base_color.rgb + line_rgb * floor_emission * 0.35, line_rgb, mask);
	// EMISSION: separator lines glow brightly; floor area emits dimmer glow from note positions.
	EMISSION = line_rgb * mask * line_emission
	         + line_rgb * (1.0 - mask) * floor_emission;
	// ALPHA is implicitly 1.0 in the opaque render_mode (no blend_mix).
}
