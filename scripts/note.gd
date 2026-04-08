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

## Z offset places the label on the front face of the note box (box depth = 0.50).
const LABEL_Z : float = -0.26
## X offset between tens and ones digit for two-digit fret numbers.
const DIGIT_X_OFFSET : float = 0.11

const FRET_SPACING  : float = 1.0
const STRING_SPACING: float = 0.5
## Minimum Y above the highway surface (XZ plane at Y=0).
## Must match highway.gd STRING_Y_BASE so notes sit on their string lines.
const STRING_Y_BASE : float = 0.20
const START_Z       : float = 20.0
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = 8.0   # units per second – must match music_play.gd
const MAX_DELTA     : float = 0.05  # cap frame delta to keep notes on-screen on slow renderers

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false

@onready var _mesh       : MeshInstance3D = $NoteMesh
@onready var _fret_label : Node3D         = $FretLabel


func _ready() -> void:
	# Give each instance its own copy of the ShaderMaterial so colours are independent.
	if _mesh:
		var mat := _mesh.get_surface_override_material(0)
		if mat:
			_mesh.set_surface_override_material(0, mat.duplicate())


## Called by NotePool to activate and position this note.
func setup(p_fret: int, p_string: int, p_time: float, p_duration: float) -> void:
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	is_active    = true
	visible      = true

	position = Vector3(fret * FRET_SPACING, STRING_Y_BASE + string_index * STRING_SPACING, START_Z)

	# Apply string colour to the per-instance material.
	if _mesh:
		var mat := _mesh.get_surface_override_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("note_color", STRING_COLORS[string_index])

	_rebuild_fret_label()


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
		# Two-digit fret (10–24): place tens left, ones right on the front face.
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


func _process(delta: float) -> void:
	if not is_active:
		return

	position.z -= TRAVEL_SPEED * minf(delta, MAX_DELTA)

	# Return to pool once it has passed the strum line.
	if position.z < STRUM_Z - 2.0:
		deactivate()


## Deactivate and return to pool.
func deactivate() -> void:
	is_active = false
	visible   = false
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)
