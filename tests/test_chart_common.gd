## test_chart_common.gd — validates fret X-coordinate math in ChartCommon.
##
## Run headless from the project root:
##   Godot_v4.4.1-stable_linux.x86_64 --headless --path . --script tests/test_chart_common.gd

extends SceneTree

const ChartCommon = preload("res://scripts/common.gd")

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	_run_all()
	_print_summary()
	quit(_fail_count)


func _assert_near(actual: float, expected: float, description: String) -> void:
	if is_equal_approx(actual, expected):
		print("  PASS  %s  (= %.3f)" % [description, actual])
		_pass_count += 1
	else:
		printerr("  FAIL  %s  (expected %.3f, got %.3f)" % [description, expected, actual])
		_fail_count += 1


func _run_all() -> void:
	print("\n═══════ ChartCommon Fret Formula Tests ═══════")
	_assert_near(ChartCommon.chart_fret_pos(0.0), 0.0, "chart_fret_pos(0) is 0")
	_assert_near(ChartCommon.chart_fret_pos(12.0), 24.0, "chart_fret_pos(12) is 24")
	_assert_near(ChartCommon.fret_separator_world_x(0), 0.0, "fret_separator_world_x(0) is 0")
	_assert_near(ChartCommon.fret_separator_world_x(12), 24.0, "fret_separator_world_x(12) is 24")
	_assert_near(ChartCommon.fret_separator_world_x(24), 48.0, "fret_separator_world_x(24) is 48")
	_assert_near(ChartCommon.fret_mid_world_x(0), 1.0, "fret_mid_world_x(0) is 1.0")
	_assert_near(ChartCommon.fret_mid_world_x(23), 47.0, "fret_mid_world_x(23) is 47.0")
	_assert_near(ChartCommon.string_world_y(0), 2.75, "string_world_y(0) is 2.75")
	_assert_near(ChartCommon.string_world_y(5), 0.25, "string_world_y(5) is 0.25")
	_assert_near(ChartCommon.note_world_z(8.0, 5.0, 0.0), -3.0, "note_world_z uses 1 unit = 1 second")
	_assert_near(ChartCommon.note_indicator_size(0).x, 2.0, "note indicator width at fret 0 is 2")
	_assert_near(ChartCommon.note_indicator_size(20).x, 2.0, "note indicator width at fret 20 is 2")


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
