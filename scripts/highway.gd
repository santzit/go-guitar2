extends Node3D
## highway.gd  –  runtime configuration for the Highway surface.
## The visual geometry and material are defined in highway.tscn / highway.gdshader.

const LANE_COUNT : int = 6
const TRAVEL_SPEED : float = 2.0
const HIGHWAY_Z_MIN : float = -20.0
const HIGHWAY_Z_MAX : float = 0.0
const FRET_GLOW_MAP_HEIGHT : int = 256
const APPROACH_WINDOW_SECS : float = 1.5
const HIT_WINDOW_SECS : float = 0.08
const SUSTAIN_KEEP_SECS : float = 0.05
const SUSTAIN_MIN_SECS : float = 0.05

@onready var _surface: MeshInstance3D = $HighwaySurface

var _fret_count: int = 24
var _glow_image: Image = null
var _glow_texture: ImageTexture = null
var _glow_map_width: int = 0


func _ready() -> void:
	set_lane_intensities(_zero_lanes())
	set_active_fret_range(0, -1)
	_init_fret_glow_map()


## Reconfigure fret/string counts at runtime (e.g. for different tunings).
func configure(fret_count: int, string_count: int) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if mat:
		_fret_count = max(1, fret_count)
		mat.set_shader_parameter("fret_count",   fret_count)
		mat.set_shader_parameter("string_count", string_count)
	_init_fret_glow_map()


func set_lane_intensities(values: Array[float]) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if not mat:
		return
	if values.size() < LANE_COUNT:
		push_warning("Highway: expected %d lane intensities, got %d" % [LANE_COUNT, values.size()])
		return
	# Keep this packing in sync with shaders/highway.gdshader lane_intensity().
	mat.set_shader_parameter("lane_intensity_0_3", Vector4(
		clampf(values[0], 0.0, 1.0),
		clampf(values[1], 0.0, 1.0),
		clampf(values[2], 0.0, 1.0),
		clampf(values[3], 0.0, 1.0)
	))
	mat.set_shader_parameter("lane_intensity_4_5", Vector2(
		clampf(values[4], 0.0, 1.0),
		clampf(values[5], 0.0, 1.0)
	))


func set_active_fret_range(min_fret: int, max_fret: int) -> void:
	if not _surface:
		return
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if not mat:
		return
	mat.set_shader_parameter("active_fret_min", min_fret)
	mat.set_shader_parameter("active_fret_max", max_fret)


func _zero_lanes() -> Array[float]:
	var values: Array[float] = []
	values.resize(LANE_COUNT)
	for i in LANE_COUNT:
		values[i] = 0.0
	return values


func update_fret_glow_map(
		notes: Array,
		song_time: float,
		start_index: int = 0,
		hand_window_start: int = -1,
		hand_window_end: int = -1
) -> void:
	if _glow_image == null or _glow_texture == null or _glow_map_width <= 0:
		return

	var sample_count: int = _glow_map_width * FRET_GLOW_MAP_HEIGHT
	# R channel: note-start / head-bump glow (bright flash).
	var accum_r := PackedFloat32Array()
	accum_r.resize(sample_count)
	for i in sample_count:
		accum_r[i] = 0.0
	# G channel: sustain glow (soft, dimmer).
	var accum_g := PackedFloat32Array()
	accum_g.resize(sample_count)
	for i in sample_count:
		accum_g[i] = 0.0

	var note_idx: int = maxi(start_index, 0)
	while note_idx < notes.size():
		var nd: Dictionary = notes[note_idx]
		if not nd.has("time"):
			note_idx += 1
			continue
		var note_time: float = float(nd.get("time", -1.0))
		var duration: float = maxf(float(nd.get("duration", 0.0)), 0.0)
		var sustain_end: float = note_time + duration
		if note_time > song_time + APPROACH_WINDOW_SECS:
			break
		if sustain_end < song_time - SUSTAIN_KEEP_SECS:
			note_idx += 1
			continue

		var fret: int = int(nd.get("fret", 0))
		if fret < 1 or fret > _fret_count:
			note_idx += 1
			continue

		var left_boundary: int = clampi(fret - 1, 0, _fret_count)
		var right_boundary: int = clampi(fret, 0, _fret_count)

		var dt: float = note_time - song_time
		var peak: float = 0.15
		if dt >= 0.0 and dt <= APPROACH_WINDOW_SECS:
			peak = lerpf(0.15, 0.55, 1.0 - dt / APPROACH_WINDOW_SECS)
		if absf(dt) <= HIT_WINDOW_SECS:
			peak = 1.0

		# Note-start head bump → R channel (bright).
		_add_head_bump(accum_r, left_boundary, note_time, song_time, peak)
		_add_head_bump(accum_r, right_boundary, note_time, song_time, peak)

		# Sustain segment → G channel (dim).
		if duration >= SUSTAIN_MIN_SECS:
			_add_sustain_segment(accum_g, left_boundary, note_time, sustain_end, song_time)
			_add_sustain_segment(accum_g, right_boundary, note_time, sustain_end, song_time)

		note_idx += 1

	if hand_window_start >= 0 and hand_window_end >= hand_window_start:
		var start_boundary: int = clampi(hand_window_start, 0, _fret_count)
		var end_boundary: int = clampi(hand_window_end, 0, _fret_count)
		_add_window_boundary_glow(accum_r, start_boundary, 0.45)
		_add_window_boundary_glow(accum_r, end_boundary, 0.45)

	# Pack as RG8: 2 bytes per pixel (R = note-start, G = sustain).
	var packed := PackedByteArray()
	packed.resize(sample_count * 2)
	for i in sample_count:
		packed[i * 2]     = int(clampf(accum_r[i], 0.0, 1.0) * 255.0)
		packed[i * 2 + 1] = int(clampf(accum_g[i], 0.0, 1.0) * 255.0)

	_glow_image.set_data(_glow_map_width, FRET_GLOW_MAP_HEIGHT, false, Image.FORMAT_RG8, packed)
	_glow_texture.update(_glow_image)


func _init_fret_glow_map() -> void:
	_glow_map_width = _fret_count + 1
	if _glow_map_width <= 0:
		return
	_glow_image = Image.create(_glow_map_width, FRET_GLOW_MAP_HEIGHT, false, Image.FORMAT_RG8)
	_glow_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	if _glow_texture == null:
		_glow_texture = ImageTexture.create_from_image(_glow_image)
	else:
		_glow_texture.update(_glow_image)
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if mat and _glow_texture:
		mat.set_shader_parameter("fret_glow_map", _glow_texture)


func _add_head_bump(
		accum: PackedFloat32Array,
		boundary_idx: int,
		note_time: float,
		song_time: float,
		peak: float
) -> void:
	var z: float = _note_time_to_world_z(note_time, song_time)
	var center: int = _z_to_row(z)
	if center < 0:
		return
	const RADIUS: int = 10
	for offset in range(-RADIUS, RADIUS + 1):
		var row: int = center + offset
		if row < 0 or row >= FRET_GLOW_MAP_HEIGHT:
			continue
		var t: float = float(offset) / float(RADIUS)
		var intensity: float = peak * exp(-3.0 * t * t)
		_accumulate_sample(accum, boundary_idx, row, intensity)


func _add_sustain_segment(
		accum: PackedFloat32Array,
		boundary_idx: int,
		start_time: float,
		end_time: float,
		song_time: float
) -> void:
	var z_start: float = _note_time_to_world_z(start_time, song_time)
	var z_end: float = _note_time_to_world_z(end_time, song_time)
	var row_start: int = _z_to_row_clamped(z_start)
	var row_end: int = _z_to_row_clamped(z_end)
	var row_min: int = mini(row_start, row_end)
	var row_max: int = maxi(row_start, row_end)
	var span: int = maxi(1, row_max - row_min)
	for row in range(row_min, row_max + 1):
		var head_mix: float = 1.0 - float(row - row_min) / float(span)
		var intensity: float = 0.28 + head_mix * 0.22
		_accumulate_sample(accum, boundary_idx, row, intensity)


func _add_window_boundary_glow(
		accum: PackedFloat32Array,
		boundary_idx: int,
		intensity: float
) -> void:
	for row in FRET_GLOW_MAP_HEIGHT:
		_accumulate_sample(accum, boundary_idx, row, intensity)


func _accumulate_sample(
		accum: PackedFloat32Array,
		boundary_idx: int,
		row: int,
		value: float
) -> void:
	if boundary_idx < 0 or boundary_idx >= _glow_map_width:
		return
	if row < 0 or row >= FRET_GLOW_MAP_HEIGHT:
		return
	var idx: int = row * _glow_map_width + boundary_idx
	accum[idx] = maxf(accum[idx], value)


func _note_time_to_world_z(note_time: float, song_time: float) -> float:
	# Future notes (note_time > song_time) move toward negative Z on the highway.
	# Hit line is z=0, far end is z=-20.
	return (song_time - note_time) * TRAVEL_SPEED


func _z_to_row(z: float) -> int:
	if z < HIGHWAY_Z_MIN or z > HIGHWAY_Z_MAX:
		return -1
	return _z_to_row_clamped(z)


func _z_to_row_clamped(z: float) -> int:
	var t: float = inverse_lerp(HIGHWAY_Z_MIN, HIGHWAY_Z_MAX, clampf(z, HIGHWAY_Z_MIN, HIGHWAY_Z_MAX))
	return int(round(t * float(FRET_GLOW_MAP_HEIGHT - 1)))
