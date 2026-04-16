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
	quit(_fail_count > 0)


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
	_assert_near(ChartCommon.chart_fret_pos(12.0), 12.0, "chart_fret_pos(12) is 12")
	_assert_near(ChartCommon.fret_separator_world_x(0), 0.0, "fret_separator_world_x(0) is 0")
	_assert_near(ChartCommon.fret_separator_world_x(12), 12.0, "fret_separator_world_x(12) is 12")
	_assert_near(ChartCommon.fret_separator_world_x(24), 24.0, "fret_separator_world_x(24) is 24")
	_assert_near(ChartCommon.fret_mid_world_x(0), 0.5, "fret_mid_world_x(0) is 0.5")
	_assert_near(ChartCommon.fret_mid_world_x(23), 23.5, "fret_mid_world_x(23) is 23.5")
	_assert_near(ChartCommon.note_indicator_size(0).x, 1.0, "note indicator width at fret 0 is 1")
	_assert_near(ChartCommon.note_indicator_size(20).x, 1.0, "note indicator width at fret 20 is 1")


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
