extends WorldEnvironment
class_name WorldEnviromentController


const SUN_LIGHT_NAME := "DirectionalLight3D"


func _ready() -> void:
	if environment == null:
		environment = Environment.new()

	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.glow_enabled = true
	environment.glow_intensity = 1.5
	environment.glow_bloom = 0.55
	environment.glow_hdr_threshold = 0.4

	_ensure_directional_light()


func _ensure_directional_light() -> void:
	var sun := get_node_or_null(SUN_LIGHT_NAME) as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = SUN_LIGHT_NAME
		add_child(sun)

	sun.transform = Transform3D(
		Basis(
			Vector3(0.866025, -0.433013, 0.25),
			Vector3(0.0, 0.5, 0.866025),
			Vector3(-0.5, -0.75, 0.433013)
		),
		Vector3(0.0, 8.0, 0.0)
	)
	sun.light_color = Color(0.9, 0.85, 1.0, 1.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
