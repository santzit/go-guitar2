extends Camera3D
class_name CameraController

const ChartCommon = preload("res://scripts/common.gd")

const FRET_COUNT         : int = ChartCommon.FRET_COUNT
const FRET_WORLD_WIDTH   : float = ChartCommon.FRET_WORLD_WIDTH
const DEFAULT_CAMERA_FRET: float = FRET_COUNT * 0.5

const CAM_FOV           : float = 60.0
const CAMERA_Y          : float = 4.0
const CAMERA_Y_MAX      : float = 6.5
const CAMERA_Z          : float = 7.0
const CAMERA_Z_MIN      : float = 6.0
const CAMERA_Z_MAX      : float = 14.5
const CAMERA_Z_SOFT_MAX : float = 11.0
const CAMERA_LOOK_AT_Z  : float = -7.0
const CAMERA_WORLD_DAMPING_RATE : float = 0.40
const CAMERA_LOOK_DAMPING_RATE  : float = 0.45
const CAMERA_FRET_DAMPING_RATE  : float = 0.85
const CAMERA_Y_DAMPING_RATE     : float = 0.45
const CAMERA_Z_DAMPING_RATE     : float = 0.24
const CAMERA_LEFT_SHIFT_DAMPING_RATE : float = 0.50
const CAMERA_EVENT_LOOKBACK : float = 0.35
const CAMERA_X_MIN      : float = 0.75
const CAMERA_X_MAX      : float = FRET_WORLD_WIDTH
const CAMERA_TARGET_FRET_MIN : float = 1.5
const CAMERA_TARGET_FRET_MAX : float = float(FRET_COUNT)
const CAMERA_POSITION_FRET_BIAS : float = 0.35
const CAMERA_FOCUS_FRET_DEADBAND  : float = 1.5
const CAMERA_LOOK_X_DEADBAND      : float = 0.35
const CAMERA_EXCESS_TO_LEFT_GAIN : float = 0.65
const CAMERA_MAX_LEFT_SHIFT : float = 2.2
const CAMERA_CHARTPLAYER_OFFSET_BLEND : float = 0.35
const CAMERA_DISTANCE_SPREAD_FREE : float = 4.0
const CAMERA_DISTANCE_MIN_SPREAD  : float = 4.0
const CAMERA_DISTANCE_PER_FRET    : float = 0.50
const CAMERA_DISTANCE_BASE        : float = 5.2
const CAMERA_SPREAD_ATTACK_RATE   : float = 0.90
const CAMERA_SPREAD_RELEASE_RATE  : float = 0.20
const CAMERA_TARGET_Y_DEADBAND    : float = 0.45
const CAMERA_LOOK_AHEAD_DEPTH     : float = 15.0
const CAMERA_LOOK_AT_Z_MIN        : float = -14.0
const CAMERA_LOOK_AT_Z_MAX        : float = -2.0
const CAMERA_Z_ATTACK_RATE        : float = 0.55
const CAMERA_Z_RELEASE_RATE       : float = 0.18
const CAMERA_Y_FROM_DEPTH_GAIN    : float = 0.18
const CAMERA_LOOKAHEAD_SECONDS    : float = 3.0
const CAMERA_LOOKAHEAD_RECENCY_TAU: float = 0.65
const CAMERA_LOOKAHEAD_BLEND_RATE : float = 0.75
const CAMERA_TARGET_BEHIND_SECONDS: float = 0.20
const CAMERA_TARGET_AHEAD_SECONDS : float = 1.60
const CAMERA_TARGET_HYSTERESIS_FRETS: float = 2.60
const CAMERA_JUMP_REANCHOR_FRETS: float = 4.5
const CAMERA_ZOOM_HYSTERESIS_FRETS: float = 2.75
const CAMERA_LOW_FRET_ZOOM_BONUS_PER_FRET: float = 0.45
const CAMERA_FRET_EDGE_BLEND      : float = 0.10
const CAMERA_LOOKAHEAD_LOOK_X_BLEND: float = 0.03
const CAMERA_MAX_YAW_DEGREES      : float = 1.0
const CAMERA_LOW_FRET_OFFSET_START: float = 1.0
const CAMERA_LOW_FRET_OFFSET_END  : float = 5.0
const CAMERA_TARGET_X_FROM_TARGET_BLEND: float = 0.75

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
var _stable_center_fret : float = DEFAULT_CAMERA_FRET
var _stable_focus_fret  : float = DEFAULT_CAMERA_FRET
var _smoothed_spread_frets : float = CAMERA_DISTANCE_MIN_SPREAD
var _lookahead_center_fret : float = DEFAULT_CAMERA_FRET
var _lookahead_span_frets  : float = CAMERA_DISTANCE_MIN_SPREAD
var _stable_zoom_span_frets: float = CAMERA_DISTANCE_MIN_SPREAD
var _smoothed_depth_target_z: float = CAMERA_Z


func reset_camera_defaults() -> void:
	_camera_position_fret = DEFAULT_CAMERA_FRET
	_camera_target_position_fret = DEFAULT_CAMERA_FRET
	_camera_target_x = clampf(_camera_x_from_fret(_camera_position_fret), CAMERA_X_MIN, CAMERA_X_MAX)
	_camera_target_look_at_x = _camera_target_x
	_camera_look_at_x = _camera_target_look_at_x
	_camera_target_y = CAMERA_Y
	_camera_target_z = CAMERA_Z
	_camera_left_shift = 0.0
	_camera_target_left_shift = 0.0
	_camera_look_at_z = CAMERA_LOOK_AT_Z
	_camera_target_look_at_z = CAMERA_LOOK_AT_Z
	_stable_center_fret = DEFAULT_CAMERA_FRET
	_stable_focus_fret = DEFAULT_CAMERA_FRET
	_smoothed_spread_frets = CAMERA_DISTANCE_MIN_SPREAD
	_lookahead_center_fret = DEFAULT_CAMERA_FRET
	_lookahead_span_frets = CAMERA_DISTANCE_MIN_SPREAD
	_stable_zoom_span_frets = CAMERA_DISTANCE_MIN_SPREAD
	_smoothed_depth_target_z = CAMERA_Z
	position.x = _camera_target_x
	position.y = _camera_target_y
	position.z = _camera_target_z
	fov = CAM_FOV
	look_at(Vector3(_camera_look_at_x, 0.0, _camera_look_at_z), Vector3.UP)


func tick_camera(events: Array, debug_strum_event_idx: int, song_time: float, lead_time: float, delta: float, max_delta: float) -> void:
	var damp_delta := minf(delta, max_delta)
	_update_camera_targets_from_visible_events(events, debug_strum_event_idx, song_time, lead_time, damp_delta)

	_camera_position_fret = _damp_float(_camera_position_fret, _camera_target_position_fret, CAMERA_FRET_DAMPING_RATE, damp_delta)
	_camera_left_shift = _damp_float(_camera_left_shift, _camera_target_left_shift, CAMERA_LEFT_SHIFT_DAMPING_RATE, damp_delta)
	var target_x_from_current: float = _camera_x_from_fret(_camera_position_fret)
	var target_x_from_target: float = _camera_x_from_fret(_camera_target_position_fret)
	var blended_target_x: float = lerpf(target_x_from_current, target_x_from_target, CAMERA_TARGET_X_FROM_TARGET_BLEND)
	_camera_target_x = clampf(blended_target_x - _camera_left_shift, CAMERA_X_MIN, CAMERA_X_MAX)
	_camera_look_at_z = _damp_float(_camera_look_at_z, _camera_target_look_at_z, CAMERA_LOOK_DAMPING_RATE, damp_delta)

	var cam_pos  := position
	cam_pos.x = _damp_float(cam_pos.x, _camera_target_x, CAMERA_WORLD_DAMPING_RATE, damp_delta)
	cam_pos.y = _damp_float(cam_pos.y, _camera_target_y, CAMERA_Y_DAMPING_RATE, damp_delta)
	cam_pos.z = _damp_float(cam_pos.z, _camera_target_z, CAMERA_Z_DAMPING_RATE, damp_delta)
	position = cam_pos
	var yaw_limited_look_x: float = _clamp_look_x_for_yaw(_camera_target_look_at_x, cam_pos.x, cam_pos.z, _camera_look_at_z)
	_camera_look_at_x = _damp_float(_camera_look_at_x, yaw_limited_look_x, CAMERA_LOOK_DAMPING_RATE, damp_delta)
	look_at(Vector3(_camera_look_at_x, 0.0, _camera_look_at_z), Vector3.UP)


func _update_camera_targets_from_visible_events(events: Array, debug_strum_event_idx: int, song_time: float, lead_time: float, damp_delta: float) -> void:
	var min_fret: float = INF
	var max_fret: float = -INF
	var has_visible_note: bool = false
	var target_focus_fret: float = DEFAULT_CAMERA_FRET
	var has_focus_fret: bool = false
	var weighted_fret_sum: float = 0.0
	var weight_sum: float = 0.0
	var lookahead_end: float = song_time + maxf(lead_time, CAMERA_LOOKAHEAD_SECONDS)
	var target_window_start: float = song_time - CAMERA_TARGET_BEHIND_SECONDS
	var target_window_end: float = song_time + minf(maxf(lead_time, CAMERA_TARGET_AHEAD_SECONDS), CAMERA_LOOKAHEAD_SECONDS)

	var i: int = debug_strum_event_idx
	while i < events.size():
		var ev: Dictionary = events[i]
		var event_time: float = float(ev.get("time_start", -1.0))
		if event_time < song_time - CAMERA_EVENT_LOOKBACK:
			i += 1
			continue
		if event_time > lookahead_end:
			break
		if not has_focus_fret and event_time > song_time:
			var hand_start: int = int(ev.get("hand_fret_start", -1))
			var hand_end: int = int(ev.get("hand_fret_end", -1))
			if hand_start >= 1 and hand_end >= hand_start:
				target_focus_fret = (float(hand_start) + float(hand_end)) * 0.5
				has_focus_fret = true
		var recency_weight: float = 0.0
		if event_time >= target_window_start and event_time <= target_window_end:
			recency_weight = exp(-(absf(event_time - song_time) / maxf(CAMERA_LOOKAHEAD_RECENCY_TAU, 0.05)))
		for n in ev.get("notes", []):
			var fret: int = int(n.get("fret", -1))
			if fret < 1 or fret > FRET_COUNT:
				continue
			var fret_f: float = float(fret)
			min_fret = minf(min_fret, float(fret))
			max_fret = maxf(max_fret, float(fret))
			if recency_weight > 0.0:
				weighted_fret_sum += fret_f * recency_weight
				weight_sum += recency_weight
			has_visible_note = true
		i += 1

	if has_visible_note:
		var raw_center_fret: float = (min_fret + max_fret) * 0.5
		var weighted_center_fret: float = (weighted_fret_sum / weight_sum) if weight_sum > 0.0 else raw_center_fret
		if weight_sum <= 0.0 and has_focus_fret:
			weighted_center_fret = target_focus_fret
		var raw_focus_fret: float = target_focus_fret if has_focus_fret else weighted_center_fret
		var lookahead_blend: float = 1.0 - pow(1.0 - CAMERA_LOOKAHEAD_BLEND_RATE, clampf(damp_delta, 0.0001, 0.2))
		_lookahead_center_fret = lerpf(_lookahead_center_fret, weighted_center_fret, lookahead_blend)
		_lookahead_span_frets = lerpf(_lookahead_span_frets, maxf(max_fret - min_fret, 1.0), lookahead_blend)

		if absf(raw_focus_fret - _stable_focus_fret) >= CAMERA_FOCUS_FRET_DEADBAND:
			_stable_focus_fret = raw_focus_fret
		var should_reanchor_jump: bool = absf(_lookahead_center_fret - _stable_center_fret) >= CAMERA_JUMP_REANCHOR_FRETS
		if should_reanchor_jump:
			_stable_center_fret = _lookahead_center_fret
			_stable_focus_fret = raw_focus_fret
		elif absf(_lookahead_center_fret - _stable_center_fret) >= CAMERA_TARGET_HYSTERESIS_FRETS:
			_stable_center_fret = _lookahead_center_fret
 
		if absf(_lookahead_span_frets - _stable_zoom_span_frets) >= CAMERA_ZOOM_HYSTERESIS_FRETS:
			_stable_zoom_span_frets = _lookahead_span_frets

		var clamped_center_fret: float = _stable_center_fret
		var low_fret_t: float = clampf((min_fret - CAMERA_LOW_FRET_OFFSET_START) / maxf(CAMERA_LOW_FRET_OFFSET_END - CAMERA_LOW_FRET_OFFSET_START, 0.001), 0.0, 1.0)
		var dynamic_bias: float = CAMERA_POSITION_FRET_BIAS * low_fret_t
		_camera_target_position_fret = clampf(clamped_center_fret, CAMERA_TARGET_FRET_MIN, CAMERA_TARGET_FRET_MAX) - dynamic_bias
		var weighted_edge_x: float = (_fret_to_world_x(1.0) * 0.6) + (_fret_to_world_x(float(FRET_COUNT)) * 0.4)
		var lookahead_look_x: float = lerpf(_fret_to_world_x(_lookahead_center_fret), weighted_edge_x, CAMERA_FRET_EDGE_BLEND)
		var expected_cam_x: float = clampf(_camera_x_from_fret(_camera_target_position_fret) - _camera_target_left_shift, CAMERA_X_MIN, CAMERA_X_MAX)
		var desired_look_x: float = expected_cam_x + ((lookahead_look_x - expected_cam_x) * CAMERA_LOOKAHEAD_LOOK_X_BLEND)
		if absf(desired_look_x - _camera_target_look_at_x) >= CAMERA_LOOK_X_DEADBAND:
			_camera_target_look_at_x = desired_look_x

		var raw_fret_dist: float = maxf(_lookahead_span_frets, 0.0)
		var spread_rate: float = CAMERA_SPREAD_ATTACK_RATE if raw_fret_dist > _smoothed_spread_frets else CAMERA_SPREAD_RELEASE_RATE
		_smoothed_spread_frets = _damp_float(_smoothed_spread_frets, raw_fret_dist, spread_rate, damp_delta)
		var adjusted_fret_dist: float = maxf(_smoothed_spread_frets - CAMERA_DISTANCE_SPREAD_FREE, 0.0)
		var zoom_span: float = maxf(_stable_zoom_span_frets, CAMERA_DISTANCE_MIN_SPREAD)
		var span_driven_distance: float = CAMERA_DISTANCE_BASE + (maxf(adjusted_fret_dist, zoom_span - CAMERA_DISTANCE_MIN_SPREAD) * CAMERA_DISTANCE_PER_FRET)
		var low_fret_zoom_bonus: float = maxf(0.0, 5.0 - min_fret) * CAMERA_LOW_FRET_ZOOM_BONUS_PER_FRET
		var base_desired_z: float = CAMERA_Z + maxf(span_driven_distance - CAMERA_DISTANCE_BASE, 0.0) + low_fret_zoom_bonus
		var z_rate: float = CAMERA_Z_ATTACK_RATE if base_desired_z > _smoothed_depth_target_z else CAMERA_Z_RELEASE_RATE
		_smoothed_depth_target_z = _damp_float(_smoothed_depth_target_z, base_desired_z, z_rate, damp_delta)
		var desired_z: float = clampf(_smoothed_depth_target_z, CAMERA_Z_MIN, CAMERA_Z_MAX)
		var extra_depth: float = maxf(desired_z - CAMERA_Z_SOFT_MAX, 0.0)

		_camera_target_left_shift = minf(extra_depth * CAMERA_EXCESS_TO_LEFT_GAIN, CAMERA_MAX_LEFT_SHIFT)
		var desired_y: float = clampf(CAMERA_Y + (extra_depth * CAMERA_Y_FROM_DEPTH_GAIN), CAMERA_Y, CAMERA_Y_MAX)
		if absf(desired_y - _camera_target_y) >= CAMERA_TARGET_Y_DEADBAND:
			_camera_target_y = desired_y
		_camera_target_z = desired_z
		_camera_target_look_at_z = clampf(_camera_target_z - CAMERA_LOOK_AHEAD_DEPTH, CAMERA_LOOK_AT_Z_MIN, CAMERA_LOOK_AT_Z_MAX)
	else:
		var next_center_fret := _find_next_upcoming_center_fret(events, debug_strum_event_idx, song_time)
		if next_center_fret >= 0.0:
			_camera_target_position_fret = clampf(next_center_fret, CAMERA_TARGET_FRET_MIN, CAMERA_TARGET_FRET_MAX) - CAMERA_POSITION_FRET_BIAS
			_stable_center_fret = next_center_fret
			_stable_focus_fret = next_center_fret
			_lookahead_center_fret = next_center_fret
			_camera_target_look_at_x = _camera_x_from_fret(_camera_target_position_fret)
		else:
			_camera_target_position_fret = DEFAULT_CAMERA_FRET
			_stable_center_fret = DEFAULT_CAMERA_FRET
			_stable_focus_fret = DEFAULT_CAMERA_FRET
			_lookahead_center_fret = DEFAULT_CAMERA_FRET
			_camera_target_look_at_x = _camera_x_from_fret(DEFAULT_CAMERA_FRET)
		_camera_target_left_shift = 0.0
		_camera_target_x = clampf(_camera_x_from_fret(_camera_target_position_fret), CAMERA_X_MIN, CAMERA_X_MAX)
		_camera_target_y = CAMERA_Y
		_smoothed_depth_target_z = _damp_float(_smoothed_depth_target_z, CAMERA_Z, CAMERA_Z_RELEASE_RATE, damp_delta)
		_camera_target_z = _smoothed_depth_target_z
		_lookahead_span_frets = _damp_float(_lookahead_span_frets, CAMERA_DISTANCE_MIN_SPREAD, CAMERA_SPREAD_RELEASE_RATE, damp_delta)
		_stable_zoom_span_frets = _damp_float(_stable_zoom_span_frets, CAMERA_DISTANCE_MIN_SPREAD, CAMERA_SPREAD_RELEASE_RATE, damp_delta)
		_camera_target_look_at_z = clampf(CAMERA_Z - CAMERA_LOOK_AHEAD_DEPTH, CAMERA_LOOK_AT_Z_MIN, CAMERA_LOOK_AT_Z_MAX)


func _fret_to_world_x(fret_num: float) -> float:
	return ChartCommon.chart_fret_pos(fret_num) - (ChartCommon.FRET_SPACING * 0.5)


func _camera_x_from_fret(position_fret: float) -> float:
	var fret_offset: float = (10.0 - position_fret) / 4.0
	var low_fret_t: float = clampf((position_fret - CAMERA_LOW_FRET_OFFSET_START) / maxf(CAMERA_LOW_FRET_OFFSET_END - CAMERA_LOW_FRET_OFFSET_START, 0.001), 0.0, 1.0)
	var offset_blend: float = CAMERA_CHARTPLAYER_OFFSET_BLEND * low_fret_t
	return _fret_to_world_x(position_fret + (fret_offset * offset_blend))


func _clamp_look_x_for_yaw(target_look_x: float, cam_x: float, cam_z: float, look_z: float) -> float:
	var depth_to_look: float = maxf(absf(cam_z - look_z), 0.001)
	var max_dx: float = tan(deg_to_rad(CAMERA_MAX_YAW_DEGREES)) * depth_to_look
	return clampf(target_look_x, cam_x - max_dx, cam_x + max_dx)


func _find_next_upcoming_center_fret(events: Array, start_idx: int, song_time: float) -> float:
	for i in range(maxi(start_idx, 0), events.size()):
		var ev: Dictionary = events[i]
		var event_time: float = float(ev.get("time_start", -1.0))
		if event_time <= song_time:
			continue

		var min_fret: float = INF
		var max_fret: float = -INF
		for n in ev.get("notes", []):
			var fret: int = int(n.get("fret", -1))
			if fret < 1 or fret > FRET_COUNT:
				continue
			min_fret = minf(min_fret, float(fret))
			max_fret = maxf(max_fret, float(fret))

		if min_fret != INF and max_fret != -INF:
			return (min_fret + max_fret) * 0.5

		var hand_start: int = int(ev.get("hand_fret_start", -1))
		var hand_end: int = int(ev.get("hand_fret_end", -1))
		if hand_start >= 1 and hand_end >= hand_start:
			return (float(hand_start) + float(hand_end)) * 0.5

	return -1.0


func _damp_float(from_value: float, target: float, rate: float, delta: float) -> float:
	var blend: float = 1.0 - exp(-maxf(rate, 0.001) * delta)
	return lerpf(from_value, target, blend)
