extends Node3D
## note_pool.gd  –  manages a fixed pool of up to MAX_NOTES Note instances.

const MAX_NOTES  : int         = 128
const NOTE_SCENE : PackedScene = preload("res://scenes/note.tscn")

var _pool  : Array[Node3D] = []
var _active: Array[Node3D] = []


func _ready() -> void:
	_build_pool()


func _build_pool() -> void:
	for i in MAX_NOTES:
		var note: Node3D = NOTE_SCENE.instantiate()
		note.visible = false
		add_child(note)
		_pool.append(note)


## Activate a note from the pool.
## p_show_label controls whether the fret number is rendered on this note.
## Returns the note node, or null if the pool is exhausted.
func spawn_note(p_fret: int, p_string: int, p_time: float, p_duration: float, p_show_label: bool = true) -> Node3D:
	if _pool.is_empty():
		push_warning("NotePool: pool exhausted – cannot spawn note.")
		return null

	var note: Node3D = _pool.pop_back()
	note.setup(p_fret, p_string, p_time, p_duration, p_show_label)
	_active.append(note)
	return note


## Called by a Note when it passes the strum line and deactivates itself.
func return_note(note: Node3D) -> void:
	_active.erase(note)
	_pool.append(note)


## Called every frame by music_play.gd with the audio-derived song time.
## Updates every active note's Z position directly from the audio clock so
## notes are always pixel-perfectly synced to what the player hears.
func tick(song_time: float) -> void:
	# Iterate a duplicate because note.tick() may call deactivate() which
	# modifies _active mid-iteration.
	for note in _active.duplicate():
		note.tick(song_time)


## Deactivate all active notes (e.g. on song stop / restart).
func clear_notes() -> void:
	for note in _active.duplicate():
		note.deactivate()
