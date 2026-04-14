extends Node3D
## fretboard.gd  –  Drives per-string glow intensity via shader parameters,
## builds vertical fret-line markers at ChartPlayer fret positions, and
## places fret-number labels (1–24) below the lowest (purple) string.
##
## Each string (String0 … String5) must have a ShaderMaterial that uses
## shaders/string_glow.gdshader, which exposes the `glow_intensity` uniform.
## Call set_string_glow() each frame from music_play.gd to light up the
## strings that have notes arriving within the glow window.

const STRING_COUNT : int = 6

## Width of each fret-line quad in world units.
## Slightly wider than the highway shader lines to be clearly visible.
const FRET_LINE_WIDTH  : float = 0.035
## Y span of the fretboard: just above string 0 (Y≈2.75) to just below string 5 (Y≈0.15).
const FRET_LINE_HEIGHT : float = 2.6
## Y centre of the string span  = (2.7 + 0.2) / 2.
const FRET_LINE_Y      : float = 1.45
## Z offset so fret lines sit just in front of the string cylinders (Z=0).
const FRET_LINE_Z      : float = 0.03

## Y position of string 5 (purple / high-e) in world units.
const STRING5_Y        : float = 0.2
## How far below string 5 the fret number labels are placed.
const FRET_NUM_Y_OFFSET: float = 0.22
## Pixel size for the fret-number Label3D nodes (world units per pixel).
const FRET_NUM_PIXEL_SIZE: float = 0.005
## Additional Z offset so fret-number labels sit in front of fret lines.
const FRET_NUM_Z_OFFSET: float = 0.04

## Cache of ShaderMaterial per string (index 0–5).
var _string_mats : Array = []


func _ready() -> void:
	for i in STRING_COUNT:
		var mi := get_node_or_null("String%d" % i) as MeshInstance3D
		if mi:
			var mat := mi.get_surface_override_material(0) as ShaderMaterial
			_string_mats.append(mat)
		else:
			push_warning("Fretboard: String%d node not found." % i)
			_string_mats.append(null)
	_build_fret_lines()
	_build_fret_numbers()


## Set the glow intensity (0.0–1.0) for a single string.
## 0.0 = resting (always colored), 1.0 = full bright peak (note imminent).
func set_string_glow(string_idx: int, intensity: float) -> void:
	if string_idx < 0 or string_idx >= _string_mats.size():
		return
	var mat : ShaderMaterial = _string_mats[string_idx]
	if mat:
		mat.set_shader_parameter("glow_intensity", clampf(intensity, 0.0, 1.0))


## Instantiate a thin PlaneMesh quad at each ChartPlayer fret separator X position.
## Uses a bright white emissive material so lines are clearly visible on the fretboard.
func _build_fret_lines() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color          = Color(0.9, 0.9, 1.0, 1.0)
	mat.transparency          = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode          = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode             = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled      = true
	mat.emission              = Color(0.9, 0.9, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.8

	# Fret lines for separators 1 … FRET_COUNT (omitting 0 which is the nut/edge).
	for i in range(1, ChartCommon.FRET_COUNT + 1):
		var x := ChartCommon.fret_separator_world_x(i)
		var plane := PlaneMesh.new()
		plane.size        = Vector2(FRET_LINE_WIDTH, FRET_LINE_HEIGHT)
		plane.orientation = PlaneMesh.FACE_Z
		var mi := MeshInstance3D.new()
		mi.name     = "FretLine%d" % i
		mi.mesh     = plane
		mi.set_surface_override_material(0, mat)
		mi.position = Vector3(x, FRET_LINE_Y, FRET_LINE_Z)
		add_child(mi)


## Place a Label3D with the fret number (1–24) below the purple string,
## centred horizontally in each fret slot using ChartPlayer fret-mid positions.
func _build_fret_numbers() -> void:
	var font := load("res://assets/fonts/Inter_18pt-Bold.ttf") as FontFile
	var label_y := STRING5_Y - FRET_NUM_Y_OFFSET

	for fret in range(1, ChartCommon.FRET_COUNT + 1):
		var x := ChartCommon.fret_mid_world_x(fret)
		var lbl := Label3D.new()
		lbl.name             = "FretNum%d" % fret
		lbl.text             = str(fret)
		lbl.pixel_size       = FRET_NUM_PIXEL_SIZE
		lbl.font_size        = 20
		lbl.outline_size     = 4
		lbl.no_depth_test    = true
		lbl.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.double_sided     = true
		lbl.modulate         = Color(1.0, 1.0, 1.0, 1.0)
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		if font:
			lbl.font = font
		lbl.position = Vector3(x, label_y, FRET_NUM_Z_OFFSET)
		add_child(lbl)
