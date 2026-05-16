extends Camera3D
class_name CameraController

const ChartCommon = preload("res://scripts/common.gd")

const FRET_COUNT         : int = ChartCommon.FRET_COUNT
const FRET_WORLD_WIDTH   : float = ChartCommon.FRET_WORLD_WIDTH
const FRET_SPACING       : float = ChartCommon.FRET_SPACING
const DEFAULT_CAMERA_FRET: float = FRET_COUNT * 0.5

const CAM_FOV           : float = 60.0
const CAMERA_PITCH_DEGREES : float = 20.0
const CAMERA_LOOK_AT_Z  : float = -7.0
const CAMERA_WORLD_DAMPING_RATE : float = 0.40
const CAMERA_LOOK_DAMPING_RATE  : float = 0.45
const CAMERA_Y_DAMPING_RATE     : float = 0.45
const CAMERA_Z_DAMPING_RATE     : float = 0.24
const CAMERA_X_MIN      : float = 0.75
const CAMERA_X_MAX      : float = FRET_WORLD_WIDTH
const CAMERA_SAFE_ZONE_PADDING_X : float = FRET_SPACING * 0.75
const CAMERA_MIN_TRACK_SPAN_X    : float = FRET_SPACING
const CAMERA_DEFAULT_ZOOM_DISTANCE: float = 14.0
const CAMERA_MIN_ZOOM_DISTANCE   : float = 13.0
const CAMERA_MAX_ZOOM_DISTANCE   : float = 21.5
const CAMERA_LOOKAHEAD_SECONDS   : float = 3.0
const CAMERA_TARGET_BEHIND_SECONDS: float = 0.20
const CAMERA_TARGET_AHEAD_SECONDS : float = 1.60
const CAMERA_MAX_YAW_DEGREES      : float = 1.0

var _camera_target_x    : float = 0.0
var _camera_look_at_x   : float = 0.0
var _camera_target_look_at_x : float = 0.0
var _camera_look_at_z   : float = CAMERA_LOOK_AT_Z
var _camera_zoom_distance: float = CAMERA_DEFAULT_ZOOM_DISTANCE
var _camera_target_zoom_distance: float = CAMERA_DEFAULT_ZOOM_DISTANCE


func reset_camera_defaults() -> void:
	_camera_target_x = clampf(_fret_to_world_x(DEFAULT_CAMERA_FRET), CAMERA_X_MIN, CAMERA_X_MAX)
	_camera_target_look_at_x = _camera_target_x
	_camera_look_at_x = _camera_target_look_at_x
	_camera_zoom_distance = CAMERA_DEFAULT_ZOOM_DISTANCE
	_camera_target_zoom_distance = CAMERA_DEFAULT_ZOOM_DISTANCE
	_camera_look_at_z = CAMERA_LOOK_AT_Z
	position.x = _camera_target_x
	position.y = _zoom_distance_to_height(_camera_zoom_distance)
	position.z = CAMERA_LOOK_AT_Z + _camera_zoom_distance
	fov = CAM_FOV
	if is_inside_tree():
		look_at(Vector3(_camera_look_at_x, 0.0, _camera_look_at_z), Vector3.UP)


func tick_camera(events: Array, debug_strum_event_idx: int, song_time: float, lead_time: float, delta: float, max_delta: float) -> void:
	var damp_delta := minf(delta, max_delta)
	_update_camera_targets_from_visible_events(events, debug_strum_event_idx, song_time, lead_time, damp_delta)

	_camera_zoom_distance = _damp_float(_camera_zoom_distance, _camera_target_zoom_distance, CAMERA_Z_DAMPING_RATE, damp_delta)
	var target_z: float = CAMERA_LOOK_AT_Z + _camera_zoom_distance

	var cam_pos  := position
	cam_pos.x = _damp_float(cam_pos.x, _camera_target_x, CAMERA_WORLD_DAMPING_RATE, damp_delta)
	cam_pos.z = _damp_float(cam_pos.z, target_z, CAMERA_Z_DAMPING_RATE, damp_delta)
	cam_pos.y = _zoom_distance_to_height(maxf(cam_pos.z - CAMERA_LOOK_AT_Z, 0.001))
	position = cam_pos
	_camera_look_at_z = cam_pos.z - (cam_pos.y / maxf(tan(deg_to_rad(CAMERA_PITCH_DEGREES)), 0.001))
	var yaw_limited_look_x: float = _clamp_look_x_for_yaw(_camera_target_look_at_x, cam_pos.x, cam_pos.z, _camera_look_at_z)
	_camera_look_at_x = _damp_float(_camera_look_at_x, yaw_limited_look_x, CAMERA_LOOK_DAMPING_RATE, damp_delta)
	if is_inside_tree():
		look_at(Vector3(_camera_look_at_x, 0.0, _camera_look_at_z), Vector3.UP)


func _update_camera_targets_from_visible_events(events: Array, debug_strum_event_idx: int, song_time: float, lead_time: float, damp_delta: float) -> void:
	var min_target_x: float = INF
	var max_target_x: float = -INF
	var has_target: bool = false
	var lookahead_end: float = song_time + minf(maxf(lead_time, CAMERA_TARGET_AHEAD_SECONDS), CAMERA_LOOKAHEAD_SECONDS)
	var target_window_start: float = song_time - CAMERA_TARGET_BEHIND_SECONDS
	var target_window_end: float = lookahead_end

	var i: int = maxi(debug_strum_event_idx, 0)
	while i < events.size():
		var ev: Dictionary = events[i]
		var event_time: float = float(ev.get("time_start", -1.0))
		if event_time < target_window_start:
			i += 1
			continue
		if event_time > lookahead_end:
			break
		if event_time >= target_window_start and event_time <= target_window_end:
			for n in ev.get("notes", []):
				var fret: int = int(n.get("fret", -1))
				if fret < 1 or fret > FRET_COUNT:
					continue
				var target_x: float = _fret_to_world_x(float(fret))
				min_target_x = minf(min_target_x, target_x)
				max_target_x = maxf(max_target_x, target_x)
				has_target = true
			if not has_target:
				var hand_start: int = int(ev.get("hand_fret_start", -1))
				var hand_end: int = int(ev.get("hand_fret_end", -1))
				if hand_start >= 1 and hand_end >= hand_start:
					var hand_min_x: float = _fret_to_world_x(float(hand_start))
					var hand_max_x: float = _fret_to_world_x(float(hand_end))
					min_target_x = minf(min_target_x, hand_min_x)
					max_target_x = maxf(max_target_x, hand_max_x)
					has_target = true
		i += 1

	if has_target:
		var target_center_x: float = (min_target_x + max_target_x) * 0.5
		var spread_x: float = maxf(max_target_x - min_target_x, 0.0)
		var padded_spread_x: float = spread_x + (CAMERA_SAFE_ZONE_PADDING_X * 2.0)
		var required_zoom_distance: float = _required_zoom_distance_for_span_x(padded_spread_x)
		_camera_target_x = clampf(target_center_x, CAMERA_X_MIN, CAMERA_X_MAX)
		_camera_target_look_at_x = _camera_target_x
		_camera_target_zoom_distance = clampf(required_zoom_distance, CAMERA_MIN_ZOOM_DISTANCE, CAMERA_MAX_ZOOM_DISTANCE)
	else:
		var next_center_fret := _find_next_upcoming_center_fret(events, debug_strum_event_idx, song_time)
		if next_center_fret >= 0.0:
			_camera_target_x = clampf(_fret_to_world_x(next_center_fret), CAMERA_X_MIN, CAMERA_X_MAX)
		else:
			_camera_target_x = clampf(_fret_to_world_x(DEFAULT_CAMERA_FRET), CAMERA_X_MIN, CAMERA_X_MAX)
		_camera_target_look_at_x = _camera_target_x
		_camera_target_zoom_distance = _damp_float(_camera_target_zoom_distance, CAMERA_DEFAULT_ZOOM_DISTANCE, 0.5, damp_delta)


func _required_zoom_distance_for_span_x(span_x: float) -> float:
	var viewport := get_viewport()
	var viewport_size: Vector2 = Vector2(1280.0, 720.0)
	if viewport != null:
		viewport_size = viewport.get_visible_rect().size
	var aspect_ratio: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	var vertical_half_fov: float = deg_to_rad(fov) * 0.5
	var horizontal_half_fov: float = atan(tan(vertical_half_fov) * maxf(aspect_ratio, 0.1))
	var tan_half_hfov: float = maxf(tan(horizontal_half_fov), 0.001)
	var min_required_distance: float = (CAMERA_MIN_TRACK_SPAN_X * 0.5) / tan_half_hfov
	var required_distance: float = (maxf(span_x, CAMERA_MIN_TRACK_SPAN_X) * 0.5) / tan_half_hfov
	return CAMERA_DEFAULT_ZOOM_DISTANCE + maxf(required_distance - min_required_distance, 0.0)


func get_zoom_distance() -> float:
	return maxf(position.z - CAMERA_LOOK_AT_Z, 0.0)


func _zoom_distance_to_height(zoom_distance: float) -> float:
	return zoom_distance * tan(deg_to_rad(CAMERA_PITCH_DEGREES))


func _fret_to_world_x(fret_num: float) -> float:
	return ChartCommon.chart_fret_pos(fret_num) - (ChartCommon.FRET_SPACING * 0.5)


func _clamp_look_x_for_yaw(target_look_x: float, cam_x: float, cam_z: float, look_z: float) -> float:
	var depth_to_look: float = maxf(absf(cam_z - look_z), 0.001)
	var max_dx: float = tan(deg_to_rad(CAMERA_MAX_YAW_DEGREES)) * depth_to_look
	return clampf(target_look_x, cam_x - max_dx, cam_x + max_dx)


func _find_next_upcoming_center_fret(events: Array, start_idx: int, song_time: float) -> float:
	for j in range(maxi(start_idx, 0), events.size()):
		var ev: Dictionary = events[j]
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
