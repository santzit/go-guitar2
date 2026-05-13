extends Node3D
class_name OpenString

const ChartCommon = preload("res://scripts/common.gd")

const START_Z: float = -ChartCommon.HIGHWAY_DEPTH
const STRUM_Z: float = 0.0
const MISS_HOLD_SECS: float = 1.0
const OPEN_STRING_SPAN_FRETS: int = 4

var fret: int = 0
var string_index: int = 0
var time_offset: float = 0.0
var duration: float = 0.25
var is_active: bool = false
var _miss_until: float = -1.0
var _marker_mat: StandardMaterial3D = null

@onready var _marker: MeshInstance3D = $OpenStringMarker


func _ready() -> void:
	if _marker:
		_marker.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		_marker_mat = StandardMaterial3D.new()
		_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_marker_mat.emission_enabled = false
		_marker.set_surface_override_material(0, _marker_mat)


func setup(
		p_fret: int,
		p_string: int,
		p_time: float,
		p_duration: float,
		_unused_show_lane_connector: bool = false
) -> void:
	fret = p_fret
	string_index = clampi(p_string, 0, ChartCommon.STRING_COUNT - 1)
	time_offset = p_time
	duration = maxf(p_duration, 0.0)
	is_active = true
	visible = true
	_miss_until = -1.0

	var span_world: float = float(OPEN_STRING_SPAN_FRETS) * ChartCommon.FRET_SPACING
	var center_x: float = span_world * 0.5
	position = Vector3(center_x, ChartCommon.string_world_y(string_index), START_Z)
	_apply_color()


func tick(p_song_time: float) -> void:
	if not is_active:
		return

	position.z = ChartCommon.note_world_z(time_offset, p_song_time, STRUM_Z)

	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + duration + MISS_HOLD_SECS
	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


func deactivate() -> void:
	if not is_active:
		return
	is_active = false
	visible = false
	_miss_until = -1.0
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func is_open_string() -> bool:
	return true


func _apply_color() -> void:
	if _marker_mat == null:
		return
	var c: Color = ChartCommon.STRING_COLORS[string_index] if string_index < ChartCommon.STRING_COLORS.size() else Color.WHITE
	_marker_mat.albedo_color = c
