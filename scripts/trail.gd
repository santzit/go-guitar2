extends MeshInstance3D
class_name Trail

var _trail_mesh: BoxMesh = null
var _trail_material: ShaderMaterial = null


func _ready() -> void:
	_trail_mesh = mesh as BoxMesh
	_trail_material = get_surface_override_material(0) as ShaderMaterial
	_sync_mesh_shader_params()


func set_visual_color(color: Color) -> void:
	if _trail_material == null:
		return
	_trail_material.set_shader_parameter("base_color", color)


func set_glow_energy(value: float) -> void:
	if _trail_material == null:
		return
	_trail_material.set_shader_parameter("glow_energy", value)


func set_geometry(width: float, height: float, length: float) -> void:
	if _trail_mesh == null:
		return
	_trail_mesh.size = Vector3(maxf(width, 0.001), maxf(height, 0.001), maxf(length, 0.001))
	_sync_mesh_shader_params()


func set_width_and_length(width: float, length: float) -> void:
	if _trail_mesh == null:
		return
	_trail_mesh.size = Vector3(maxf(width, 0.001), _trail_mesh.size.y, maxf(length, 0.001))
	_sync_mesh_shader_params()


func set_local_position(local_position: Vector3) -> void:
	position = local_position


func show_trail() -> void:
	visible = true


func hide_trail() -> void:
	visible = false


func _sync_mesh_shader_params() -> void:
	if _trail_mesh == null or _trail_material == null:
		return
	_trail_material.set_shader_parameter("mesh_width", _trail_mesh.size.x)
	_trail_material.set_shader_parameter("mesh_length", _trail_mesh.size.z)
