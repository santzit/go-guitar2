extends Node3D
## note.gd  –  behaviour for a single pooled note.
##
## Coordinate mapping (ChartPlayer-like)
##   X = GetFretPosition(fret), normalized to highway width
##       GetFretPosition(f) = scale_length - scale_length / pow(2, f / 12)
##       Camera right = world +X  → low fret = screen-left, high fret = screen-right
##   Y = GetStringHeight(string_index), scaled to scene size
##       GetStringHeight(s) = 3 + s * 4
##       Camera up = world +Y  → string 0 = screen-bottom, string 5 = screen-top
##   Z = STRUM_Z − (time_offset − song_time) × TRAVEL_SPEED
##       Notes spawn at Z = 0 (horizon / top of screen) and travel toward
##       Z = STRUM_Z = -20 (strum line on the shifted highway)

# ── ChartPlayer guitar note textures (low E → high e) ────────────────────────
const STRING_TEXTURES: Array[Texture2D] = [
	preload("res://assets/textures/chartplayer/GuitarPurple.png"),
	preload("res://assets/textures/chartplayer/GuitarGreen.png"),
	preload("res://assets/textures/chartplayer/GuitarOrange.png"),
	preload("res://assets/textures/chartplayer/GuitarCyan.png"),
	preload("res://assets/textures/chartplayer/GuitarYellow.png"),
	preload("res://assets/textures/chartplayer/GuitarRed.png"),
]

# ── Digit scenes (0–9) used to display the fret number on each note ──────────
const DIGIT_SCENES: Array[PackedScene] = [
	preload("res://scenes/number_0.tscn"),
	preload("res://scenes/number_1.tscn"),
	preload("res://scenes/number_2.tscn"),
	preload("res://scenes/number_3.tscn"),
	preload("res://scenes/number_4.tscn"),
	preload("res://scenes/number_5.tscn"),
	preload("res://scenes/number_6.tscn"),
	preload("res://scenes/number_7.tscn"),
	preload("res://scenes/number_8.tscn"),
	preload("res://scenes/number_9.tscn"),
]

## Z offset places the label on the front face of the note box (faces +Z toward camera).
const LABEL_Z : float = 0.06
## X offset between tens and ones digit for two-digit fret numbers.
## Camera right = world +X  → tens (screen-left) at −X, ones (screen-right) at +X.
const DIGIT_X_OFFSET : float = 0.07

const FRET_COUNT         : int   = 24
const SCALE_LENGTH       : float = 300.0
const FRET_WORLD_WIDTH   : float = 24.0
const STRING_HEIGHT_SCALE: float = 0.125
const MIN_VALID_FRET_POS : float = 0.001
## Notes spawn at the horizon (Z=0, far from camera) and travel toward the strum line.
const START_Z       : float = 0.0
const STRUM_Z       : float = -20.0
const TRAVEL_SPEED  : float = 2.0   # units per second – must match music_play.gd
const MISS_HOLD_SECS: float = 1.0
const MISS_LABEL_Z  : float = 0.30

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0

@onready var _finger     : Sprite3D       = $FingerIndicator
@onready var _fret_label : Node3D         = $FretLabel
@onready var _miss_label : Label3D        = $MissLabel


func _ready() -> void:
	if _finger:
		_finger.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_finger.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if _miss_label:
		_miss_label.position = Vector3(0.0, 0.0, MISS_LABEL_Z)


## Called by NotePool to activate and position this note.
## p_show_label controls whether the fret number is rendered on this note.
func setup(p_fret: int, p_string: int, p_time: float, p_duration: float, p_show_label: bool = true) -> void:
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	is_active    = true
	visible      = true
	_miss_until  = -1.0

	position = Vector3(_fret_world_x(fret), _string_world_y(string_index), START_Z)
	_miss_label.visible = false

	if _finger:
		_finger.texture = STRING_TEXTURES[string_index]
		_finger.modulate = Color(1, 1, 1, 1)

	if p_show_label:
		_rebuild_fret_label()
	else:
		# Clear any label from a previous activation.
		for child in _fret_label.get_children():
			_fret_label.remove_child(child)
			child.free()


## Build digit-scene children inside FretLabel to show the fret number.
func _rebuild_fret_label() -> void:
	# Remove any digits from a previous activation.
	for child in _fret_label.get_children():
		_fret_label.remove_child(child)
		child.free()

	# Only render labels for valid frets 1–24.
	if fret < 1 or fret > 24:
		return

	var tens := fret / 10
	var ones := fret % 10

	if tens > 0:
		# Two-digit fret (10–24): camera right = world +X, so −X_OFFSET = screen left (tens),
		# +X_OFFSET = screen right (ones), giving correct left-to-right digit order.
		var d_tens := DIGIT_SCENES[tens].instantiate()
		d_tens.position = Vector3(-DIGIT_X_OFFSET, 0.0, LABEL_Z)
		_fret_label.add_child(d_tens)

		var d_ones := DIGIT_SCENES[ones].instantiate()
		d_ones.position = Vector3(DIGIT_X_OFFSET, 0.0, LABEL_Z)
		_fret_label.add_child(d_ones)
	else:
		# Single-digit fret (0–9): centred on the front face.
		var d := DIGIT_SCENES[ones].instantiate()
		d.position = Vector3(0.0, 0.0, LABEL_Z)
		_fret_label.add_child(d)


## Update this note's Z position from the authoritative audio song time.
## Called every frame by NotePool.tick() so notes are always pixel-perfectly
## synced to the audio stream rather than accumulating delta errors.
##
## Example: note with time_offset=10.0 and TRAVEL_SPEED=2.0
##   p_song_time=0.0   → Z=-20+(10-0)*2  =   0.0 = START_Z (note at horizon, far from camera)
##   p_song_time=10.0  → Z=-20+(10-10)*2 = -20.0 = STRUM_Z (note at strum line, hit time)
func tick(p_song_time: float) -> void:
	if not is_active:
		return

	# Compute Z directly from audio time.
	# Notes travel from Z=0 (horizon) toward Z=STRUM_Z=-20 (strum line on highway).
	position.z = STRUM_Z + (time_offset - p_song_time) * TRAVEL_SPEED

	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD_SECS
		_miss_label.visible = true

	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


## Deactivate and return to pool.
func deactivate() -> void:
	is_active = false
	visible   = false
	_miss_label.visible = false
	_miss_until = -1.0
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func _fret_world_x(fret_num: int) -> float:
	var max_pos: float = _chart_fret_pos(float(FRET_COUNT))
	# Safety fallback for invalid configuration (e.g. FRET_COUNT/SCALE_LENGTH set to 0).
	# This indicates a bad setup; return 0 to keep notes from exploding off-screen.
	if max_pos <= MIN_VALID_FRET_POS:
		return 0.0
	return _chart_fret_pos(float(fret_num)) / max_pos * FRET_WORLD_WIDTH


func _chart_fret_pos(fret_num: float) -> float:
	return SCALE_LENGTH - (SCALE_LENGTH / pow(2.0, fret_num / 12.0))


func _string_world_y(str_idx: int) -> float:
	return (3.0 + float(str_idx) * 4.0) * STRING_HEIGHT_SCALE
