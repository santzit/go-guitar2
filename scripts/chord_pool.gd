extends Node3D
## chord_pool.gd — manages a fixed pool of chord container instances.
##
## Usage:  spawn_event(notes, time, name, show_details, kind) → Node3D
##         tick(song_time)   — called every frame from music_play._process()
##         clear_chords()    — call on song stop / restart
##
## NotePool is a child of this node so all note instances are owned by the
## chord system.  Chord containers borrow notes via spawn_note() and return
## them via NotePool.return_note() when they deactivate.

const MAX_CHORDS  : int         = 64
const CHORD_SCENE : PackedScene = preload("res://scenes/chord.tscn")

var _pool  : Array = []   # idle chord containers
var _active: Array = []   # currently moving containers

## NotePool child — owns all Note instances used by chord containers.
@onready var _note_pool: Node3D = $NotePool


func _ready() -> void:
	for i in MAX_CHORDS:
		_pool.append(_make_chord())


func _make_chord() -> Node3D:
	var chord : Node3D = CHORD_SCENE.instantiate()
	chord.visible = false
	add_child(chord)
	return chord


## Activate an event container from the pool.
## Returns the chord node, or null if the pool is exhausted.
func spawn_event(
		p_notes: Array,
		p_time: float,
		p_chord_name: String,
		p_show_details: bool,
		p_event_kind: String
) -> Node3D:
	if _pool.is_empty():
		_pool.append(_make_chord())
	var chord : Node3D = _pool.pop_back()
	chord.setup(p_notes, p_time, p_chord_name, p_show_details, p_event_kind)
	_active.append(chord)
	return chord


## Backward-compatible wrapper.
func spawn_chord(
		p_notes: Array,
		p_time: float,
		p_chord_name: String,
		p_show_details: bool
) -> Node3D:
	return spawn_event(p_notes, p_time, p_chord_name, p_show_details, "chord")


## Borrow a Note from the NotePool on behalf of a chord container.
func spawn_note(p_fret: int, p_string: int, p_time: float, p_duration: float) -> Node3D:
	return _note_pool.spawn_note(p_fret, p_string, p_time, p_duration)


## Called by a Chord when it passes the strum line and deactivates itself.
func return_chord(chord: Node3D) -> void:
	_active.erase(chord)
	_pool.append(chord)


## Advance all active chord Z positions from the audio clock.
## Also ticks the NotePool so all borrowed note Z positions stay in sync.
## Called every frame by music_play._process().
func tick(song_time: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		_active[i].tick(song_time)
	_note_pool.tick(song_time)


## Deactivate all active chords and notes (e.g. on song stop / restart).
func clear_chords() -> void:
	for i in range(_active.size() - 1, -1, -1):
		_active[i].deactivate()
	_note_pool.clear_notes()
