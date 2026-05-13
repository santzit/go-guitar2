extends Camera3D
class_name CameraController

const ChartCommon = preload("res://scripts/common.gd")

const FRET_COUNT         : int = ChartCommon.FRET_COUNT
const FRET_WORLD_WIDTH   : float = ChartCommon.FRET_WORLD_WIDTH
const DEFAULT_CAMERA_FRET: float = FRET_COUNT * 0.5

const CAM_FOV           : float = 60.0
const CAMERA_Y          : float = 4.0
const CAMERA_Y_MAX      : float = 6.5
const CAMERA_Z          : float = 8.0
const CAMERA_Z_MIN      : float = 6.0
const CAMERA_Z_MAX      : float = 18.0
const CAMERA_Z_SOFT_MAX : float = 13.5
const CAMERA_LOOK_AT_Z  : float = -7.0
const CAMERA_WORLD_DAMPING_RATE : float = 0.55
const CAMERA_LOOK_DAMPING_RATE  : float = 0.45
const CAMERA_FRET_DAMPING_RATE  : float = 0.60
const CAMERA_Y_DAMPING_RATE     : float = 0.45
const CAMERA_Z_DAMPING_RATE     : float = 0.40
const CAMERA_LEFT_SHIFT_DAMPING_RATE : float = 0.50
const CAMERA_EVENT_LOOKBACK : float = 0.35
const CAMERA_FRAME_PADDING : float = 1.45
const CAMERA_X_MIN      : float = 1.75
const CAMERA_X_MAX      : float = FRET_WORLD_WIDTH
const CAMERA_TARGET_FRET_MIN : float = 3.5
const CAMERA_TARGET_FRET_MAX : float = float(FRET_COUNT)
const CAMERA_FOCUS_CLAMP_BEHIND : float = 3.0
const CAMERA_FOCUS_CLAMP_AHEAD  : float = 5.0
const CAMERA_POSITION_FRET_BIAS : float = 1.0
const CAMERA_FOCUS_UPDATE_INTERVAL : float = 0.50
const CAMERA_FOCUS_FRET_DEADBAND  : float = 1.5
const CAMERA_LOOK_X_DEADBAND      : float = 0.9
const CAMERA_EXCESS_TO_Y_GAIN : float = 0.45
const CAMERA_EXCESS_TO_LEFT_GAIN : float = 0.65
const CAMERA_MAX_LEFT_SHIFT : float = 4.5
const CAMERA_CHARTPLAYER_OFFSET_BLEND : float = 0.35
const CAMERA_DISTANCE_SPREAD_FREE : float = 12.0
const CAMERA_DISTANCE_MIN_SPREAD  : float = 4.0
const CAMERA_DISTANCE_PER_FRET    : float = 0.42
const CAMERA_DISTANCE_BASE        : float = 6.4
const CAMERA_SPREAD_ATTACK_RATE   : float = 0.9
const CAMERA_SPREAD_RELEASE_RATE  : float = 0.25
const CAMERA_TARGET_Z_DEADBAND    : float = 1.2
const CAMERA_TARGET_Y_DEADBAND    : float = 0.45
const CAMERA_LOOK_AHEAD_DEPTH     : float = 15.0
const CAMERA_LOOK_AT_Z_MIN        : float = -14.0
const CAMERA_LOOK_AT_Z_MAX        : float = -2.0

var _camera_target_x    : float = 0.0
var _camera_target_y    : float = CAMERA_Y
var _camera_target_z    : float = CAMERA_Z
var _camera_position_fret : float = DEFAULT_CAMERA_FRET
var _camera_target_position_fret : float = DEFAULT_CAMERA_FRET
var _camera_left_shift   : float = 0.0
var _camera_target_left_shift : float = 0.0
var _camera_look_at_x   : float = 0.0
var _camera_target_look_at_x : float = 0.0
var _camera_look_at_z   : float = CAMERA_LOOK_AT_Z
var _camera_target_look_at_z: float = CAMERA_LOOK_AT_Z
var _focus_update_timer : float = 0.0
var _stable_center_fret : float = DEFAULT_CAMERA_FRET
var _stable_focus_fret  : float = DEFAULT_CAMERA_FRET
var _smoothed_spread_frets : float = CAMERA_DISTANCE_MIN_SPREAD


func reset_camera_defaults() -> void:
	_camera_position_fret = DEFAULT_CAMERA_FRET
	_camera_target_position_fret = DEFAULT_CAMERA_FRET
	_camera_target_x = clampf(_camera_x_from_fret(_camera_position_fret), CAMERA_X_MIN, CAMERA_X_MAX)
	_camera_target_look_at_x = _fret_to_world_x(DEFAULT_CAMERA_FRET)
	_camera_look_at_x = _camera_target_look_at_x
	_camera_target_y = CAMERA_Y
	_camera_target_z = CAMERA_Z
	_camera_left_shift = 0.0
	_camera_target_left_shift = 0.0
	_camera_look_at_z = CAMERA_LOOK_AT_Z
	_camera_target_look_at_z = CAMERA_LOOK_AT_Z
	_focus_update_timer = 0.0
	_stable_center_fret = DEFAULT_CAMERA_FRET
	_stable_focus_fret = DEFAULT_CAMERA_FRET
	_smoothed_spread_frets = CAMERA_DISTANCE_MIN_SPREAD
	position.x = _camera_target_x
	position.y = _camera_target_y
	position.z = _camera_target_z
	fov = CAM_FOV
	look_at(Vector3(_camera_look_at_x, 0.0, _camera_look_at_z), Vector3.UP)


func tick_camera(events: Array, debug_strum_event_idx: int, song_time: float, lead_time: float, delta: float, max_delta: float) -> void:
	var damp_delta := minf(delta, max_delta)
	_focus_update_timer -= damp_delta
	_update_camera_targets_from_visible_events(events, debug_strum_event_idx, song_time, lead_time, damp_delta)

	_camera_position_fret = _damp_float(_camera_position_fret, _camera_target_position_fret, CAMERA_FRET_DAMPING_RATE, damp_delta)
	_camera_left_shift = _damp_float(_camera_left_shift, _camera_target_left_shift, CAMERA_LEFT_SHIFT_DAMPING_RATE, damp_delta)
	_camera_target_x = clampf(_camera_x_from_fret(_camera_position_fret) - _camera_left_shift, CAMERA_X_MIN, CAMERA_X_MAX)
	_camera_look_at_x = _damp_float(_camera_look_at_x, _camera_target_look_at_x, CAMERA_LOOK_DAMPING_RATE, damp_delta)
	_camera_look_at_z = _damp_float(_camera_look_at_z, _camera_target_look_at_z, CAMERA_LOOK_DAMPING_RATE, damp_delta)

	var cam_pos  := position
	cam_pos.x = _damp_float(cam_pos.x, _camera_target_x, CAMERA_WORLD_DAMPING_RATE, damp_delta)
	cam_pos.y = _damp_float(cam_pos.y, _camera_target_y, CAMERA_Y_DAMPING_RATE, damp_delta)
	cam_pos.z = _damp_float(cam_pos.z, _camera_target_z, CAMERA_Z_DAMPING_RATE, damp_delta)
	position = cam_pos
	look_at(Vector3(_camera_look_at_x, 0.0, _camera_look_at_z), Vector3.UP)


func _update_camera_targets_from_visible_events(events: Array, debug_strum_event_idx: int, song_time: float, lead_time: float, damp_delta: float) -> void:
	var min_x: float = INF
	var max_x: float = -INF
	var min_fret: float = INF
	var max_fret: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	var has_visible_note: bool = false
	var target_focus_fret: float = DEFAULT_CAMERA_FRET
	var has_focus_fret: bool = false

	var i: int = debug_strum_event_idx
	while i < events.size():
		var ev: Dictionary = events[i]
		var event_time: float = float(ev.get("time_start", -1.0))
		if event_time < song_time - CAMERA_EVENT_LOOKBACK:
			i += 1
			continue
		if event_time > song_time + lead_time:
			break
		if not has_focus_fret and event_time > song_time:
			var hand_start: int = int(ev.get("hand_fret_start", -1))
			var hand_end: int = int(ev.get("hand_fret_end", -1))
			if hand_start >= 1 and hand_end >= hand_start:
				target_focus_fret = (float(hand_start) + float(hand_end)) * 0.5
				has_focus_fret = true
		for n in ev.get("notes", []):
			var fret: int = int(n.get("fret", -1))
			if fret < 1 or fret > FRET_COUNT:
				continue
			min_fret = minf(min_fret, float(fret))
			max_fret = maxf(max_fret, float(fret))
			var note_x: float = ChartCommon.fret_mid_world_x(fret - 1)
			var note_z: float = ChartCommon.note_world_z(event_time, song_time, 0.0)
			min_x = minf(min_x, note_x)
			max_x = maxf(max_x, note_x)
			min_z = minf(min_z, note_z)
			max_z = maxf(max_z, note_z)
			has_visible_note = true
		i += 1

	if has_visible_note:
		var raw_center_fret: float = (min_fret + max_fret) * 0.5
		var raw_focus_fret: float = target_focus_fret if has_focus_fret else raw_center_fret

		if _focus_update_timer <= 0.0:
			_focus_update_timer = CAMERA_FOCUS_UPDATE_INTERVAL
			if absf(raw_focus_fret - _stable_focus_fret) >= CAMERA_FOCUS_FRET_DEADBAND:
				_stable_focus_fret = raw_focus_fret
			if absf(raw_center_fret - _stable_center_fret) >= CAMERA_FOCUS_FRET_DEADBAND:
				_stable_center_fret = raw_center_fret

		var clamped_center_fret: float = clampf(_stable_center_fret, _stable_focus_fret - CAMERA_FOCUS_CLAMP_BEHIND, _stable_focus_fret + CAMERA_FOCUS_CLAMP_AHEAD)
		_camera_target_position_fret = clampf(clamped_center_fret, CAMERA_TARGET_FRET_MIN, CAMERA_TARGET_FRET_MAX) - CAMERA_POSITION_FRET_BIAS
		var desired_look_x: float = _fret_to_world_x(_stable_center_fret)
		if absf(desired_look_x - _camera_target_look_at_x) >= CAMERA_LOOK_X_DEADBAND:
			_camera_target_look_at_x = desired_look_x

		var raw_fret_dist: float = maxf(max_fret - min_fret, 0.0)
		var spread_rate: float = CAMERA_SPREAD_ATTACK_RATE if raw_fret_dist > _smoothed_spread_frets else CAMERA_SPREAD_RELEASE_RATE
		_smoothed_spread_frets = _damp_float(_smoothed_spread_frets, raw_fret_dist, spread_rate, damp_delta)
		var adjusted_fret_dist: float = maxf(_smoothed_spread_frets - CAMERA_DISTANCE_SPREAD_FREE, 0.0)
		var chartplayer_distance: float = CAMERA_DISTANCE_BASE + (maxf(adjusted_fret_dist, CAMERA_DISTANCE_MIN_SPREAD) * CAMERA_DISTANCE_PER_FRET)
		var half_x: float = maxf((max_x - min_x) * 0.5 * CAMERA_FRAME_PADDING, 0.5)
		var half_z: float = maxf((max_z - min_z) * 0.5 * CAMERA_FRAME_PADDING, 0.5)
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
		var vfov: float = deg_to_rad(CAM_FOV)
		var hfov: float = 2.0 * atan(tan(vfov * 0.5) * aspect)
		var distance_for_x: float = half_x / maxf(tan(hfov * 0.5), 0.001)
		var distance_for_z: float = half_z / maxf(tan(vfov * 0.5), 0.001)
		var required_distance: float = maxf(maxf(distance_for_x, distance_for_z), chartplayer_distance)
		var spread_driven_depth: float = maxf(required_distance - CAMERA_DISTANCE_BASE, 0.0)
		var base_desired_z: float = CAMERA_Z + spread_driven_depth
		var extra_depth: float = maxf(base_desired_z - CAMERA_Z_SOFT_MAX, 0.0)

		_camera_target_left_shift = minf(extra_depth * CAMERA_EXCESS_TO_LEFT_GAIN, CAMERA_MAX_LEFT_SHIFT)
		var desired_y: float = clampf(CAMERA_Y + (extra_depth * CAMERA_EXCESS_TO_Y_GAIN), CAMERA_Y, CAMERA_Y_MAX)
		var desired_z: float = clampf(base_desired_z, CAMERA_Z_MIN, CAMERA_Z_MAX)
		if absf(desired_y - _camera_target_y) >= CAMERA_TARGET_Y_DEADBAND:
			_camera_target_y = desired_y
		if absf(desired_z - _camera_target_z) >= CAMERA_TARGET_Z_DEADBAND:
			_camera_target_z = desired_z
		_camera_target_look_at_z = clampf(_camera_target_z - CAMERA_LOOK_AHEAD_DEPTH, CAMERA_LOOK_AT_Z_MIN, CAMERA_LOOK_AT_Z_MAX)
	else:
		_camera_target_position_fret = DEFAULT_CAMERA_FRET
		_stable_center_fret = DEFAULT_CAMERA_FRET
		_stable_focus_fret = DEFAULT_CAMERA_FRET
		_camera_target_look_at_x = _fret_to_world_x(DEFAULT_CAMERA_FRET)
		_camera_target_left_shift = 0.0
		_camera_target_x = clampf(_camera_x_from_fret(_camera_target_position_fret), CAMERA_X_MIN, CAMERA_X_MAX)
		_camera_target_y = CAMERA_Y
		_camera_target_z = CAMERA_Z
		_camera_target_look_at_z = clampf(CAMERA_Z - CAMERA_LOOK_AHEAD_DEPTH, CAMERA_LOOK_AT_Z_MIN, CAMERA_LOOK_AT_Z_MAX)


func _fret_to_world_x(fret_num: float) -> float:
	return ChartCommon.chart_fret_pos(fret_num) - (ChartCommon.FRET_SPACING * 0.5)


func _camera_x_from_fret(position_fret: float) -> float:
	var fret_offset: float = (10.0 - position_fret) / 4.0
	return _fret_to_world_x(position_fret + (fret_offset * CAMERA_CHARTPLAYER_OFFSET_BLEND))


func _damp_float(current: float, target: float, rate: float, delta: float) -> float:
	var blend: float = 1.0 - exp(-maxf(rate, 0.001) * delta)
	return lerpf(current, target, blend)
