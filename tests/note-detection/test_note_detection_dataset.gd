extends SceneTree
## Dataset-based per-string note detection tests.
##
## For each WAV file in the GuitarSet dataset, analyses evenly-spaced windows
## with NoteDetection.detect_strings(). Each window shows a 6-string table:
##   ●  str N  band  →  note  fret  freq
##   ○  str N  band  →  —  (inactive)

const NoteDetection = preload("res://scripts/note_detection.gd")

const DATASET_DIR := "res://tests/dataset/guitarset/audio/mic"
const MAX_WINDOWS := 8

var _pass_count := 0
var _fail_count := 0
var _detector   : NoteDetection


func _init() -> void:
	_detector = NoteDetection.new()
	_run_all()
	_print_summary()
	quit(_fail_count > 0)


func _assert(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  " + description)
		_pass_count += 1
	else:
		printerr("  FAIL  " + description)
		_fail_count += 1


func _run_all() -> void:
	print("\n═══════ Dataset Per-String Detection Tests ═══════")
	print("  NoteDetection.detect_strings() — 6 strings analysed independently.")
	print("  Standard tuning bands:")
	for s in 6:
		print("    %s" % NoteDetection.STRING_LABELS[s])
	print("")

	var wav_paths: Array[String] = _collect_wav_paths(DATASET_DIR)
	if wav_paths.is_empty():
		print("  SKIP  No WAV files found under %s" % DATASET_DIR)
		return
	wav_paths.sort()
	for path in wav_paths:
		_test_file(path)


func _test_file(path: String) -> void:
	var fname := path.get_file()
	var key   := _parse_key_from_filename(fname)
	print("\n  ─── %s  (key: %s) ───" % [fname, key])

	var parsed := _parse_wav_pcm16(path)
	if not bool(parsed.get("ok", false)):
		print("    ERROR: %s" % parsed.get("error", "unknown"))
		_assert(false, "decoded %s" % fname)
		return

	var sr: int       = int(parsed.get("sample_rate", 0))
	var channels: int = int(parsed.get("channels",    0))
	_assert(true, "decoded %s  (%d Hz, %d ch)" % [fname, sr, channels])

	var samples: PackedFloat32Array = parsed.get("samples", PackedFloat32Array())
	var total      := samples.size()
	var duration_s := float(total) / float(sr)

	var edge   := total / 20
	var usable := total - edge * 2
	var hop    := maxi(NoteDetection.FFT_WINDOW, usable / MAX_WINDOWS)

	print("    duration %.2f s  |  %d Hz  |  %d ch  |  hop %.0f ms" % [
		duration_s, sr, channels, float(hop) / float(sr) * 1000.0])

	var windows_with_activity := 0
	var all_valid_frets        := true

	var t := edge
	while t + NoteDetection.FFT_WINDOW <= total - edge:
		var rms := _rms(samples, t, NoteDetection.FFT_WINDOW)
		if rms >= NoteDetection.MIN_RMS:
			var detection: Array[Dictionary] = _detector.detect_strings(samples, sr, t)

			var active_labels: Array[String] = []
			for entry in detection:
				if bool(entry.get("active", false)):
					var s: int    = int(entry.get("string_idx", 0))
					var fret: int = int(entry.get("fret", -1))
					active_labels.append("str%d(fr%d)" % [6 - s, fret])
					if fret < 0 or fret > NoteDetection.MAX_FRET:
						all_valid_frets = false

			if not active_labels.is_empty():
				windows_with_activity += 1
				var time_s := float(t) / float(sr)
				print("\n    t=%.3fs  RMS=%.3f  active: %s" % [
					time_s, rms, "  ".join(active_labels)])
				print("    %-3s  %-22s  %-6s  %-4s  %s" % [
					"", "string / band", "note", "fret", "freq (Hz)"])
				for entry in detection:
					_print_string_row(entry)
		t += hop

	if windows_with_activity == 0:
		print("    (no active windows above RMS %.3f)" % NoteDetection.MIN_RMS)

	_assert(windows_with_activity > 0,
		"at least one active window in %s" % fname)
	_assert(all_valid_frets,
		"all active frets within 0\u201324 in %s" % fname)


func _print_string_row(entry: Dictionary) -> void:
	var s: int       = int(entry.get("string_idx", 0))
	var active: bool = bool(entry.get("active", false))
	if active:
		print("    \u25cf  %-22s  %-6s  %-4d  %.2f Hz" % [
			NoteDetection.STRING_LABELS[s],
			entry.get("note", ""),
			int(entry.get("fret", -1)),
			float(entry.get("hz", 0.0))])
	else:
		print("    \u25cb  %-22s  \u2014" % NoteDetection.STRING_LABELS[s])


func _rms(samples: PackedFloat32Array, offset: int, n: int) -> float:
	var sum := 0.0
	for i in n:
		var v: float = samples[offset + i]
		sum += v * v
	return sqrt(sum / float(n))


func _parse_key_from_filename(fname: String) -> String:
	for part in fname.get_basename().split("_"):
		var subs := part.split("-")
		if subs.size() >= 3:
			var candidate: String = subs[subs.size() - 1]
			if candidate.length() >= 1 and candidate.length() <= 2:
				var first := candidate.unicode_at(0)
				if first >= 65 and first <= 71:
					return candidate
	return "?"


func _collect_wav_paths(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	_collect_wav_paths_recursive(dir_path, found)
	return found


func _collect_wav_paths_recursive(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var child := dir_path.path_join(name)
		if dir.current_is_dir():
			if name != "." and name != "..":
				_collect_wav_paths_recursive(child, out)
		elif name.to_lower().ends_with(".wav"):
			out.append(child)
		name = dir.get_next()
	dir.list_dir_end()


func _parse_wav_pcm16(path: String) -> Dictionary:
	var abs_path := ProjectSettings.globalize_path(path)
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "open_failed"}
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44:
		return {"ok": false, "error": "too_small"}
	if _read_ascii(bytes, 0, 4) != "RIFF" or _read_ascii(bytes, 8, 4) != "WAVE":
		return {"ok": false, "error": "not_riff_wave"}

	var fmt_found       := false
	var data_found      := false
	var channels        := 0
	var sample_rate     := 0
	var bits_per_sample := 0
	var audio_format    := 0
	var data_offset     := 0
	var data_size       := 0

	var p := 12
	while p + 8 <= bytes.size():
		var chunk_id   := _read_ascii(bytes, p, 4)
		var chunk_size := _u32le(bytes, p + 4)
		var chunk_data := p + 8
		if chunk_id == "fmt " and chunk_data + chunk_size <= bytes.size():
			audio_format    = _u16le(bytes, chunk_data)
			channels        = _u16le(bytes, chunk_data + 2)
			sample_rate     = _u32le(bytes, chunk_data + 4)
			bits_per_sample = _u16le(bytes, chunk_data + 14)
			fmt_found = true
		elif chunk_id == "data" and chunk_data + chunk_size <= bytes.size():
			data_offset = chunk_data
			data_size   = chunk_size
			data_found  = true
		p = chunk_data + chunk_size + (chunk_size % 2)
		if p >= bytes.size():
			break

	if not fmt_found or not data_found:
		return {"ok": false, "error": "missing_chunks"}
	if audio_format != 1 or bits_per_sample != 16:
		return {"ok": false, "error": "unsupported_format"}
	if channels < 1 or channels > 2 or sample_rate <= 0:
		return {"ok": false, "error": "invalid_fmt"}
	if data_size <= 1 or data_offset + data_size > bytes.size():
		return {"ok": false, "error": "invalid_data"}

	var frame_count := data_size / (2 * channels)
	var samples     := PackedFloat32Array()
	samples.resize(frame_count)
	for frame_i in frame_count:
		var frame_base := data_offset + frame_i * channels * 2
		var mono       := 0.0
		for ch in channels:
			var lo  := bytes[frame_base + ch * 2]
			var hi  := bytes[frame_base + ch * 2 + 1]
			var s16 := int(lo | (hi << 8))
			if s16 >= 32768:
				s16 -= 65536
			mono += float(s16) / 32768.0
		samples[frame_i] = mono / float(channels)

	return {
		"ok":          true,
		"sample_rate": sample_rate,
		"channels":    channels,
		"samples":     samples,
	}


func _u16le(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset] | (bytes[offset + 1] << 8))


func _u32le(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]
		| (bytes[offset + 1] << 8)
		| (bytes[offset + 2] << 16)
		| (bytes[offset + 3] << 24))


func _read_ascii(bytes: PackedByteArray, offset: int, count: int) -> String:
	var out := PackedByteArray()
	out.resize(count)
	for i in count:
		out[i] = bytes[offset + i]
	return out.get_string_from_ascii()


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
