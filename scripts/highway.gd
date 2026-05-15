extends Node3D
## highway.gd  –  runtime configuration for the Highway surface.
## The visual geometry and material are defined in highway.tscn / highway.gdshader.
const ChartCommon = preload("res://scripts/common.gd")

const START_Z : float = -ChartCommon.HIGHWAY_DEPTH
const STRUM_Z : float = 0.0
const BEAT_LINE_HEIGHT : float = 0.012
const BEAT_LINE_Y : float = 0.02
const BEAT_LINE_THICKNESS : float = 0.024
const BAR_LINE_THICKNESS : float = 0.080
const MAX_VISIBLE_BEAT_MARKERS : int = 128
const BEAT_TAIL_SECS : float = 0.35
const BEAT_HEAD_SECS : float = 0.20
const FRET_LABEL_Y : float = 0.08
const FRET_LABEL_Z : float = -0.75

@onready var _surface: MeshInstance3D = $HighwaySurface

var _beats : Array = []
var _first_visible_beat_idx : int = 0
var _beat_markers : Array[MeshInstance3D] = []
var _fret_labels : Array[Label3D] = []
var _beat_line_mesh : BoxMesh = null
var _beat_line_material : StandardMaterial3D = null
var _bar_line_material : StandardMaterial3D = null


func _ready() -> void:
	_ensure_marker_resources()
	_ensure_beat_marker_pool()
	_refresh_fret_labels(ChartCommon.FRET_COUNT)


## Reconfigure fret/string counts at runtime (e.g. for different tunings).
func configure(fret_count: int, _string_count: int) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fret_count",   fret_count)
	_refresh_fret_labels(fret_count)


func set_beats(beats: Array) -> void:
	_beats = beats.duplicate()
	_beats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
	)
	_first_visible_beat_idx = 0
	_hide_all_markers()


func update_beat_grid(song_time: float, lead_time: float) -> void:
	if _beats.is_empty():
		_hide_all_markers()
		return

	var visible_start: float = song_time - BEAT_TAIL_SECS
	var visible_end: float = song_time + lead_time + BEAT_HEAD_SECS
	while _first_visible_beat_idx < _beats.size():
		if float(_beats[_first_visible_beat_idx].get("time", 0.0)) >= visible_start:
			break
		_first_visible_beat_idx += 1

	var marker_idx: int = 0
	var beat_idx: int = _first_visible_beat_idx
	while beat_idx < _beats.size():
		var beat: Dictionary = _beats[beat_idx]
		var beat_time: float = float(beat.get("time", 0.0))
		if beat_time > visible_end:
			break
		if marker_idx >= _beat_markers.size():
			break

		var marker: MeshInstance3D = _beat_markers[marker_idx]
		var is_bar: bool = bool(beat.get("is_bar", int(beat.get("measure", -1)) >= 0))
		marker.material_override = _bar_line_material if is_bar else _beat_line_material
		marker.scale.z = BAR_LINE_THICKNESS if is_bar else BEAT_LINE_THICKNESS
		marker.position.z = ChartCommon.note_world_z(beat_time, song_time, STRUM_Z)
		marker.visible = true
		marker_idx += 1
		beat_idx += 1

	for i in range(marker_idx, _beat_markers.size()):
		_beat_markers[i].visible = false


func _ensure_marker_resources() -> void:
	if _beat_line_mesh == null:
		_beat_line_mesh = BoxMesh.new()
		_beat_line_mesh.size = Vector3(ChartCommon.FRET_WORLD_WIDTH, BEAT_LINE_HEIGHT, 1.0)

	if _beat_line_material == null:
		_beat_line_material = StandardMaterial3D.new()
		_beat_line_material.albedo_color = Color(1.0, 1.0, 1.0, 0.88)
		_beat_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beat_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beat_line_material.emission_enabled = true
		_beat_line_material.emission = Color(1.0, 1.0, 1.0, 1.0)
		_beat_line_material.emission_energy_multiplier = 1.3

	if _bar_line_material == null:
		_bar_line_material = StandardMaterial3D.new()
		_bar_line_material.albedo_color = Color(1.0, 1.0, 1.0, 0.98)
		_bar_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bar_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bar_line_material.emission_enabled = true
		_bar_line_material.emission = Color(1.0, 1.0, 1.0, 1.0)
		_bar_line_material.emission_energy_multiplier = 2.1


func _ensure_beat_marker_pool() -> void:
	if not _beat_markers.is_empty():
		return
	for _i in MAX_VISIBLE_BEAT_MARKERS:
		var marker := MeshInstance3D.new()
		marker.mesh = _beat_line_mesh
		marker.material_override = _beat_line_material
		marker.position = Vector3(ChartCommon.FRET_WORLD_WIDTH * 0.5, BEAT_LINE_Y, START_Z)
		marker.scale = Vector3(1.0, 1.0, BEAT_LINE_THICKNESS)
		marker.visible = false
		add_child(marker)
		_beat_markers.append(marker)


func _refresh_fret_labels(fret_count: int) -> void:
	for label in _fret_labels:
		if is_instance_valid(label):
			label.queue_free()
	_fret_labels.clear()

	for fret in _marker_frets(fret_count):
		var label := Label3D.new()
		label.text = str(fret)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.005
		label.font_size = 52
		label.modulate = Color(0.95, 0.95, 0.98, 1.0)
		label.outline_size = 10
		label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		label.position = Vector3(ChartCommon.fret_mid_world_x(fret), FRET_LABEL_Y, FRET_LABEL_Z)
		add_child(label)
		_fret_labels.append(label)


func _marker_frets(fret_count: int) -> Array[int]:
	var frets: Array[int] = []
	for fret in range(1, fret_count + 1):
		if fret == 1 or fret == 12 or (fret % 2) == 1:
			frets.append(fret)
	return frets


func _hide_all_markers() -> void:
	for marker in _beat_markers:
		marker.visible = false
