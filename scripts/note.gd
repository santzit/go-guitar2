extends Node3D
## note.gd  –  behaviour for a single pooled note.
##
## Coordinate mapping (simple, no inversions)
##   X = fret × FRET_SPACING − FRET_SPACING × 0.5
##       fret 1 → X = 0.5 (left),  fret 24 → X = 23.5 (right)
##       Camera right = world +X  → low fret = screen-left, high fret = screen-right
##   Y = STRING_Y_BASE + string_index × STRING_SPACING
##       string 0 (purple) → Y = 0.20 (bottom),  string 5 (red) → Y = 2.70 (top)
##       Camera up = world +Y  → string 0 = screen-bottom, string 5 = screen-top
##   Z = STRUM_Z − (time_offset − song_time) × TRAVEL_SPEED
##       Notes spawn at Z = 0 (horizon / top of screen) and travel toward
##       Z = STRUM_Z = 20 (strum line near camera at Z = 26)

# ── String colour palette (Rocksmith 2014 convention) ────────────────────────
const STRING_COLORS: Array[Color] = [
	Color(1.00, 0.20, 0.20, 1.0),  # 0 – red     (low E)
	Color(1.00, 0.88, 0.12, 1.0),  # 1 – yellow  (A)
	Color(0.00, 0.60, 1.00, 1.0),  # 2 – cyan    (D)
	Color(1.00, 0.56, 0.05, 1.0),  # 3 – orange  (G)
	Color(0.10, 0.80, 0.00, 1.0),  # 4 – green   (B)
	Color(0.80, 0.00, 0.80, 1.0),  # 5 – purple  (high e)
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

const FRET_COUNT    : int   = 24   # total number of fret lanes on the highway
const SCALE_LENGTH  : float = 300.0  # ChartPlayer scale length used by GetFretPosition().
const SCALE_END     : float = SCALE_LENGTH - (SCALE_LENGTH / pow(2.0, float(FRET_COUNT) / 12.0))  # Fret 24 raw position.
const HIGHWAY_WIDTH : float = 24.0   # Local world-space width for normalized fret mapping.
const HIGHWAY_X_OFFSET : float = -0.5  # Keep fret 0 aligned with legacy/open-string lane origin.
const STRING_SPACING: float = 0.5
## Minimum Y above the highway surface (XZ plane at Y=0).
## Must match highway.gd STRING_Y_BASE so notes sit on their string lines.
const STRING_Y_BASE : float = 0.20
## Notes spawn at the horizon (Z=0, far from camera) and travel toward the strum line.
const START_Z       : float = 0.0
const STRUM_Z       : float = 20.0
const TRAVEL_SPEED  : float = 2.0   # units per second – must match music_play.gd
const MISS_HOLD_SECS: float = 1.0
const MISS_LABEL_Z  : float = 0.30

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0

@onready var _mesh       : MeshInstance3D = $NoteMesh
@onready var _fret_label : Node3D         = $FretLabel
@onready var _miss_label : Label3D        = $MissLabel


func _ready() -> void:
	# Give each instance its own copy of the ShaderMaterial so colours are independent.
	if _mesh:
		var mat := _mesh.get_surface_override_material(0)
		if mat:
			_mesh.set_surface_override_material(0, mat.duplicate())
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

	position = Vector3(_fret_world_x(fret), STRING_Y_BASE + string_index * STRING_SPACING, START_Z)
	_miss_label.visible = false

	# Apply string colour to the per-instance material.
	if _mesh:
		var mat := _mesh.get_surface_override_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("note_color", STRING_COLORS[string_index])

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
##   p_song_time=0.0   → Z=20-(10-0)*2  =  0.0 = START_Z (note at horizon, far from camera)
##   p_song_time=10.0  → Z=20-(10-10)*2 = 20.0 = STRUM_Z (note at strum line, hit time)
func tick(p_song_time: float) -> void:
	if not is_active:
		return

	# Compute Z directly from audio time.
	# Notes travel from Z=0 (horizon) toward Z=STRUM_Z=20 (strum line near camera).
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


## Convert a fret index into world X using the ChartPlayer `GetFretPosition()` curve.
## Parameter `f` is the fret number (0..24). Return value is local highway X.
func _fret_world_x(f: int) -> float:
	var fretf := clampf(float(f), 0.0, float(FRET_COUNT))
	var raw := SCALE_LENGTH - (SCALE_LENGTH / pow(2.0, fretf / 12.0))
	return (raw / SCALE_END) * HIGHWAY_WIDTH + HIGHWAY_X_OFFSET
