extends Node3D
## note.gd  –  behaviour for a single pooled note with 3D BoxMesh finger indicators.
##
## All coordinate formulas live in scripts/common.gd (class ChartCommon) so they
## can be shared with highway.gd, music_play.gd, and fretboard.gd.
##
## Coordinate mapping summary
##   X = ChartCommon.fret_mid_world_x(fret)      — ChartPlayer fret spacing
##   Y = ChartCommon.string_world_y(string_index) — string 0 = top, 5 = bottom
##   Z = STRUM_Z − (time_offset − song_time) × TRAVEL_SPEED
##       Notes spawn at Z = -20 and travel toward Z = 0.
##
## Finger indicator is a 3D mesh (assets/models/note.obj) with a border mesh:
##   - Visual states: filled → transparent (final 1s) → hit flash

# ── Per-string note colors (string 0 top → string 5 bottom) ───────────────────
const STRING_COLORS: Array[Color] = [
	Color(0.98, 0.26, 0.22, 1.0), # red
	Color(0.98, 0.78, 0.16, 1.0), # yellow
	Color(0.20, 0.80, 0.95, 1.0), # cyan
	Color(1.00, 0.55, 0.10, 1.0), # orange
	Color(0.20, 0.88, 0.30, 1.0), # green
	Color(0.72, 0.38, 0.98, 1.0), # purple
]

# ── Digit scenes (0–9) used to display the fret number on each note ──────────
const DIGIT_SCENES: Array[PackedScene] = [
	preload("res://scenes/number_0.tscn"),
	preload("res://scenes/number_1.tscn"),
	preload("res://scenes/number_2.tscn"),
	preload("res://scenes/number_3.tscn"),
	preload("res://scenes/number_4.tscn"),
	preload("res://scenes/number_5.tscn"),
	preload("res://scenes/number_6.tscn"),
	preload("res://scenes/number_7.tscn"),
	preload("res://scenes/number_8.tscn"),
	preload("res://scenes/number_9.tscn"),
]

## Visual constants for 3D box indicators
const LABEL_Z : float = 0.06
const DIGIT_X_OFFSET : float = 0.07
const START_Z       : float = -20.0
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = 2.0
const MISS_HOLD_SECS: float = 1.0
const MISS_LABEL_Z  : float = 0.30
const APPROACH_FADE_SECS: float = 1.0
const HIT_FLASH_SECS: float = 0.25
const BOX_DEPTH: float = 0.04
const BORDER_EXTRA: float = 0.012
const NOTE_MODEL_BASE_SIZE: Vector3 = Vector3(0.12, 0.2, 0.6)

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0
var _hit_fx_start: float = -1.0
var _last_sized_fret: int = -1
var _indicator_color: Color = Color(1.0, 0.5, 0.1, 1.0)

var _fill_mat: StandardMaterial3D = null
var _border_mat: StandardMaterial3D = null
var _finger_base_scale: Vector3 = Vector3.ONE
var _border_base_scale: Vector3 = Vector3.ONE

@onready var _finger     : MeshInstance3D = $FingerIndicator
@onready var _finger_border: MeshInstance3D = $FingerBorder
@onready var _fret_label : Node3D         = $FretLabel
@onready var _miss_label : Label3D        = $MissLabel


func _ready() -> void:
	if _finger:
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fill_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.0)
		_fill_mat.metallic = 0.15
		_fill_mat.roughness = 0.25
		_fill_mat.metallic_specular = 1.0
		_fill_mat.emission_enabled = true
		_fill_mat.emission = Color(1.0, 0.6, 0.2, 1.0)
		_fill_mat.emission_energy_multiplier = 0.0
		_finger.set_surface_override_material(0, _fill_mat)

		_border_mat = StandardMaterial3D.new()
		_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_border_mat.albedo_color = Color(1.0, 0.7, 0.25, 0.7)
		_border_mat.metallic = 0.05
		_border_mat.roughness = 0.3
		_border_mat.emission_enabled = true
		_border_mat.emission = Color(1.0, 0.7, 0.25, 1.0)
		_border_mat.emission_energy_multiplier = 1.5
		if _finger_border:
			_finger_border.set_surface_override_material(0, _border_mat)
		_update_indicator_geometry(1)

	if _miss_label:
		_miss_label.position = Vector3(0.0, 0.0, MISS_LABEL_Z)


func setup(p_fret: int, p_string: int, p_time: float, p_duration: float, p_show_label: bool = true) -> void:
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	is_active    = true
	visible      = true
	_miss_until  = -1.0
	_hit_fx_start = -1.0

	position = Vector3(ChartCommon.fret_mid_world_x(fret - 1), ChartCommon.string_world_y(string_index), START_Z)
	_miss_label.visible = false

	if _finger:
		if fret != _last_sized_fret:
			_last_sized_fret = fret
			_update_indicator_geometry(fret)
		_indicator_color = STRING_COLORS[string_index]
		_update_indicator_visuals(0.85, 0.95, 1.0, 1.0)
		_finger.scale = _finger_base_scale
		if _finger_border:
			_finger_border.scale = _border_base_scale

	if p_show_label:
		_rebuild_fret_label()
	else:
		for child in _fret_label.get_children():
			_fret_label.remove_child(child)
			child.free()


func _rebuild_fret_label() -> void:
	for child in _fret_label.get_children():
		_fret_label.remove_child(child)
		child.free()

	if fret < 1 or fret > 24:
		return

	var tens := fret / 10
	var ones := fret % 10

	if tens > 0:
		var d_tens := DIGIT_SCENES[tens].instantiate()
		d_tens.position = Vector3(-DIGIT_X_OFFSET, 0.0, LABEL_Z)
		_fret_label.add_child(d_tens)

		var d_ones := DIGIT_SCENES[ones].instantiate()
		d_ones.position = Vector3(DIGIT_X_OFFSET, 0.0, LABEL_Z)
		_fret_label.add_child(d_ones)
	else:
		var d := DIGIT_SCENES[ones].instantiate()
		d.position = Vector3(0.0, 0.0, LABEL_Z)
		_fret_label.add_child(d)


func tick(p_song_time: float) -> void:
	if not is_active:
		return

	position.z = STRUM_Z - (time_offset - p_song_time) * TRAVEL_SPEED
	_update_hit_visuals(p_song_time)

	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD_SECS
		_miss_label.visible = true

	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


func deactivate() -> void:
	is_active    = false
	visible      = false
	_miss_label.visible = false
	_miss_until  = -1.0
	_hit_fx_start = -1.0
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func _update_indicator_geometry(fret_num: int) -> void:
	if _finger == null:
		return
	var sz2: Vector2 = ChartCommon.note_indicator_size(fret_num)
	_finger_base_scale = Vector3(
		sz2.x / NOTE_MODEL_BASE_SIZE.x,
		sz2.y / NOTE_MODEL_BASE_SIZE.y,
		BOX_DEPTH / NOTE_MODEL_BASE_SIZE.z
	)

	if _finger_border:
		_border_base_scale = Vector3(
			(sz2.x + BORDER_EXTRA) / NOTE_MODEL_BASE_SIZE.x,
			(sz2.y + BORDER_EXTRA) / NOTE_MODEL_BASE_SIZE.y,
			(BOX_DEPTH + BORDER_EXTRA) / NOTE_MODEL_BASE_SIZE.z
		)
	else:
		_border_base_scale = Vector3.ONE


func _update_hit_visuals(song_time: float) -> void:
	var lead: float = time_offset - song_time
	if _hit_fx_start < 0.0:
		if lead <= 0.0:
			_hit_fx_start = song_time
			lead = 0.0
		var fill_alpha: float = 0.85
		var border_alpha: float = 0.95
		var emit_energy: float = 1.0
		if lead <= APPROACH_FADE_SECS:
			var ramp: float = clampf((APPROACH_FADE_SECS - lead) / APPROACH_FADE_SECS, 0.0, 1.0)
			fill_alpha = 0.0
			border_alpha = lerpf(0.95, 1.0, ramp)
			emit_energy = lerpf(1.0, 1.6, ramp)
		_update_indicator_visuals(fill_alpha, border_alpha, emit_energy, 1.0)
		return

	var t: float = clampf((song_time - _hit_fx_start) / HIT_FLASH_SECS, 0.0, 1.0)
	var fade: float = 1.0 - t
	var pulse: float = sin(t * PI)
	var scale_boost: float = 1.0 + pulse * 0.2
	_update_indicator_visuals(fade, fade, lerpf(3.5, 0.0, t), scale_boost)


func _update_indicator_visuals(fill_alpha: float, border_alpha: float, emission_energy: float, scale_mul: float) -> void:
	if _fill_mat:
		var fill_col := _indicator_color
		fill_col.a = clampf(fill_alpha, 0.0, 1.0)
		_fill_mat.albedo_color = fill_col
		_fill_mat.emission = _indicator_color
		_fill_mat.emission_energy_multiplier = maxf(0.0, emission_energy)
	if _border_mat:
		var edge_col := _indicator_color.lightened(0.25)
		edge_col.a = clampf(border_alpha, 0.0, 1.0)
		_border_mat.albedo_color = edge_col
		_border_mat.emission = _indicator_color.lightened(0.2)
		_border_mat.emission_energy_multiplier = maxf(0.0, emission_energy * 0.8)
	if _finger:
		_finger.scale = _finger_base_scale * scale_mul
	if _finger_border:
		_finger_border.scale = _border_base_scale * scale_mul
