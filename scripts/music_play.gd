extends Node3D
## music_play.gd -- main gameplay controller.

# -- Timing constants (must match note.gd) -----------------------------------
const TRAVEL_SPEED : float = 8.0
const START_Z      : float = 20.0
const LEAD_TIME    : float = START_Z / TRAVEL_SPEED   # = 2.5 s

# -- Screenshot capture (for automated testing) ------------------------------
const SCREENSHOT_TIMES : Array  = [30.0, 60.0, 90.0, 120.0, 150.0]
const SCREENSHOT_DIR   : String = "user://screenshots"

# -- Max delta clamp to prevent fast-renderer notes from vanishing too quickly
const MAX_DELTA : float = 0.05

# -- Scene references --------------------------------------------------------
@onready var _pool   : Node3D            = $NotePool
@onready var _highway: Node3D            = $Highway
@onready var _player : AudioStreamPlayer = $AudioStreamPlayer

# -- State -------------------------------------------------------------------
var _bridge        : RsBridge = null
var _notes         : Array    = []
var _next_idx      : int      = 0
var _song_time     : float    = 0.0
var _playing       : bool     = false
var _shot_idx      : int      = 0
var _start_wall_ms : int      = 0


func _ready() -> void:
	_bridge = RsBridge.new()

	var psarc_path := _find_dlc_psarc()
	if psarc_path != "":
		print("MusicPlay: loading " + psarc_path)
		if _bridge.load_psarc(psarc_path):
			_notes = _bridge.get_notes()
			var stream := _bridge.get_audio_stream()
			if stream:
				_player.stream = stream
				_player.play()
		else:
			push_warning("MusicPlay: failed to load psarc - using demo notes.")
	else:
		push_warning("MusicPlay: no .psarc found in res://DLC/ - using demo notes.")

	if _notes.is_empty():
		_notes = _generate_demo_notes()

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SCREENSHOT_DIR)
	)
	_start_wall_ms = Time.get_ticks_msec()
	_playing = true


func _process(delta: float) -> void:
	if not _playing:
		return

	# Clamp delta to avoid huge first-frame jumps from initialization.
	var clamped_delta := minf(delta, MAX_DELTA)
	_song_time += clamped_delta

	while _next_idx < _notes.size():
		var nd: Dictionary = _notes[_next_idx]
		if nd["time"] - _song_time <= LEAD_TIME:
			var f: int = nd["fret"]
			# Skip open-string (fret 0) notes and any out-of-range fret values.
			if f >= 1 and f <= 24:
				_pool.spawn_note(f, nd["string"], nd["time"], nd["duration"])
			_next_idx += 1
		else:
			break

	# Screenshots based on real wall-clock time to avoid timer batching on slow renderers.
	if _shot_idx < SCREENSHOT_TIMES.size():
		var wall_sec := (Time.get_ticks_msec() - _start_wall_ms) / 1000.0
		if wall_sec >= SCREENSHOT_TIMES[_shot_idx]:
			_take_screenshot(_shot_idx + 1)
			_shot_idx += 1


# -- Helpers -----------------------------------------------------------------

func _take_screenshot(num: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# Convert to RGB8 — the OpenGL Compatibility framebuffer has alpha=0 for 3D content;
	# converting drops the alpha channel so the saved PNG shows the actual rendered colours.
	img.convert(Image.FORMAT_RGB8)
	var path := SCREENSHOT_DIR + "/music_play_%d.png" % num
	var abs_path := ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	print("Screenshot saved: " + abs_path)


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


func _generate_demo_notes() -> Array:
	var result  : Array = []
	var frets   := [2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24]
	var strings := [0, 1, 2, 3, 4, 5]
	var beat    : float = 0.35
	var t       : float = 0.0
	for i in 300:
		result.append({
			"time"    : t,
			"fret"    : frets[i % frets.size()],
			"string"  : strings[i % strings.size()],
			"duration": beat * 0.8,
		})
		t += beat
	return result


func push_print(msg: String) -> void:
	print(msg)
