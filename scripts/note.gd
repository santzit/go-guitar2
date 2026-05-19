extends Node3D
const ChartCommon = preload("res://scripts/common.gd")
const EventLifecycle = preload("res://scripts/event_lifecycle.gd")
## note.gd  –  behaviour for a single pooled note with a static 3D NoteMarker mesh.
##
## All coordinate formulas live in scripts/common.gd (class ChartCommon) so they
## can be shared with highway.gd, music_play.gd, and fretboard.gd.
##
## Coordinate mapping summary
##   X = ChartCommon.fret_mid_world_x(fret)      — linear fret spacing (2 units/fret)
##   Y = ChartCommon.string_world_y(string_index) — string 0 = top, 5 = bottom
##   Z = ChartCommon.note_world_z(time_offset, song_time, STRUM_Z)
##       Notes spawn at Z = -ChartCommon.HIGHWAY_DEPTH and travel toward Z = 0.
##
const START_Z       : float = -ChartCommon.HIGHWAY_DEPTH
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = ChartCommon.Z_UNITS_PER_SECOND
## Local transform aligns the note marker plane in-lane.
## Lift marker slightly so the visual middle aligns with the string centerline.
const NOTE_MARKER_LOCAL_OFFSET: Vector3 = Vector3(0.0, 0.1, 0.08)
const NOTE_MARKER_NEON_GLOW_BASE: float = 2.4
const NOTE_MARKER_NEON_GLOW_PULSE: float = 0.8
const NOTE_MARKER_PULSE_FREQUENCY: float = 8.0
const NOTE_MARKER_TEXTURE_ALPHA: float = 1.0
const NOTE_LANE_CONNECTOR_WIDTH: float = 0.012
const NOTE_LANE_CONNECTOR_DEPTH: float = 0.012
const NOTE_LANE_CONNECTOR_MIN_HEIGHT: float = 0.02
const NOTE_LANE_CONNECTOR_GLOW_MULTIPLIER: float = 2.2
const NOTE_VISUAL_ALPHA: float = 0.4
const SUSTAIN_MIN_SECS: float = 0.05
const SUSTAIN_TRAIL_WIDTH: float = 0.5
const SUSTAIN_TRAIL_HEIGHT: float = 0.08
const SUSTAIN_MIN_LENGTH: float = SUSTAIN_MIN_SECS * TRAVEL_SPEED

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _head_hidden : bool  = false
var _show_lane_connector: bool = true
var _lifecycle: EventLifecycle = EventLifecycle.new()
var _note_marker_mat: ShaderMaterial = null
var _lane_connector: MeshInstance3D = null
var _lane_connector_mat: ShaderMaterial = null
var _sustain_trail: MeshInstance3D = null
var _sustain_trail_mat: ShaderMaterial = null
var _indicator_color: Color = Color(1.0, 0.5, 0.1, 1.0)
var _note_marker_offset: Vector3 = NOTE_MARKER_LOCAL_OFFSET

@onready var _note_marker: MeshInstance3D = $NoteMarker


func _ready() -> void:
	_ensure_visual_nodes()


func _ensure_visual_nodes() -> void:
	if _note_marker == null:
		_note_marker = get_node_or_null("NoteMarker") as MeshInstance3D
	if _note_marker:
		if _note_marker_mat == null:
			_note_marker_mat = _note_marker.get_surface_override_material(0) as ShaderMaterial
		_note_marker_offset = _note_marker.position
		var marker_mesh := _note_marker.mesh as BoxMesh
		if _note_marker_mat != null and marker_mesh != null:
			_note_marker_mat.set_shader_parameter("marker_size", Vector2(marker_mesh.size.x, marker_mesh.size.y))
	if _lane_connector == null:
		_lane_connector = get_node_or_null("LaneConnector") as MeshInstance3D
	if _lane_connector:
		if _lane_connector_mat == null:
			_lane_connector_mat = _lane_connector.get_surface_override_material(0) as ShaderMaterial
	if _sustain_trail == null:
		_sustain_trail = get_node_or_null("SustainTrail") as MeshInstance3D
	if _sustain_trail:
		if _sustain_trail_mat == null:
			_sustain_trail_mat = _sustain_trail.get_surface_override_material(0) as ShaderMaterial
		_sustain_trail.visible = false


func setup(
		p_fret: int,
		p_string: int,
		p_time: float,
		p_duration: float,
		p_show_lane_connector: bool = true
) -> void:
	_ensure_visual_nodes()
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	_show_lane_connector = p_show_lane_connector
	is_active    = true
	visible      = true
	_head_hidden = false
	_lifecycle.setup(time_offset, duration, SUSTAIN_MIN_SECS, true)

	position = Vector3(ChartCommon.fret_mid_world_x(fret - 1), ChartCommon.string_world_y(string_index), START_Z)
	if _note_marker != null:
		_note_marker.visible = true
	if _lane_connector != null:
		_lane_connector.visible = true
	_indicator_color = ChartCommon.STRING_COLORS[string_index] if string_index < ChartCommon.STRING_COLORS.size() else Color.WHITE
	_apply_marker_color()
	_update_lane_connector()
	_update_sustain_trail()
	_update_marker_glow(0.0)


func tick(p_song_time: float) -> void:
	if not is_active:
		return

	var state: Dictionary = _lifecycle.advance(p_song_time)

	if bool(state.get("is_crossed", false)):
		position.z = STRUM_Z
		_update_active_sustain_trail(float(state.get("remaining_secs", 0.0)))
	else:
		position.z = ChartCommon.note_world_z(time_offset, p_song_time, STRUM_Z)
	_update_marker_glow(p_song_time)

	if bool(state.get("crossed_now", false)):
		_hide_head_visuals()
		position.z = STRUM_Z
	if bool(state.get("finished_now", false)):
		deactivate()


func deactivate() -> void:
	if not is_active:
		return   # already deactivated — guard against double-deactivation from pool
	is_active    = false
	visible      = false
	_head_hidden = false
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func _hide_head_visuals() -> void:
	_head_hidden = true
	if _note_marker != null:
		_note_marker.visible = false
	if _lane_connector != null:
		_lane_connector.visible = false


func _apply_marker_color() -> void:
	if _note_marker_mat == null:
		return
	var marker_tint := Color(_indicator_color.r, _indicator_color.g, _indicator_color.b, NOTE_MARKER_TEXTURE_ALPHA)
	_note_marker_mat.set_shader_parameter("base_color", marker_tint)
	if _sustain_trail_mat != null:
		var visual_color := _with_visual_alpha(_indicator_color)
		_sustain_trail_mat.set_shader_parameter("base_color", visual_color)


func _update_marker_glow(song_time: float) -> void:
	if _note_marker_mat == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(song_time * NOTE_MARKER_PULSE_FREQUENCY)
	var glow_energy: float = NOTE_MARKER_NEON_GLOW_BASE + NOTE_MARKER_NEON_GLOW_PULSE * pulse
	_note_marker_mat.set_shader_parameter("glow_energy", glow_energy)
	if _lane_connector_mat != null:
		_lane_connector_mat.set_shader_parameter("glow_energy", glow_energy * NOTE_LANE_CONNECTOR_GLOW_MULTIPLIER)
	if _sustain_trail_mat != null:
		_sustain_trail_mat.set_shader_parameter("glow_energy", glow_energy)


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
	trail_mesh.size = Vector3(SUSTAIN_TRAIL_WIDTH, SUSTAIN_TRAIL_HEIGHT, sustain_length)
	if _sustain_trail_mat != null:
		_sustain_trail_mat.set_shader_parameter("mesh_width", trail_mesh.size.x)
	_sustain_trail.position = Vector3(
		_note_marker_offset.x,
		_note_marker_offset.y,
		_note_marker_offset.z - sustain_length * 0.5
	)
	_sustain_trail.visible = true


func _update_lane_connector() -> void:
	if _lane_connector == null:
		return
	if not _show_lane_connector:
		_lane_connector.visible = false
		return
	var marker_anchor_y: float = _note_marker_offset.y
	var highway_local_y: float = -position.y
	var connector_height: float = marker_anchor_y - highway_local_y
	if connector_height <= NOTE_LANE_CONNECTOR_MIN_HEIGHT:
		_lane_connector.visible = false
		return
	var connector_mesh := _lane_connector.mesh as BoxMesh
	if connector_mesh == null:
		return
	connector_mesh.size = Vector3(NOTE_LANE_CONNECTOR_WIDTH, connector_height, NOTE_LANE_CONNECTOR_DEPTH)
	if _lane_connector_mat != null:
		_lane_connector_mat.set_shader_parameter("connector_height", connector_height)
	_lane_connector.position = Vector3(
		_note_marker_offset.x,
		highway_local_y + (connector_height * 0.5),
		_note_marker_offset.z
	)
	_lane_connector.visible = true


func _with_visual_alpha(c: Color) -> Color:
	return Color(c.r, c.g, c.b, NOTE_VISUAL_ALPHA)
