extends Node3D
## note.gd  –  behaviour for a single pooled note with 3D note markers.
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
## Note marker is a 3D mesh from scenes/note.tscn:
##   - Solid color material with no per-frame visual animation

# ── Per-string note colors (string 0 top → string 5 bottom) ───────────────────
const STRING_COLORS: Array[Color] = [
	Color(0.98, 0.26, 0.22, 1.0), # red
	Color(0.98, 0.78, 0.16, 1.0), # yellow
	Color(0.20, 0.80, 0.95, 1.0), # cyan
	Color(1.00, 0.55, 0.10, 1.0), # orange
	Color(0.20, 0.88, 0.30, 1.0), # green
	Color(0.72, 0.38, 0.98, 1.0), # purple
]

## Visual constants for 3D note markers
const START_Z       : float = -20.0
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = 2.0
const MISS_HOLD_SECS: float = 1.0
const BOX_DEPTH: float = 0.04
const NOTE_MARKER_BASE_SIZE: Vector3 = Vector3(0.12, 0.20, 0.60)

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0
var _last_sized_fret: int = -1
var _note_marker_color: Color = Color(1.0, 0.5, 0.1, 1.0)

var _fill_mat: StandardMaterial3D = null
var _note_marker_base_scale: Vector3 = Vector3.ONE

@onready var _note_marker: MeshInstance3D = $NoteMarker


func _ready() -> void:
	if _note_marker:
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_fill_mat.albedo_color = Color(1.0, 0.5, 0.1, 1.0)
		_fill_mat.metallic = 0.0
		_fill_mat.roughness = 1.0
		_fill_mat.metallic_specular = 0.0
		_fill_mat.emission_enabled = false
		_fill_mat.albedo_texture = null
		_fill_mat.emission_texture = null
		_note_marker.material_override = _fill_mat
		var note_mesh: Mesh = _note_marker.mesh
		if note_mesh:
			for i in note_mesh.get_surface_count():
				_note_marker.set_surface_override_material(i, _fill_mat)
		_update_note_marker_geometry(1)


func setup(p_fret: int, p_string: int, p_time: float, p_duration: float, _p_show_label: bool = true) -> void:
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	is_active    = true
	visible      = true
	_miss_until  = -1.0

	position = Vector3(ChartCommon.fret_mid_world_x(fret - 1), ChartCommon.string_world_y(string_index), START_Z)

	if _note_marker:
		if fret != _last_sized_fret:
			_last_sized_fret = fret
			_update_note_marker_geometry(fret)
		_note_marker_color = STRING_COLORS[string_index]
		if _fill_mat:
			_fill_mat.albedo_color = _note_marker_color
		_note_marker.scale = _note_marker_base_scale


func tick(p_song_time: float) -> void:
	if not is_active:
		return

	position.z = STRUM_Z - (time_offset - p_song_time) * TRAVEL_SPEED

	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD_SECS

	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


func deactivate() -> void:
	is_active    = false
	visible      = false
	_miss_until  = -1.0
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func _update_note_marker_geometry(fret_num: int) -> void:
	if _note_marker == null:
		return
	var sz2: Vector2 = ChartCommon.note_indicator_size(fret_num)
	_note_marker_base_scale = Vector3(
		sz2.x / NOTE_MARKER_BASE_SIZE.x,
		sz2.y / NOTE_MARKER_BASE_SIZE.y,
		BOX_DEPTH / NOTE_MARKER_BASE_SIZE.z
	)
