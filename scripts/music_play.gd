extends Node3D
## music_play.gd -- main gameplay controller.
##
## Expects a PSARC song path selected in the song list menu (song_list.gd).

const _GoGuitarBridgeScript = preload("res://scripts/goguitar_bridge.gd")
const _GameStateScript = preload("res://scripts/game_state.gd")
const _ChartHudScript = preload("res://scripts/chartplayer_reference_hud.gd")

# -- Mixer bus indices (must match GameState.BUS_NAMES / gg-mixer BusId) ------
const BUS_MUSIC  : int = 1   # Music bus
const BUS_MASTER : int = 6   # Master bus

# -- Timing constants (must match note.gd) -----------------------------------
const TRAVEL_SPEED : float = 2.0
## Highway depth in world units.  Notes travel this distance (Z=0 → Z=20).
## LEAD_TIME = HIGHWAY_DEPTH / TRAVEL_SPEED = how many seconds ahead notes spawn.
const HIGHWAY_DEPTH : float = 20.0
const LEAD_TIME     : float = HIGHWAY_DEPTH / TRAVEL_SPEED   # = 10.0 s

# -- Highway layout (must match note.gd) ------------------------------------
const FRET_COUNT   : int   = 24
const FRET_SPACING : float = 1.0

# -- Camera follow -----------------------------------------------------------
## FOV (degrees) used for the follow camera.
const CAM_FOV           : float = 58.0
const CAMERA_Y          : float = 7.5
## Camera sits BEYOND the strum line (Z=26 > strum Z=20, defined in note.gd) looking back toward Z=0.
## This gives camera-right = world +X (fret 1 on left, fret 24 on right)
## and camera-up = world +Y (string 0 at bottom, string 5 at top). No inversions.
const CAMERA_Z          : float = 40.0
const CAMERA_LOOKAHEAD_Z: float = 18.0
const CAMERA_LERP_SPEED : float = 2.0    # units/s for smooth pan
## Camera X clamp — keeps the camera from tracking to the highway edges.
const CAMERA_X_MIN      : float = 0.5
const CAMERA_X_MAX      : float = 23.5

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

# -- String glow constants ---------------------------------------------------
## How many seconds before a note arrives to begin ramping up the string glow.
const GLOW_WINDOW : float = 2.0

# -- Debug overlay -----------------------------------------------------------
## Standard guitar string names (string index 0–5, low E to high e).
const STRING_NAMES    : Array[String] = ["E", "A", "D", "G", "B", "e"]
## Open-string MIDI note numbers in standard tuning (E2=40, A2=45, D3=50, G3=55, B3=59, e4=64).
const STRING_OPEN_MIDI: Array[int]    = [40, 45, 50, 55, 59, 64]
## Chromatic note names (MIDI mod 12 → name).
const NOTE_NAMES      : Array[String] = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
## Time window around the strum line used to detect the «current» chord for display.
const DEBUG_CHORD_WINDOW : float = 0.25
## Maximum timestamp difference between notes to be considered part of the same chord.
const CHORD_GROUP_THRESHOLD : float = 0.02
const DEFAULT_ARRANGEMENT_LABEL : String = "Lead"
const BPM_MIN_INTERVAL_SEC : float = 0.08
const BPM_MAX_INTERVAL_SEC : float = 1.5

# -- Scene references --------------------------------------------------------
@onready var _pool        : Node3D            = $NotePool
@onready var _highway     : Node3D            = $Highway
@onready var _fretboard   : Node3D            = $Fretboard
@onready var _player      : AudioStreamPlayer = $AudioStreamPlayer
@onready var _camera      : Camera3D          = $Camera3D
@onready var _debug_label : Label             = $DebugOverlay/DebugLabel
@onready var _chart_hud   : _ChartHudScript = $ChartPlayerReferenceHud

# -- State -------------------------------------------------------------------
var _bridge              = null  # GoGuitarBridge instance (no static type — avoids parse errors when class is not yet registered)
var _notes               : Array    = []
var _next_idx            : int      = 0
var _debug_strum_idx     : int      = 0   # pointer for strum-line debug printing
var _song_time           : float    = 0.0
var _playing             : bool     = false
var _shot_idx            : int      = 0
var _start_wall_ms       : int      = 0
var _camera_target_fret  : int      = FRET_COUNT / 2   # start at highway centre
var _warmup_timer        : float    = WARMUP_SECS  # counts down to 0.0, then audio+notes start
var _song_display_name   : String   = "Unknown Song"
var _estimated_bpm       : float    = 0.0

## Cached volume_db sent to the AudioStreamPlayer last frame.  -999 = first frame.
var _cached_volume_db    : float    = -999.0

## Per-string glow state for smooth transitions.
## Tracks the current shader intensity so we can lerp toward the target each frame.
var _string_glow         : Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## Scan pointer into _notes for the string-glow window.
## Advances past notes that have fully passed the strum line.
var _glow_cursor         : int      = 0

## Per-string fret-change tracker for smart label logic.
## -1 = no note has been spawned on this string yet.
## When the next note on string S has a different fret from _last_fret_per_string[S],
## the label is shown and _last_fret_per_string[S] is updated.
var _last_fret_per_string: Array[int] = [-1, -1, -1, -1, -1, -1]


func _ready() -> void:
	_bridge = _GoGuitarBridgeScript.new()

	# Load persisted mixer settings so volume/mute state is correct from the start.
	_GameStateScript.load_mixer_settings()

	var selected_psarc_path: String = _GameStateScript.selected_psarc_path
	if selected_psarc_path != "":
		_song_display_name = _extract_song_name_from_path(selected_psarc_path)
	print("MusicPlay: RocksmithBridge GDExtension loaded: %s" % str(ClassDB.class_exists("RocksmithBridge")))
	print("MusicPlay: AudioEngine GDExtension loaded: %s" % str(ClassDB.class_exists("AudioEngine")))

	if selected_psarc_path == "":
		push_error("MusicPlay: no song selected — choose a song from the game menu.")
		call_deferred("_return_to_menu")
		return

	print("MusicPlay: loading " + selected_psarc_path)
	if _bridge.load_psarc_abs(selected_psarc_path):
		_notes = _bridge.get_notes()
		_estimated_bpm = _estimate_bpm_from_notes()
		print("MusicPlay: %d notes loaded, requesting audio stream..." % _notes.size())
		# -- Diagnostic: print first 15 chord groups so fret/string values are visible.
		# Notes at the same timestamp (within 20 ms) are grouped as a single chord line.
		# Format: note[N] t=T.Ts  note=CHORD_ROOT  | fret=F1  string=S1(name), ...
		var chord_idx : int = 0
		var ni        : int = 0
		while ni < _notes.size() and chord_idx < 15:
			var dn : Dictionary = _notes[ni]
			var dt : float = float(dn.get("time", 0.0))
			# Collect all notes at the same timestamp into a chord.
			var chord_notes : Array = [dn]
			var nj : int = ni + 1
			while nj < _notes.size() \
					and absf(float(_notes[nj].get("time", 0.0)) - dt) < CHORD_GROUP_THRESHOLD:
				chord_notes.append(_notes[nj])
				nj += 1
			# The chord root name is the note of the very first note (before sorting).
			var first_f    : int    = int(dn.get("fret",   -1))
			var first_s    : int    = int(dn.get("string", -1))
			var chord_root : String = _get_note_name(first_f, first_s)
			# Sort chord notes by fret ascending for readability.
			var parts : Array[String] = []
			for cn in _sort_notes_by_fret(chord_notes):
				var cf    : int    = int(cn.get("fret",   -1))
				var cs    : int    = int(cn.get("string", -1))
				var csname : String = STRING_NAMES[cs] if cs >= 0 and cs < 6 else "?"
				parts.append("fret=%d  string=%d(%s)" % [cf, cs, csname])
			print("MusicPlay:  note[%d] t=%.3fs  note=%s  | %s" \
				% [chord_idx, dt, chord_root, "  ".join(parts)])
			chord_idx += 1
			ni = nj
		var stream : AudioStream = _bridge.get_audio_stream()
		if stream:
			print("MusicPlay: stream type=%s, assigning to AudioStreamPlayer" % stream.get_class())
			_player.stream = stream
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
		_camera.position.x = clampf(_fret_world_x(_camera_target_fret), CAMERA_X_MIN, CAMERA_X_MAX)
		_camera.position.y = CAMERA_Y
		_camera.position.z = CAMERA_Z
		_camera.fov        = CAM_FOV
		_camera.look_at(Vector3(_camera.position.x, 0.0, _camera.position.z - CAMERA_LOOKAHEAD_Z), Vector3.UP)

	# Start warmup countdown.  _process() will count down WARMUP_SECS real
	# seconds showing only the empty highway, then start both audio and note
	# spawning together so they are in sync from the first beat.
	_warmup_timer = WARMUP_SECS
	if is_instance_valid(_chart_hud):
		_chart_hud.set_song_meta(_song_display_name, DEFAULT_ARRANGEMENT_LABEL)
		_chart_hud.set_reference_lyrics("Now playing: " + _song_display_name, "Get ready")


func _process(delta: float) -> void:
	# Warmup phase: show the empty highway for WARMUP_SECS real seconds,
	# then start audio and note spawning simultaneously.
	if _warmup_timer > 0.0:
		_warmup_timer -= delta
		if _warmup_timer <= 0.0:
			_warmup_timer = 0.0
			if _player and _player.stream:
				_player.play(0.0)
				print("MusicPlay: playback started — AudioStreamPlayer.playing=%s  volume_db=%s" % [
					str(_player.playing), str(_player.volume_db)])
			_start_wall_ms = Time.get_ticks_msec()
			_playing = true
		return

	if not _playing:
		return

	# ── Apply mixer settings from GameState to the AudioStreamPlayer ──────────
	# This allows the Mixer screen to affect playback volume in real time.
	# Music bus (index 1) + Master bus (index 6) combine additively in dB.
	if _player:
		var music_muted  : bool  = _GameStateScript.bus_mutes[BUS_MUSIC]
		var master_muted : bool  = _GameStateScript.bus_mutes[BUS_MASTER]
		var target_db : float
		if music_muted or master_muted:
			target_db = -80.0   # effectively silent
		else:
			target_db = _GameStateScript.bus_gains_db[BUS_MUSIC] \
				+ _GameStateScript.bus_gains_db[BUS_MASTER]
		# Only write the property when the value actually changed to avoid
		# unnecessary per-frame property updates when the mixer is idle.
		if target_db != _cached_volume_db:
			_player.volume_db  = target_db
			_cached_volume_db  = target_db

	# ── Song clock ───────────────────────────────────────────────────────────
	# The MAIN WEM is the full-length song — no loop detection needed.
	if _player and _player.playing:
		_song_time = _player.get_playback_position() \
			+ AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
		_song_time = maxf(_song_time, 0.0)
	else:
		# Wall-clock fallback when audio isn't playing.
		_song_time = float(Time.get_ticks_msec() - _start_wall_ms) / 1000.0

	# Push the authoritative audio time to all active notes so their Z
	# positions are computed directly from the audio clock (not accumulated delta).
	_pool.tick(_song_time)

	# ── Strum-line debug print ─────────────────────────────────────────────────
	# Print each chord group the moment it crosses the strum line (song_time >= note.time).
	while _debug_strum_idx < _notes.size():
		var nd : Dictionary = _notes[_debug_strum_idx]
		var dt : float      = float(nd.get("time", 0.0))
		if _song_time >= dt:
			# Collect all notes sharing this timestamp.
			var chord_notes : Array = [nd]
			var nj : int = _debug_strum_idx + 1
			while nj < _notes.size() \
					and absf(float(_notes[nj].get("time", 0.0)) - dt) < CHORD_GROUP_THRESHOLD:
				chord_notes.append(_notes[nj])
				nj += 1
			print("STRUM %dms | %s" % [int(_song_time * 1000), _chord_debug_str(chord_notes)])
			_debug_strum_idx = nj
		else:
			break

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
		var target_x := clampf(_fret_world_x(_camera_target_fret), CAMERA_X_MIN, CAMERA_X_MAX)
		var cam_pos  := _camera.position
		cam_pos.x = lerp(cam_pos.x, target_x, CAMERA_LERP_SPEED * minf(delta, MAX_DELTA))
		cam_pos.y = CAMERA_Y
		cam_pos.z = CAMERA_Z
		_camera.position = cam_pos
		_camera.look_at(Vector3(cam_pos.x, 0.0, cam_pos.z - CAMERA_LOOKAHEAD_Z), Vector3.UP)

	# Screenshots based on real wall-clock time to avoid timer batching on slow renderers.
	if _shot_idx < SCREENSHOT_TIMES.size():
		var wall_sec := (Time.get_ticks_msec() - _start_wall_ms) / 1000.0
		if wall_sec >= SCREENSHOT_TIMES[_shot_idx]:
			_take_screenshot(_shot_idx + 1)
			_shot_idx += 1

	# Drive per-string glow intensity from upcoming note data.
	_update_string_glows()

	# Update debug info overlay.
	_update_debug_info()
	_update_chartplayer_reference_hud()


# -- Helpers -----------------------------------------------------------------

## World X centre for a fret lane.  Mirrors note.gd formula:
##   X = fret × FRET_SPACING − FRET_SPACING × 0.5
## fret 1 → X = 0.5 (left), fret 24 → X = 23.5 (right).  No inversion needed.
func _fret_world_x(f: int) -> float:
	return f * FRET_SPACING - FRET_SPACING * 0.5


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


## Scan notes within GLOW_WINDOW seconds and set per-string shader intensity.
## Strings ramp from 0.0 (dim) → 1.0 (bright) as a note approaches, then
## decay back to 0.0 after the note passes the strum line.
func _update_string_glows() -> void:
	if not is_instance_valid(_fretboard):
		return

	# Advance the glow cursor past notes that have already left the strum zone.
	while _glow_cursor < _notes.size() \
			and (_notes[_glow_cursor]["time"] as float) < _song_time - 0.20:
		_glow_cursor += 1

	# Compute target glow intensity per string: highest intensity wins when
	# multiple notes for the same string fall within the window.
	var targets : Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var i : int = _glow_cursor
	while i < _notes.size():
		var note_time : float = _notes[i]["time"]
		var dt        : float = note_time - _song_time
		if dt > GLOW_WINDOW:
			break
		var s : int = int(_notes[i].get("string", -1))
		if s >= 0 and s < 6:
			# Quadratic ease-in: near-zero far away, steep rise in the last 0.5 s.
			var t         : float = clampf(dt / GLOW_WINDOW, 0.0, 1.0)
			var intensity : float = 1.0 - t * t
			if intensity > targets[s]:
				targets[s] = intensity
		i += 1

	# Smooth transitions: fast attack (note arriving) / slow decay (note gone).
	for s in 6:
		var current : float = _string_glow[s]
		var target  : float = targets[s]
		var lerp_k  : float = 0.25 if target > current else 0.06
		var new_val : float = lerpf(current, target, lerp_k)
		if absf(new_val - current) > 0.001:
			_string_glow[s] = new_val
			_fretboard.set_string_glow(s, new_val)


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/game_menu.tscn")


## Compute the note name for a given fret + string index using standard tuning.
## Returns e.g. "G", "C#", "D".
func _get_note_name(fret: int, string_idx: int) -> String:
	if string_idx < 0 or string_idx >= 6 or fret < 0 or fret > 24:
		return "?"
	var midi := STRING_OPEN_MIDI[string_idx] + fret
	return NOTE_NAMES[midi % 12]


## Sort an array of note dictionaries by fret ascending (returns a sorted copy).
func _sort_notes_by_fret(notes: Array) -> Array:
	var sorted : Array = notes.duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("fret", -1)) < int(b.get("fret", -1)))
	return sorted


## Build a compact debug string for a chord (group of notes at the same timestamp).
## Format per note: "Fret F/String S(note)"   e.g. "Fret 3/String B(D)"
## Notes are sorted by fret ascending.
func _chord_debug_str(chord_notes: Array) -> String:
	var parts : Array[String] = []
	for nd in _sort_notes_by_fret(chord_notes):
		var f     : int    = int(nd.get("fret",   -1))
		var s     : int    = int(nd.get("string", -1))
		var sname : String = STRING_NAMES[s] if s >= 0 and s < 6 else "?"
		var nname : String = _get_note_name(f, s)
		parts.append("Fret %d/String %s(%s)" % [f, sname, nname])
	return ", ".join(parts)


## Update the on-screen debug label with current song time and nearest chord info.
## Format: "TIME_MS - Note CHORD_ROOT - Fret F/String S(note), ..."
## Called every frame from _process().
func _update_debug_info() -> void:
	if not is_instance_valid(_debug_label):
		return

	var time_ms : int = int(_song_time * 1000.0)

	# Scan notes to find the chord group closest to (and just ahead of) the strum line.
	# We look in the window [song_time - 0.10s, song_time + DEBUG_CHORD_WINDOW].
	var best_chord     : Array  = []
	var best_time      : float  = INF
	var best_time_diff : float  = INF

	var i : int = 0
	# Start from a position close to _song_time to avoid scanning the entire array.
	# Use _glow_cursor as a cheap lower-bound (it's already near _song_time).
	i = maxi(0, _glow_cursor - 10)
	while i < _notes.size():
		var nd     : Dictionary = _notes[i]
		var t      : float      = float(nd.get("time", -1.0))
		if t > _song_time + DEBUG_CHORD_WINDOW:
			break
		if t < _song_time - 0.10:
			i += 1
			continue
		# Candidate note: find its chord group (all notes with the same timestamp).
		var diff : float = absf(t - _song_time)
		if diff < best_time_diff:
			best_time_diff = diff
			best_time      = t
			best_chord     = []
		if absf(t - best_time) < CHORD_GROUP_THRESHOLD:
			best_chord.append(nd)
		i += 1

	var chord_str : String = ""
	if best_chord.size() > 0:
		# Chord root = note name of the first note in the chord (before sorting).
		var root_f    : int    = int(best_chord[0].get("fret",   -1))
		var root_s    : int    = int(best_chord[0].get("string", -1))
		var root_name : String = _get_note_name(root_f, root_s)
		chord_str = " - Note %s - %s" % [root_name, _chord_debug_str(best_chord)]

	_debug_label.text = "%dms%s" % [time_ms, chord_str]


func _update_chartplayer_reference_hud() -> void:
	if not is_instance_valid(_chart_hud):
		return
	var root_note := ""
	if _glow_cursor >= 0 and _glow_cursor < _notes.size():
		var nd : Dictionary = _notes[_glow_cursor]
		root_note = _get_note_name(int(nd.get("fret", -1)), int(nd.get("string", -1)))
	var song_length := 1.0
	if _notes.size() > 0:
		song_length = maxf(float(_notes[_notes.size() - 1].get("time", 0.0)), 1.0)
	_chart_hud.update_runtime(_song_time, _estimated_bpm, _next_idx, _notes.size(), root_note, song_length)


func _estimate_bpm_from_notes() -> float:
	if _notes.size() < 2:
		return 0.0
	var intervals: Array[float] = []
	var prev_time: float = float(_notes[0].get("time", 0.0))
	for i in range(1, _notes.size()):
		var t: float = float(_notes[i].get("time", prev_time))
		var dt: float = t - prev_time
		if dt > BPM_MIN_INTERVAL_SEC and dt < BPM_MAX_INTERVAL_SEC:
			intervals.append(dt)
		prev_time = t
	if intervals.is_empty():
		return 0.0
	intervals.sort()
	var median_index: int = intervals.size() / 2
	var dominant_interval: float = intervals[median_index]
	if intervals.size() % 2 == 0:
		dominant_interval = (intervals[median_index - 1] + intervals[median_index]) * 0.5
	return clampf(60.0 / dominant_interval, 40.0, 240.0)


func _extract_song_name_from_path(song_path: String) -> String:
	return song_path.get_file().trim_suffix(".psarc")


func push_print(msg: String) -> void:
	print(msg)
