extends Node3D
## fretboard.gd  –  Drives per-string glow intensity via shader parameters,
## and builds vertical fret-line markers at ChartPlayer fret positions.
##
## Each string (String0 … String5) must have a ShaderMaterial that uses
## shaders/string_glow.gdshader, which exposes the `glow_intensity` uniform.
## Call set_string_glow() each frame from music_play.gd to light up the
## strings that have notes arriving within the glow window.

const STRING_COUNT : int = 6

## VerticalFretLine texture (same source used by the highway shader).
const _FRET_LINE_TEX := preload("res://assets/textures/chartplayer/VerticalFretLine.png")

## Width of each fret-line quad in world units.
const FRET_LINE_WIDTH  : float = 0.015
## Y span of the fretboard: just above string 0 (Y≈2.75) to just below string 5 (Y≈0.15).
const FRET_LINE_HEIGHT : float = 2.6
## Y centre of the string span  = (2.7 + 0.2) / 2.
const FRET_LINE_Y      : float = 1.45
## Z offset so fret lines sit just in front of the string cylinders (Z=0).
const FRET_LINE_Z      : float = 0.02

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


## Set the glow intensity (0.0–1.0) for a single string.
## 0.0 = fully dark (no note approaching), 1.0 = full bright peak (note imminent).
func set_string_glow(string_idx: int, intensity: float) -> void:
	if string_idx < 0 or string_idx >= _string_mats.size():
		return
	var mat : ShaderMaterial = _string_mats[string_idx]
	if mat:
		mat.set_shader_parameter("glow_intensity", clampf(intensity, 0.0, 1.0))


## Instantiate a thin PlaneMesh quad at each ChartPlayer fret separator X position
## using the VerticalFretLine.png texture, matching the highway shader fret lines.
func _build_fret_lines() -> void:
	# All fret lines share one StandardMaterial3D — this is intentional for
	# performance.  If per-fret material variation is needed later, call
	# mat.duplicate() per line before calling set_surface_override_material().
	var mat := StandardMaterial3D.new()
	mat.albedo_texture  = _FRET_LINE_TEX
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode       = BaseMaterial3D.CULL_DISABLED

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
