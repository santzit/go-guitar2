extends Node3D
## note.gd  –  behaviour for a single pooled note.
##
## Coordinate mapping (ChartPlayer-like)
##   X = GetFretPosition(fret), normalized to highway width
##       GetFretPosition(f) = scale_length - scale_length / pow(2, f / 12)
##       Camera right = world +X  → low fret = screen-left, high fret = screen-right
##   Y = GetStringHeight(string_index), scaled to scene size
##       GetStringHeight(s) = 3 + (5 - s) * 4
##       String 0 (low E) = screen-top, string 5 (high e) = screen-bottom
##   Z = STRUM_Z − (time_offset − song_time) × TRAVEL_SPEED
##       Notes spawn at Z = -20 and travel toward Z = 0.

# ── ChartPlayer guitar note textures (string 0 top → string 5 bottom) ────────
# Order: Red, Yellow, Cyan(Blue), Orange, Green, Purple
const STRING_TEXTURES: Array[Texture2D] = [
	preload("res://assets/textures/chartplayer/GuitarRed.png"),
	preload("res://assets/textures/chartplayer/GuitarYellow.png"),
	preload("res://assets/textures/chartplayer/GuitarCyan.png"),
	preload("res://assets/textures/chartplayer/GuitarOrange.png"),
	preload("res://assets/textures/chartplayer/GuitarGreen.png"),
	preload("res://assets/textures/chartplayer/GuitarPurple.png"),
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
## Height of one string slot in world units (= 4 × STRING_HEIGHT_SCALE).
const STRING_SLOT_HEIGHT : float = 4.0 * STRING_HEIGHT_SCALE  # 0.5
const MIN_VALID_FRET_POS : float = 0.001
## Notes spawn at Z=-20 and travel toward Z=0.
const START_Z       : float = -20.0
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = 2.0   # units per second – must match music_play.gd
const MISS_HOLD_SECS: float = 1.0
const MISS_LABEL_Z  : float = 0.30

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0
## Track the last fret this note was sized for so we skip the expensive PlaneMesh
## resize on pool reuse when the fret hasn't changed.
var _last_sized_fret: int = -1

@onready var _finger     : MeshInstance3D = $FingerIndicator
@onready var _fret_label : Node3D         = $FretLabel
@onready var _miss_label : Label3D        = $MissLabel


func _ready() -> void:
	# ── Finger indicator: StandardMaterial3D with alpha transparency + billboard ──
	# Using TRANSPARENCY_ALPHA so the circular guitar textures render without a
	# rectangular opaque background, and BILLBOARD_ENABLED so the plane always faces
	# the camera.  Each note instance owns its own material so pool reuse never bleeds
	# albedo_texture state across notes.
	if _finger:
		var mat := StandardMaterial3D.new()
		mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.no_depth_test  = true
		_finger.set_surface_override_material(0, mat)
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
		var mat := _finger.get_surface_override_material(0) as StandardMaterial3D
		# Resize the PlaneMesh only when the fret changes (first use or different fret).
		# Skipping the resize on pool reuse for the same fret avoids redundant mesh mutations.
		if fret != _last_sized_fret:
			_last_sized_fret = fret
			var sz  := _fret_indicator_size(fret)
			var plane := _finger.mesh as PlaneMesh
			if plane:
				plane.size = sz
		if mat:
			mat.albedo_texture = STRING_TEXTURES[string_index]

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
##   p_song_time=0.0   → Z=0-(10-0)*2    = -20.0 = START_Z
##   p_song_time=10.0  → Z=0-(10-10)*2   = 0.0 = STRUM_Z
func tick(p_song_time: float) -> void:
	if not is_active:
		return

	# Compute Z directly from audio time.
	# Notes travel from Z=-20 toward Z=STRUM_Z=0.
	position.z = STRUM_Z - (time_offset - p_song_time) * TRAVEL_SPEED

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
	# Centre the note in the middle of its fret slot.
	var curr := _chart_fret_pos(float(fret_num))
	var nxt  := _chart_fret_pos(float(fret_num) + 1.0)
	return (curr + nxt) * 0.5 / max_pos * FRET_WORLD_WIDTH


## Returns the world-unit size (X = fret spacing, Y = 80 % of string slot) for a note
## at the given fret using the ChartPlayer fret-spacing formula.
func _fret_indicator_size(fret_num: int) -> Vector2:
	var max_pos := _chart_fret_pos(float(FRET_COUNT))
	if max_pos <= MIN_VALID_FRET_POS:
		return Vector2(0.116, 0.06)
	var curr := _chart_fret_pos(float(fret_num))
	var nxt  := _chart_fret_pos(float(fret_num) + 1.0)
	var w    := (nxt - curr) / max_pos * FRET_WORLD_WIDTH
	var h    := STRING_SLOT_HEIGHT * 0.8
	return Vector2(w, h)


func _chart_fret_pos(fret_num: float) -> float:
	return SCALE_LENGTH - (SCALE_LENGTH / pow(2.0, fret_num / 12.0))


func _string_world_y(str_idx: int) -> float:
	return (3.0 + float(5 - str_idx) * 4.0) * STRING_HEIGHT_SCALE
