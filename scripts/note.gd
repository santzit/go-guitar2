extends Node3D
## note.gd  –  behaviour for a single pooled note with 3D trapezoidal prism finger indicators.
##
## All coordinate formulas live in scripts/common.gd (class ChartCommon) so they
## can be shared with highway.gd, music_play.gd, and fretboard.gd.
##
## Coordinate mapping summary
##   X = ChartCommon.fret_mid_world_x(fret)      — linear fret spacing (1 unit/fret)
##   Y = ChartCommon.string_world_y(string_index) — string 0 = top, 5 = bottom
##   Z = STRUM_Z − (time_offset − song_time) × TRAVEL_SPEED
##       Notes spawn at Z = -20 and travel toward Z = 0.
##
## Finger indicator is a 3D trapezoidal prism:
##   - Small face at front (+Z), larger face at back (-Z)
##   - Visual states: filled → transparent (final 1s) → hit flash

# ── Per-string note colors (string 0 top → string 5 bottom) ───────────────────
const STRING_COLORS: Array[Color] = [
	Color(0.98, 0.26, 0.22, 1.0), # red
	Color(0.98, 0.78, 0.16, 1.0), # yellow
	Color(0.20, 0.80, 0.95, 1.0), # cyan
	Color(1.00, 0.55, 0.10, 1.0), # orange
	Color(0.20, 0.88, 0.30, 1.0), # green
	Color(0.72, 0.38, 0.98, 1.0), # purple
]

# ── Digit scenes (0–9) used to display the fret number on each note ──────────
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

## Visual constants for trapezoidal prism
const LABEL_Z : float = 0.06
const DIGIT_X_OFFSET : float = 0.07
const START_Z       : float = -20.0
const STRUM_Z       : float = 0.0
const TRAVEL_SPEED  : float = 2.0
const MISS_HOLD_SECS: float = 1.0
const MISS_LABEL_Z  : float = 0.30
const APPROACH_FADE_SECS: float = 1.0
const HIT_FLASH_SECS: float = 0.25
const BOX_DEPTH: float = 0.04
const BORDER_THICKNESS_RATIO: float = 0.18
const TRAPEZOID_FRONT_RATIO: float = 0.55

var fret         : int   = 0
var string_index : int   = 0
var time_offset  : float = 0.0
var duration     : float = 0.25
var is_active    : bool  = false
var _miss_until  : float = -1.0
var _hit_fx_start: float = -1.0
var _last_sized_fret: int = -1
var _indicator_color: Color = Color(1.0, 0.5, 0.1, 1.0)

var _fill_mat: StandardMaterial3D = null
var _border_mat: StandardMaterial3D = null
var _border_root: Node3D = null
var _border_segments: Array[MeshInstance3D] = []

@onready var _finger     : MeshInstance3D = $FingerIndicator
@onready var _fret_label : Node3D         = $FretLabel
@onready var _miss_label : Label3D        = $MissLabel


func _ready() -> void:
	if _finger:
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fill_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.0)
		_fill_mat.metallic = 0.15
		_fill_mat.roughness = 0.25
		_fill_mat.metallic_specular = 1.0
		_fill_mat.emission_enabled = true
		_fill_mat.emission = Color(1.0, 0.6, 0.2, 1.0)
		_fill_mat.emission_energy_multiplier = 0.0
		_finger.set_surface_override_material(0, _fill_mat)

		_border_root = Node3D.new()
		_border_root.position = _finger.position
		add_child(_border_root)
		_border_mat = StandardMaterial3D.new()
		_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_border_mat.albedo_color = Color(1.0, 0.7, 0.25, 0.7)
		_border_mat.metallic = 0.05
		_border_mat.roughness = 0.3
		_border_mat.emission_enabled = true
		_border_mat.emission = Color(1.0, 0.7, 0.25, 1.0)
		_border_mat.emission_energy_multiplier = 1.5
		_ensure_border_segments()
		_update_indicator_geometry(1)

	if _miss_label:
		_miss_label.position = Vector3(0.0, 0.0, MISS_LABEL_Z)


func setup(p_fret: int, p_string: int, p_time: float, p_duration: float, p_show_label: bool = true) -> void:
	fret         = p_fret
	string_index = clampi(p_string, 0, 5)
	time_offset  = p_time
	duration     = p_duration
	is_active    = true
	visible      = true
	_miss_until  = -1.0
	_hit_fx_start = -1.0

	position = Vector3(ChartCommon.fret_mid_world_x(fret - 1), ChartCommon.string_world_y(string_index), START_Z)
	_miss_label.visible = false

	if _finger:
		if fret != _last_sized_fret:
			_last_sized_fret = fret
			_update_indicator_geometry(fret)
		_indicator_color = STRING_COLORS[string_index]
		_update_indicator_visuals(0.85, 0.95, 1.0, 1.0)
		_finger.scale = Vector3.ONE
		if _border_root:
			_border_root.scale = Vector3.ONE

	if p_show_label:
		_rebuild_fret_label()
	else:
		for child in _fret_label.get_children():
			_fret_label.remove_child(child)
			child.free()


func _rebuild_fret_label() -> void:
	for child in _fret_label.get_children():
		_fret_label.remove_child(child)
		child.free()

	if fret < 1 or fret > 24:
		return

	var tens := fret / 10
	var ones := fret % 10

	if tens > 0:
		var d_tens := DIGIT_SCENES[tens].instantiate()
		d_tens.position = Vector3(-DIGIT_X_OFFSET, 0.0, LABEL_Z)
		_fret_label.add_child(d_tens)

		var d_ones := DIGIT_SCENES[ones].instantiate()
		d_ones.position = Vector3(DIGIT_X_OFFSET, 0.0, LABEL_Z)
		_fret_label.add_child(d_ones)
	else:
		var d := DIGIT_SCENES[ones].instantiate()
		d.position = Vector3(0.0, 0.0, LABEL_Z)
		_fret_label.add_child(d)


func tick(p_song_time: float) -> void:
	if not is_active:
		return

	position.z = STRUM_Z - (time_offset - p_song_time) * TRAVEL_SPEED
	_update_hit_visuals(p_song_time)

	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD_SECS
		_miss_label.visible = true

	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


func deactivate() -> void:
	is_active    = false
	visible      = false
	_miss_label.visible = false
	_miss_until  = -1.0
	_hit_fx_start = -1.0
	var pool := get_parent()
	if pool and pool.has_method("return_note"):
		pool.return_note(self)


func _update_indicator_geometry(fret_num: int) -> void:
	if _finger == null:
		return
	var sz2: Vector2 = ChartCommon.note_indicator_size(fret_num)
	_finger.mesh = _build_trapezoid_mesh(sz2, BOX_DEPTH)
	_resize_border_segments(sz2)


func _ensure_border_segments() -> void:
	if _border_root == null or not _border_segments.is_empty():
		return
	for _i in range(8):
		var seg := MeshInstance3D.new()
		seg.mesh = BoxMesh.new()
		seg.set_surface_override_material(0, _border_mat)
		_border_root.add_child(seg)
		_border_segments.append(seg)
	for _i in range(4):
		var edge := MeshInstance3D.new()
		edge.mesh = BoxMesh.new()
		edge.set_surface_override_material(0, _border_mat)
		_border_root.add_child(edge)
		_border_segments.append(edge)


func _resize_border_segments(size_xy: Vector2) -> void:
	if _border_root == null:
		return
	_ensure_border_segments()
	var thickness: float = clampf(minf(size_xy.x, size_xy.y) * BORDER_THICKNESS_RATIO, 0.008, 0.03)
	var side_h: float = maxf(size_xy.y - thickness * 2.0, thickness)
	var hz: float = BOX_DEPTH * 0.5
	var half_back_w: float = size_xy.x * 0.5
	var half_front_w: float = half_back_w * TRAPEZOID_FRONT_RATIO
	var half_h: float = size_xy.y * 0.5
	var front_w: float = half_front_w * 2.0
	var back_w: float = half_back_w * 2.0

	_set_segment(_border_segments[0], Vector3(front_w, thickness, thickness), Vector3(0.0, half_h - thickness * 0.5, hz))
	_set_segment(_border_segments[1], Vector3(front_w, thickness, thickness), Vector3(0.0, -half_h + thickness * 0.5, hz))
	_set_segment(_border_segments[2], Vector3(thickness, side_h, thickness), Vector3(-half_front_w + thickness * 0.5, 0.0, hz))
	_set_segment(_border_segments[3], Vector3(thickness, side_h, thickness), Vector3(half_front_w - thickness * 0.5, 0.0, hz))

	_set_segment(_border_segments[4], Vector3(back_w, thickness, thickness), Vector3(0.0, half_h - thickness * 0.5, -hz))
	_set_segment(_border_segments[5], Vector3(back_w, thickness, thickness), Vector3(0.0, -half_h + thickness * 0.5, -hz))
	_set_segment(_border_segments[6], Vector3(thickness, side_h, thickness), Vector3(-half_back_w + thickness * 0.5, 0.0, -hz))
	_set_segment(_border_segments[7], Vector3(thickness, side_h, thickness), Vector3(half_back_w - thickness * 0.5, 0.0, -hz))

	_set_edge_segment(_border_segments[8], Vector3(-half_front_w, half_h, hz), Vector3(-half_back_w, half_h, -hz), thickness)
	_set_edge_segment(_border_segments[9], Vector3(half_front_w, half_h, hz), Vector3(half_back_w, half_h, -hz), thickness)
	_set_edge_segment(_border_segments[10], Vector3(-half_front_w, -half_h, hz), Vector3(-half_back_w, -half_h, -hz), thickness)
	_set_edge_segment(_border_segments[11], Vector3(half_front_w, -half_h, hz), Vector3(half_back_w, -half_h, -hz), thickness)


func _set_segment(seg: MeshInstance3D, seg_size: Vector3, seg_pos: Vector3) -> void:
	var mesh := seg.mesh as BoxMesh
	if mesh:
		mesh.size = seg_size
	seg.position = seg_pos
	seg.basis = Basis.IDENTITY


func _set_edge_segment(seg: MeshInstance3D, from_pt: Vector3, to_pt: Vector3, thickness: float) -> void:
	var mesh := seg.mesh as BoxMesh
	if mesh:
		mesh.size = Vector3(thickness, thickness, from_pt.distance_to(to_pt))
	seg.position = (from_pt + to_pt) * 0.5
	seg.look_at(to_pt, Vector3.UP, true)


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


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _update_hit_visuals(song_time: float) -> void:
	var lead: float = time_offset - song_time
	if _hit_fx_start < 0.0:
		if lead <= 0.0:
			_hit_fx_start = song_time
			lead = 0.0
		var fill_alpha: float = 0.85
		var border_alpha: float = 0.95
		var emit_energy: float = 1.0
		if lead <= APPROACH_FADE_SECS:
			var ramp: float = clampf((APPROACH_FADE_SECS - lead) / APPROACH_FADE_SECS, 0.0, 1.0)
			fill_alpha = 0.0
			border_alpha = lerpf(0.95, 1.0, ramp)
			emit_energy = lerpf(1.0, 1.6, ramp)
		_update_indicator_visuals(fill_alpha, border_alpha, emit_energy, 1.0)
		return

	var t: float = clampf((song_time - _hit_fx_start) / HIT_FLASH_SECS, 0.0, 1.0)
	var fade: float = 1.0 - t
	var pulse: float = sin(t * PI)
	var scale_boost: float = 1.0 + pulse * 0.2
	_update_indicator_visuals(fade, fade, lerpf(3.5, 0.0, t), scale_boost)


func _update_indicator_visuals(fill_alpha: float, border_alpha: float, emission_energy: float, scale_mul: float) -> void:
	if _fill_mat:
		var fill_col := _indicator_color
		fill_col.a = clampf(fill_alpha, 0.0, 1.0)
		_fill_mat.albedo_color = fill_col
		_fill_mat.emission = _indicator_color
		_fill_mat.emission_energy_multiplier = maxf(0.0, emission_energy)
	if _border_mat:
		var edge_col := _indicator_color.lightened(0.25)
		edge_col.a = clampf(border_alpha, 0.0, 1.0)
		_border_mat.albedo_color = edge_col
		_border_mat.emission = _indicator_color.lightened(0.2)
		_border_mat.emission_energy_multiplier = maxf(0.0, emission_energy * 0.8)
	if _finger:
		_finger.scale = Vector3.ONE * scale_mul
	if _border_root:
		_border_root.scale = Vector3.ONE * scale_mul
