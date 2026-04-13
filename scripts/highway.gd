extends Node3D
## highway.gd  –  runtime configuration for the Highway surface.
## The visual geometry and material are defined in highway.tscn / highway.gdshader.

const LANE_COUNT : int = 6

@onready var _surface: MeshInstance3D = $HighwaySurface


func _ready() -> void:
	set_lane_intensities([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	set_active_fret_range(0, -1)


## Reconfigure fret/string counts at runtime (e.g. for different tunings).
func configure(fret_count: int, string_count: int) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fret_count",   fret_count)
		mat.set_shader_parameter("string_count", string_count)


func set_lane_intensities(values: Array[float]) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if not mat:
		return
	if values.size() < LANE_COUNT:
		return
	mat.set_shader_parameter("lane_intensity_0_3", Vector4(
		clampf(values[0], 0.0, 1.0),
		clampf(values[1], 0.0, 1.0),
		clampf(values[2], 0.0, 1.0),
		clampf(values[3], 0.0, 1.0)
	))
	mat.set_shader_parameter("lane_intensity_4_5", Vector2(
		clampf(values[4], 0.0, 1.0),
		clampf(values[5], 0.0, 1.0)
	))


func set_active_fret_range(min_fret: int, max_fret: int) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if not mat:
		return
	mat.set_shader_parameter("active_fret_min", min_fret)
	mat.set_shader_parameter("active_fret_max", max_fret)
