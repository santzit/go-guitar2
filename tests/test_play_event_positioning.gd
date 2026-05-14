## test_play_event_positioning.gd — validates event base-fret positioning rules.
##
## Run headless from the project root:
##   godot --headless --path . --script tests/test_play_event_positioning.gd

extends SceneTree

const PlayEventBuilder = preload("res://scripts/play_event_builder.gd")
const ChartCommon = preload("res://scripts/common.gd")
const CHORD_GROUP_THRESHOLD: float = 0.02

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


func _assert_eq(actual: Variant, expected: Variant, description: String) -> void:
	if actual == expected:
		print("  PASS  %s  (= %s)" % [description, str(actual)])
		_pass_count += 1
	else:
		printerr("  FAIL  %s  (expected %s, got %s)" % [description, str(expected), str(actual)])
		_fail_count += 1


func _build_events(notes: Array) -> Array:
	return PlayEventBuilder.build_play_events(
		notes,
		ChartCommon.FRET_COUNT,
		CHORD_GROUP_THRESHOLD,
		Callable(self, "_note_name_stub")
	)


func _note_name_stub(_fret: int, _string_idx: int) -> String:
	return "N"


func _run_all() -> void:
	print("\n═══════ Play Event Positioning Tests ═══════")

	var lead_open_notes: Array = [
		{"time": 1.0, "fret": 0, "string": 0, "duration": 0.5},
		{"time": 1.4, "fret": 10, "string": 1, "duration": 0.4},
	]
	var lead_open_events: Array = _build_events(lead_open_notes)
	_assert_eq(lead_open_events.size(), 2, "builds events for lead-open scenario")
	if lead_open_events.size() >= 2:
		_assert_eq(int(lead_open_events[0].get("hand_fret_start", -1)), 9, "phrase-start open event uses lookahead hand fret")
		_assert_eq(int(lead_open_events[0].get("visual_base_fret", -1)), 9, "phrase-start open event uses lookahead visual base")

	var inherit_open_notes: Array = [
		{"time": 2.0, "fret": 7, "string": 2, "duration": 0.3},
		{"time": 2.4, "fret": 0, "string": 4, "duration": 0.2},
	]
	var inherit_open_events: Array = _build_events(inherit_open_notes)
	_assert_eq(inherit_open_events.size(), 2, "builds events for inherited-open scenario")
	if inherit_open_events.size() >= 2:
		_assert_eq(int(inherit_open_events[0].get("visual_base_fret", -1)), 6, "fretted event sets visual base from fret")
		_assert_eq(int(inherit_open_events[1].get("visual_base_fret", -1)), 6, "open-only event inherits previous visual base")

	var isolated_open_notes: Array = [
		{"time": 3.0, "fret": 0, "string": 3, "duration": 0.5},
	]
	var isolated_open_events: Array = _build_events(isolated_open_notes)
	_assert_eq(isolated_open_events.size(), 1, "builds events for isolated open scenario")
	if isolated_open_events.size() == 1:
		_assert_eq(int(isolated_open_events[0].get("visual_base_fret", -1)), 1, "isolated open-only event falls back to base fret 1")

	var open_chord_notes: Array = [
		{"time": 4.0, "fret": 9, "string": 1, "duration": 0.25},
		{"time": 4.3, "fret": 0, "string": 0, "duration": 0.25},
		{"time": 4.3, "fret": 0, "string": 2, "duration": 0.25},
	]
	var open_chord_events: Array = _build_events(open_chord_notes)
	_assert_eq(open_chord_events.size(), 2, "builds events for open-chord scenario")
	if open_chord_events.size() >= 2:
		_assert_eq(String(open_chord_events[1].get("kind", "")), "chord", "open-only multi-string group is a chord event")
		_assert_eq(int(open_chord_events[1].get("visual_base_fret", -1)), 8, "open-only chord event inherits visual base")


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
