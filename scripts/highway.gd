extends Node3D
## highway.gd  –  runtime configuration for the Highway surface.
## The visual geometry and material are defined in highway.tscn / highway.gdshader.

@onready var _surface: MeshInstance3D = $HighwaySurface


## Reconfigure fret/string counts at runtime (e.g. for different tunings).
func configure(fret_count: int, string_count: int) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fret_count",   fret_count)
		mat.set_shader_parameter("string_count", string_count)
