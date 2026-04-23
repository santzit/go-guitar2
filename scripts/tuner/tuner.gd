extends Control

const _GameStateScript = preload("res://scripts/game_state.gd")

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

@onready var _tuning_name_label: Label = $Panel/MarginContainer/VBoxRoot/TopMeta/TuningNameLabel
@onready var _target_notes_label: Label = $Panel/MarginContainer/VBoxRoot/TopMeta/TargetNotesLabel
@onready var _selected_string_label: Label = $Panel/MarginContainer/VBoxRoot/TopMeta/SelectedStringLabel
@onready var _detected_note_label: Label = $Panel/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/NoteCircle/DetectedNoteLabel
@onready var _frequency_label: Label = $Panel/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/NoteCircle/DetectedFrequencyLabel
@onready var _cents_label: Label = $Panel/MarginContainer/VBoxRoot/BottomControls/BottomRow/CentsChip/CentsLabel
@onready var _guidance_label: Label = $Panel/MarginContainer/VBoxRoot/MainArea/CenterStack/GuidanceLabel
@onready var _cents_bar: ProgressBar = $Panel/MarginContainer/VBoxRoot/MainArea/CenterStack/CentsBar
@onready var _string_buttons: HBoxContainer = $Panel/MarginContainer/VBoxRoot/BottomControls/StringButtons
@onready var _left_note_label: Label = $Panel/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/LeftNoteLabel
@onready var _right_note_label: Label = $Panel/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/RightNoteLabel

var _pitch_detector = null
var _input_audio_manager = null
var _target_notes: Array[String] = []
var _target_freqs: Array[float] = []
var _selected_string_idx: int = -1

var _smoothed_freq_hz: float = 0.0
var _smoothed_cents: float = 0.0
var _has_detection: bool = false
var _last_detection_ms: int = 0


func _ready() -> void:
	_target_notes = _GameStateScript.selected_tuning_notes.duplicate()
	_input_audio_manager = get_node_or_null("/root/InputAudioManager")
	if _target_notes.size() != 6:
		_target_notes = DEFAULT_TUNING_NOTES.duplicate()
	_GameStateScript.selected_tuning_notes = _target_notes.duplicate()
	if _GameStateScript.selected_tuning_name.is_empty():
		_GameStateScript.selected_tuning_name = DEFAULT_TUNING_NAME

	_tuning_name_label.text = "Preset: %s" % _GameStateScript.selected_tuning_name
	_target_notes_label.text = "Target notes: %s" % " ".join(PackedStringArray(_target_notes))
	_target_freqs = _build_target_freqs(_target_notes)
	_build_string_buttons()
	_update_selected_string_label()

	_cents_bar.min_value = -50.0
	_cents_bar.max_value = 50.0
	_cents_bar.value = 0.0
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


func _process(_delta: float) -> void:
	if _has_detection and Time.get_ticks_msec() - _last_detection_ms > STALE_TIMEOUT_MS:
		_set_waiting_ui()


func _exit_tree() -> void:
	if _input_audio_manager != null and _input_audio_manager.samples_ready.is_connected(_on_guitar_samples):
		_input_audio_manager.samples_ready.disconnect(_on_guitar_samples)
	if _pitch_detector != null:
		_pitch_detector.stop()


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
	var cents: float = _freq_to_cents(freq_hz, target_hz)

	if not _has_detection:
		_smoothed_freq_hz = freq_hz
		_smoothed_cents = cents
		_has_detection = true
	else:
		_smoothed_freq_hz = lerpf(_smoothed_freq_hz, freq_hz, SMOOTH_FACTOR)
		_smoothed_cents = lerpf(_smoothed_cents, cents, SMOOTH_FACTOR)

	_last_detection_ms = Time.get_ticks_msec()
	_apply_live_ui(target_idx)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tuner/tuning_list.tscn")


func _on_string_button_pressed(string_idx: int) -> void:
	if _selected_string_idx == string_idx:
		_selected_string_idx = -1
	else:
		_selected_string_idx = string_idx
	_update_string_button_states()
	_update_selected_string_label()
	if _has_detection:
		_apply_live_ui(_get_target_string_index(_smoothed_freq_hz))


func _build_string_buttons() -> void:
	for child in _string_buttons.get_children():
		child.queue_free()
	for i in range(_target_notes.size()):
		var btn := Button.new()
		btn.text = _target_notes[i]
		btn.toggle_mode = true
		btn.pressed.connect(_on_string_button_pressed.bind(i))
		_string_buttons.add_child(btn)
	_update_string_button_states()


func _update_string_button_states() -> void:
	for i in range(_string_buttons.get_child_count()):
		var btn := _string_buttons.get_child(i) as Button
		btn.button_pressed = i == _selected_string_idx


func _update_selected_string_label() -> void:
	if _selected_string_idx >= 0 and _selected_string_idx < _target_notes.size():
		_selected_string_label.text = "Selected string: %s (manual)" % _target_notes[_selected_string_idx]
	else:
		_selected_string_label.text = "Selected string: Auto (closest target note)"


func _apply_live_ui(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= _target_freqs.size():
		return
	var target_hz: float = _target_freqs[target_idx]
	var note_name: String = _freq_to_note_name(_smoothed_freq_hz)
	_detected_note_label.text = note_name
	_frequency_label.text = "%.2f Hz" % _smoothed_freq_hz
	_cents_label.text = "Offset: %+0.1f cents vs %s (%.2f Hz)" % [_smoothed_cents, _target_notes[target_idx], target_hz]
	_cents_bar.value = clampf(_smoothed_cents, -50.0, 50.0)
	_update_side_note_labels(note_name)

	if absf(_smoothed_cents) <= IN_TUNE_TOLERANCE_CENTS:
		_guidance_label.text = "IN TUNE ✓"
		_guidance_label.modulate = Color(0.4, 1.0, 0.5)
	elif _smoothed_cents < 0.0:
		_guidance_label.text = "FLAT — tune up"
		_guidance_label.modulate = Color(1.0, 0.8, 0.4)
	else:
		_guidance_label.text = "SHARP — tune down"
		_guidance_label.modulate = Color(1.0, 0.7, 0.4)


func _set_waiting_ui() -> void:
	_has_detection = false
	_detected_note_label.text = "--"
	_frequency_label.text = "-- Hz"
	_cents_label.text = "Offset: -- cents"
	_left_note_label.text = "--"
	_right_note_label.text = "--"
	_guidance_label.text = "Waiting for signal…"
	_guidance_label.modulate = Color(1.0, 1.0, 1.0)
	_cents_bar.value = 0.0


func _build_target_freqs(notes: Array[String]) -> Array[float]:
	var out: Array[float] = []
	for n in notes:
		out.append(_note_to_freq(String(n)))
	return out


func _find_closest_target_string(freq_hz: float) -> int:
	if _target_freqs.is_empty():
		return -1
	var best_idx: int = 0
	var best_abs_cents: float = INF
	for i in range(_target_freqs.size()):
		var cents: float = absf(_freq_to_cents(freq_hz, _target_freqs[i]))
		if cents < best_abs_cents:
			best_abs_cents = cents
			best_idx = i
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
	var midi: int = int(round(A4_MIDI_NOTE + SEMITONES_PER_OCTAVE * (log(freq_hz / A4_FREQUENCY_HZ) / log(2.0))))
	var note_name: String = NOTE_NAMES[posmod(midi, 12)]
	var octave: int = int(floor(float(midi) / 12.0)) - 1
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
	var octave: int = int(note.substr(split))
	var name: String = note.substr(0, split)
	var semitone: int = NOTE_NAMES.find(name)
	if semitone < 0:
		return 0.0
	var midi: int = (octave + 1) * 12 + semitone
	return A4_FREQUENCY_HZ * pow(2.0, float(midi - A4_MIDI_NOTE) / SEMITONES_PER_OCTAVE)


func _update_side_note_labels(note_with_octave: String) -> void:
	if note_with_octave == "--":
		_left_note_label.text = "--"
		_right_note_label.text = "--"
		return
	var split: int = note_with_octave.length()
	while split > 0:
		var ch: String = note_with_octave.substr(split - 1, 1)
		if ch < "0" or ch > "9":
			break
		split -= 1
	var base: String = note_with_octave.substr(0, split)
	var idx: int = NOTE_NAMES.find(base)
	if idx < 0:
		_left_note_label.text = "--"
		_right_note_label.text = "--"
		return
	_left_note_label.text = NOTE_NAMES[posmod(idx - 1, NOTE_NAMES.size())]
	_right_note_label.text = NOTE_NAMES[posmod(idx + 1, NOTE_NAMES.size())]
