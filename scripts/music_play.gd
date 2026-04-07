extends Node3D
## music_play.gd  –  main gameplay controller.
##
## Start-up sequence
## -----------------
## 1. Scan res://DLC/ for the first *.psarc file.
## 2. Load it through RsBridge (GDExtension).  If the extension is absent or
##    no psarc is found, fall back to built-in demo notes so the highway is
##    always populated.
## 3. Start the AudioStreamPlayer with the song audio (if available).
## 4. Each _process frame, spawn notes LEAD_TIME seconds before their hit
##    time so they travel the full highway length and arrive exactly at the
##    strum line on cue.

# ── Timing constants (must match note.gd) ───────────────────────────────────
const TRAVEL_SPEED : float = 8.0    # units/s  (note.gd TRAVEL_SPEED)
const START_Z      : float = 20.0   # note.gd  START_Z
# Lead-time so that a note spawned LEAD_TIME seconds early travels START_Z units.
const LEAD_TIME    : float = START_Z / TRAVEL_SPEED   # = 2.5 s

# ── Scene references ─────────────────────────────────────────────────────────
@onready var _pool   : Node3D             = $NotePool
@onready var _highway: Node3D             = $Highway
@onready var _player : AudioStreamPlayer  = $AudioStreamPlayer

# ── State ────────────────────────────────────────────────────────────────────
var _bridge   : RsBridge = null
var _notes    : Array    = []
var _next_idx : int      = 0
var _song_time: float    = 0.0
var _playing  : bool     = false


func _ready() -> void:
	_bridge = RsBridge.new()

	# ── Try to load the first .psarc found in DLC/ ───────────────────────
	var psarc_path := _find_dlc_psarc()
	if psarc_path != "":
		push_print("MusicPlay: loading " + psarc_path)
		if _bridge.load_psarc(psarc_path):
			_notes = _bridge.get_notes()
			var stream := _bridge.get_audio_stream()
			if stream:
				_player.stream = stream
				_player.play()
			# Reconfigure highway fret/string counts from the loaded song if needed.
			# _highway.configure(24, 6)
		else:
			push_warning("MusicPlay: failed to load psarc – using demo notes.")
	else:
		push_warning("MusicPlay: no .psarc found in res://DLC/ – using demo notes.")

	# ── Fall back to demo notes when no real song data is available ───────
	if _notes.is_empty():
		_notes = _generate_demo_notes()

	_playing = true


func _process(delta: float) -> void:
	if not _playing:
		return

	_song_time += delta

	# Spawn upcoming notes that should now be visible.
	while _next_idx < _notes.size():
		var nd: Dictionary = _notes[_next_idx]
		# A note must be on screen LEAD_TIME seconds before its hit time.
		if nd["time"] - _song_time <= LEAD_TIME:
			_pool.spawn_note(
				nd["fret"],
				nd["string"],
				nd["time"],
				nd["duration"]
			)
			_next_idx += 1
		else:
			break   # notes are sorted by time


# ── Helpers ──────────────────────────────────────────────────────────────────

## Scan res://DLC/ and return the path of the first .psarc file, or "".
func _find_dlc_psarc() -> String:
	var dir := DirAccess.open("res://DLC")
	if dir == null:
		return ""
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".psarc"):
			dir.list_dir_end()
			return "res://DLC/" + file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	return ""


## Generate demo notes (chromatic scale across all strings) for visual testing.
func _generate_demo_notes() -> Array:
	var result : Array = []
	var frets  := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19]
	var strings := [0, 1, 2, 3, 4, 5]
	var beat   : float = 0.45
	var t      : float = 0.0
	for i in 240:
		result.append({
			"time"    : t,
			"fret"    : frets[i % frets.size()],
			"string"  : strings[i % strings.size()],
			"duration": beat * 0.8,
		})
		t += beat
	return result


## Convenience wrapper so scripts can call push_print (Godot 4 print).
func push_print(msg: String) -> void:
	print(msg)
