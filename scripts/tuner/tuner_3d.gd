## Tuner3D — 3D scene root for the live tuner.
##
## The tuner indicator is a TU300-style LED bar built from small 3D meshes
## that light up left/center/right for pitch guidance.
## The fretboard is the real scenes/fretboard.tscn (MeshInstance3D cylinders with
## string_glow.gdshader) instanced directly in the 3D world.
## Text labels (note name, Hz, guidance, etc.) stay in a CanvasLayer overlay.
extends Node3D

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
const CAMERA_POSITION: Vector3 = Vector3(0.0, 7.5, 42.0)
const CAMERA_LOOK_AT: Vector3 = Vector3(0.0, -2.0, -8.0)
const CAMERA_FOV_DEGREES: float = 32.0
const FRETBOARD_RIG_POSITION: Vector3 = Vector3(0.0, -8.8, -12.0)
const FRETBOARD_RIG_ROTATION: Vector3 = Vector3(0.0, -45.0, -15.0)
const FRETBOARD_OFFSET: Vector3 = Vector3(-24.0, -1.5, 0.0)
const INDICATOR_RIG_POSITION: Vector3 = Vector3(0.0, 9.2, -6.5)
const INDICATOR_RIG_ROTATION: Vector3 = Vector3(-10.0, 0.0, 0.0)
const INDICATOR_LABEL_OFFSET: Vector3 = Vector3(0.0, -0.82, 0.35)

const INDICATOR_SEGMENT_COUNT: int = 13
const INDICATOR_SEGMENT_SIZE: Vector3 = Vector3(0.7, 0.18, 0.24)
const INDICATOR_SEGMENT_GAP: float = 0.16
const INDICATOR_BASE_PADDING: Vector3 = Vector3(1.2, 0.22, 0.8)
const INDICATOR_MIN_CENTS: float = -50.0
const INDICATOR_MAX_CENTS: float = 50.0

const INDICATOR_BASE_COLOR: Color = Color(0.07, 0.09, 0.13)
const INDICATOR_DIM_COLOR: Color = Color(0.08, 0.12, 0.16)
const INDICATOR_LOW_COLOR: Color = Color(0.45, 0.75, 1.0)
const INDICATOR_CENTER_COLOR: Color = Color(0.4, 1.0, 0.5)
const INDICATOR_HIGH_COLOR: Color = Color(1.0, 0.55, 0.35)
const INDICATOR_DIM_EMISSION: float = 0.25
const INDICATOR_ACTIVE_EMISSION: float = 1.6
const INDICATOR_PEAK_EMISSION: float = 2.4
const INDICATOR_LABEL_TEXT: String = "← too low | center | too high →"

const NOTE_NAMES: PackedStringArray = [
	"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
]

# ── 3D scene nodes ─────────────────────────────────────────────────────────────
@onready var _fretboard_rig: Node3D          = $FretboardRig
@onready var _fretboard_3d                   = $FretboardRig/Fretboard
@onready var _indicator_rig: Node3D          = $IndicatorRig
@onready var _indicator_segments_root: Node3D = $IndicatorRig/IndicatorSegments
@onready var _indicator_label: Label3D       = $IndicatorRig/IndicatorLabel

# ── CanvasLayer text nodes ─────────────────────────────────────────────────────
@onready var _tuning_name_label: Label     = $UIOverlay/MarginContainer/VBoxRoot/TopMeta/TuningNameLabel
@onready var _target_notes_label: Label    = $UIOverlay/MarginContainer/VBoxRoot/TopMeta/TargetNotesLabel
@onready var _selected_string_label: Label = $UIOverlay/MarginContainer/VBoxRoot/TopMeta/SelectedStringLabel
@onready var _detected_note_label: Label   = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/NoteCircle/DetectedNoteLabel
@onready var _frequency_label: Label       = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/NoteCircle/DetectedFrequencyLabel
@onready var _cents_label: Label           = $UIOverlay/MarginContainer/VBoxRoot/BottomControls/BottomRow/CentsChip/CentsLabel
@onready var _guidance_label: Label        = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/GuidanceLabel
@onready var _left_note_label: Label       = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/LeftNoteLabel
@onready var _right_note_label: Label      = $UIOverlay/MarginContainer/VBoxRoot/MainArea/CenterStack/NoteRow/RightNoteLabel

# ── Pitch detection state ──────────────────────────────────────────────────────
var _pitch_detector      = null
var _input_audio_manager = null
var _target_notes: Array[String] = []
var _target_freqs: Array[float]  = []
var _camera: Camera3D = null

var _smoothed_freq_hz: float = 0.0
var _smoothed_cents:   float = 0.0
var _has_detection:    bool  = false
var _last_detection_ms: int  = 0

var _indicator_segments: Array[MeshInstance3D] = []
var _indicator_materials: Array[StandardMaterial3D] = []
var _indicator_center_idx: int = 0


func _ready() -> void:
	# Build 3D atmosphere (Camera, WorldEnvironment, light) and the LED indicator.
	_build_3d_environment()
	_build_indicator_meshes()
	_apply_3d_layout()

	_target_notes = _GameStateScript.selected_tuning_notes.duplicate()
	_input_audio_manager = get_node_or_null("/root/InputAudioManager")
	if _target_notes.size() != 6:
		_target_notes = DEFAULT_TUNING_NOTES.duplicate()
	_GameStateScript.selected_tuning_notes = _target_notes.duplicate()
	if _GameStateScript.selected_tuning_name.is_empty():
		_GameStateScript.selected_tuning_name = DEFAULT_TUNING_NAME

	_tuning_name_label.text  = "Preset: %s" % _GameStateScript.selected_tuning_name
	_target_notes_label.text = "Target notes: %s" % " ".join(PackedStringArray(_target_notes))
	_selected_string_label.text = "Selected string: Auto (closest target note)"
	_target_freqs = _build_target_freqs(_target_notes)

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
	# Dark atmospheric background so rainbow strings glow clearly
	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode  = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.05, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color  = Color(0.10, 0.10, 0.18)
	environment.ambient_light_energy = 1.0
	# HDR glow makes the lit string cylinders bloom against the dark bg
	environment.glow_enabled       = true
	environment.glow_normalized    = false
	environment.glow_intensity     = 1.2
	environment.glow_bloom         = 0.20
	environment.glow_hdr_threshold = 0.60
	env_node.environment = environment
	add_child(env_node)

	# Perspective framing keeps the full-scale fretboard readable after the
	# requested rotation and preserves depth between the indicator bar and strings.
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = CAMERA_FOV_DEGREES
	add_child(_camera)
	_camera.position = CAMERA_POSITION
	_camera.look_at(CAMERA_LOOK_AT, Vector3.UP)

	# Soft key light
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	key_light.light_color      = Color(1.0, 0.96, 0.88)
	key_light.light_energy     = 0.7
	add_child(key_light)

func _build_indicator_meshes() -> void:
	if _indicator_segments_root == null:
		return
	for child in _indicator_segments_root.get_children():
		child.queue_free()
	_indicator_segments.clear()
	_indicator_materials.clear()

	_indicator_center_idx = int(floor(float(INDICATOR_SEGMENT_COUNT) * 0.5))
	var segment_mesh := BoxMesh.new()
	segment_mesh.size = INDICATOR_SEGMENT_SIZE
	var total_width: float = INDICATOR_SEGMENT_SIZE.x * float(INDICATOR_SEGMENT_COUNT) \
			+ INDICATOR_SEGMENT_GAP * float(INDICATOR_SEGMENT_COUNT - 1)

	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(
		total_width + INDICATOR_BASE_PADDING.x,
		INDICATOR_SEGMENT_SIZE.y + INDICATOR_BASE_PADDING.y,
		INDICATOR_SEGMENT_SIZE.z + INDICATOR_BASE_PADDING.z
	)
	var base := MeshInstance3D.new()
	base.mesh = base_mesh
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = INDICATOR_BASE_COLOR
	base_mat.roughness = 0.42
	base_mat.metallic = 0.1
	base.material_override = base_mat
	base.position = Vector3(0.0, -INDICATOR_BASE_PADDING.y * 0.35, 0.0)
	_indicator_segments_root.add_child(base)

	var left_edge: float = -total_width * 0.5 + INDICATOR_SEGMENT_SIZE.x * 0.5
	for i in range(INDICATOR_SEGMENT_COUNT):
		var segment := MeshInstance3D.new()
		segment.mesh = segment_mesh
		segment.position = Vector3(
			left_edge + float(i) * (INDICATOR_SEGMENT_SIZE.x + INDICATOR_SEGMENT_GAP),
			0.0,
			0.0
		)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		_set_indicator_material(mat, INDICATOR_DIM_COLOR, INDICATOR_DIM_EMISSION)
		segment.material_override = mat
		_indicator_segments_root.add_child(segment)
		_indicator_segments.append(segment)
		_indicator_materials.append(mat)

	if _indicator_label != null:
		_indicator_label.text = INDICATOR_LABEL_TEXT
		_indicator_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_indicator_label.pixel_size = 0.007
		_indicator_label.font_size = 24
		_indicator_label.modulate = Color(0.85, 0.88, 0.92, 1.0)
		_indicator_label.outline_size = 6
		_indicator_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)

func _apply_3d_layout() -> void:
	if _fretboard_rig == null or _fretboard_3d == null or _indicator_rig == null:
		return

	# Center the real fretboard scene on the rig before applying the requested
	# angled presentation, so the 48-unit neck rotates around its midpoint.
	_fretboard_rig.position = FRETBOARD_RIG_POSITION
	_fretboard_rig.rotation_degrees = FRETBOARD_RIG_ROTATION
	_fretboard_3d.position = FRETBOARD_OFFSET

	_indicator_rig.position = INDICATOR_RIG_POSITION
	_indicator_rig.rotation_degrees = INDICATOR_RIG_ROTATION
	if _indicator_label != null:
		_indicator_label.position = INDICATOR_LABEL_OFFSET


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

	var target_idx: int = _find_closest_target_string(freq_hz)
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
	SceneManager.goto_tuning_list()


# ── UI updates ────────────────────────────────────────────────────────────────

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
	_set_indicator_state(_smoothed_cents, true, is_in_tune)
	_update_side_note_labels(note_name)

	# Clear all string glows, then light the active string
	for i in _target_freqs.size():
		_fretboard_3d.set_string_glow(i, 0.0)
	# Full brightness when in tune; slightly dimmer otherwise so the colour
	# gradient of the shader is still easy to distinguish
	var glow: float = 1.0 if is_in_tune else 0.72
	_fretboard_3d.set_string_glow(target_idx, glow)

	if is_in_tune:
		_guidance_label.text     = "IN TUNE ✓"
		_guidance_label.modulate = Color(0.4, 1.0, 0.5)
	elif _smoothed_cents < 0.0:
		_guidance_label.text     = "FLAT — tune up"
		_guidance_label.modulate = Color(1.0, 0.8, 0.4)
	else:
		_guidance_label.text     = "SHARP — tune down"
		_guidance_label.modulate = Color(1.0, 0.7, 0.4)


func _set_waiting_ui() -> void:
	_has_detection            = false
	_detected_note_label.text = "--"
	_frequency_label.text     = "-- Hz"
	_cents_label.text         = "Offset: -- cents"
	_left_note_label.text     = "--"
	_right_note_label.text    = "--"
	_guidance_label.text      = "Waiting for signal..."
	_guidance_label.modulate  = Color(1.0, 1.0, 1.0)
	_set_indicator_state(0.0, false, false)
	# Extinguish all strings while waiting for audio
	for i in _target_freqs.size():
		_fretboard_3d.set_string_glow(i, 0.0)


func _set_indicator_state(cents: float, has_signal: bool, is_in_tune: bool) -> void:
	if _indicator_materials.is_empty():
		return
	for mat in _indicator_materials:
		_set_indicator_material(mat, INDICATOR_DIM_COLOR, INDICATOR_DIM_EMISSION)

	if not has_signal:
		return

	var center_idx: int = _indicator_center_idx
	var clamped: float = clampf(cents, INDICATOR_MIN_CENTS, INDICATOR_MAX_CENTS)
	if is_in_tune:
		_set_indicator_material(_indicator_materials[center_idx], INDICATOR_CENTER_COLOR, INDICATOR_PEAK_EMISSION)
		return

	var t: float = (clamped - INDICATOR_MIN_CENTS) / (INDICATOR_MAX_CENTS - INDICATOR_MIN_CENTS)
	var target_idx: int = int(round(t * float(INDICATOR_SEGMENT_COUNT - 1)))
	var color: Color = INDICATOR_LOW_COLOR if clamped < 0.0 else INDICATOR_HIGH_COLOR
	var step: int = 1 if target_idx >= center_idx else -1
	var distance: int = max(1, abs(target_idx - center_idx))
	var i: int = center_idx
	var step_idx: int = 0
	while true:
		var intensity: float = lerpf(INDICATOR_ACTIVE_EMISSION, INDICATOR_PEAK_EMISSION, float(step_idx) / float(distance))
		_set_indicator_material(_indicator_materials[i], color, intensity)
		if i == target_idx:
			break
		i += step
		step_idx += 1


func _set_indicator_material(mat: StandardMaterial3D, color: Color, emission: float) -> void:
	mat.albedo_color = color
	mat.emission = color
	mat.emission_energy_multiplier = emission


# ── Pitch math helpers ────────────────────────────────────────────────────────

func _build_target_freqs(notes: Array[String]) -> Array[float]:
	var out: Array[float] = []
	for n in notes:
		out.append(_note_to_freq(String(n)))
	return out


func _find_closest_target_string(freq_hz: float) -> int:
	if _target_freqs.is_empty():
		return -1
	var best_idx: int         = 0
	var best_abs_cents: float = INF
	for i in range(_target_freqs.size()):
		var cents: float = absf(_freq_to_cents(freq_hz, _target_freqs[i]))
		if cents < best_abs_cents:
			best_abs_cents = cents
			best_idx       = i
	return best_idx


func _freq_to_cents(freq_hz: float, reference_hz: float) -> float:
	if freq_hz <= 0.0 or reference_hz <= 0.0:
		return 0.0
	return 1200.0 * (log(freq_hz / reference_hz) / log(2.0))


func _freq_to_note_name(freq_hz: float) -> String:
	if freq_hz <= 0.0:
		return "--"
	var midi: int         = int(round(A4_MIDI_NOTE + SEMITONES_PER_OCTAVE * (log(freq_hz / A4_FREQUENCY_HZ) / log(2.0))))
	var note_name: String = NOTE_NAMES[posmod(midi, 12)]
	var octave: int       = int(floor(float(midi) / 12.0)) - 1
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
