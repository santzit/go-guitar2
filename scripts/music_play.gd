extends Node3D
## music_play.gd -- main gameplay controller.
##
## Expects a PSARC song path selected in the song list menu (song_list.gd).

const _RsBridgeScript = preload("res://scripts/rs_bridge.gd")
const _GameStateScript = preload("res://scripts/game_state.gd")

# -- Timing constants (must match note.gd) -----------------------------------
const TRAVEL_SPEED : float = 8.0
const START_Z      : float = 20.0
const LEAD_TIME    : float = START_Z / TRAVEL_SPEED   # = 2.5 s

# -- Highway layout (must match note.gd) ------------------------------------
const FRET_COUNT   : int   = 24
const FRET_SPACING : float = 1.0

# -- Camera follow -----------------------------------------------------------
## FOV (degrees) used for the zoomed-in follow camera.
const CAM_FOV_ZOOM      : float = 40.0
const CAMERA_Y          : float = 6.0
const CAMERA_Z          : float = -8.0
const CAMERA_LERP_SPEED : float = 4.0    # units/s for smooth pan

# -- Screenshot capture (for automated testing) ------------------------------
const SCREENSHOT_TIMES : Array  = [5.0, 10.0, 15.0, 20.0, 25.0]
const SCREENSHOT_DIR   : String = "user://screenshots"

# -- Max delta clamp to prevent fast-renderer notes from vanishing too quickly
const MAX_DELTA : float = 0.05

# -- Startup warmup ----------------------------------------------------------
## Seconds to show the empty highway before starting audio and note spawning.
## Gives the player a moment to see the highway before the music begins,
## matching the Rocksmith-style 3-second intro pause.
const WARMUP_SECS : float = 3.0

# -- Scene references --------------------------------------------------------
@onready var _pool   : Node3D            = $NotePool
@onready var _highway: Node3D            = $Highway
@onready var _player : AudioStreamPlayer = $AudioStreamPlayer
@onready var _camera : Camera3D          = $Camera3D

# -- State -------------------------------------------------------------------
var _bridge              = null  # RsBridge instance (no static type — avoids parse errors when class is not yet registered)
var _notes               : Array    = []
var _next_idx            : int      = 0
var _song_time           : float    = 0.0
var _playing             : bool     = false
var _shot_idx            : int      = 0
var _start_wall_ms       : int      = 0
var _play_from           : float    = 0.0   # audio seek offset (>0 when skipping a long intro)
var _camera_target_fret  : int      = FRET_COUNT / 2   # start at highway centre
var _warmup_timer        : float    = WARMUP_SECS  # counts down to 0.0, then audio+notes start

## Per-string fret-change tracker for smart label logic.
## -1 = no note has been spawned on this string yet.
## When the next note on string S has a different fret from _last_fret_per_string[S],
## the label is shown and _last_fret_per_string[S] is updated.
var _last_fret_per_string: Array[int] = [-1, -1, -1, -1, -1, -1]


func _ready() -> void:
	_bridge = _RsBridgeScript.new()

	var selected_psarc_path: String = _GameStateScript.selected_psarc_path
	print("MusicPlay: RocksmithBridge GDExtension loaded: %s" % str(ClassDB.class_exists("RocksmithBridge")))
	print("MusicPlay: AudioEngine GDExtension loaded: %s" % str(ClassDB.class_exists("AudioEngine")))

	if selected_psarc_path == "":
		push_error("MusicPlay: no song selected — choose a song from the game menu.")
		call_deferred("_return_to_menu")
		return

	print("MusicPlay: loading " + selected_psarc_path)
	if _bridge.load_psarc_abs(selected_psarc_path):
		_notes = _bridge.get_notes()
		print("MusicPlay: %d notes loaded, requesting audio stream..." % _notes.size())
		var stream : AudioStream = _bridge.get_audio_stream()
		if stream:
			print("MusicPlay: stream type=%s, assigning to AudioStreamPlayer" % stream.get_class())
			_player.stream = stream
			# Always start from the beginning of the decoded audio.
			_play_from = 0.0
			if _notes.size() > 0:
				var first_note_time: float = _notes[0]["time"]
				print("MusicPlay: first note at t=%.2fs — starting playback from beginning" % first_note_time)
		else:
			push_warning("MusicPlay: audio stream not available (no WEM/OGG in PSARC).")
	else:
		push_error("MusicPlay: failed to load psarc — place a valid .psarc in the DLC/ folder.")
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SCREENSHOT_DIR)
	)

	# Snap camera to the centre of the highway on startup; enable zoom FOV.
	if _camera:
		_camera.position.x = _fret_world_x(_camera_target_fret)
		_camera.position.y = CAMERA_Y
		_camera.position.z = CAMERA_Z
		_camera.fov        = CAM_FOV_ZOOM
		_camera.look_at(Vector3(_camera.position.x, 0.0, 10.0), Vector3.UP)

	# Start warmup countdown.  _process() will count down WARMUP_SECS real
	# seconds showing only the empty highway, then start both audio and note
	# spawning together so they are in sync from the first beat.
	_warmup_timer = WARMUP_SECS


func _process(delta: float) -> void:
	# Warmup phase: show the empty highway for WARMUP_SECS real seconds,
	# then start audio and note spawning simultaneously.
	if _warmup_timer > 0.0:
		_warmup_timer -= delta
		if _warmup_timer <= 0.0:
			_warmup_timer = 0.0
			if _player and _player.stream:
				_player.play(_play_from)
				print("MusicPlay: playback started — AudioStreamPlayer.playing=%s  volume_db=%s" % [
					str(_player.playing), str(_player.volume_db)])
			_start_wall_ms = Time.get_ticks_msec()
			_playing = true
		return

	if not _playing:
		return

	# Sync song time to the audio stream position, compensated for audio output
	# latency so that note spawning is accurate regardless of driver buffering.
	#
	# AudioServer.get_time_since_last_mix() gives sub-frame precision by
	# interpolating within the current mix interval.
	# AudioServer.get_output_latency() subtracts the time the OS audio stack
	# still has buffered before the samples actually reach the speakers.
	# Together they correct the ~50-200 ms latency typical on desktop hardware.
	if _player and _player.playing:
		_song_time = maxf(
			_play_from,
			_player.get_playback_position()
				+ AudioServer.get_time_since_last_mix()
				- AudioServer.get_output_latency()
		)
	else:
		# Wall-clock fallback: offset by _play_from so song time matches note timestamps.
		_song_time = _play_from + (Time.get_ticks_msec() - _start_wall_ms) / 1000.0

	# Push the authoritative audio time to all active notes so their Z
	# positions are computed directly from the audio clock (not accumulated delta).
	_pool.tick(_song_time)

	while _next_idx < _notes.size():
		var nd: Dictionary = _notes[_next_idx]
		if nd["time"] - _song_time <= LEAD_TIME:
			var f: int = nd["fret"]
			var s: int = nd["string"]
			# Skip open-string (fret 0) notes and any out-of-range fret values.
			if f >= 1 and f <= 24:
				# Smart label: show the fret number only when the fret changes on this string.
				var show_label := (f != _last_fret_per_string[s])
				if show_label:
					_last_fret_per_string[s] = f
				_pool.spawn_note(f, s, nd["time"], nd["duration"], show_label)
				# Track which fret the camera should follow.
				_camera_target_fret = f
			_next_idx += 1
		else:
			break

	# Camera always follows the most recently scheduled fret lane.
	if _camera:
		var target_x := _fret_world_x(_camera_target_fret)
		var cam_pos  := _camera.position
		cam_pos.x = lerp(cam_pos.x, target_x, CAMERA_LERP_SPEED * minf(delta, MAX_DELTA))
		cam_pos.y = CAMERA_Y
		cam_pos.z = CAMERA_Z
		_camera.position = cam_pos
		_camera.look_at(Vector3(cam_pos.x, 0.0, 10.0), Vector3.UP)

	# Screenshots based on real wall-clock time to avoid timer batching on slow renderers.
	if _shot_idx < SCREENSHOT_TIMES.size():
		var wall_sec := (Time.get_ticks_msec() - _start_wall_ms) / 1000.0
		if wall_sec >= SCREENSHOT_TIMES[_shot_idx]:
			_take_screenshot(_shot_idx + 1)
			_shot_idx += 1


# -- Helpers -----------------------------------------------------------------

## World X centre for a fret lane.  Mirrors note.gd formula:
##   X = (FRET_COUNT - fret + 0.5) * FRET_SPACING
func _fret_world_x(f: int) -> float:
	return (FRET_COUNT - f + 0.5) * FRET_SPACING


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


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/game_menu.tscn")


func push_print(msg: String) -> void:
	print(msg)
