extends SceneTree

const NoteDetection = preload("res://scripts/note_detection.gd")
const Score = preload("res://scripts/score.gd")

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	_run_all()
	_print_summary()
	quit(_fail_count)


func _assert(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  " + description)
		_pass_count += 1
	else:
		printerr("  FAIL  " + description)
		_fail_count += 1


func _assert_eq(actual, expected, description: String) -> void:
	_assert(actual == expected, "%s (expected %s, got %s)" % [description, str(expected), str(actual)])


func _run_all() -> void:
	print("\n═══════ NoteDetection / Score Tests ═══════")
	_test_build_play_events_groups_chords()
	_test_score_event_counts_per_string()


func _test_build_play_events_groups_chords() -> void:
	var detector := NoteDetection.new()
	var src_notes: Array = [
		{"time": 1.0, "fret": 3, "string": 0, "duration": 0.5},
		{"time": 1.0, "fret": 5, "string": 1, "duration": 0.5},
		{"time": 2.0, "fret": 7, "string": 2, "duration": 0.25}
	]
	var result: Dictionary = detector.build_play_events(
		src_notes,
		24,
		0.02,
		func(fret: int, string_idx: int) -> String:
			return "%d:%d" % [fret, string_idx],
		""
	)
	var events: Array = result.get("events", [])
	_assert_eq(events.size(), 2, "build_play_events creates two grouped events")
	_assert_eq(events[0].get("kind", ""), "chord", "first event is chord")
	_assert_eq(Array(events[0].get("notes", [])).size(), 2, "first event contains 2 notes")
	_assert_eq(events[1].get("kind", ""), "single", "second event is single note")


func _test_score_event_counts_per_string() -> void:
	var score := Score.new()
	var expected_notes: Array = [
		{"string": 0},
		{"string": 2},
		{"string": 4}
	]
	var event_result: Dictionary = score.score_event(expected_notes, [0, 4])
	_assert_eq(int(event_result.get("detected_notes", -1)), 2, "score_event counts matched notes")
	_assert_eq(int(event_result.get("expected_notes", -1)), 3, "score_event returns expected note count")
	_assert(is_equal_approx(float(event_result.get("ratio", 0.0)), 2.0 / 3.0), "score_event ratio is 2/3")


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
