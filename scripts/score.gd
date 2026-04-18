extends RefCounted
class_name Score


var _detected_notes_total: int = 0
var _expected_notes_total: int = 0


func reset() -> void:
	_detected_notes_total = 0
	_expected_notes_total = 0


func register_chart_events(events: Array) -> void:
	_expected_notes_total = 0
	for ev in events:
		_expected_notes_total += int(Array(ev.get("notes", [])).size())


func score_event(expected_notes: Array, detected_strings: Array[int]) -> Dictionary:
	var expected_by_string: Dictionary = {}
	for note in expected_notes:
		var s: int = int(note.get("string", -1))
		if s >= 0:
			expected_by_string[s] = true

	var matched: int = 0
	var seen: Dictionary = {}
	for s in detected_strings:
		if seen.has(s):
			continue
		seen[s] = true
		if expected_by_string.has(s):
			matched += 1

	_detected_notes_total += matched
	var expected_count: int = expected_by_string.size()
	return {
		"detected_notes": matched,
		"expected_notes": expected_count,
		"ratio": float(matched) / float(expected_count) if expected_count > 0 else 0.0
	}


func get_totals() -> Dictionary:
	return {
		"detected_notes": _detected_notes_total,
		"total_notes": _expected_notes_total,
		"ratio": float(_detected_notes_total) / float(_expected_notes_total) if _expected_notes_total > 0 else 0.0
	}
