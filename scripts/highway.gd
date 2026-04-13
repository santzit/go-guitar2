extends Node3D
## highway.gd  –  runtime configuration for the Highway surface.
## The visual geometry and material are defined in highway.tscn / highway.gdshader.

# ── String visual constants (must match note.gd) ────────────────────────────
const STRING_Y_BASE   : float = 0.20
const STRING_SPACING  : float = 0.50
const STRING_COLORS: Array[Color] = [
	Color(1.00, 0.20, 0.20, 1.0),  # 0 – red     (low E)
	Color(1.00, 0.88, 0.12, 1.0),  # 1 – yellow  (A)
	Color(0.00, 0.60, 1.00, 1.0),  # 2 – cyan    (D)
	Color(1.00, 0.56, 0.05, 1.0),  # 3 – orange  (G)
	Color(0.10, 0.80, 0.00, 1.0),  # 4 – green   (B)
	Color(0.80, 0.00, 0.80, 1.0),  # 5 – purple  (high e)
]

@onready var _surface: MeshInstance3D = $HighwaySurface


func _ready() -> void:
	_create_string_lines()


## Build six thin glowing line meshes – one per string – at the correct heights.
func _create_string_lines() -> void:
	for i in STRING_COLORS.size():
		var box := BoxMesh.new()
		box.size = Vector3(24.0, 0.012, 20.0)

		var mat := StandardMaterial3D.new()
		var c: Color = STRING_COLORS[i]
		mat.albedo_color           = Color(c.r, c.g, c.b, 0.75)
		mat.emission_enabled       = true
		mat.emission               = c
		mat.emission_energy_multiplier = 2.5
		mat.transparency           = BaseMaterial3D.TRANSPARENCY_ALPHA

		var mi := MeshInstance3D.new()
		mi.name = "StringLine%d" % i
		mi.mesh = box
		mi.set_surface_override_material(0, mat)
		mi.transform.origin = Vector3(12.0, STRING_Y_BASE + i * STRING_SPACING, 10.0)
		mi.visible = true
		add_child(mi)


## Reconfigure fret/string counts at runtime (e.g. for different tunings).
func configure(fret_count: int, string_count: int) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fret_count",   fret_count)
		mat.set_shader_parameter("string_count", string_count)
