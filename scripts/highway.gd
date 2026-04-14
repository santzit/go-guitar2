extends Node3D
## highway.gd  –  runtime configuration for the Highway surface.
## The visual geometry and material are defined in highway.tscn / highway.gdshader.
## Also creates 3D fret markers (nut and fret wires) using BoxMesh.

const LANE_COUNT : int = 6
const FRET_COUNT : int = 24
const STRING_COUNT : int = 6

@onready var _surface: MeshInstance3D = $HighwaySurface

var _fret_markers: Array[MeshInstance3D] = []
var _fret_mats: Array[StandardMaterial3D] = []
var _nut_mesh: MeshInstance3D = null
var _nut_mat: StandardMaterial3D = null

const FRET_WIRE_Z : float = 0.0
const FRET_WIRE_WIDTH : float = 0.015
const FRET_WIRE_HEIGHT : float = 5.5
const NUT_WIDTH : float = 0.04


func _ready() -> void:
	_create_fret_markers()
	set_lane_intensities(_zero_lanes())
	set_active_fret_range(0, -1)


func _create_fret_markers() -> void:
	var fret_wire_mat := StandardMaterial3D.new()
	fret_wire_mat.albedo_color = Color(0.22, 0.23, 0.27, 1.0)
	fret_wire_mat.metallic = 0.3
	fret_wire_mat.roughness = 0.4
	fret_wire_mat.emission_enabled = true
	fret_wire_mat.emission = Color(0.15, 0.15, 0.2, 1.0)
	fret_wire_mat.emission_energy_multiplier = 0.3
	
	var nut_mat := StandardMaterial3D.new()
	nut_mat.albedo_color = Color(0.15, 0.12, 0.1, 1.0)
	nut_mat.metallic = 0.2
	nut_mat.roughness = 0.6
	
	_nut_mat = nut_mat
	
	_nut_mesh = MeshInstance3D.new()
	var nut_mesh_obj := BoxMesh.new()
	nut_mesh_obj.size = Vector3(NUT_WIDTH, FRET_WIRE_HEIGHT, 0.15)
	_nut_mesh.mesh = nut_mesh_obj
	_nut_mesh.position = Vector3(ChartCommon.fret_separator_world_x(0), 0, FRET_WIRE_Z)
	_nut_mesh.set_surface_override_material(0, nut_mat)
	add_child(_nut_mesh)
	
	for fret in range(1, FRET_COUNT + 1):
		var fret_x := ChartCommon.fret_separator_world_x(fret)
		
		var marker := MeshInstance3D.new()
		var fret_mesh := BoxMesh.new()
		
		var is_inlay := (fret == 3 or fret == 5 or fret == 7 or fret == 9 or 
		                  fret == 12 or fret == 15 or fret == 17 or fret == 19 or fret == 21)
		
		if is_inlay:
			fret_mesh.size = Vector3(FRET_WIRE_WIDTH * 1.5, FRET_WIRE_HEIGHT * 0.6, 0.12)
			var inlay_mat := StandardMaterial3D.new()
			inlay_mat.albedo_color = Color(0.4, 0.4, 0.5, 1.0)
			inlay_mat.metallic = 0.2
			inlay_mat.roughness = 0.5
			inlay_mat.emission_enabled = true
			inlay_mat.emission = Color(0.3, 0.3, 0.4, 1.0)
			inlay_mat.emission_energy_multiplier = 0.5
			marker.set_surface_override_material(0, inlay_mat)
			_fret_mats.append(inlay_mat)
		else:
			fret_mesh.size = Vector3(FRET_WIRE_WIDTH, FRET_WIRE_HEIGHT, 0.12)
			marker.set_surface_override_material(0, fret_wire_mat)
			_fret_mats.append(fret_wire_mat)
		
		marker.mesh = fret_mesh
		marker.position = Vector3(fret_x, 0, FRET_WIRE_Z)
		add_child(marker)
		_fret_markers.append(marker)


func set_fret_markers_active(min_fret: int, max_fret: int) -> void:
	var active_color := Color(0.4, 0.43, 0.48, 1.0)
	var idle_color := Color(0.22, 0.23, 0.27, 1.0)
	
	if _nut_mat:
		_nut_mat.albedo_color = active_color
		_nut_mat.emission = Color(0.2, 0.2, 0.25, 1.0)
		_nut_mat.emission_energy_multiplier = 0.5
	
	for i in range(_fret_markers.size()):
		var fret := i + 1
		var marker := _fret_markers[i]
		var mat := _fret_mats[i] if i < _fret_mats.size() else null
		
		var is_active := (fret >= min_fret and fret <= max_fret)
		
		if mat:
			if is_active:
				mat.albedo_color = active_color
				mat.emission = Color(0.25, 0.28, 0.35, 1.0)
				mat.emission_energy_multiplier = 0.5
			else:
				mat.albedo_color = idle_color
				mat.emission = Color(0.1, 0.1, 0.15, 1.0)
				mat.emission_energy_multiplier = 0.2


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
		push_warning("Highway: expected %d lane intensities, got %d" % [LANE_COUNT, values.size()])
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
	
	set_fret_markers_active(min_fret, max_fret)


func _zero_lanes() -> Array[float]:
	var values: Array[float] = []
	values.resize(LANE_COUNT)
	for i in LANE_COUNT:
		values[i] = 0.0
	return values
