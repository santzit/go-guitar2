extends Node3D
## fretboard.gd  –  Drives per-string glow intensity via shader parameters,
## builds vertical fret-line markers at ChartPlayer fret positions, and
## places fret-number labels (1–24) below the lowest (purple) string.
##
## Each string (String0 … String5) must have a ShaderMaterial that uses
## shaders/string_glow.gdshader, which exposes the `glow_intensity` uniform.
## Call set_string_glow() each frame from music_play.gd to light up the
## strings that have notes arriving within the glow window.

## Mirrors ChartCommon.STRING_COUNT — kept local for brevity in this file.
const STRING_COUNT : int = ChartCommon.STRING_COUNT
const NOTE_MARKER_SHADER: Shader = preload("res://shaders/note_marker_corner_glow.gdshader")

## Width of each fret-line quad in world units.
## Slightly wider than the highway shader lines to be clearly visible.
const FRET_LINE_WIDTH  : float = 0.035
## Z offset so fret lines sit just in front of the string cylinders (Z=0).
const FRET_LINE_Z      : float = 0.03

## How far below the lowest string the fret-number labels are placed.
const FRET_NUM_Y_OFFSET: float = 0.22
## Pixel size for the fret-number Label3D nodes (world units per pixel).
const FRET_NUM_PIXEL_SIZE: float = 0.005
## Additional Z offset so fret-number labels sit in front of fret lines.
const FRET_NUM_Z_OFFSET: float = 0.04
const UPCOMING_MARKER_Z: float = 0.02
const UPCOMING_OPEN_STRING_SPAN_FRETS: int = 4
const UPCOMING_SCAN_MAX_EVENTS: int = 24
const UPCOMING_NOTE_HEAD_SIZE: Vector3 = Vector3(0.78, 0.34, 0.04)
const UPCOMING_NOTE_HEAD_CORNER_RADIUS: float = 0.08
const UPCOMING_NOTE_HEAD_CORNER_GLOW_WIDTH: float = 0.22
const UPCOMING_NOTE_HEAD_CORNER_GLOW_BOOST: float = 18.0
const UPCOMING_NOTE_HEAD_GLOW_ENERGY: float = 2.4

## Cache of ShaderMaterial per string (index 0–5).
var _string_mats : Array = []
var _upcoming_root: Node3D = null


func _ready() -> void:
	for i in STRING_COUNT:
		var mi := get_node_or_null("String%d" % i) as MeshInstance3D
		if mi:
			var mat := mi.get_surface_override_material(0) as ShaderMaterial
			_string_mats.append(mat)
		else:
			push_warning("Fretboard: String%d node not found." % i)
			_string_mats.append(null)
	for i in STRING_COUNT:
		set_string_glow(i, 0.0)
	_upcoming_root = Node3D.new()
	_upcoming_root.name = "UpcomingMarkers"
	add_child(_upcoming_root)
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


func update_upcoming_markers(events: Array, song_time: float, lookahead: float, start_idx: int = 0) -> void:
	if _upcoming_root == null:
		return
	for child in _upcoming_root.get_children():
		child.free()

	var added: int = 0
	for i in range(maxi(start_idx, 0), events.size()):
		if added >= UPCOMING_SCAN_MAX_EVENTS:
			break
		var ev: Dictionary = events[i]
		var t: float = float(ev.get("time_start", -1.0))
		if t <= song_time:
			continue
		if t > song_time + lookahead:
			break
		var notes: Array = ev.get("notes", [])
		if notes.is_empty():
			continue
		_render_event_markers(notes)
		added += 1


func _render_event_markers(notes: Array) -> void:
	var fretted: Array = []
	var open_notes: Array = []
	for n in notes:
		var f: int = int(n.get("fret", -1))
		var s: int = int(n.get("string", -1))
		if s < 0 or s >= STRING_COUNT:
			continue
		if f == 0:
			open_notes.append({"string": s})
		elif f >= 1 and f <= ChartCommon.FRET_COUNT:
			fretted.append({"fret": f, "string": s})

	for n in open_notes:
		_add_open_string_marker(int(n.get("string", 0)))

	var fretted_marker_type: String = "single"
	if fretted.size() > 1:
		fretted_marker_type = "chord"
	for n in fretted:
		_add_note_head_marker(int(n.get("fret", 1)), int(n.get("string", 0)), fretted_marker_type)


func _add_note_head_marker(fret: int, string_idx: int, marker_type: String) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "UpcomingNoteHead"
	marker.set_meta("marker_type", marker_type)
	var mesh := BoxMesh.new()
	mesh.size = UPCOMING_NOTE_HEAD_SIZE
	marker.mesh = mesh
	marker.position = Vector3(
		ChartCommon.fret_mid_world_x(fret - 1),
		ChartCommon.string_world_y(string_idx) + 0.10,
		UPCOMING_MARKER_Z
	)
	marker.set_surface_override_material(0, _make_note_head_material(string_idx))
	_upcoming_root.add_child(marker)


func _add_open_string_marker(string_idx: int) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "UpcomingOpen"
	marker.set_meta("marker_type", "open")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.018
	mesh.bottom_radius = 0.018
	mesh.height = float(UPCOMING_OPEN_STRING_SPAN_FRETS) * ChartCommon.FRET_SPACING
	marker.mesh = mesh
	marker.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	marker.position = Vector3(
		(float(UPCOMING_OPEN_STRING_SPAN_FRETS) * ChartCommon.FRET_SPACING) * 0.5,
		ChartCommon.string_world_y(string_idx),
		UPCOMING_MARKER_Z
	)
	marker.set_surface_override_material(0, _make_marker_material(Color(1.0, 1.0, 1.0, 1.0)))
	_upcoming_root.add_child(marker)


func _make_marker_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = false
	mat.albedo_color = color
	return mat


func _make_note_head_material(string_idx: int) -> ShaderMaterial:
	var c: Color = ChartCommon.STRING_COLORS[string_idx] if string_idx >= 0 and string_idx < ChartCommon.STRING_COLORS.size() else Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = NOTE_MARKER_SHADER
	mat.set_shader_parameter("base_color", Color(c.r, c.g, c.b, 1.0))
	mat.set_shader_parameter("corner_glow_color", Color(1.0, 1.0, 1.0, 1.0))
	mat.set_shader_parameter("corner_glow_width", UPCOMING_NOTE_HEAD_CORNER_GLOW_WIDTH)
	mat.set_shader_parameter("corner_glow_boost", UPCOMING_NOTE_HEAD_CORNER_GLOW_BOOST)
	mat.set_shader_parameter("corner_radius_uv", UPCOMING_NOTE_HEAD_CORNER_RADIUS / minf(UPCOMING_NOTE_HEAD_SIZE.x, UPCOMING_NOTE_HEAD_SIZE.y))
	mat.set_shader_parameter("glow_energy", UPCOMING_NOTE_HEAD_GLOW_ENERGY)
	return mat


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

	# Derive height and Y-centre from ChartCommon so fret lines always span
	# exactly the string range separators (top/bottom margins included).
	var top_sep    : float = ChartCommon.string_top_separator_y(0)
	var bot_sep    : float = ChartCommon.string_separator_y(STRING_COUNT - 1)
	var line_height: float = top_sep - bot_sep
	var line_y     : float = (top_sep + bot_sep) * 0.5

	# Fret lines for separators 1 … FRET_COUNT (omitting 0 which is the nut/edge).
	for i in range(1, ChartCommon.FRET_COUNT + 1):
		var x := ChartCommon.fret_separator_world_x(i)
		var plane := PlaneMesh.new()
		plane.size        = Vector2(FRET_LINE_WIDTH, line_height)
		plane.orientation = PlaneMesh.FACE_Z
		var mi := MeshInstance3D.new()
		mi.name     = "FretLine%d" % i
		mi.mesh     = plane
		mi.set_surface_override_material(0, mat)
		mi.position = Vector3(x, line_y, FRET_LINE_Z)
		add_child(mi)


## Place a Label3D with the fret number (1–24) below the lowest string,
## centred horizontally in each fret slot using ChartPlayer fret-mid positions.
func _build_fret_numbers() -> void:
	var font := load("res://assets/fonts/Inter_18pt-Bold.ttf") as FontFile
	var label_y := ChartCommon.string_world_y(STRING_COUNT - 1) - FRET_NUM_Y_OFFSET

	for fret in range(1, ChartCommon.FRET_COUNT + 1):
		# fret_mid_world_x(n) returns center between fret n and n+1
		# For label "N", we need center of fret N's slot (between N-1 and N)
		var x := ChartCommon.fret_mid_world_x(fret - 1)
		var lbl := Label3D.new()
		lbl.name             = "FretNum%d" % fret
		lbl.text             = str(fret)
		lbl.pixel_size       = FRET_NUM_PIXEL_SIZE
		lbl.font_size        = 32
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
