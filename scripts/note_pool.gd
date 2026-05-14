extends Node3D
## note_pool.gd  –  manages a fixed pool of up to MAX_NOTES Note instances.
const EventPoolBase = preload("res://scripts/event_pool_base.gd")

const MAX_NOTES  : int         = 128
const MAX_OPEN_STRINGS: int    = 64
const NOTE_SCENE : PackedScene = preload("res://scenes/note.tscn")
const OPEN_STRING_SCENE: PackedScene = preload("res://scenes/open_string.tscn")

var _notes: EventPoolBase = EventPoolBase.new()
var _opens: EventPoolBase = EventPoolBase.new()


func _ready() -> void:
	_build_pool()


func _build_pool() -> void:
	_notes.warm(MAX_NOTES, Callable(self, "_make_note"))
	_opens.warm(MAX_OPEN_STRINGS, Callable(self, "_make_open_string"))


func _make_note() -> Node3D:
	var note: Node3D = NOTE_SCENE.instantiate()
	note.visible = false
	add_child(note)
	return note


func _make_open_string() -> Node3D:
	var open_string: Node3D = OPEN_STRING_SCENE.instantiate()
	open_string.visible = false
	add_child(open_string)
	return open_string


## Activate a note from the pool.
## Returns the note node, or null if the pool is exhausted.
func spawn_note(
		p_fret: int,
		p_string: int,
		p_time: float,
		p_duration: float,
		p_show_lane_connector: bool = true,
		p_hand_fret_start: int = 1,
		p_visual_base_fret: int = -1
) -> Node3D:
	if p_fret == 0:
		var open_string: Node3D = _opens.acquire(Callable(self, "_make_open_string"))
		open_string.setup(
			p_fret,
			p_string,
			p_time,
			p_duration,
			false,
			p_hand_fret_start,
			p_visual_base_fret
		)
		return open_string

	var note: Node3D = _notes.acquire(Callable(self, "_make_note"))
	note.setup(p_fret, p_string, p_time, p_duration, p_show_lane_connector)
	return note


## Called by a Note when it passes the strum line and deactivates itself.
func return_note(note: Node3D) -> void:
	if note.has_method("is_open_string") and note.call("is_open_string"):
		_opens.release(note)
		return
	_notes.release(note)


## Called every frame by music_play.gd with the audio-derived song time.
## Updates every active note's Z position directly from the audio clock so
## notes are always pixel-perfectly synced to what the player hears.
func tick(song_time: float) -> void:
	# Iterate backwards so that note.tick() calling deactivate() (which removes
	# from _active via return_note) is safe without allocating a duplicate array.
	for i in range(_notes.get_active().size() - 1, -1, -1):
		_notes.get_active()[i].tick(song_time)
	for i in range(_opens.get_active().size() - 1, -1, -1):
		_opens.get_active()[i].tick(song_time)


## Deactivate all active notes (e.g. on song stop / restart).
func clear_notes() -> void:
	for i in range(_notes.get_active().size() - 1, -1, -1):
		_notes.get_active()[i].deactivate()
	for i in range(_opens.get_active().size() - 1, -1, -1):
		_opens.get_active()[i].deactivate()
