extends Node3D
## chord.gd — Chord container with 3D trapezoidal prism finger indicators.
##
## For the first occurrence (or chord change): renders per-string finger indicators
## + chord name label to the top-left outside the container.
## For repeated chords: renders only the border outline.
##
## Coordinate conventions (shared via ChartCommon):
##   X = fret position, Y = string height, Z = time (spawns at -20 → travels to 0)
##
## The border always spans BORDER_FRET_SPAN (4) frets starting from min_fret.
## Finger indicators are 3D trapezoidal prisms with visual states:
##   - Filled before final 1s
##   - Transparent/border-focused in final 1s
##   - Hit flash on successful strum

const STRING_COLORS: Array[Color] = [
	Color(0.98, 0.26, 0.22, 1.0), # red
	Color(0.98, 0.78, 0.16, 1.0), # yellow
	Color(0.20, 0.80, 0.95, 1.0), # cyan
	Color(1.00, 0.55, 0.10, 1.0), # orange
	Color(0.20, 0.88, 0.30, 1.0), # green
	Color(0.72, 0.38, 0.98, 1.0), # purple
]

const _INTER_BOLD: FontFile = preload("res://assets/fonts/Inter_18pt-Bold.ttf")

const START_Z          : float = -20.0
const STRUM_Z          : float =  0.0
const TRAVEL_SPEED     : float =  2.0
const MISS_HOLD        : float =  1.0
const BORDER_FRET_SPAN : int   = 4
const APPROACH_FADE_SECS: float = 1.0
const HIT_FLASH_SECS: float = 0.25
const BOX_DEPTH: float = 0.04
const BORDER_THICKNESS_RATIO: float = 0.18
const TRAPEZOID_FRONT_RATIO: float = 0.55

var time_offset    : float = 0.0
var is_active      : bool  = false
var _miss_until    : float = -1.0
var _hit_fx_start  : float = -1.0

var _border_mesh   : MeshInstance3D = null
var _chord_label   : Label3D        = null
var _last_min_fret : int            = -1

var _indicators    : Array          = []
var _indicator_meta: Array          = []


func setup(
		p_notes: Array,
		p_time: float,
		p_chord_name: String,
		p_show_details: bool
) -> void:
	time_offset = p_time
	is_active   = true
	visible     = true
	_miss_until = -1.0
	_hit_fx_start = -1.0

	var min_fret   : int = 999
	var min_string : int = 999
	var max_string : int = -1
	for n in p_notes:
		var f : int = int(n.get("fret", 0))
		var s : int = int(n.get("string", 0))
		if f < min_fret:   min_fret   = f
		if s < min_string: min_string = s
		if s > max_string: max_string = s
	if min_fret == 999 or min_string == 999:
		return

	var left_x   : float = ChartCommon.fret_separator_world_x(min_fret)
	var right_x  : float = ChartCommon.fret_separator_world_x(min_fret + BORDER_FRET_SPAN)
	var top_y    : float = ChartCommon.string_world_y(min_string)
	var bot_y    : float = ChartCommon.string_world_y(max_string)
	var center_x : float = (left_x + right_x) * 0.5
	var center_y : float = (top_y + bot_y) * 0.5
	position = Vector3(center_x, center_y, START_Z)

	var w : float = right_x - left_x
	var h : float = absf(top_y - bot_y) + ChartCommon.STRING_SLOT_HEIGHT
	_ensure_border(min_fret, w, h)

	_clear_indicators()
	if p_show_details:
		for n in p_notes:
			var f : int = int(n.get("fret", 0))
			var s : int = clampi(int(n.get("string", 0)), 0, 5)
			_add_indicator(f, s, center_x, center_y)

	_ensure_label()
	_chord_label.visible = p_show_details
	if p_show_details:
		_chord_label.text = p_chord_name
		_chord_label.position = Vector3(
			left_x  - center_x - 0.25,
			top_y   - center_y + 0.15,
			0.10
		)


func _ensure_border(min_fret: int, w: float, h: float) -> void:
	if _border_mesh == null:
		_border_mesh = MeshInstance3D.new()
		_border_mesh.position = Vector3(0.0, 0.0, 0.05)
		add_child(_border_mesh)

	if min_fret != _last_min_fret:
		_last_min_fret = min_fret
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_border_mesh.mesh = _build_border_box(w, h)
		_border_mesh.material_override = mat


func _build_border_box(w: float, h: float) -> ArrayMesh:
	var d: float = 0.01
	var hw: float = w * 0.5
	var hh: float = h * 0.5
	var hd: float = d * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v0 := Vector3(-hw, -hh, hd)
	var v1 := Vector3(hw, -hh, hd)
	var v2 := Vector3(hw, hh, hd)
	var v3 := Vector3(-hw, hh, hd)
	var v4 := Vector3(-hw, -hh, -hd)
	var v5 := Vector3(hw, -hh, -hd)
	var v6 := Vector3(hw, hh, -hd)
	var v7 := Vector3(-hw, hh, -hd)

	_add_quad(st, v0, v1, v2, v3)
	_add_quad(st, v5, v4, v7, v6)
	_add_quad(st, v4, v0, v3, v7)
	_add_quad(st, v1, v5, v6, v2)
	_add_quad(st, v3, v2, v6, v7)
	_add_quad(st, v4, v5, v1, v0)

	st.generate_normals()
	return st.commit()


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _ensure_label() -> void:
	if _chord_label == null:
		_chord_label = Label3D.new()
		_chord_label.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
		_chord_label.pixel_size       = 0.005
		_chord_label.font_size        = 48
		_chord_label.font             = _INTER_BOLD
		_chord_label.modulate         = Color(1.0, 1.0, 1.0, 1.0)
		_chord_label.outline_size     = 8
		_chord_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		add_child(_chord_label)


func _add_indicator(f: int, s: int, center_x: float, center_y: float) -> void:
	var ind := MeshInstance3D.new()
	ind.position = Vector3(
		ChartCommon.fret_mid_world_x(f) - center_x,
		ChartCommon.string_world_y(s)   - center_y,
		0.08
	)
	var sz := ChartCommon.note_indicator_size(f)
	ind.mesh = _build_trapezoid_mesh(sz, BOX_DEPTH)

	var fill_mat := StandardMaterial3D.new()
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.albedo_color = Color(STRING_COLORS[s].r, STRING_COLORS[s].g, STRING_COLORS[s].b, 0.85)
	fill_mat.metallic = 0.15
	fill_mat.roughness = 0.25
	fill_mat.metallic_specular = 1.0
	fill_mat.emission_enabled = true
	fill_mat.emission = STRING_COLORS[s]
	fill_mat.emission_energy_multiplier = 1.0
	ind.set_surface_override_material(0, fill_mat)

	var border_root := Node3D.new()
	ind.add_child(border_root)
	var border_mat := StandardMaterial3D.new()
	border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border_mat.albedo_color = STRING_COLORS[s].lightened(0.2)
	border_mat.albedo_color.a = 0.7
	border_mat.metallic = 0.05
	border_mat.roughness = 0.3
	border_mat.emission_enabled = true
	border_mat.emission = STRING_COLORS[s].lightened(0.2)
	border_mat.emission_energy_multiplier = 1.5
	_build_indicator_border(border_root, border_mat, sz)

	add_child(ind)
	_indicators.append(ind)
	_indicator_meta.append({
		"fill": fill_mat,
		"border": border_mat,
		"color": STRING_COLORS[s]
	})


func _build_indicator_border(root: Node3D, mat: StandardMaterial3D, size_xy: Vector2) -> void:
	var thickness: float = clampf(minf(size_xy.x, size_xy.y) * BORDER_THICKNESS_RATIO, 0.008, 0.03)
	var side_h: float = maxf(size_xy.y - thickness * 2.0, thickness)
	var hz: float = BOX_DEPTH * 0.5
	var half_back_w: float = size_xy.x * 0.5
	var half_front_w: float = half_back_w * TRAPEZOID_FRONT_RATIO
	var half_h: float = size_xy.y * 0.5
	var front_w: float = half_front_w * 2.0
	var back_w: float = half_back_w * 2.0

	_add_border_segment(root, mat, Vector3(front_w, thickness, thickness), Vector3(0.0, half_h - thickness * 0.5, hz))
	_add_border_segment(root, mat, Vector3(front_w, thickness, thickness), Vector3(0.0, -half_h + thickness * 0.5, hz))
	_add_border_segment(root, mat, Vector3(thickness, side_h, thickness), Vector3(-half_front_w + thickness * 0.5, 0.0, hz))
	_add_border_segment(root, mat, Vector3(thickness, side_h, thickness), Vector3(half_front_w - thickness * 0.5, 0.0, hz))

	_add_border_segment(root, mat, Vector3(back_w, thickness, thickness), Vector3(0.0, half_h - thickness * 0.5, -hz))
	_add_border_segment(root, mat, Vector3(back_w, thickness, thickness), Vector3(0.0, -half_h + thickness * 0.5, -hz))
	_add_border_segment(root, mat, Vector3(thickness, side_h, thickness), Vector3(-half_back_w + thickness * 0.5, 0.0, -hz))
	_add_border_segment(root, mat, Vector3(thickness, side_h, thickness), Vector3(half_back_w - thickness * 0.5, 0.0, -hz))

	_add_edge_segment(root, mat, Vector3(-half_front_w, half_h, hz), Vector3(-half_back_w, half_h, -hz), thickness)
	_add_edge_segment(root, mat, Vector3(half_front_w, half_h, hz), Vector3(half_back_w, half_h, -hz), thickness)
	_add_edge_segment(root, mat, Vector3(-half_front_w, -half_h, hz), Vector3(-half_back_w, -half_h, -hz), thickness)
	_add_edge_segment(root, mat, Vector3(half_front_w, -half_h, hz), Vector3(half_back_w, -half_h, -hz), thickness)


func _add_border_segment(root: Node3D, mat: StandardMaterial3D, seg_size: Vector3, seg_pos: Vector3) -> void:
	var seg := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = seg_size
	seg.mesh = mesh
	seg.position = seg_pos
	seg.set_surface_override_material(0, mat)
	root.add_child(seg)


func _add_edge_segment(root: Node3D, mat: StandardMaterial3D, from_pt: Vector3, to_pt: Vector3, thickness: float) -> void:
	var seg := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, from_pt.distance_to(to_pt))
	seg.mesh = mesh
	seg.position = (from_pt + to_pt) * 0.5
	seg.look_at(to_pt, Vector3.UP, true)
	seg.set_surface_override_material(0, mat)
	root.add_child(seg)


func _build_trapezoid_mesh(size_xy: Vector2, depth: float) -> ArrayMesh:
	var hw_back: float = size_xy.x * 0.5
	var hh_back: float = size_xy.y * 0.5
	var hw_front: float = hw_back * TRAPEZOID_FRONT_RATIO
	var hh_front: float = hh_back
	var hz: float = depth * 0.5

	var v0 := Vector3(-hw_front, -hh_front, hz)
	var v1 := Vector3(hw_front, -hh_front, hz)
	var v2 := Vector3(hw_front, hh_front, hz)
	var v3 := Vector3(-hw_front, hh_front, hz)
	var v4 := Vector3(-hw_back, -hh_back, -hz)
	var v5 := Vector3(hw_back, -hh_back, -hz)
	var v6 := Vector3(hw_back, hh_back, -hz)
	var v7 := Vector3(-hw_back, hh_back, -hz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_quad(st, v0, v1, v2, v3)
	_add_quad(st, v5, v4, v7, v6)
	_add_quad(st, v4, v0, v3, v7)
	_add_quad(st, v1, v5, v6, v2)
	_add_quad(st, v3, v2, v6, v7)
	_add_quad(st, v4, v5, v1, v0)

	st.generate_normals()
	return st.commit()


func _clear_indicators() -> void:
	for ind in _indicators:
		if is_instance_valid(ind):
			remove_child(ind)
			ind.queue_free()
	_indicators.clear()
	_indicator_meta.clear()


func tick(p_song_time: float) -> void:
	if not is_active:
		return
	position.z = STRUM_Z - (time_offset - p_song_time) * TRAVEL_SPEED
	_update_indicator_visuals(p_song_time)
	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD
	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


func _update_indicator_visuals(song_time: float) -> void:
	var lead: float = time_offset - song_time
	if _hit_fx_start < 0.0 and lead <= 0.0:
		_hit_fx_start = song_time

	var fill_alpha: float = 0.85
	var border_alpha: float = 0.95
	var emission: float = 1.0
	var scale_mul: float = 1.0

	if _hit_fx_start < 0.0:
		if lead <= APPROACH_FADE_SECS:
			var ramp: float = clampf((APPROACH_FADE_SECS - lead) / APPROACH_FADE_SECS, 0.0, 1.0)
			fill_alpha = 0.0
			border_alpha = lerpf(0.95, 1.0, ramp)
			emission = lerpf(1.0, 1.6, ramp)
	else:
		var t: float = clampf((song_time - _hit_fx_start) / HIT_FLASH_SECS, 0.0, 1.0)
		var fade: float = 1.0 - t
		fill_alpha = fade
		border_alpha = fade
		emission = lerpf(3.5, 0.0, t)
		scale_mul = 1.0 + sin(t * PI) * 0.2

	var count: int = mini(_indicators.size(), _indicator_meta.size())
	for i in range(count):
		var info: Dictionary = _indicator_meta[i]
		var col: Color = info.get("color", Color(1, 1, 1, 1))
		var fill_mat: StandardMaterial3D = info.get("fill", null) as StandardMaterial3D
		if fill_mat:
			var fill_col := col
			fill_col.a = clampf(fill_alpha, 0.0, 1.0)
			fill_mat.albedo_color = fill_col
			fill_mat.emission = col
			fill_mat.emission_energy_multiplier = maxf(0.0, emission)
		var border_mat: StandardMaterial3D = info.get("border", null) as StandardMaterial3D
		if border_mat:
			var edge_col := col.lightened(0.2)
			edge_col.a = clampf(border_alpha, 0.0, 1.0)
			border_mat.albedo_color = edge_col
			border_mat.emission = edge_col
			border_mat.emission_energy_multiplier = maxf(0.0, emission * 0.8)
		var ind: MeshInstance3D = _indicators[i] as MeshInstance3D
		if ind:
			ind.scale = Vector3.ONE * scale_mul


func deactivate() -> void:
	is_active   = false
	visible     = false
	_miss_until = -1.0
	_hit_fx_start = -1.0
	_clear_indicators()
	if is_instance_valid(_chord_label):
		_chord_label.visible = false
	var pool := get_parent()
	if pool and pool.has_method("return_chord"):
		pool.return_chord(self)
