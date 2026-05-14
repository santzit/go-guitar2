extends Node3D
class_name OpenString

const ChartCommon = preload("res://scripts/common.gd")

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
var time_offset: float = 0.0
var duration: float = 0.25
var is_active: bool = false
var _head_hidden: bool = false
var _end_time: float = 0.0
var _has_sustain: bool = false
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
		_marker.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		_marker.position = Vector3(0.0, 0.0, OPEN_STRING_LOCAL_Z)
		if _marker_mat == null:
			_marker_mat = StandardMaterial3D.new()
			_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_marker_mat.emission_enabled = false
		_marker.set_surface_override_material(0, _marker_mat)
	if _sustain_trail == null:
		_sustain_trail = get_node_or_null("SustainTrail") as MeshInstance3D
	if _sustain_trail == null:
		_sustain_trail = MeshInstance3D.new()
		_sustain_trail.name = "SustainTrail"
		add_child(_sustain_trail)
	if _sustain_trail_mat == null:
		_sustain_trail_mat = StandardMaterial3D.new()
		_sustain_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sustain_trail_mat.emission_enabled = true
		_sustain_trail_mat.metallic = 0.2
		_sustain_trail_mat.roughness = 0.08
		_sustain_trail_mat.emission_energy_multiplier = NOTE_MARKER_NEON_GLOW_BASE
	_sustain_trail.visible = false


func setup(
		p_fret: int,
		p_string: int,
		p_time: float,
		p_duration: float,
		_unused_show_lane_connector: bool = false
) -> void:
	_ensure_visual_nodes()
	fret = p_fret
	string_index = clampi(p_string, 0, ChartCommon.STRING_COUNT - 1)
	time_offset = p_time
	duration = maxf(p_duration, 0.0)
	is_active = true
	visible = true
	_head_hidden = false
	_end_time = time_offset
	_has_sustain = false

	var span_world: float = float(OPEN_STRING_SPAN_FRETS) * ChartCommon.FRET_SPACING
	var center_x: float = span_world * 0.5
	position = Vector3(center_x, ChartCommon.string_world_y(string_index), START_Z)
	if _marker != null:
		_marker.visible = true
	_apply_color()
	_update_sustain_trail()
	if duration * TRAVEL_SPEED >= SUSTAIN_MIN_LENGTH:
		_has_sustain = true
		_end_time = time_offset + duration


func tick(song_time: float) -> void:
	if not is_active:
		return

	if _head_hidden:
		position.z = STRUM_Z
		_update_active_sustain_trail(song_time)
	else:
		position.z = ChartCommon.note_world_z(time_offset, song_time, STRUM_Z)
	_update_sustain_glow(song_time)

	if not _head_hidden and song_time >= time_offset:
		_hide_head_visuals()
		position.z = STRUM_Z
		_update_active_sustain_trail(song_time)
	if _head_hidden and song_time >= _end_time:
		deactivate()


func deactivate() -> void:
	if not is_active:
		return
	is_active = false
	visible = false
	_head_hidden = false
	_end_time = 0.0
	_has_sustain = false
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
		_has_sustain = false
		_sustain_trail.visible = false
		return
	_has_sustain = true
	_set_sustain_trail_length(sustain_length)


func _update_active_sustain_trail(song_time: float) -> void:
	if not _has_sustain or _sustain_trail == null:
		return
	var remaining_secs: float = maxf(_end_time - song_time, 0.0)
	if remaining_secs <= 0.0:
		_sustain_trail.visible = false
		return
	_set_sustain_trail_length(remaining_secs * TRAVEL_SPEED)


func _set_sustain_trail_length(sustain_length: float) -> void:
	if _sustain_trail == null:
		return
	var trail_mesh: BoxMesh = _sustain_trail.mesh as BoxMesh
	if trail_mesh == null:
		trail_mesh = BoxMesh.new()
		_sustain_trail.mesh = trail_mesh
		if _sustain_trail_mat:
			_sustain_trail.set_surface_override_material(0, _sustain_trail_mat)
	var span_world: float = float(OPEN_STRING_SPAN_FRETS) * ChartCommon.FRET_SPACING
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


func _with_visual_alpha(c: Color) -> Color:
	return Color(c.r, c.g, c.b, NOTE_VISUAL_ALPHA)
