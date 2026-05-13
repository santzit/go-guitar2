extends Node3D
const ChartCommon = preload("res://scripts/common.gd")
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
const STRING_TEXTURES: Array[Texture2D] = [
	preload("res://assets/textures/chartplayer/GuitarRed.png"),
	preload("res://assets/textures/chartplayer/GuitarYellow.png"),
	preload("res://assets/textures/chartplayer/GuitarCyan.png"),
	preload("res://assets/textures/chartplayer/GuitarOrange.png"),
	preload("res://assets/textures/chartplayer/GuitarGreen.png"),
	preload("res://assets/textures/chartplayer/GuitarPurple.png"),
]
const NOTE_MARKER_SHADER: Shader = preload("res://shaders/note_marker_border.gdshader")

const START_Z       : float = -ChartCommon.HIGHWAY_DEPTH
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = ChartCommon.Z_UNITS_PER_SECOND
## Keep notes alive briefly after crossing STRUM_Z so game-side hit/miss checks
## in the same frame window can still observe the note before it is returned.
const MISS_HOLD_SECS: float = 1.0

## Local transform aligns the note marker plane in-lane.
## Lift marker slightly so the visual middle aligns with the string centerline.
const NOTE_MARKER_LOCAL_OFFSET: Vector3 = Vector3(0.0, 0.1, 0.08)
const NOTE_MARKER_LOCAL_ROTATION_DEGREES: Vector3 = Vector3.ZERO
const NOTE_MARKER_NEON_GLOW_BASE: float = 1.8
const NOTE_MARKER_NEON_GLOW_PULSE: float = 0.8
const NOTE_MARKER_PULSE_FREQUENCY: float = 8.0
const NOTE_MARKER_TEXTURE_ALPHA: float = 1.0
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
var _miss_until  : float = -1.0
var _note_marker_mat: ShaderMaterial = null
var _sustain_trail: MeshInstance3D = null
var _sustain_trail_mat: StandardMaterial3D = null
var _indicator_color: Color = Color(1.0, 0.5, 0.1, 1.0)
var _marker_texture: Texture2D = null

@onready var _note_marker: MeshInstance3D = $NoteMarker


func _ready() -> void:
	if _note_marker:
		_note_marker.position = NOTE_MARKER_LOCAL_OFFSET
		_note_marker.rotation_degrees = NOTE_MARKER_LOCAL_ROTATION_DEGREES
		_note_marker_mat = ShaderMaterial.new()
		_note_marker_mat.shader = NOTE_MARKER_SHADER
		_note_marker_mat.set_shader_parameter("tint_color", Color(1.0, 1.0, 1.0, NOTE_MARKER_TEXTURE_ALPHA))
		_note_marker_mat.set_shader_parameter("border_color", Color(1.0, 1.0, 1.0, 1.0))
		_note_marker_mat.set_shader_parameter("emission_energy", NOTE_MARKER_NEON_GLOW_BASE)
		_note_marker.set_surface_override_material(0, _note_marker_mat)
		if _marker_texture == null:
			_marker_texture = STRING_TEXTURES[string_index] if string_index < STRING_TEXTURES.size() else null
		_apply_marker_texture(_marker_texture)
		_sustain_trail = MeshInstance3D.new()
		_sustain_trail_mat = StandardMaterial3D.new()
		_sustain_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sustain_trail_mat.albedo_color = _with_visual_alpha(_indicator_color)
		_sustain_trail_mat.emission_enabled = true
		_sustain_trail_mat.emission = _with_visual_alpha(_indicator_color)
		_sustain_trail_mat.metallic = 0.2
		_sustain_trail_mat.roughness = 0.08
		_sustain_trail_mat.emission_energy_multiplier = NOTE_MARKER_NEON_GLOW_BASE
		_sustain_trail.visible = false
		add_child(_sustain_trail)


func setup(
		p_fret: int,
		p_string: int,
		p_time: float,
		p_duration: float,
		_unused_show_label: bool = true
) -> void:
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	is_active    = true
	visible      = true
	_miss_until  = -1.0

	position = Vector3(ChartCommon.fret_mid_world_x(fret - 1), ChartCommon.string_world_y(string_index), START_Z)
	_indicator_color = ChartCommon.STRING_COLORS[string_index] if string_index < ChartCommon.STRING_COLORS.size() else Color.WHITE
	_marker_texture = STRING_TEXTURES[string_index] if string_index < STRING_TEXTURES.size() else null
	_apply_marker_texture(_marker_texture)
	_apply_marker_color()
	_update_sustain_trail()
	_update_marker_glow(0.0)


func tick(p_song_time: float) -> void:
	if not is_active:
		return

	position.z = ChartCommon.note_world_z(time_offset, p_song_time, STRUM_Z)
	_update_marker_glow(p_song_time)

	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD_SECS

	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


func deactivate() -> void:
	if not is_active:
		return   # already deactivated — guard against double-deactivation from pool
	is_active    = false
	visible      = false
	_miss_until  = -1.0
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func _apply_marker_color() -> void:
	if _note_marker_mat == null:
		return
	var marker_tint := Color(_indicator_color.r, _indicator_color.g, _indicator_color.b, NOTE_MARKER_TEXTURE_ALPHA)
	_note_marker_mat.set_shader_parameter("tint_color", marker_tint)
	if _sustain_trail_mat != null:
		var visual_color := _with_visual_alpha(_indicator_color)
		_sustain_trail_mat.albedo_color = visual_color
		_sustain_trail_mat.emission = visual_color


func _apply_marker_texture(texture: Texture2D) -> void:
	if _note_marker_mat == null:
		return
	_note_marker_mat.set_shader_parameter("albedo_tex", texture)


func _update_marker_glow(song_time: float) -> void:
	if _note_marker_mat == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(song_time * NOTE_MARKER_PULSE_FREQUENCY)
	var glow_energy: float = NOTE_MARKER_NEON_GLOW_BASE + NOTE_MARKER_NEON_GLOW_PULSE * pulse
	_note_marker_mat.set_shader_parameter("emission_energy", glow_energy)
	if _sustain_trail_mat != null:
		_sustain_trail_mat.emission_energy_multiplier = glow_energy


func _update_sustain_trail() -> void:
	if _sustain_trail == null:
		return
	var sustain_length: float = maxf(duration * TRAVEL_SPEED, 0.0)
	if sustain_length < SUSTAIN_MIN_LENGTH:
		_sustain_trail.visible = false
		return
	var trail_mesh: BoxMesh = _sustain_trail.mesh as BoxMesh
	if trail_mesh == null:
		trail_mesh = BoxMesh.new()
		_sustain_trail.mesh = trail_mesh
		if _sustain_trail_mat != null:
			_sustain_trail.set_surface_override_material(0, _sustain_trail_mat)
	trail_mesh.size = Vector3(SUSTAIN_TRAIL_WIDTH, SUSTAIN_TRAIL_HEIGHT, sustain_length)
	_sustain_trail.position = Vector3(
		NOTE_MARKER_LOCAL_OFFSET.x,
		NOTE_MARKER_LOCAL_OFFSET.y,
		NOTE_MARKER_LOCAL_OFFSET.z - sustain_length * 0.5
	)
	_sustain_trail.visible = true


func _with_visual_alpha(c: Color) -> Color:
	return Color(c.r, c.g, c.b, NOTE_VISUAL_ALPHA)
