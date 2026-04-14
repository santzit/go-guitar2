extends Node3D
## note.gd  –  behaviour for a single pooled note with 3D trapezoidal prism finger indicators.
##
## Based on TheStringTheory rendering approach:
##   - Note body (trapezoidal prism)
##   - Tail (approach line) from note to strike line
##   - Marker (sphere) at strike line position
##   - Hit/miss visual feedback with flash and fade

## Visual constants
const START_Z            : float = -20.0
const STRUM_Z            : float = 0.0
const TRAVEL_SPEED       : float = 2.0
const MISS_HOLD_SECS     : float = 1.0
const MISS_LABEL_Z       : float = 0.30
const APPROACH_FADE_SECS : float = 1.0
const HIT_FLASH_SECS     : float = 0.25
const TAIL_THICKNESS     : float = 0.08
const MARKER_SIZE        : float = 0.25

const STRING_COLORS: Array[Color] = [
	Color(0.98, 0.26, 0.22, 1.0), # red
	Color(0.98, 0.78, 0.16, 1.0), # yellow
	Color(0.20, 0.80, 0.95, 1.0), # cyan
	Color(1.00, 0.55, 0.10, 1.0), # orange
	Color(0.20, 0.88, 0.30, 1.0), # green
	Color(0.72, 0.38, 0.98, 1.0), # purple
]

const DIGIT_SCENES: Array[PackedScene] = [
	preload("res://scenes/number_0.tscn"),
	preload("res://scenes/number_1.tscn"),
	preload("res://scenes/number_2.tscn"),
	preload("res://scenes/number_3.tscn"),
	preload("res://scenes/number_4.tscn"),
	preload("res://scenes/number_5.tscn"),
	preload("res://scenes/number_6.tscn"),
	preload("res://scenes/number_7.tscn"),
	preload("res://scenes/number_8.tscn"),
	preload("res://scenes/number_9.tscn"),
]

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0
var _hit_fx_start: float = -1.0
var _hit_result : int = 0  # 0=pending, 1=hit, -1=missed

var _fill_mat: StandardMaterial3D = null
var _tail_mat: StandardMaterial3D = null
var _marker_mat: StandardMaterial3D = null

var _finger: MeshInstance3D = null
var _tail: MeshInstance3D = null
var _marker: MeshInstance3D = null
var _fret_label: Node3D = null
var _miss_label: Label3D = null
var _label_z: float = 0.06

var _indicator_color: Color = Color.WHITE
var _note_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	_fret_label = $FretLabel
	_miss_label = $MissLabel
	
	_finger = $FingerIndicator
	_create_tail()
	_create_marker()
	
	if _finger:
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fill_mat.albedo_color = Color.WHITE
		_fill_mat.metallic = 0.15
		_fill_mat.roughness = 0.25
		_fill_mat.emission_enabled = true
		_fill_mat.emission = Color.WHITE
		_fill_mat.emission_energy_multiplier = 1.0
		_finger.set_surface_override_material(0, _fill_mat)
	
	if _tail:
		_tail_mat = StandardMaterial3D.new()
		_tail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tail_mat.albedo_color = Color.WHITE
		_tail_mat.emission_enabled = true
		_tail_mat.emission = Color.WHITE
		_tail_mat.emission_energy_multiplier = 0.5
		_tail.set_surface_override_material(0, _tail_mat)
	
	if _marker:
		_marker_mat = StandardMaterial3D.new()
		_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_marker_mat.albedo_color = Color.WHITE
		_marker_mat.emission_enabled = true
		_marker_mat.emission = Color.WHITE
		_marker_mat.emission_energy_multiplier = 1.5
		_marker.set_surface_override_material(0, _marker_mat)
	
	if _miss_label:
		_miss_label.position = Vector3(0.0, 0.0, MISS_LABEL_Z)


func _create_tail() -> void:
	_tail = MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(TAIL_THICKNESS, TAIL_THICKNESS, 1.0)
	_tail.mesh = tail_mesh
	_tail.position = Vector3(0.0, 0.0, 0.5)
	add_child(_tail)


func _create_marker() -> void:
	_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = MARKER_SIZE * 0.5
	marker_mesh.height = MARKER_SIZE
	_marker.mesh = marker_mesh
	_marker.position = Vector3(0.0, 0.0, STRUM_Z)
	_marker.visible = true
	add_child(_marker)


func setup(p_fret: int, p_string: int, p_time: float, p_duration: float, p_show_label: bool = true) -> void:
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	is_active    = true
	visible      = true
	_miss_until  = -1.0
	_hit_fx_start = -1.0
	_hit_result = 0
	
	position = Vector3(ChartCommon.fret_mid_world_x(fret - 1), ChartCommon.string_world_y(string_index), START_Z)
	
	_indicator_color = STRING_COLORS[string_index]
	_note_size = ChartCommon.note_indicator_size(fret)
	
	if _finger:
		_update_finger_geometry()
	
	if _tail:
		_tail.visible = true
	
	if _marker:
		_marker.visible = true
	
	if _miss_label:
		_miss_label.visible = false
	
	_update_visuals(0.0)
	
	if p_show_label:
		_rebuild_fret_label()
	else:
		_clear_fret_label()


func _update_finger_geometry() -> void:
	if _finger == null:
		return
	
	var hw: float = _note_size.x * 0.5
	var hh: float = _note_size.y * 0.5
	var depth: float = 0.04
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var front_ratio: float = 0.6
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
	_finger.mesh = st.commit()


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _clear_fret_label() -> void:
	if _fret_label:
		for child in _fret_label.get_children():
			_fret_label.remove_child(child)
			child.free()


func _rebuild_fret_label() -> void:
	if _fret_label == null:
		return
	_clear_fret_label()
	
	if fret < 1 or fret > 24:
		return
	
	var tens := fret / 10
	var ones := fret % 10
	var digit_x_offset := 0.07
	
	if tens > 0:
		var d_tens := DIGIT_SCENES[tens].instantiate()
		d_tens.position = Vector3(-digit_x_offset, 0.0, _label_z)
		_fret_label.add_child(d_tens)
		
		var d_ones := DIGIT_SCENES[ones].instantiate()
		d_ones.position = Vector3(digit_x_offset, 0.0, _label_z)
		_fret_label.add_child(d_ones)
	else:
		var d := DIGIT_SCENES[ones].instantiate()
		d.position = Vector3(0.0, 0.0, _label_z)
		_fret_label.add_child(d)


func tick(p_song_time: float) -> void:
	if not is_active:
		return
	
	position.z = STRUM_Z - (time_offset - p_song_time) * TRAVEL_SPEED
	
	_update_tail()
	_update_visuals(p_song_time)
	
	if _hit_result == 0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD_SECS
		if _miss_label:
			_miss_label.visible = true
	
	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		if _hit_result == 0:
			_hit_result = -1
		deactivate()


func _update_tail() -> void:
	if _tail == null or _tail_mat == null:
		return
	
	var note_z: float = position.z
	var tail_length: float = maxf(0.0, note_z - STRUM_Z)
	
	if tail_length < 0.01:
		_tail.visible = false
		return
	
	_tail.visible = true
	
	var hw: float = TAIL_THICKNESS * 0.5
	var hh: float = TAIL_THICKNESS * 0.5
	var center_z: float = STRUM_Z + tail_length * 0.5
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var v0 := Vector3(-hw, -hh, center_z - tail_length * 0.5)
	var v1 := Vector3(hw, -hh, center_z - tail_length * 0.5)
	var v2 := Vector3(hw, hh, center_z - tail_length * 0.5)
	var v3 := Vector3(-hw, hh, center_z - tail_length * 0.5)
	var v4 := Vector3(-hw, -hh, center_z + tail_length * 0.5)
	var v5 := Vector3(hw, -hh, center_z + tail_length * 0.5)
	var v6 := Vector3(hw, hh, center_z + tail_length * 0.5)
	var v7 := Vector3(-hw, hh, center_z + tail_length * 0.5)
	
	_add_quad(st, v0, v1, v2, v3)
	_add_quad(st, v5, v4, v7, v6)
	_add_quad(st, v4, v0, v3, v7)
	_add_quad(st, v1, v5, v6, v2)
	_add_quad(st, v3, v2, v6, v7)
	_add_quad(st, v4, v5, v1, v0)
	
	st.generate_normals()
	_tail.mesh = st.commit()
	
	_tail_mat.emission = _indicator_color


func _update_visuals(song_time: float) -> void:
	var lead: float = time_offset - song_time
	var result_color: Color = _indicator_color
	var fill_alpha: float = 0.9
	var emit_energy: float = 1.0
	var tail_alpha: float = 0.4
	var marker_alpha: float = 0.8
	
	if _hit_result != 0:
		var t: float
		if _hit_fx_start < 0.0:
			_hit_fx_start = song_time
		t = clampf((song_time - _hit_fx_start) / HIT_FLASH_SECS, 0.0, 1.0)
		
		if _hit_result == 1:
			result_color = Color.WHITE
			fill_alpha = lerpf(0.9, 0.0, t)
			emit_energy = lerpf(2.0, 0.0, t)
			tail_alpha = lerpf(0.4, 0.0, t)
			marker_alpha = lerpf(1.5, 0.0, t)
		else:
			result_color = Color(1.0, 0.2, 0.2, 1.0)
			fill_alpha = lerpf(0.9, 0.0, t)
			emit_energy = lerpf(0.5, 0.0, t)
			tail_alpha = lerpf(0.2, 0.0, t)
			marker_alpha = lerpf(0.5, 0.0, t)
		
		if _finger:
			_finger.visible = t < 0.8
		if _tail:
			_tail.visible = t < 0.5
		if _marker:
			_marker.visible = t < 0.3
		
	elif lead <= 0.0:
		_hit_fx_start = song_time
		_hit_result = 1
		result_color = Color.WHITE
		fill_alpha = 1.0
		emit_energy = 2.5
		tail_alpha = 0.0
		marker_alpha = 2.0
		
	elif lead <= APPROACH_FADE_SECS:
		var ramp: float = (APPROACH_FADE_SECS - lead) / APPROACH_FADE_SECS
		fill_alpha = lerpf(0.9, 1.0, ramp)
		emit_energy = lerpf(0.8, 1.5, ramp)
		tail_alpha = lerpf(0.2, 0.6, ramp)
		marker_alpha = lerpf(0.3, 1.0, ramp)
	
	if _fill_mat:
		var col := result_color
		col.a = clampf(fill_alpha, 0.0, 1.0)
		_fill_mat.albedo_color = col
		_fill_mat.emission = result_color
		_fill_mat.emission_energy_multiplier = maxf(0.0, emit_energy)
	
	if _tail_mat:
		var tcol := _indicator_color
		tcol.a = clampf(tail_alpha, 0.0, 1.0)
		_tail_mat.albedo_color = tcol
		_tail_mat.emission = _indicator_color
		_tail_mat.emission_energy_multiplier = maxf(0.0, emit_energy * 0.5)
	
	if _marker_mat:
		var mcol := result_color
		mcol.a = clampf(marker_alpha, 0.0, 1.0)
		_marker_mat.albedo_color = mcol
		_marker_mat.emission = result_color
		_marker_mat.emission_energy_multiplier = maxf(0.0, emit_energy * 1.5)


func mark_hit() -> void:
	if _hit_result == 0:
		_hit_result = 1
		_hit_fx_start = -1.0


func deactivate() -> void:
	is_active    = false
	visible      = false
	_hit_result = 0
	_miss_until = -1.0
	_hit_fx_start = -1.0
	
	if _finger:
		_finger.visible = false
	if _tail:
		_tail.visible = false
	if _marker:
		_marker.visible = false
	if _miss_label:
		_miss_label.visible = false
	
	_clear_fret_label()
	
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)
