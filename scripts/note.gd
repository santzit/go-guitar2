extends Node3D
## note.gd  –  behaviour for a single pooled note with a static 3D NoteMarker mesh.
##
## All coordinate formulas live in scripts/common.gd (class ChartCommon) so they
## can be shared with highway.gd, music_play.gd, and fretboard.gd.
##
## Coordinate mapping summary
##   X = ChartCommon.fret_mid_world_x(fret)      — linear fret spacing (1 unit/fret)
##   Y = ChartCommon.string_world_y(string_index) — string 0 = top, 5 = bottom
##   Z = STRUM_Z − (time_offset − song_time) × TRAVEL_SPEED
##       Notes spawn at Z = -20 and travel toward Z = 0.
##
const START_Z       : float = -20.0
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = 2.0
## Keep notes alive briefly after crossing STRUM_Z so game-side hit/miss checks
## in the same frame window can still observe the note before it is returned.
const MISS_HOLD_SECS: float = 1.0

## Local offset recenters the imported note mesh on the string lane.
const NOTE_MARKER_LOCAL_OFFSET: Vector3 = Vector3(0.0, -0.1, 0.08)

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0

@onready var _note_marker: MeshInstance3D = $NoteMarker


func _ready() -> void:
	if _note_marker:
		_note_marker.position = NOTE_MARKER_LOCAL_OFFSET


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
