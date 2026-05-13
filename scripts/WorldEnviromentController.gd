extends WorldEnvironment
class_name WorldEnviromentController


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
