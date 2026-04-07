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

@onready var _mesh: MeshInstance3D = $NoteMesh


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
