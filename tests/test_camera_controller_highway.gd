## test_camera_controller_highway.gd — validates Rocksmith-style highway camera pan/zoom behavior.
##
## Run headless from the project root:
##   godot --headless --path . --script tests/test_camera_controller_highway.gd

extends SceneTree

const CameraControllerScript = preload("res://scripts/CameraController.gd")

const FRAME_DELTA: float = 1.0 / 60.0
const MAX_DELTA: float = 0.05

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	_run_all()
	_print_summary()
	quit(_fail_count)


func _assert_true(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  %s" % description)
		_pass_count += 1
	else:
		printerr("  FAIL  %s" % description)
		_fail_count += 1


func _run_ticks(camera: CameraController, events: Array, song_time: float, frames: int) -> void:
	for _i in range(frames):
		camera.tick_camera(events, 0, song_time, 3.0, FRAME_DELTA, MAX_DELTA)


func _run_all() -> void:
	print("\n═══════ Camera Highway Tracking Tests ═══════")

	var camera: CameraController = CameraControllerScript.new()
	get_root().add_child(camera)
	camera.reset_camera_defaults()

	var center_events: Array = [
		{"time_start": 1.0, "notes": [{"fret": 8}]}
	]
	_run_ticks(camera, center_events, 1.0, 90)
	var center_x: float = camera.position.x
	var center_zoom: float = camera.get_zoom_distance()

	var left_events: Array = [
		{"time_start": 1.0, "notes": [{"fret": 2}]}
	]
	_run_ticks(camera, left_events, 1.0, 90)
	var left_x: float = camera.position.x

	var right_events: Array = [
		{"time_start": 1.0, "notes": [{"fret": 20}]}
	]
	_run_ticks(camera, right_events, 1.0, 90)
	var right_x: float = camera.position.x

	var wide_events: Array = [
		{"time_start": 1.0, "notes": [{"fret": 2}, {"fret": 20}]}
	]
	_run_ticks(camera, wide_events, 1.0, 120)
	var wide_zoom: float = camera.get_zoom_distance()

	var expected_height: float = wide_zoom * tan(deg_to_rad(20.0))

	_assert_true(left_x < center_x, "camera pans left for left-side targets")
	_assert_true(right_x > center_x, "camera pans right for right-side targets")
	_assert_true(wide_zoom > center_zoom + 0.4, "camera pulls back when target spread increases")
	_assert_true(wide_zoom <= 21.6, "camera zoom stays clamped to max zoom distance")
	_assert_true(absf(camera.position.y - expected_height) <= 0.35, "camera keeps a fixed low-angle track ratio while dollying")

	camera.queue_free()


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
