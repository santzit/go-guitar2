extends RefCounted
class_name NoteDetection


func build_play_events(
	src_notes: Array,
	fret_count: int,
	chord_group_threshold: float,
	get_note_name: Callable,
	last_chord_sig: String
) -> Dictionary:
	var events: Array = []
	var note_index: int = 0
	var next_chord_sig: String = last_chord_sig
	while note_index < src_notes.size():
		var nd : Dictionary = src_notes[note_index]
		var t0 : float = float(nd.get("time", 0.0))
		var group: Array = [nd]
		var group_end_index: int = note_index + 1
		while group_end_index < src_notes.size() \
				and absf(float(src_notes[group_end_index].get("time", 0.0)) - t0) < chord_group_threshold:
			group.append(src_notes[group_end_index])
			group_end_index += 1

		var valid_notes: Array = []
		var max_duration: float = 0.0
		var min_fret: int = 999
		for gn in group:
			var f: int = int(gn.get("fret", 0))
			var s: int = int(gn.get("string", 0))
			if f < 1 or f > fret_count or s < 0 or s > 5:
				continue
			var dur: float = maxf(float(gn.get("duration", 0.25)), 0.0)
			valid_notes.append({"fret": f, "string": s, "duration": dur})
			max_duration = maxf(max_duration, dur)
			min_fret = mini(min_fret, f)

		if not valid_notes.is_empty():
			var event_kind: String = "single" if valid_notes.size() == 1 else "chord"
			var hand_start: int = maxi(min_fret - 1, 1)
			var hand_end: int = mini(hand_start + 3, fret_count)
			var chord_name: String = ""
			var show_details: bool = false
			if event_kind == "chord":
				var sig := chord_signature(valid_notes)
				show_details = (sig != next_chord_sig)
				next_chord_sig = sig
				var root_f: int = int(valid_notes[0].get("fret", 0))
				var root_s: int = int(valid_notes[0].get("string", 0))
				chord_name = String(get_note_name.call(root_f, root_s))

			events.append({
				"time_start": t0,
				"time_end": t0 + max_duration,
				"hand_fret_start": hand_start,
				"hand_fret_end": hand_end,
				"notes": valid_notes,
				"kind": event_kind,
				"chord_name": chord_name,
				"show_details": show_details
			})

		note_index = group_end_index

	return {
		"events": events,
		"last_chord_sig": next_chord_sig
	}


func chord_signature(notes: Array) -> String:
	var parts : Array[String] = []
	for n in notes:
		parts.append("%d:%d" % [int(n.get("fret", 0)), int(n.get("string", 0))])
	parts.sort()
	return ",".join(parts)


func sort_notes_by_fret(notes: Array) -> Array:
	var sorted : Array = notes.duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("fret", -1)) < int(b.get("fret", -1)))
	return sorted
