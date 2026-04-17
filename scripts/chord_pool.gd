extends Node3D
## chord_pool.gd — manages a fixed pool of chord container instances.
##
## Usage:  spawn_chord(notes, time, name, show_details) → Node3D
##         tick(song_time)   — called every frame from music_play._process()
##         clear_chords()    — call on song stop / restart

const MAX_CHORDS  : int         = 64
const CHORD_SCENE : PackedScene = preload("res://scenes/chord.tscn")

var _pool  : Array = []   # idle chord containers
var _active: Array = []   # currently moving containers


func _ready() -> void:
	for i in MAX_CHORDS:
		_pool.append(_make_chord())


func _make_chord() -> Node3D:
	var chord : Node3D = CHORD_SCENE.instantiate()
	chord.visible = false
	add_child(chord)
	return chord


## Activate a chord container from the pool.
## Returns the chord node, or null if the pool is exhausted.
func spawn_chord(
		p_notes: Array,
		p_time: float,
		p_chord_name: String,
		p_show_details: bool
) -> Node3D:
	if _pool.is_empty():
		_pool.append(_make_chord())
	var chord : Node3D = _pool.pop_back()
	chord.setup(p_notes, p_time, p_chord_name, p_show_details)
	_active.append(chord)
	return chord


## Called by a Chord when it passes the strum line and deactivates itself.
func return_chord(chord: Node3D) -> void:
	_active.erase(chord)
	_pool.append(chord)


## Advance all active chord Z positions from the audio clock.
## Called every frame by music_play._process().
func tick(song_time: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		_active[i].tick(song_time)


## Deactivate all active chords (e.g. on song stop / restart).
func clear_chords() -> void:
	for i in range(_active.size() - 1, -1, -1):
		_active[i].deactivate()
