extends Node3D

const ChartCommon = preload("res://scripts/common.gd")
const NOTE_MARKER_SHADER: Shader = preload("res://shaders/note_marker_corner_glow.gdshader")

const NOTE_MARKER_SIZE: Vector3 = Vector3(0.78, 0.34, 0.04)
const NOTE_MARKER_CORNER_RADIUS: float = 0.08
const NOTE_MARKER_CORNER_SEGMENTS: int = 8
const NOTE_MARKER_CORNER_GLOW_WIDTH: float = 0.22
const NOTE_MARKER_CORNER_GLOW_BOOST: float = 18.0
const NOTE_MARKER_GLOW_ENERGY: float = 2.4
const UPCOMING_DIM_ALPHA: float = 0.22
const UPCOMING_DIM_COLOR_MUL: float = 0.45
const NOTE_HEAD_Y_OFFSET: float = 0.10
const NOTE_HEAD_Z: float = 0.02

static var _note_marker_mesh_cache: ArrayMesh = null

var fret: int = 1
var string_index: int = 0
var marker_type: String = "single"
var visual_style: String = "primary"
var _note_marker_mat: ShaderMaterial = null

@onready var _note_marker: MeshInstance3D = $NoteMarker


func _ready() -> void:
	_ensure_visual_nodes()


func setup_head(
		p_fret: int,
		p_string: int,
		p_marker_type: String = "single",
		p_visual_style: String = "primary",
		p_alpha: float = -1.0,
		p_glow_energy: float = -1.0
) -> void:
	_ensure_visual_nodes()
	fret = clampi(p_fret, 1, ChartCommon.FRET_COUNT)
	string_index = clampi(p_string, 0, ChartCommon.STRING_COUNT - 1)
	marker_type = p_marker_type
	visual_style = p_visual_style
	set_meta("marker_type", marker_type)
	set_meta("visual_style", visual_style)
	set_meta("fret", fret)
	set_meta("string_index", string_index)
	position = Vector3(
		ChartCommon.fret_mid_world_x(fret - 1),
		ChartCommon.string_world_y(string_index) + NOTE_HEAD_Y_OFFSET,
		NOTE_HEAD_Z
	)
	_apply_visual_style(p_glow_energy)
	_apply_color(p_alpha)
	visible = true


func hide_head() -> void:
	visible = false


func _ensure_visual_nodes() -> void:
	if _note_marker == null:
		_note_marker = get_node_or_null("NoteMarker") as MeshInstance3D
	if _note_marker == null:
		return
	_note_marker.mesh = _get_note_marker_mesh()
	if _note_marker_mat == null:
		_note_marker_mat = ShaderMaterial.new()
		_note_marker_mat.shader = NOTE_MARKER_SHADER
		_note_marker_mat.set_shader_parameter("corner_glow_color", Color(1.0, 1.0, 1.0, 1.0))
		_note_marker_mat.set_shader_parameter("corner_glow_width", NOTE_MARKER_CORNER_GLOW_WIDTH)
		_note_marker_mat.set_shader_parameter("corner_glow_boost", NOTE_MARKER_CORNER_GLOW_BOOST)
		_note_marker_mat.set_shader_parameter("corner_radius_uv", NOTE_MARKER_CORNER_RADIUS / minf(NOTE_MARKER_SIZE.x, NOTE_MARKER_SIZE.y))
		_note_marker_mat.set_shader_parameter("glow_energy", NOTE_MARKER_GLOW_ENERGY)
	_note_marker.set_surface_override_material(0, _note_marker_mat)


func _apply_color(alpha_override: float = -1.0) -> void:
	if _note_marker_mat == null:
		return
	var c: Color = ChartCommon.STRING_COLORS[string_index] if string_index < ChartCommon.STRING_COLORS.size() else Color.WHITE
	var alpha: float = 1.0
	if visual_style == "upcoming_dim":
		alpha = UPCOMING_DIM_ALPHA
		c = Color(c.r * UPCOMING_DIM_COLOR_MUL, c.g * UPCOMING_DIM_COLOR_MUL, c.b * UPCOMING_DIM_COLOR_MUL, c.a)
	elif alpha_override >= 0.0:
		alpha = clampf(alpha_override, 0.0, 1.0)
	_note_marker_mat.set_shader_parameter("base_color", Color(c.r, c.g, c.b, alpha))


func _apply_visual_style(glow_energy_override: float = -1.0) -> void:
	if _note_marker_mat == null:
		return
	var glow_energy: float = NOTE_MARKER_GLOW_ENERGY
	if visual_style == "upcoming_dim":
		glow_energy = 0.0
	elif glow_energy_override >= 0.0:
		glow_energy = clampf(glow_energy_override, 0.0, NOTE_MARKER_GLOW_ENERGY)
	_note_marker_mat.set_shader_parameter("glow_energy", glow_energy)
	var glow_t: float = glow_energy / NOTE_MARKER_GLOW_ENERGY if NOTE_MARKER_GLOW_ENERGY > 0.00001 else 0.0
	_note_marker_mat.set_shader_parameter("corner_glow_boost", NOTE_MARKER_CORNER_GLOW_BOOST * glow_t)


func _get_note_marker_mesh() -> ArrayMesh:
	if _note_marker_mesh_cache != null:
		return _note_marker_mesh_cache
	_note_marker_mesh_cache = _build_rounded_box_mesh(
		NOTE_MARKER_SIZE.x,
		NOTE_MARKER_SIZE.y,
		NOTE_MARKER_SIZE.z,
		NOTE_MARKER_CORNER_RADIUS,
		NOTE_MARKER_CORNER_SEGMENTS
	)
	return _note_marker_mesh_cache


func _build_rounded_box_mesh(width: float, height: float, depth: float, corner_radius: float, corner_segments: int) -> ArrayMesh:
	var hw := width * 0.5
	var hh := height * 0.5
	var hz := depth * 0.5
	var radius := minf(corner_radius, minf(hw, hh))
	var segs := maxi(corner_segments, 2)

	var points: PackedVector2Array = _rounded_rect_points(hw, hh, radius, segs)
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	if tri.is_empty():
		var reversed: PackedVector2Array = points.duplicate()
		reversed.reverse()
		points = reversed
		tri = Geometry2D.triangulate_polygon(points)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(tri.size() / 3):
		var i0: int = tri[i * 3]
		var i1: int = tri[i * 3 + 1]
		var i2: int = tri[i * 3 + 2]
		_emit_tri(st, points[i0], points[i1], points[i2], hz)
		_emit_tri(st, points[i2], points[i1], points[i0], -hz)

	for i in points.size():
		var j := (i + 1) % points.size()
		var p0: Vector2 = points[i]
		var p1: Vector2 = points[j]
		_emit_side_quad(st, p0, p1, hz)

	st.generate_normals()
	return st.commit()


func _rounded_rect_points(half_w: float, half_h: float, radius: float, segments: int) -> PackedVector2Array:
	var centers := [
		Vector2(half_w - radius, half_h - radius),
		Vector2(half_w - radius, -half_h + radius),
		Vector2(-half_w + radius, -half_h + radius),
		Vector2(-half_w + radius, half_h - radius),
	]
	var angle_pairs := [
		Vector2(PI * 0.5, 0.0),
		Vector2(0.0, -PI * 0.5),
		Vector2(-PI * 0.5, -PI),
		Vector2(PI, PI * 0.5),
	]

	var out := PackedVector2Array()
	for c in centers.size():
		var center: Vector2 = centers[c]
		var a0: float = angle_pairs[c].x
		var a1: float = angle_pairs[c].y
		for s in range(segments):
			var t := float(s) / float(segments - 1)
			var a := lerpf(a0, a1, t)
			var p := center + Vector2(cos(a), sin(a)) * radius
			if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 0.000001:
				out.append(p)
	return out


func _emit_tri(st: SurfaceTool, a2: Vector2, b2: Vector2, c2: Vector2, z: float) -> void:
	var a := Vector3(a2.x, a2.y, z)
	var b := Vector3(b2.x, b2.y, z)
	var c := Vector3(c2.x, c2.y, z)
	st.set_uv(_xy_uv(a2))
	st.add_vertex(a)
	st.set_uv(_xy_uv(b2))
	st.add_vertex(b)
	st.set_uv(_xy_uv(c2))
	st.add_vertex(c)


func _emit_side_quad(st: SurfaceTool, p0: Vector2, p1: Vector2, hz: float) -> void:
	var a := Vector3(p0.x, p0.y, hz)
	var b := Vector3(p1.x, p1.y, hz)
	var c := Vector3(p1.x, p1.y, -hz)
	var d := Vector3(p0.x, p0.y, -hz)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(b)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(c)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(c)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(d)


func _xy_uv(p: Vector2) -> Vector2:
	return Vector2(
		(p.x / NOTE_MARKER_SIZE.x) + 0.5,
		(p.y / NOTE_MARKER_SIZE.y) + 0.5
	)
