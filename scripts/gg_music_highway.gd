extends Node3D

const LANE_COUNT : int = 6
const BASE_INTENSITY : float = 0.18
const PULSE_SCALE : float = 1.35

@onready var _highway_surface : MeshInstance3D = $HighwaySurface

var _mat : ShaderMaterial = null


func _ready() -> void:
	if is_instance_valid(_highway_surface):
		_mat = _highway_surface.get_surface_override_material(0) as ShaderMaterial
	for lane in LANE_COUNT:
		set_lane_intensity(lane, 0.0)


func set_lane_intensity(lane: int, intensity: float) -> void:
	if _mat == null:
		return
	var idx := clampi(lane, 0, LANE_COUNT - 1)
	var v := clampf(BASE_INTENSITY + intensity * PULSE_SCALE, 0.0, 2.0)
	_mat.set_shader_parameter("lane_intensity_%d" % idx, v)
