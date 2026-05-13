extends Node3D
const ChartCommon = preload("res://scripts/common.gd")
const NOTE_MARKER_SHADER: Shader = preload("res://shaders/note_marker_corner_glow.gdshader")
const NOTE_LANE_CONNECTOR_SHADER: Shader = preload("res://shaders/note_lane_connector.gdshader")
## note.gd  –  behaviour for a single pooled note with a static 3D NoteMarker mesh.
##
## All coordinate formulas live in scripts/common.gd (class ChartCommon) so they
## can be shared with highway.gd, music_play.gd, and fretboard.gd.
##
## Coordinate mapping summary
##   X = ChartCommon.fret_mid_world_x(fret)      — linear fret spacing (2 units/fret)
##   Y = ChartCommon.string_world_y(string_index) — string 0 = top, 5 = bottom
##   Z = ChartCommon.note_world_z(time_offset, song_time, STRUM_Z)
##       Notes spawn at Z = -ChartCommon.HIGHWAY_DEPTH and travel toward Z = 0.
##
const START_Z       : float = -ChartCommon.HIGHWAY_DEPTH
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = ChartCommon.Z_UNITS_PER_SECOND
## Keep notes alive briefly after crossing STRUM_Z so game-side hit/miss checks
## in the same frame window can still observe the note before it is returned.
const MISS_HOLD_SECS: float = 1.0

## Local transform aligns the note marker plane in-lane.
## Lift marker slightly so the visual middle aligns with the string centerline.
const NOTE_MARKER_LOCAL_OFFSET: Vector3 = Vector3(0.0, 0.1, 0.08)
const NOTE_MARKER_LOCAL_ROTATION_DEGREES: Vector3 = Vector3.ZERO
const NOTE_MARKER_NEON_GLOW_BASE: float = 2.4
const NOTE_MARKER_NEON_GLOW_PULSE: float = 0.8
const NOTE_MARKER_PULSE_FREQUENCY: float = 8.0
const NOTE_MARKER_TEXTURE_ALPHA: float = 1.0
const NOTE_MARKER_SIZE: Vector3 = Vector3(0.78, 0.34, 0.04)
const NOTE_MARKER_CORNER_RADIUS: float = 0.08
const NOTE_MARKER_CORNER_SEGMENTS: int = 8
const NOTE_MARKER_CORNER_GLOW_WIDTH: float = 0.22
const NOTE_MARKER_CORNER_GLOW_BOOST: float = 18.0
const NOTE_LANE_CONNECTOR_WIDTH: float = 0.012
const NOTE_LANE_CONNECTOR_DEPTH: float = 0.012
const NOTE_LANE_CONNECTOR_MIN_HEIGHT: float = 0.02
const NOTE_LANE_CONNECTOR_GLOW_MULTIPLIER: float = 2.2
const NOTE_VISUAL_ALPHA: float = 0.4
const SUSTAIN_MIN_SECS: float = 0.05
const SUSTAIN_TRAIL_WIDTH: float = 0.5
const SUSTAIN_TRAIL_HEIGHT: float = 0.08
const SUSTAIN_MIN_LENGTH: float = SUSTAIN_MIN_SECS * TRAVEL_SPEED

static var _note_marker_mesh_cache: ArrayMesh = null

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0
var _show_lane_connector: bool = true
var _note_marker_mat: ShaderMaterial = null
var _lane_connector: MeshInstance3D = null
var _lane_connector_mat: ShaderMaterial = null
var _sustain_trail: MeshInstance3D = null
var _sustain_trail_mat: StandardMaterial3D = null
var _indicator_color: Color = Color(1.0, 0.5, 0.1, 1.0)

@onready var _note_marker: MeshInstance3D = $NoteMarker


func _ready() -> void:
	if _note_marker:
		_note_marker.mesh = _get_note_marker_mesh()
		_note_marker.position = NOTE_MARKER_LOCAL_OFFSET
		_note_marker.rotation_degrees = NOTE_MARKER_LOCAL_ROTATION_DEGREES
		_note_marker_mat = ShaderMaterial.new()
		_note_marker_mat.shader = NOTE_MARKER_SHADER
		_note_marker_mat.set_shader_parameter("corner_glow_color", Color(1.0, 1.0, 1.0, 1.0))
		_note_marker_mat.set_shader_parameter("corner_glow_width", NOTE_MARKER_CORNER_GLOW_WIDTH)
		_note_marker_mat.set_shader_parameter("corner_glow_boost", NOTE_MARKER_CORNER_GLOW_BOOST)
		_note_marker_mat.set_shader_parameter("corner_radius_uv", NOTE_MARKER_CORNER_RADIUS / minf(NOTE_MARKER_SIZE.x, NOTE_MARKER_SIZE.y))
		_note_marker_mat.set_shader_parameter("glow_energy", NOTE_MARKER_NEON_GLOW_BASE)
		_note_marker.set_surface_override_material(0, _note_marker_mat)
		_lane_connector = MeshInstance3D.new()
		var connector_mesh := BoxMesh.new()
		connector_mesh.size = Vector3(NOTE_LANE_CONNECTOR_WIDTH, NOTE_LANE_CONNECTOR_MIN_HEIGHT, NOTE_LANE_CONNECTOR_DEPTH)
		_lane_connector.mesh = connector_mesh
		_lane_connector_mat = ShaderMaterial.new()
		_lane_connector_mat.shader = NOTE_LANE_CONNECTOR_SHADER
		_lane_connector_mat.set_shader_parameter("line_color", Color(1.0, 1.0, 1.0, 1.0))
		_lane_connector_mat.set_shader_parameter("glow_energy", NOTE_MARKER_NEON_GLOW_BASE * NOTE_LANE_CONNECTOR_GLOW_MULTIPLIER)
		_lane_connector_mat.set_shader_parameter("connector_width", NOTE_LANE_CONNECTOR_WIDTH)
		_lane_connector_mat.set_shader_parameter("connector_depth", NOTE_LANE_CONNECTOR_DEPTH)
		_lane_connector_mat.set_shader_parameter("connector_height", NOTE_LANE_CONNECTOR_MIN_HEIGHT)
		_lane_connector.set_surface_override_material(0, _lane_connector_mat)
		add_child(_lane_connector)
		_sustain_trail = MeshInstance3D.new()
		_sustain_trail_mat = StandardMaterial3D.new()
		_sustain_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sustain_trail_mat.albedo_color = _with_visual_alpha(_indicator_color)
		_sustain_trail_mat.emission_enabled = true
		_sustain_trail_mat.emission = _with_visual_alpha(_indicator_color)
		_sustain_trail_mat.metallic = 0.2
		_sustain_trail_mat.roughness = 0.08
		_sustain_trail_mat.emission_energy_multiplier = NOTE_MARKER_NEON_GLOW_BASE
		_sustain_trail.visible = false
		add_child(_sustain_trail)


func setup(
		p_fret: int,
		p_string: int,
		p_time: float,
		p_duration: float,
		p_show_lane_connector: bool = true
) -> void:
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	_show_lane_connector = p_show_lane_connector
	is_active    = true
	visible      = true
	_miss_until  = -1.0

	position = Vector3(ChartCommon.fret_mid_world_x(fret - 1), ChartCommon.string_world_y(string_index), START_Z)
	_indicator_color = ChartCommon.STRING_COLORS[string_index] if string_index < ChartCommon.STRING_COLORS.size() else Color.WHITE
	_apply_marker_color()
	_update_lane_connector()
	_update_sustain_trail()
	_update_marker_glow(0.0)


func tick(p_song_time: float) -> void:
	if not is_active:
		return

	position.z = ChartCommon.note_world_z(time_offset, p_song_time, STRUM_Z)
	_update_marker_glow(p_song_time)

	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD_SECS

	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


func deactivate() -> void:
	if not is_active:
		return   # already deactivated — guard against double-deactivation from pool
	is_active    = false
	visible      = false
	_miss_until  = -1.0
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func _apply_marker_color() -> void:
	if _note_marker_mat == null:
		return
	var marker_tint := Color(_indicator_color.r, _indicator_color.g, _indicator_color.b, NOTE_MARKER_TEXTURE_ALPHA)
	_note_marker_mat.set_shader_parameter("base_color", marker_tint)
	if _sustain_trail_mat != null:
		var visual_color := _with_visual_alpha(_indicator_color)
		_sustain_trail_mat.albedo_color = visual_color
		_sustain_trail_mat.emission = visual_color


func _update_marker_glow(song_time: float) -> void:
	if _note_marker_mat == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(song_time * NOTE_MARKER_PULSE_FREQUENCY)
	var glow_energy: float = NOTE_MARKER_NEON_GLOW_BASE + NOTE_MARKER_NEON_GLOW_PULSE * pulse
	_note_marker_mat.set_shader_parameter("glow_energy", glow_energy)
	if _lane_connector_mat != null:
		_lane_connector_mat.set_shader_parameter("glow_energy", glow_energy * NOTE_LANE_CONNECTOR_GLOW_MULTIPLIER)
	if _sustain_trail_mat != null:
		_sustain_trail_mat.emission_energy_multiplier = glow_energy


func _update_sustain_trail() -> void:
	if _sustain_trail == null:
		return
	var sustain_length: float = maxf(duration * TRAVEL_SPEED, 0.0)
	if sustain_length < SUSTAIN_MIN_LENGTH:
		_sustain_trail.visible = false
		return
	var trail_mesh: BoxMesh = _sustain_trail.mesh as BoxMesh
	if trail_mesh == null:
		trail_mesh = BoxMesh.new()
		_sustain_trail.mesh = trail_mesh
		if _sustain_trail_mat != null:
			_sustain_trail.set_surface_override_material(0, _sustain_trail_mat)
	trail_mesh.size = Vector3(SUSTAIN_TRAIL_WIDTH, SUSTAIN_TRAIL_HEIGHT, sustain_length)
	_sustain_trail.position = Vector3(
		NOTE_MARKER_LOCAL_OFFSET.x,
		NOTE_MARKER_LOCAL_OFFSET.y,
		NOTE_MARKER_LOCAL_OFFSET.z - sustain_length * 0.5
	)
	_sustain_trail.visible = true


func _update_lane_connector() -> void:
	if _lane_connector == null:
		return
	if not _show_lane_connector:
		_lane_connector.visible = false
		return
	var marker_anchor_y: float = NOTE_MARKER_LOCAL_OFFSET.y
	var highway_local_y: float = -position.y
	var connector_height: float = marker_anchor_y - highway_local_y
	if connector_height <= NOTE_LANE_CONNECTOR_MIN_HEIGHT:
		_lane_connector.visible = false
		return
	var connector_mesh := _lane_connector.mesh as BoxMesh
	if connector_mesh == null:
		connector_mesh = BoxMesh.new()
		_lane_connector.mesh = connector_mesh
	connector_mesh.size = Vector3(NOTE_LANE_CONNECTOR_WIDTH, connector_height, NOTE_LANE_CONNECTOR_DEPTH)
	if _lane_connector_mat != null:
		_lane_connector_mat.set_shader_parameter("connector_height", connector_height)
	_lane_connector.position = Vector3(
		NOTE_MARKER_LOCAL_OFFSET.x,
		highway_local_y + (connector_height * 0.5),
		NOTE_MARKER_LOCAL_OFFSET.z
	)
	_lane_connector.visible = true


func _with_visual_alpha(c: Color) -> Color:
	return Color(c.r, c.g, c.b, NOTE_VISUAL_ALPHA)


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
