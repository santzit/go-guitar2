## test_event_lifecycle.gd — validates shared EventLifecycle timing transitions.
##
## Run headless from the project root:
##   godot --headless --path . --script tests/test_event_lifecycle.gd

extends SceneTree

const EventLifecycle = preload("res://scripts/event_lifecycle.gd")

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	_run_all()
	_print_summary()
	quit(_fail_count)


func _assert_true(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  " + description)
		_pass_count += 1
	else:
		printerr("  FAIL  " + description)
		_fail_count += 1


func _assert_eq(actual, expected, description: String) -> void:
	if actual == expected:
		print("  PASS  %s  (= %s)" % [description, str(actual)])
		_pass_count += 1
	else:
		printerr("  FAIL  %s  (expected %s, got %s)" % [description, str(expected), str(actual)])
		_fail_count += 1


func _run_all() -> void:
	print("\n═══════ EventLifecycle Tests ═══════")

	var sustain_lc := EventLifecycle.new()
	sustain_lc.setup(5.0, 0.5, 0.05, true)
	var s0: Dictionary = sustain_lc.advance(4.9)
	_assert_true(not bool(s0.get("is_crossed", false)), "Sustain event not crossed before strum")
	_assert_true(not bool(s0.get("is_finished", false)), "Sustain event not finished before strum")

	var s1: Dictionary = sustain_lc.advance(5.0)
	_assert_true(bool(s1.get("crossed_now", false)), "Sustain event crosses at strum time")
	_assert_true(not bool(s1.get("finished_now", false)), "Sustain event not finished at strum")
	_assert_true(bool(s1.get("has_sustain", false)), "Sustain event flagged with sustain")

	var s2: Dictionary = sustain_lc.advance(5.3)
	_assert_true(float(s2.get("remaining_secs", 0.0)) > 0.0, "Sustain event has remaining duration after strum")
	_assert_true(not bool(s2.get("finished_now", false)), "Sustain event still active before end")

	var s3: Dictionary = sustain_lc.advance(5.5)
	_assert_true(bool(s3.get("finished_now", false)), "Sustain event finishes at end time")
	_assert_eq(float(s3.get("remaining_secs", 1.0)), 0.0, "Sustain event remaining seconds clamp to zero")

	var instant_lc := EventLifecycle.new()
	instant_lc.setup(10.0, 0.8, 1.5, true)
	var i0: Dictionary = instant_lc.advance(10.0)
	_assert_true(bool(i0.get("crossed_now", false)), "Instant event crosses at strum")
	_assert_true(bool(i0.get("finished_now", false)), "Instant event finishes immediately without sustain")
	_assert_true(not bool(i0.get("has_sustain", true)), "Instant event has no sustain")


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
