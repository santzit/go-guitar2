extends Node3D
## note.gd  –  behaviour for a single pooled note.
##
## Coordinate mapping
##   X = fret number  × FRET_SPACING
##   Y = STRING_Y_BASE + string index × STRING_SPACING
##   Z = time axis; note spawns at START_Z and travels toward STRUM_Z

# ── String colour palette ────────────────────────────────────────────────────
const STRING_COLORS: Array[Color] = [
	Color(0.70, 0.10, 0.95, 1.0),  # 0 – purple
	Color(0.10, 0.80, 0.20, 1.0),  # 1 – green
	Color(0.90, 0.50, 0.05, 1.0),  # 2 – orange
	Color(0.10, 0.50, 0.95, 1.0),  # 3 – blue
	Color(0.85, 0.85, 0.05, 1.0),  # 4 – yellow
	Color(0.85, 0.15, 0.15, 1.0),  # 5 – red
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

## Z offset places the label on the front face of the note box (box depth = 0.10).
const LABEL_Z : float = -0.06
## X offset between tens and ones digit for two-digit fret numbers.
const DIGIT_X_OFFSET : float = 0.07

const FRET_COUNT    : int   = 24   # total number of fret lanes on the highway
const FRET_SPACING  : float = 1.0
const STRING_SPACING: float = 0.5
## Minimum Y above the highway surface (XZ plane at Y=0).
## Must match highway.gd STRING_Y_BASE so notes sit on their string lines.
const STRING_Y_BASE : float = 0.20
const START_Z       : float = 20.0
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = 8.0   # units per second – must match music_play.gd
const MISS_HOLD_SECS: float = 1.0
const MISS_LABEL_Z  : float = -0.30

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

	position = Vector3((FRET_COUNT - fret) * FRET_SPACING + FRET_SPACING * 0.5, STRING_Y_BASE + string_index * STRING_SPACING, START_Z)
	_miss_label.visible = false
	_miss_label.position = Vector3(0.0, 0.0, MISS_LABEL_Z)

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
		# Two-digit fret (10–24): camera right = world -X, so +X_OFFSET = screen left (tens),
		# -X_OFFSET = screen right (ones), giving correct left-to-right digit order.
		var d_tens := DIGIT_SCENES[tens].instantiate()
		d_tens.position = Vector3(DIGIT_X_OFFSET, 0.0, LABEL_Z)
		_fret_label.add_child(d_tens)

		var d_ones := DIGIT_SCENES[ones].instantiate()
		d_ones.position = Vector3(-DIGIT_X_OFFSET, 0.0, LABEL_Z)
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
## Example: note with time_offset=10.0 and TRAVEL_SPEED=8.0
##   p_song_time=7.5  → Z=(10-7.5)*8 = 20.0 = START_Z  (just spawned)
##   p_song_time=10.0 → Z=(10-10)*8  =  0.0 = STRUM_Z  (hit time)
func tick(p_song_time: float) -> void:
	if not is_active:
		return

	# Compute Z directly from audio time.
	position.z = (time_offset - p_song_time) * TRAVEL_SPEED

	if _miss_until < 0.0 and position.z <= STRUM_Z:
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
