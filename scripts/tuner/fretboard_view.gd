extends Control
class_name FretboardView

## FretboardView — draws a stylised guitar neck (portrait-style, horizontal strings).
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

var _string_names: PackedStringArray = _STRING_DEFAULT_NAMES.duplicate()
var _active_string_idx:   int = -1   # detected right now (yellow)
var _selected_string_idx: int = -1   # manually locked (cyan)


func set_string_names(names: PackedStringArray) -> void:
	if names.size() == 6:
		_string_names = names.duplicate()
		queue_redraw()


func set_active_string(idx: int) -> void:
	if _active_string_idx != idx:
		_active_string_idx = idx
		queue_redraw()


func set_selected_string(idx: int) -> void:
	if _selected_string_idx != idx:
		_selected_string_idx = idx
		queue_redraw()


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

	# ── Fret position dot (12th-fret style, single) ─────────────────────────
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
			# Outer glow layer
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					Color(_ACTIVE_GLOW.r, _ACTIVE_GLOW.g, _ACTIVE_GLOW.b, 0.16),
					sw * 12.0, true)
			# Mid glow layer
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					Color(_ACTIVE_GLOW.r, _ACTIVE_GLOW.g, _ACTIVE_GLOW.b, 0.42),
					sw * 4.5, true)
			# String core
			draw_line(Vector2(neck_left, sy), Vector2(neck_right, sy),
					_ACTIVE_GLOW, sw, true)
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
			label_col = _ACTIVE_GLOW
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
