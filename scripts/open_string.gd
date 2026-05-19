extends Node3D
class_name OpenString

const ChartCommon = preload("res://scripts/common.gd")
const EventLifecycle = preload("res://scripts/event_lifecycle.gd")

const START_Z: float = -ChartCommon.HIGHWAY_DEPTH
const STRUM_Z: float = 0.0
const TRAVEL_SPEED: float = ChartCommon.Z_UNITS_PER_SECOND
const OPEN_STRING_SPAN_FRETS: int = 4
const OPEN_STRING_LOCAL_Z: float = 0.08
const NOTE_MARKER_NEON_GLOW_BASE: float = 2.4
const NOTE_MARKER_NEON_GLOW_PULSE: float = 0.8
const NOTE_MARKER_PULSE_FREQUENCY: float = 8.0
const NOTE_VISUAL_ALPHA: float = 0.4
const SUSTAIN_MIN_SECS: float = 0.05
const SUSTAIN_TRAIL_HEIGHT: float = 0.08
const SUSTAIN_MIN_LENGTH: float = SUSTAIN_MIN_SECS * TRAVEL_SPEED

var fret: int = 0
var string_index: int = 0
var hand_fret_start: int = 1
var visual_base_fret: int = -1
var time_offset: float = 0.0
var duration: float = 0.25
var is_active: bool = false
var _head_hidden: bool = false
var _lifecycle: EventLifecycle = EventLifecycle.new()
var _marker_mat: StandardMaterial3D = null
var _sustain_trail: MeshInstance3D = null
var _sustain_trail_mat: StandardMaterial3D = null

@onready var _marker: MeshInstance3D = $OpenStringMarker


func _ready() -> void:
	_ensure_visual_nodes()


func _ensure_visual_nodes() -> void:
	if _marker == null:
		_marker = get_node_or_null("OpenStringMarker") as MeshInstance3D
	if _marker:
		if _marker_mat == null:
			_marker_mat = _marker.get_surface_override_material(0) as StandardMaterial3D
	if _sustain_trail == null:
		_sustain_trail = get_node_or_null("SustainTrail") as MeshInstance3D
	if _sustain_trail:
		if _sustain_trail_mat == null:
			_sustain_trail_mat = _sustain_trail.get_surface_override_material(0) as StandardMaterial3D
		_sustain_trail.visible = false


func setup(
		p_fret: int,
		p_string: int,
		p_time: float,
		p_duration: float,
		_unused_show_lane_connector: bool = false,
		p_hand_fret_start: int = 1,
		p_visual_base_fret: int = -1
) -> void:
	_ensure_visual_nodes()
	fret = p_fret
	string_index = clampi(p_string, 0, ChartCommon.STRING_COUNT - 1)
	hand_fret_start = clampi(p_hand_fret_start, 1, ChartCommon.FRET_COUNT)
	visual_base_fret = clampi(p_visual_base_fret, 1, ChartCommon.FRET_COUNT) if p_visual_base_fret >= 1 else -1
	time_offset = p_time
	duration = maxf(p_duration, 0.0)
	is_active = true
	visible = true
	_head_hidden = false
	_lifecycle.setup(time_offset, duration, SUSTAIN_MIN_SECS, true)

	var anchor_fret_start: int = _anchor_fret_start()
	var left_x: float = ChartCommon.fret_separator_world_x(anchor_fret_start - 1)
	var right_x: float = ChartCommon.fret_separator_world_x(mini(anchor_fret_start + 3, ChartCommon.FRET_COUNT))
	var center_x: float = (left_x + right_x) * 0.5
	position = Vector3(center_x, ChartCommon.string_world_y(string_index), START_Z)
	if _marker != null:
		_marker.visible = true
	_apply_color()
	_update_sustain_trail()


func tick(song_time: float) -> void:
	if not is_active:
		return

	var state: Dictionary = _lifecycle.advance(song_time)

	if bool(state.get("is_crossed", false)):
		position.z = STRUM_Z
		_update_active_sustain_trail(float(state.get("remaining_secs", 0.0)))
	else:
		position.z = ChartCommon.note_world_z(time_offset, song_time, STRUM_Z)
	_update_sustain_glow(song_time)

	if bool(state.get("crossed_now", false)):
		_hide_head_visuals()
		position.z = STRUM_Z
	if bool(state.get("finished_now", false)):
		deactivate()


func deactivate() -> void:
	if not is_active:
		return
	is_active = false
	visible = false
	_head_hidden = false
	if _sustain_trail:
		_sustain_trail.visible = false
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func _hide_head_visuals() -> void:
	_head_hidden = true
	if _marker != null:
		_marker.visible = false


func is_open_string() -> bool:
	return true


func _apply_color() -> void:
	if _marker_mat == null:
		return
	var c: Color = ChartCommon.STRING_COLORS[string_index] if string_index < ChartCommon.STRING_COLORS.size() else Color.WHITE
	_marker_mat.albedo_color = c
	if _sustain_trail_mat:
		var visual_color := _with_visual_alpha(c)
		_sustain_trail_mat.albedo_color = visual_color
		_sustain_trail_mat.emission = visual_color


func _update_sustain_trail() -> void:
	if _sustain_trail == null:
		return
	var sustain_length: float = maxf(duration * TRAVEL_SPEED, 0.0)
	if sustain_length < SUSTAIN_MIN_LENGTH:
		_sustain_trail.visible = false
		return
	_set_sustain_trail_length(sustain_length)


func _update_active_sustain_trail(remaining_secs: float) -> void:
	if _sustain_trail == null:
		return
	if remaining_secs <= 0.0:
		_sustain_trail.visible = false
		return
	_set_sustain_trail_length(remaining_secs * TRAVEL_SPEED)


func _set_sustain_trail_length(sustain_length: float) -> void:
	if _sustain_trail == null:
		return
	var trail_mesh: BoxMesh = _sustain_trail.mesh as BoxMesh
	if trail_mesh == null:
		return
	var anchor_fret_start: int = _anchor_fret_start()
	var left_x: float = ChartCommon.fret_separator_world_x(anchor_fret_start - 1)
	var right_x: float = ChartCommon.fret_separator_world_x(mini(anchor_fret_start + 3, ChartCommon.FRET_COUNT))
	var span_world: float = maxf(right_x - left_x, ChartCommon.FRET_SPACING)
	trail_mesh.size = Vector3(span_world, SUSTAIN_TRAIL_HEIGHT, sustain_length)
	_sustain_trail.position = Vector3(
		0.0,
		0.0,
		OPEN_STRING_LOCAL_Z - sustain_length * 0.5
	)
	_sustain_trail.visible = true


func _update_sustain_glow(song_time: float) -> void:
	if _sustain_trail_mat == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(song_time * NOTE_MARKER_PULSE_FREQUENCY)
	_sustain_trail_mat.emission_energy_multiplier = NOTE_MARKER_NEON_GLOW_BASE + NOTE_MARKER_NEON_GLOW_PULSE * pulse


func _anchor_fret_start() -> int:
	if visual_base_fret >= 1:
		return clampi(visual_base_fret, 1, ChartCommon.FRET_COUNT)
	return clampi(hand_fret_start, 1, ChartCommon.FRET_COUNT)


func _with_visual_alpha(c: Color) -> Color:
	return Color(c.r, c.g, c.b, NOTE_VISUAL_ALPHA)
