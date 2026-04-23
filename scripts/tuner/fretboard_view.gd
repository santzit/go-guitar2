extends Control
class_name FretboardView

## FretboardView — 3D-style guitar neck with 6 horizontal strings.
##
## Active string effects (driven by tuner.gd):
##   • Static layered glow   — drawn by _draw() as base
##   • Vibrating sine wave   — GLSL shader overlay (animated, runs in _process)
##   • Expanding ring ripples — same GLSL shader (concentric circles from pluck point)
##
## Selected string (manual lock) shows a cyan highlight.
## Clicking a string emits string_pressed(idx).
##
## String index order matches DEFAULT_TUNING_NOTES: 0=E2(thick/top), 5=E4(thin/bottom).
## Visual feedback:
##   • Active string  → bright yellow glow  (currently detected by PitchDetector)
##   • Selected string → cyan soft glow     (manually locked by the player)
##   • Idle strings    → dimmed when another string is active

signal string_pressed(idx: int)

const FRET_COUNT: int = 5

# Per-string display data (index 0 = E2 low, index 5 = E4 high)
const _STRING_DEFAULT_NAMES: PackedStringArray = ["E2", "A2", "D3", "G3", "B3", "E4"]
const _STRING_BASE_COLORS: Array[Color] = [
	Color(0.60, 0.51, 0.36),   # E2 – wound brass
	Color(0.60, 0.52, 0.38),   # A2 – wound
	Color(0.62, 0.54, 0.40),   # D3 – wound
	Color(0.82, 0.78, 0.72),   # G3 – plain/wound
	Color(0.88, 0.88, 0.88),   # B3 – plain
	Color(0.95, 0.95, 0.95),   # E4 – plain (thinnest)
]
const _STRING_WIDTHS: PackedFloat32Array = [5.5, 4.4, 3.4, 2.5, 1.9, 1.3]

# Colours
const _NECK_FACE:      Color = Color(0.13, 0.08, 0.05, 1.0)
const _NECK_TOP_RIM:   Color = Color(0.24, 0.16, 0.10, 1.0)
const _NECK_BOT_RIM:   Color = Color(0.07, 0.04, 0.02, 1.0)
const _FRET_COLOR:     Color = Color(0.74, 0.68, 0.60, 0.85)
const _NUT_COLOR:      Color = Color(0.92, 0.88, 0.80, 1.0)
const _ACTIVE_GLOW:    Color = Color(1.00, 0.93, 0.22, 1.0)
const _SELECTED_GLOW:  Color = Color(0.35, 0.87, 1.00, 1.0)
const _DIM_FACTOR:     float = 0.50

# Layout
const _LABEL_W:       float = 70.0
const _NECK_SIDE_H:   float = 11.0
const _LABEL_FONT_SZ: int   = 21

## Combined shader: vibrating sine wave + expanding concentric ring ripples.
## The ColorRect overlay covers only the neck face; UV (0,0)→(1,1) maps to that rect.
const _VIBRATE_SHADER: String = """
shader_type canvas_item;

uniform float string_y   : hint_range(0.0, 1.0) = 0.5;
uniform float t          = 0.0;
uniform float aspect_r   = 0.13;
uniform vec4  glow_color : source_color = vec4(1.0, 0.93, 0.22, 1.0);

// Vibration
const float VIBE_AMPL  = 0.030;
const float VIBE_FREQ  = 4.5;
const float VIBE_SPEED = 15.0;
const float GLOW_W     = 0.055;
const float CORE_W     = 0.007;

// Ring ripples
const int   RING_COUNT = 4;
const float RING_SPEED = 0.28;
const float RING_MAX_R = 0.45;
const float RING_WIDTH = 0.014;
// RING_STEP = 1.0 / RING_COUNT; hardcoded to avoid a loop-body division in GLSL ES 1.0
const float RING_STEP  = 0.25;

void fragment() {
	vec2  uv   = UV;
	vec3  rgb  = vec3(0.0);
	float alph = 0.0;

	// --- Vibrating string ---
	float wave   = VIBE_AMPL * sin(uv.x * VIBE_FREQ * TAU + t * VIBE_SPEED);
	float ds     = abs(uv.y - string_y - wave);
	float s_glow = smoothstep(GLOW_W, 0.0, ds);
	float s_core = smoothstep(CORE_W, 0.0, ds);
	float s_a    = s_glow * 0.38 + s_core * 0.88;
	rgb  += glow_color.rgb * s_a;
	alph  = max(alph, s_a);

	// --- Expanding ring ripples (ellipse-corrected) ---
	vec2  origin = vec2(0.5, string_y);
	float dx     = uv.x - origin.x;
	float dy     = (uv.y - origin.y) / max(aspect_r, 0.02);
	float r      = length(vec2(dx, dy));

	for (int i = 0; i < RING_COUNT; i++) {
		float phase = mod(t * RING_SPEED + float(i) * RING_STEP, RING_MAX_R);
		float fade  = 1.0 - smoothstep(0.0, RING_MAX_R, phase);
		float rd    = abs(r - phase);
		float rv    = smoothstep(RING_WIDTH, 0.0, rd) * fade * 0.65;
		rgb  += glow_color.rgb * rv * 0.75;
		alph  = max(alph, rv * 0.55);
	}

	COLOR = vec4(rgb, clamp(alph, 0.0, 1.0));
}
"""

var _string_names:        PackedStringArray = _STRING_DEFAULT_NAMES.duplicate()
var _active_string_idx:   int   = -1   # currently detected (yellow + shader)
var _selected_string_idx: int   = -1   # manually locked (cyan)
var _vibration_color:     Color = _ACTIVE_GLOW

var _vibration_rect: ColorRect      = null
var _vibration_mat:  ShaderMaterial = null
var _vibration_time: float          = 0.0


func _ready() -> void:
	_setup_vibration_overlay()


func _setup_vibration_overlay() -> void:
	var sh := Shader.new()
	sh.code = _VIBRATE_SHADER

	_vibration_mat = ShaderMaterial.new()
	_vibration_mat.shader = sh

	_vibration_rect = ColorRect.new()
	_vibration_rect.name         = "VibrationOverlay"
	_vibration_rect.color        = Color.WHITE
	_vibration_rect.material     = _vibration_mat
	_vibration_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vibration_rect.visible      = false

	# Anchor to cover only the neck face area (inside rims + label)
	_vibration_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vibration_rect.offset_left   = _LABEL_W
	_vibration_rect.offset_top    = _NECK_SIDE_H
	_vibration_rect.offset_right  = -6.0
	_vibration_rect.offset_bottom = -_NECK_SIDE_H

	add_child(_vibration_rect)
	_push_aspect_ratio()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _vibration_mat != null:
		_push_aspect_ratio()


func _push_aspect_ratio() -> void:
	var nw: float = maxf(size.x - _LABEL_W - 6.0, 1.0)
	var nh: float = maxf(size.y - 2.0 * _NECK_SIDE_H, 1.0)
	_vibration_mat.set_shader_parameter("aspect_r", nh / nw)


func _process(delta: float) -> void:
	if _vibration_rect == null or _active_string_idx < 0:
		if _vibration_rect != null:
			_vibration_rect.visible = false
		return
	_vibration_time += delta
	_vibration_rect.visible = true
	_vibration_mat.set_shader_parameter("string_y",   (float(_active_string_idx) + 0.5) / 6.0)
	_vibration_mat.set_shader_parameter("t",          _vibration_time)
	_vibration_mat.set_shader_parameter("glow_color", _vibration_color)


# ── Public API ─────────────────────────────────────────────────────────────────

func set_string_names(names: PackedStringArray) -> void:
	if names.size() == 6:
		_string_names = names.duplicate()
		queue_redraw()


func set_active_string(idx: int) -> void:
	if _active_string_idx != idx:
		_active_string_idx = idx
		if idx >= 0:
			# Reset to t=0 so each new string starts with full-amplitude rings,
			# simulating a fresh pluck.
			_vibration_time = 0.0
		queue_redraw()


func set_selected_string(idx: int) -> void:
	if _selected_string_idx != idx:
		_selected_string_idx = idx
		queue_redraw()


func set_vibration_color(color: Color) -> void:
	_vibration_color = color


# ── Input ──────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var si: int = _hit_string(event.position)
		if si >= 0:
			string_pressed.emit(si)
			accept_event()


func _hit_string(pos: Vector2) -> int:
	var neck_top:    float = _NECK_SIDE_H
	var neck_bottom: float = size.y - _NECK_SIDE_H
	var neck_h:      float = neck_bottom - neck_top
	var hit_half:    float = neck_h / 12.0
	for si in range(6):
		var t: float = (float(si) + 0.5) / 6.0
		var y: float = neck_top + t * neck_h
		if absf(pos.y - y) < hit_half:
			return si
	return -1


# ── Drawing ────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y

	var neck_left:   float = _LABEL_W
	var neck_right:  float = w - 6.0
	var neck_top:    float = _NECK_SIDE_H
	var neck_bottom: float = h - _NECK_SIDE_H
	var neck_w:      float = neck_right - neck_left
	var neck_h:      float = neck_bottom - neck_top

	# ── Neck body (3-layer for depth illusion) ──────────────────────────────
	draw_rect(Rect2(neck_left, 0.0, neck_w, _NECK_SIDE_H), _NECK_TOP_RIM)
	draw_rect(Rect2(neck_left, neck_top, neck_w, neck_h), _NECK_FACE)
	draw_rect(Rect2(neck_left, neck_bottom, neck_w, _NECK_SIDE_H), _NECK_BOT_RIM)

	# Subtle wood grain lines
	for gi in range(3):
		var gx: float = neck_left + neck_w * (0.25 + float(gi) * 0.25)
		draw_line(Vector2(gx, neck_top), Vector2(gx, neck_bottom),
				Color(1, 1, 1, 0.025), 1.0)

	# ── Nut (left edge bar) ─────────────────────────────────────────────────
	draw_line(Vector2(neck_left - 1.0, neck_top - 2.0),
			Vector2(neck_left - 1.0, neck_bottom + 2.0), _NUT_COLOR, 7.0)

	# ── Fret wires ──────────────────────────────────────────────────────────
	for fi in range(1, FRET_COUNT + 1):
		var t: float = float(fi) / float(FRET_COUNT)
		var fx: float = neck_left + t * neck_w
		draw_line(Vector2(fx, neck_top), Vector2(fx, neck_bottom), _FRET_COLOR, 2.5)
		# Highlight edge for metallic look
		draw_line(Vector2(fx + 1.5, neck_top), Vector2(fx + 1.5, neck_bottom),
				Color(1.0, 1.0, 1.0, 0.18), 1.0)

	# ── Decorative inlay dot (centred between frets 2-3, simplified) ───────────
	var dot_x: float = neck_left + (2.5 / float(FRET_COUNT)) * neck_w
	var dot_y: float = neck_top + neck_h * 0.5
	draw_circle(Vector2(dot_x, dot_y), 5.0, Color(0.35, 0.25, 0.15, 0.55))

	# ── Strings ─────────────────────────────────────────────────────────────
	var font := ThemeDB.fallback_font
	for si in range(6):
		var t: float = (float(si) + 0.5) / 6.0
		var sy: float = neck_top + t * neck_h
		var sw: float = _STRING_WIDTHS[si]
		var is_active:   bool = si == _active_string_idx
		var is_selected: bool = (not is_active) and si == _selected_string_idx
		var any_highlight: bool = (_active_string_idx >= 0) or (_selected_string_idx >= 0)

		# String shadow (depth)
		draw_line(Vector2(neck_left, sy + 1.5), Vector2(neck_right, sy + 1.5),
				Color(0, 0, 0, 0.38), sw * 0.75, true)

		var base_col: Color = _STRING_BASE_COLORS[si]
		if any_highlight and not is_active and not is_selected:
			base_col = base_col.darkened(_DIM_FACTOR)

		if is_active:
			# Base glow (shader overlay adds animated wave + rings on top)
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					Color(_vibration_color.r, _vibration_color.g, _vibration_color.b, 0.16),
					sw * 12.0, true)
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					Color(_vibration_color.r, _vibration_color.g, _vibration_color.b, 0.42),
					sw * 4.5, true)
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					_vibration_color, sw, true)
		elif is_selected:
			# Cyan selection glow
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					Color(_SELECTED_GLOW.r, _SELECTED_GLOW.g, _SELECTED_GLOW.b, 0.28),
					sw * 8.0, true)
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					_SELECTED_GLOW, sw, true)
		else:
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					base_col, sw, true)

		# ── Left label (note name) ──────────────────────────────────────────
		var label_col: Color
		if is_active:
			label_col = _vibration_color
		elif is_selected:
			label_col = _SELECTED_GLOW
		elif any_highlight:
			label_col = Color(0.42, 0.42, 0.42, 0.75)
		else:
			label_col = Color(0.80, 0.80, 0.80, 0.90)

		var label_y: float = sy + float(_LABEL_FONT_SZ) * 0.38
		draw_string(font, Vector2(4.0, label_y),
				_string_names[si],
				HORIZONTAL_ALIGNMENT_LEFT,
				_LABEL_W - 6.0,
				_LABEL_FONT_SZ,
				label_col)
