extends Node3D
## highway.gd  –  runtime configuration for the Highway surface.
## The visual geometry and material are defined in highway.tscn / highway.gdshader.

const LANE_COUNT : int = 6
const TRAVEL_SPEED : float = 2.0
const HIGHWAY_Z_MIN : float = -20.0
const HIGHWAY_Z_MAX : float = 0.0
## Dim full-line sustain glow intensity for hand-window boundaries.
const HAND_WINDOW_GLOW : float = 0.1
## Boundaries with an active note mark above this threshold won't be overridden.
const HAND_WINDOW_PEAK_THRESHOLD : float = 0.01
## Glow mark follows the note for its entire visible journey on the highway.
## Must match music_play.gd LEAD_TIME (HIGHWAY_DEPTH / TRAVEL_SPEED = 10.0 s).
const APPROACH_WINDOW_SECS : float = 10.0
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


## Update the 1D fret-glow texture each frame.
## Each of the (fret_count+1) columns stores RGBA8 data for one separator line:
##   R = note-start peak intensity   [0..1]
##   G = note-head UV.y position     [0=far end, 1=strum line]
##   B = sustain peak intensity      [0..1]
##   A = sustain-tail UV.y position  [0..1, ≤ G]
## The shader reads G to place a Gaussian mark at the note's current UV.y position,
## completely sidestepping any row-to-UV.y mapping ambiguity.
func update_fret_glow_map(
		notes: Array,
		song_time: float,
		start_index: int = 0,
		hand_window_start: int = -1,
		hand_window_end: int = -1
) -> void:
	if _glow_image == null or _glow_texture == null or _glow_map_width <= 0:
		return

	# Per-boundary arrays: best (highest-peak) note for each of the 25 columns.
	var peaks     := PackedFloat32Array()
	var note_ys   := PackedFloat32Array()
	var sus_peaks := PackedFloat32Array()
	var sus_ys    := PackedFloat32Array()
	peaks.resize(_glow_map_width)
	note_ys.resize(_glow_map_width)
	sus_peaks.resize(_glow_map_width)
	sus_ys.resize(_glow_map_width)
	for b in _glow_map_width:
		peaks[b]     = 0.0
		note_ys[b]   = 0.5   # default centre (unused when peak = 0)
		sus_peaks[b] = 0.0
		sus_ys[b]    = 0.0

	var note_idx: int = maxi(start_index, 0)
	while note_idx < notes.size():
		var nd: Dictionary = notes[note_idx]
		if not nd.has("time"):
			note_idx += 1
			continue
		var note_time: float    = float(nd.get("time", -1.0))
		var duration: float     = maxf(float(nd.get("duration", 0.0)), 0.0)
		var sustain_end: float  = note_time + duration
		if note_time > song_time + APPROACH_WINDOW_SECS:
			break
		if sustain_end < song_time - SUSTAIN_KEEP_SECS:
			note_idx += 1
			continue

		var fret: int = int(nd.get("fret", 0))
		if fret < 1 or fret > _fret_count:
			note_idx += 1
			continue

		# Note-start peak: ramps from dim (0.1) at max approach to bright (0.65)
		# at the strum line, then snaps to 1.0 inside the hit window.
		# Notes outside the approach window never reach this code (loop breaks above),
		# so peak stays 0.0 for any note that has already passed without being hit.
		var dt: float = note_time - song_time
		var peak: float = 0.0
		if dt >= 0.0 and dt <= APPROACH_WINDOW_SECS:
			peak = lerpf(0.1, 0.65, 1.0 - dt / APPROACH_WINDOW_SECS)
		if absf(dt) <= HIT_WINDOW_SECS:
			peak = 1.0

		# UV.y of note head: (z + 20) / 20, where z = world Z = (song_time - note_time) * speed.
		# UV.y = 0 at far end (Z = -20), UV.y = 1 at strum (Z = 0) — matches PlaneMesh UV.
		var z: float = _note_time_to_world_z(note_time, song_time)
		var uv_y: float = clampf((z - HIGHWAY_Z_MIN) / (HIGHWAY_Z_MAX - HIGHWAY_Z_MIN), 0.0, 1.0)

		# UV.y of sustain tail (always <= uv_y since the tail is further from the strum).
		var sus_uv_y: float = 0.0
		var sus_peak: float = 0.0
		if duration >= SUSTAIN_MIN_SECS:
			var z_end: float = _note_time_to_world_z(sustain_end, song_time)
			sus_uv_y = clampf((z_end - HIGHWAY_Z_MIN) / (HIGHWAY_Z_MAX - HIGHWAY_Z_MIN), 0.0, 1.0)
			sus_peak = 0.5   # sustain is visibly dimmer than the note-start mark

		var left_boundary:  int = clampi(fret - 1, 0, _fret_count)
		var right_boundary: int = clampi(fret,     0, _fret_count)

		for boundary in [left_boundary, right_boundary]:
			if peak > peaks[boundary]:
				peaks[boundary]     = peak
				note_ys[boundary]   = uv_y
				sus_peaks[boundary] = sus_peak
				sus_ys[boundary]    = sus_uv_y

		note_idx += 1

	# Hand-window boundary: a constant dim glow across the full separator line.
	if hand_window_start >= 0 and hand_window_end >= hand_window_start:
		for boundary in [clampi(hand_window_start, 0, _fret_count),
						 clampi(hand_window_end,   0, _fret_count)]:
			if sus_peaks[boundary] < HAND_WINDOW_GLOW:
				sus_peaks[boundary] = HAND_WINDOW_GLOW
				# Full-line coverage: sustain from UV.y 0 to 1.
				# If no note on this boundary, set note_ys = 1.0 so the sustain
				# fill (sus_ys..note_ys) spans the whole highway depth.
				if peaks[boundary] < HAND_WINDOW_PEAK_THRESHOLD:
					note_ys[boundary] = 1.0
				sus_ys[boundary] = 0.0

	# Pack as RGBA8 (1 row × _glow_map_width columns = 25 pixels = 100 bytes).
	var packed := PackedByteArray()
	packed.resize(_glow_map_width * 4)
	for b in _glow_map_width:
		packed[b * 4 + 0] = int(clampf(peaks[b],     0.0, 1.0) * 255.0)
		packed[b * 4 + 1] = int(clampf(note_ys[b],   0.0, 1.0) * 255.0)
		packed[b * 4 + 2] = int(clampf(sus_peaks[b], 0.0, 1.0) * 255.0)
		packed[b * 4 + 3] = int(clampf(sus_ys[b],    0.0, 1.0) * 255.0)

	_glow_image.set_data(_glow_map_width, 1, false, Image.FORMAT_RGBA8, packed)
	_glow_texture.update(_glow_image)


func _init_fret_glow_map() -> void:
	_glow_map_width = _fret_count + 1
	if _glow_map_width <= 0:
		return
	# 1D RGBA8 texture: one row, one column per fret boundary.
	_glow_image = Image.create(_glow_map_width, 1, false, Image.FORMAT_RGBA8)
	_glow_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	if _glow_texture == null:
		_glow_texture = ImageTexture.create_from_image(_glow_image)
	else:
		_glow_texture.update(_glow_image)
	var mat := _surface.get_surface_override_material(0) as ShaderMaterial
	if mat and _glow_texture:
		mat.set_shader_parameter("fret_glow_map", _glow_texture)


func _note_time_to_world_z(note_time: float, song_time: float) -> float:
	# Future notes (note_time > song_time) sit at negative Z (far end of highway).
	# Hit line is z = 0, far end is z = -20.
	return (song_time - note_time) * TRAVEL_SPEED
