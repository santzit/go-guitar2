## Tuner3D — 3D scene root for the live tuner.
##
## The 3D environment (Camera, WorldEnvironment, lights) is built here in code.
## All UI (gauge, note circle, FretboardView) lives inside a CanvasLayer overlay
## so the FretboardView is reused as-is with its GLSL vibration + ring shaders.
extends Node3D

const _GameStateScript = preload("res://scripts/game_state.gd")
const _PitchGaugeScript = preload("res://scripts/tuner/pitch_gauge.gd")

const DEFAULT_TUNING_NAME: String = "E Standard"
const DEFAULT_TUNING_NOTES: Array[String] = ["E2", "A2", "D3", "G3", "B3", "E4"]
const IN_TUNE_TOLERANCE_CENTS: float = 5.0
const SMOOTH_FACTOR: float = 0.35
const MIN_PERIODICITY: float = 0.60
const STALE_TIMEOUT_MS: int = 700
const A4_FREQUENCY_HZ: float = 440.0
const A4_MIDI_NOTE: int = 69
const SEMITONES_PER_OCTAVE: float = 12.0

const NOTE_NAMES: PackedStringArray = [
	"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
]

# ── UI node references (inside CanvasLayer) ────────────────────────────────────
@onready var _tuning_name_label: Label    = $UIOverlay/MarginContainer/VBoxRoot/TopMeta/TuningNameLabel
@onready var _target_notes_label: Label   = $UIOverlay/MarginContainer/VBoxRoot/TopMeta/TargetNotesLabel
@onready var _selected_string_label: Label = $UIOverlay/MarginContainer/VBoxRoot/TopMeta/SelectedStringLabel
@onready var _detected_note_label: Label  = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/NoteCircle/DetectedNoteLabel
@onready var _frequency_label: Label      = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/NoteCircle/DetectedFrequencyLabel
@onready var _cents_label: Label          = $UIOverlay/MarginContainer/VBoxRoot/BottomControls/BottomRow/CentsChip/CentsLabel
@onready var _guidance_label: Label       = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/GuidanceLabel
@onready var _gauge_meter: _PitchGaugeScript = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/GaugeMeter
@onready var _fretboard                   = $UIOverlay/MarginContainer/VBoxRoot/BottomControls/FretboardView
@onready var _left_note_label: Label      = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/LeftNoteLabel
@onready var _right_note_label: Label     = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/RightNoteLabel

# ── Pitch detection state ──────────────────────────────────────────────────────
var _pitch_detector      = null
var _input_audio_manager = null
var _target_notes: Array[String] = []
var _target_freqs: Array[float]  = []
var _selected_string_idx: int    = -1

var _smoothed_freq_hz: float = 0.0
var _smoothed_cents:   float = 0.0
var _has_detection:    bool  = false
var _last_detection_ms: int  = 0


func _ready() -> void:
	# Build the 3D atmosphere first (before @onready UI nodes are needed).
	# _build_3d_environment() only creates Node3D children and does not
	# reference any UIOverlay elements, so this ordering is safe.
	_build_3d_environment()

	_target_notes = _GameStateScript.selected_tuning_notes.duplicate()
	_input_audio_manager = get_node_or_null("/root/InputAudioManager")
	if _target_notes.size() != 6:
		_target_notes = DEFAULT_TUNING_NOTES.duplicate()
	_GameStateScript.selected_tuning_notes = _target_notes.duplicate()
	if _GameStateScript.selected_tuning_name.is_empty():
		_GameStateScript.selected_tuning_name = DEFAULT_TUNING_NAME

	_tuning_name_label.text  = "Preset: %s" % _GameStateScript.selected_tuning_name
	_target_notes_label.text = "Target notes: %s" % " ".join(PackedStringArray(_target_notes))
	_target_freqs = _build_target_freqs(_target_notes)

	_fretboard.set_string_names(PackedStringArray(_target_notes))
	_fretboard.set_selected_string(_selected_string_idx)
	_fretboard.string_pressed.connect(_on_string_button_pressed)
	_update_selected_string_label()

	_gauge_meter.set_meter_value(0.0, false, false)
	_set_waiting_ui()

	if ClassDB.class_exists("PitchDetector"):
		if _input_audio_manager == null:
			_guidance_label.text = "InputAudioManager singleton unavailable."
		else:
			_pitch_detector = ClassDB.instantiate("PitchDetector")
			var sample_rate: int = AudioServer.get_mix_rate()
			if _pitch_detector.start(sample_rate):
				if not _input_audio_manager.samples_ready.is_connected(_on_guitar_samples):
					_input_audio_manager.samples_ready.connect(_on_guitar_samples)
			else:
				_pitch_detector = null
				_guidance_label.text = "PitchDetector.start() failed."
	else:
		_guidance_label.text = "PitchDetector class not available."


# ── 3D environment setup ───────────────────────────────────────────────────────

func _build_3d_environment() -> void:
	# Dark atmospheric background that makes the rainbow strings pop
	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode  = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.07, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color  = Color(0.10, 0.10, 0.16)
	environment.ambient_light_energy = 1.0
	# Glow makes the lit string colours bloom into the dark background
	environment.glow_enabled       = true
	environment.glow_normalized    = false
	environment.glow_intensity     = 1.0
	environment.glow_bloom         = 0.18
	environment.glow_hdr_threshold = 0.65
	env_node.environment = environment
	add_child(env_node)

	# Camera — orthographic so the UI and fretboard stay pixel-accurate
	var camera := Camera3D.new()
	camera.position       = Vector3(0.0, 0.0, 1.0)
	camera.current        = true
	camera.projection     = Camera3D.PROJECTION_ORTHOGONAL
	camera.size           = 2.0
	add_child(camera)

	# Soft key light from the top-left
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	key_light.light_color      = Color(1.0, 0.96, 0.88)
	key_light.light_energy     = 0.8
	add_child(key_light)


# ── Game loop ─────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _has_detection and Time.get_ticks_msec() - _last_detection_ms > STALE_TIMEOUT_MS:
		_set_waiting_ui()


func _exit_tree() -> void:
	if _input_audio_manager != null \
			and _input_audio_manager.samples_ready.is_connected(_on_guitar_samples):
		_input_audio_manager.samples_ready.disconnect(_on_guitar_samples)
	if _pitch_detector != null:
		_pitch_detector.stop()


# ── Audio input ───────────────────────────────────────────────────────────────

func _on_guitar_samples(player_id: int, pcm_bytes: PackedByteArray) -> void:
	if player_id != 1 or _pitch_detector == null:
		return

	var detections: Array = _pitch_detector.process_samples(pcm_bytes)
	if detections.is_empty():
		return

	var best: Dictionary = {}
	var best_periodicity: float = -1.0
	for d in detections:
		var p: float = float(d.get("periodicity", 0.0))
		if p > best_periodicity:
			best_periodicity = p
			best = d

	if best_periodicity < MIN_PERIODICITY:
		return

	var freq_hz: float = float(best.get("frequency", 0.0))
	if freq_hz <= 0.0:
		return
	if _target_freqs.is_empty():
		return

	var target_idx: int = _get_target_string_index(freq_hz)
	if target_idx < 0 or target_idx >= _target_freqs.size():
		return

	var target_hz: float = _target_freqs[target_idx]
	var cents: float     = _freq_to_cents(freq_hz, target_hz)

	if not _has_detection:
		_smoothed_freq_hz = freq_hz
		_smoothed_cents   = cents
		_has_detection    = true
	else:
		_smoothed_freq_hz = lerpf(_smoothed_freq_hz, freq_hz, SMOOTH_FACTOR)
		_smoothed_cents   = lerpf(_smoothed_cents, cents, SMOOTH_FACTOR)

	_last_detection_ms = Time.get_ticks_msec()
	_apply_live_ui(target_idx)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tuner/tuning_list.tscn")


func _on_string_button_pressed(string_idx: int) -> void:
	if _selected_string_idx == string_idx:
		_selected_string_idx = -1
	else:
		_selected_string_idx = string_idx
	_fretboard.set_selected_string(_selected_string_idx)
	_update_selected_string_label()
	if _has_detection:
		_apply_live_ui(_get_target_string_index(_smoothed_freq_hz))


# ── UI updates ────────────────────────────────────────────────────────────────

func _update_selected_string_label() -> void:
	if _selected_string_idx >= 0 and _selected_string_idx < _target_notes.size():
		_selected_string_label.text = "Selected string: %s (manual)" % _target_notes[_selected_string_idx]
	else:
		_selected_string_label.text = "Selected string: Auto (closest target note)"


func _apply_live_ui(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= _target_freqs.size():
		return
	var target_hz: float  = _target_freqs[target_idx]
	var note_name: String = _freq_to_note_name(_smoothed_freq_hz)
	var is_in_tune: bool  = absf(_smoothed_cents) <= IN_TUNE_TOLERANCE_CENTS

	_detected_note_label.text = note_name
	_frequency_label.text     = "%.2f Hz" % _smoothed_freq_hz
	_cents_label.text         = "Offset: %+0.1f cents vs %s (%.2f Hz)" % \
			[_smoothed_cents, _target_notes[target_idx], target_hz]
	_gauge_meter.set_meter_value(_smoothed_cents, true, is_in_tune)
	_update_side_note_labels(note_name)

	var vib_col: Color
	if is_in_tune:
		vib_col = Color(0.4, 1.0, 0.5)
		_guidance_label.text     = "IN TUNE ✓"
		_guidance_label.modulate = Color(0.4, 1.0, 0.5)
	elif _smoothed_cents < 0.0:
		vib_col = Color(0.45, 0.75, 1.0)
		_guidance_label.text     = "FLAT — tune up"
		_guidance_label.modulate = Color(1.0, 0.8, 0.4)
	else:
		vib_col = Color(1.0, 0.52, 0.35)
		_guidance_label.text     = "SHARP — tune down"
		_guidance_label.modulate = Color(1.0, 0.7, 0.4)

	_fretboard.set_active_string(target_idx)
	_fretboard.set_vibration_color(vib_col)


func _set_waiting_ui() -> void:
	_has_detection            = false
	_detected_note_label.text = "--"
	_frequency_label.text     = "-- Hz"
	_cents_label.text         = "Offset: -- cents"
	_left_note_label.text     = "--"
	_right_note_label.text    = "--"
	_guidance_label.text      = "Waiting for signal…"
	_guidance_label.modulate  = Color(1.0, 1.0, 1.0)
	_gauge_meter.set_meter_value(0.0, false, false)
	_fretboard.set_active_string(-1)


# ── Pitch math helpers (identical to tuner.gd) ────────────────────────────────

func _build_target_freqs(notes: Array[String]) -> Array[float]:
	var out: Array[float] = []
	for n in notes:
		out.append(_note_to_freq(String(n)))
	return out


func _find_closest_target_string(freq_hz: float) -> int:
	if _target_freqs.is_empty():
		return -1
	var best_idx: int        = 0
	var best_abs_cents: float = INF
	for i in range(_target_freqs.size()):
		var cents: float = absf(_freq_to_cents(freq_hz, _target_freqs[i]))
		if cents < best_abs_cents:
			best_abs_cents = cents
			best_idx       = i
	return best_idx


func _get_target_string_index(freq_hz: float) -> int:
	if _selected_string_idx >= 0:
		return _selected_string_idx
	return _find_closest_target_string(freq_hz)


func _freq_to_cents(freq_hz: float, reference_hz: float) -> float:
	if freq_hz <= 0.0 or reference_hz <= 0.0:
		return 0.0
	return 1200.0 * (log(freq_hz / reference_hz) / log(2.0))


func _freq_to_note_name(freq_hz: float) -> String:
	if freq_hz <= 0.0:
		return "--"
	var midi: int      = int(round(A4_MIDI_NOTE + SEMITONES_PER_OCTAVE * (log(freq_hz / A4_FREQUENCY_HZ) / log(2.0))))
	var note_name: String = NOTE_NAMES[posmod(midi, 12)]
	var octave: int    = int(floor(float(midi) / 12.0)) - 1
	return "%s%d" % [note_name, octave]


func _note_to_freq(note: String) -> float:
	if note.length() < 2:
		return 0.0
	var split: int = note.length() - 1
	while split >= 0:
		var ch: String = note.substr(split, 1)
		if ch < "0" or ch > "9":
			break
		split -= 1
	split += 1
	if split <= 0 or split >= note.length():
		return 0.0
	var octave: int   = int(note.substr(split))
	var name: String  = note.substr(0, split)
	var semitone: int = NOTE_NAMES.find(name)
	if semitone < 0:
		return 0.0
	var midi: int = (octave + 1) * 12 + semitone
	return A4_FREQUENCY_HZ * pow(2.0, float(midi - A4_MIDI_NOTE) / SEMITONES_PER_OCTAVE)


func _update_side_note_labels(note_with_octave: String) -> void:
	if note_with_octave == "--":
		_left_note_label.text  = "--"
		_right_note_label.text = "--"
		return
	var split: int = note_with_octave.length()
	while split > 0:
		var ch: String = note_with_octave.substr(split - 1, 1)
		if ch < "0" or ch > "9":
			break
		split -= 1
	var base: String = note_with_octave.substr(0, split)
	var idx: int     = NOTE_NAMES.find(base)
	if idx < 0:
		_left_note_label.text  = "--"
		_right_note_label.text = "--"
		return
	_left_note_label.text  = NOTE_NAMES[posmod(idx - 1, NOTE_NAMES.size())]
	_right_note_label.text = NOTE_NAMES[posmod(idx + 1, NOTE_NAMES.size())]
