extends RefCounted
class_name PlayEventBuilder


static func build_play_events(
		src_notes: Array,
		fret_count: int,
		chord_group_threshold: float,
		note_name_resolver: Callable
) -> Array:
	var events: Array = []
	var last_chord_sig: String = ""
	var last_fretted_hand_start: int = 1
	var last_visual_base_fret: int = 1
	var i: int = 0

	while i < src_notes.size():
		var nd: Dictionary = src_notes[i]
		var t0: float = float(nd.get("time", 0.0))
		var group: Array = [nd]
		var j: int = i + 1
		while j < src_notes.size() \
				and absf(float(src_notes[j].get("time", 0.0)) - t0) < chord_group_threshold:
			group.append(src_notes[j])
			j += 1

		var valid_notes: Array = []
		var max_duration: float = 0.0
		var min_fret: int = 999
		var min_fretted: int = 999
		var has_hand_shape: bool = false
		var outline_min_fret: int = 999
		var outline_max_fret: int = -1
		var outline_min_string: int = 999
		var outline_max_string: int = -1

		for gn in group:
			var f: int = int(gn.get("fret", 0))
			var s: int = int(gn.get("string", 0))
			if f < 0 or f > fret_count or s < 0 or s > 5:
				continue
			var dur: float = maxf(float(gn.get("duration", 0.25)), 0.0)
			var hs_id: int = int(gn.get("hand_shape_id", -1))
			var hs_chord_id: int = int(gn.get("hand_shape_chord_id", -1))
			var hs_min_fret: int = int(gn.get("hand_shape_min_fret", -1))
			var hs_max_fret: int = int(gn.get("hand_shape_max_fret", -1))
			var hs_min_string: int = int(gn.get("hand_shape_min_string", -1))
			var hs_max_string: int = int(gn.get("hand_shape_max_string", -1))
			valid_notes.append({
				"fret": f,
				"string": s,
				"duration": dur,
				"hand_shape_id": hs_id,
				"hand_shape_chord_id": hs_chord_id,
				"hand_shape_min_fret": hs_min_fret,
				"hand_shape_max_fret": hs_max_fret,
				"hand_shape_min_string": hs_min_string,
				"hand_shape_max_string": hs_max_string,
			})
			if hs_id >= 0:
				has_hand_shape = true
			if hs_min_fret >= 1 and hs_max_fret >= hs_min_fret:
				outline_min_fret = mini(outline_min_fret, hs_min_fret)
				outline_max_fret = maxi(outline_max_fret, hs_max_fret)
			if hs_min_string >= 0 and hs_max_string >= hs_min_string:
				outline_min_string = mini(outline_min_string, hs_min_string)
				outline_max_string = maxi(outline_max_string, hs_max_string)
			max_duration = maxf(max_duration, dur)
			min_fret = mini(min_fret, f)
			if f >= 1:
				min_fretted = mini(min_fretted, f)

		if not valid_notes.is_empty():
			var event_kind: String = "single"
			if valid_notes.size() > 1 or has_hand_shape:
				event_kind = "chord"

			var hand_start: int = last_fretted_hand_start
			if min_fretted != 999:
				hand_start = maxi(min_fretted - 1, 1)
			elif min_fret != 999 and min_fret >= 1:
				hand_start = maxi(min_fret - 1, 1)
			else:
				hand_start = _find_next_fretted_hand_start(src_notes, j, fret_count, last_fretted_hand_start)
			var hand_end: int = mini(hand_start + 3, fret_count)

			var force_outline: bool = has_hand_shape
			if outline_min_fret == 999:
				outline_min_fret = -1
			if outline_min_string == 999:
				outline_min_string = -1
			if force_outline and outline_min_fret >= 1 and outline_max_fret >= outline_min_fret:
				hand_start = maxi(outline_min_fret - 1, 1)
				hand_end = mini(outline_max_fret, fret_count)

			var visual_base_fret: int = _resolve_visual_base_fret(
				hand_start,
				min_fretted,
				force_outline,
				outline_min_fret,
				src_notes,
				j,
				fret_count,
				last_visual_base_fret
			)

			if min_fretted != 999 or (force_outline and outline_min_fret >= 1):
				last_fretted_hand_start = hand_start
				last_visual_base_fret = visual_base_fret

			var chord_name: String = ""
			var show_details: bool = false
			if event_kind == "chord":
				var sig: String
				if force_outline:
					var hs_sig_id: int = int(valid_notes[0].get("hand_shape_id", -1))
					var hs_sig_chord_id: int = int(valid_notes[0].get("hand_shape_chord_id", -1))
					sig = "hs:%d:%d" % [hs_sig_id, hs_sig_chord_id]
				else:
					sig = _chord_signature(valid_notes)
				show_details = (sig != last_chord_sig)
				last_chord_sig = sig
				var root_f: int = int(valid_notes[0].get("fret", 0))
				var root_s: int = int(valid_notes[0].get("string", 0))
				if note_name_resolver.is_valid():
					chord_name = String(note_name_resolver.call(root_f, root_s))

			events.append({
				"time_start": t0,
				"time_end": t0 + max_duration,
				"hand_fret_start": hand_start,
				"hand_fret_end": hand_end,
				"visual_base_fret": visual_base_fret,
				"notes": valid_notes,
				"kind": event_kind,
				"chord_name": chord_name,
				"show_details": show_details,
				"force_outline": force_outline,
				"outline_min_fret": outline_min_fret,
				"outline_max_fret": outline_max_fret,
				"outline_min_string": outline_min_string,
				"outline_max_string": outline_max_string,
			})

		i = j

	return events


static func _resolve_visual_base_fret(
		hand_start: int,
		min_fretted: int,
		force_outline: bool,
		outline_min_fret: int,
		src_notes: Array,
		next_group_idx: int,
		fret_count: int,
		last_visual_base_fret: int
) -> int:
	if force_outline and outline_min_fret >= 1:
		return maxi(outline_min_fret - 1, 1)
	if min_fretted != 999:
		return maxi(hand_start, 1)
	if last_visual_base_fret > 1:
		return last_visual_base_fret
	return _find_next_fretted_hand_start(src_notes, next_group_idx, fret_count, last_visual_base_fret)


static func _find_next_fretted_hand_start(src_notes: Array, start_idx: int, fret_count: int, fallback: int) -> int:
	var idx: int = maxi(start_idx, 0)
	while idx < src_notes.size():
		var nd: Dictionary = src_notes[idx]
		var hs_min_fret: int = int(nd.get("hand_shape_min_fret", -1))
		if hs_min_fret >= 1:
			return maxi(hs_min_fret - 1, 1)
		var f: int = int(nd.get("fret", -1))
		if f >= 1 and f <= fret_count:
			return maxi(f - 1, 1)
		idx += 1
	return maxi(fallback, 1)


static func _chord_signature(notes: Array) -> String:
	var parts: Array[String] = []
	for n in notes:
		parts.append("%d:%d" % [int(n.get("fret", 0)), int(n.get("string", 0))])
	parts.sort()
	return ",".join(parts)
