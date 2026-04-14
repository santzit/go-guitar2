extends Node3D
## chord.gd — Chord container with 3D trapezoidal prism finger indicators and box frame.
##
## Based on TheStringTheory rendering:
##   - Trapezoidal prism indicators for each note in the chord
##   - Box frame with 4 edges (top, bottom, left, right)
##   - Chord name label
##   - Hit/miss visual feedback

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
const FRAME_THICKNESS  : float = 0.025

var time_offset    : float = 0.0
var is_active      : bool  = false
var _miss_until    : float = -1.0
var _hit_result   : int = 0

var _frame_root   : Node3D = null
var _frame_mats  : Array = []
var _indicators   : Array = []
var _chord_label  : Label3D = null
var _label_z      : float = 0.10

var _box_width    : float = 0.0
var _box_height   : float = 0.0
var _note_count   : int = 0


func _ready() -> void:
	pass


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
	_hit_result = 0

	var min_fret   : int = 999
	var min_string : int = 999
	var max_string : int = -1
	_note_count = 0
	
	for n in p_notes:
		var f : int = int(n.get("fret", 0))
		var s : int = int(n.get("string", 0))
		_note_count += 1
		if f < min_fret:   min_fret   = f
		if s < min_string: min_string = s
		if s > max_string: max_string = s
	
	if min_fret == 999 or min_string == 999:
		return

	var left_x   : float = ChartCommon.fret_separator_world_x(min_fret - 1)
	var right_x  : float = ChartCommon.fret_separator_world_x(min_fret + BORDER_FRET_SPAN - 1)
	var top_y    : float = ChartCommon.string_world_y(0)
	var bot_y    : float = ChartCommon.string_world_y(5) - ChartCommon.STRING_SLOT_HEIGHT
	var center_x : float = (left_x + right_x) * 0.5
	var center_y : float = (top_y + bot_y) * 0.5
	
	_box_width = right_x - left_x
	_box_height = absf(top_y - bot_y)
	
	position = Vector3(center_x, center_y, START_Z)

	_ensure_frame()
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
			-_box_width * 0.5 - 0.15,
			_box_height * 0.5 + 0.15,
			_label_z
		)


func _ensure_frame() -> void:
	if _frame_root == null:
		_frame_root = Node3D.new()
		add_child(_frame_root)
		_frame_mats.clear()
		
		for i in range(4):
			var seg := MeshInstance3D.new()
			seg.mesh = BoxMesh.new()
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.95, 1.0, 0.8)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.95, 1.0, 1.0)
			mat.emission_energy_multiplier = 1.5
			seg.set_surface_override_material(0, mat)
			_frame_root.add_child(seg)
			_frame_mats.append(mat)
	
	_update_frame_geometry()


func _update_frame_geometry() -> void:
	if _frame_root == null:
		return
	
	var half_w := _box_width * 0.5
	var half_h := _box_height * 0.5
	var thick := FRAME_THICKNESS
	var depth := 0.02
	
	var segs := _frame_root.get_children()
	
	if segs.size() >= 4:
		_set_box_segment(segs[0], Vector3(_box_width, thick, depth), Vector3(0.0, half_h, 0.0))
		_set_box_segment(segs[1], Vector3(_box_width, thick, depth), Vector3(0.0, -half_h, 0.0))
		_set_box_segment(segs[2], Vector3(thick, _box_height, depth), Vector3(-half_w, 0.0, 0.0))
		_set_box_segment(segs[3], Vector3(thick, _box_height, depth), Vector3(half_w, 0.0, 0.0))


func _set_box_segment(seg: Node3D, size: Vector3, pos: Vector3) -> void:
	if seg is MeshInstance3D and seg.mesh is BoxMesh:
		(seg.mesh as BoxMesh).size = size
	seg.position = pos


func _add_indicator(f: int, s: int, center_x: float, center_y: float) -> void:
	var ind := MeshInstance3D.new()
	ind.position = Vector3(
		ChartCommon.fret_mid_world_x(f - 1) - center_x,
		ChartCommon.string_world_y(s)        - center_y,
		0.06
	)
	
	var sz := ChartCommon.note_indicator_size(f)
	var hw := sz.x * 0.5
	var hh := sz.y * 0.5
	var depth := 0.03
	var front_ratio := 0.6
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var v0 := Vector3(-hw * front_ratio, -hh, depth * 0.5)
	var v1 := Vector3(hw * front_ratio, -hh, depth * 0.5)
	var v2 := Vector3(hw * front_ratio, hh, depth * 0.5)
	var v3 := Vector3(-hw * front_ratio, hh, depth * 0.5)
	var v4 := Vector3(-hw, -hh, -depth * 0.5)
	var v5 := Vector3(hw, -hh, -depth * 0.5)
	var v6 := Vector3(hw, hh, -depth * 0.5)
	var v7 := Vector3(-hw, hh, -depth * 0.5)
	
	_add_quad(st, v0, v1, v2, v3)
	_add_quad(st, v5, v4, v7, v6)
	_add_quad(st, v4, v0, v3, v7)
	_add_quad(st, v1, v5, v6, v2)
	_add_quad(st, v3, v2, v6, v7)
	_add_quad(st, v4, v5, v1, v0)
	
	st.generate_normals()
	ind.mesh = st.commit()
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STRING_COLORS[s]
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.15
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = STRING_COLORS[s]
	mat.emission_energy_multiplier = 1.0
	ind.set_surface_override_material(0, mat)
	
	add_child(ind)
	_indicators.append({"mesh": ind, "color": STRING_COLORS[s]})


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


func _clear_indicators() -> void:
	for ind_data in _indicators:
		var ind : Node = ind_data.get("mesh")
		if is_instance_valid(ind):
			remove_child(ind)
			ind.queue_free()
	_indicators.clear()


func tick(p_song_time: float) -> void:
	if not is_active:
		return
	position.z = STRUM_Z - (time_offset - p_song_time) * TRAVEL_SPEED
	
	_update_visuals(p_song_time)
	
	if _hit_result == 0 and p_song_time >= time_offset:
		_hit_result = 1
	
	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD
	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


func _update_visuals(song_time: float) -> void:
	var lead: float = time_offset - song_time
	var base_color: Color = Color.WHITE
	var emit_energy: float = 1.5
	var alpha: float = 0.8
	
	if _hit_result != 0:
		if _hit_result == 1:
			base_color = Color.WHITE
			emit_energy = 2.0
		else:
			base_color = Color(1.0, 0.2, 0.2, 1.0)
			emit_energy = 0.5
		alpha = 0.4
	elif lead <= 0.0:
		_hit_result = 1
		base_color = Color.WHITE
		emit_energy = 2.5
		alpha = 1.0
	elif lead <= 1.0:
		var ramp: float = 1.0 - (lead / 1.0)
		emit_energy = lerpf(1.0, 2.0, ramp)
		alpha = lerpf(0.6, 1.0, ramp)
	
	for mat in _frame_mats:
		if mat is StandardMaterial3D:
			var col := base_color
			col.a = alpha
			mat.albedo_color = col
			mat.emission = base_color
			mat.emission_energy_multiplier = emit_energy
	
	for ind_data in _indicators:
		var ind : Node = ind_data.get("mesh")
		var col : Color = ind_data.get("color")
		if ind is MeshInstance3D:
			var mat := ind.get_surface_override_material(0) as StandardMaterial3D
			if mat:
				var final_col := col
				final_col.a = alpha
				mat.albedo_color = final_col
				mat.emission = col
				mat.emission_energy_multiplier = emit_energy


func deactivate() -> void:
	is_active   = false
	visible     = false
	_miss_until = -1.0
	_hit_result = 0
	_clear_indicators()
	if is_instance_valid(_chord_label):
		_chord_label.visible = false
	var pool := get_parent()
	if pool and pool.has_method("return_chord"):
		pool.return_chord(self)
