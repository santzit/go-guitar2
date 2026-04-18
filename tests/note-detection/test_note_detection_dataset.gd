extends SceneTree

const DATASET_DIR := "res://tests/note-detection/dataset"
## Per-subdataset decode scan limit (keeps runtime reasonable).
const MAX_DECODE_PER_SUBDIR := 16
## Maximum note-labeled files on which to run pitch estimation.
const MAX_PITCH_FILES := 24
const MIN_FREQ_HZ := 70.0
const MAX_FREQ_HZ := 1200.0

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
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
	print("\n═══════ Note Detection Dataset Tests ═══════")
	var all_wav_paths: Array[String] = _collect_wav_paths(DATASET_DIR)
	if all_wav_paths.is_empty():
		print("  SKIP  No WAV files found under %s" % DATASET_DIR)
		print("        Add dataset WAV files from:")
		print("        https://github.com/santzit/guitar-pitch-detection-/tree/main/tests/dataset")
		return

	# Build a balanced sample: cap per immediate subdirectory so that every
	# subdataset (guitarset, idmt_guitar, …) is represented equally.
	var scan_paths: Array[String] = _balanced_sample(all_wav_paths, MAX_DECODE_PER_SUBDIR)

	# For pitch estimation, prefer note-labeled files from the full list.
	var pitch_paths: Array[String] = _note_labeled_paths(all_wav_paths, MAX_PITCH_FILES)

	_test_wav_decode(scan_paths)
	if not pitch_paths.is_empty():
		_test_pitch_estimation(pitch_paths)
	else:
		print("  INFO  No note-labeled files found; pitch matching skipped.")
	_test_wav_playback_path(scan_paths[0])


## Return up to `max_per_subdir` WAV paths from each immediate subdirectory of DATASET_DIR.
func _balanced_sample(paths: Array[String], max_per_subdir: int) -> Array[String]:
	var counts: Dictionary = {}
	var result: Array[String] = []
	for p in paths:
		# Determine subdataset name from path (first component after DATASET_DIR).
		var rel := p.trim_prefix(ProjectSettings.globalize_path(DATASET_DIR)).trim_prefix("/")
		var sub := rel.split("/")[0] if "/" in rel else ""
		var n: int = counts.get(sub, 0)
		if n < max_per_subdir:
			result.append(p)
			counts[sub] = n + 1
	return result


## Return up to `max_count` paths whose filename contains a note token (e.g. Db4, E3).
func _note_labeled_paths(paths: Array[String], max_count: int) -> Array[String]:
	var result: Array[String] = []
	for p in paths:
		if result.size() >= max_count:
			break
		if _extract_note_from_filename(p.get_file()) != "":
			result.append(p)
	return result


func _test_wav_decode(wav_paths: Array[String]) -> void:
	var decoded_count := 0
	for path in wav_paths:
		var parsed: Dictionary = _parse_wav_pcm16(path)
		if bool(parsed.get("ok", false)):
			decoded_count += 1
	_assert(decoded_count > 0, "decoded at least one dataset WAV file (%d/%d)" % [decoded_count, wav_paths.size()])


func _test_pitch_estimation(wav_paths: Array[String]) -> void:
	var expected_note_files := 0
	var matched_pitch_files := 0

	for path in wav_paths:
		var expected_note: String = _extract_note_from_filename(path.get_file())
		if expected_note == "":
			continue
		var expected_hz: float = _note_to_frequency(expected_note)
		if expected_hz <= 0.0:
			continue

		var parsed: Dictionary = _parse_wav_pcm16(path)
		if not bool(parsed.get("ok", false)):
			continue
		var sr: int = int(parsed.get("sample_rate", 0))
		var samples: PackedFloat32Array = parsed.get("samples", PackedFloat32Array())
		if sr <= 0 or samples.is_empty():
			continue

		expected_note_files += 1
		var detected_hz: float = _estimate_frequency(samples, sr)
		if detected_hz <= 0.0:
			continue

		var rel_error := absf(detected_hz - expected_hz) / expected_hz
		var matched := rel_error <= 0.20
		if matched:
			matched_pitch_files += 1
		print("  INFO  %s  expected=%.1f Hz  detected=%.1f Hz  err=%.0f%%  %s" % [
			path.get_file(), expected_hz, detected_hz, rel_error * 100.0,
			"OK" if matched else "MISS"])

	_assert(expected_note_files > 0, "found note-labeled WAV files for pitch estimation")
	_assert(matched_pitch_files > 0,
		"matched pitch in at least one note-labeled WAV file (%d/%d)" % [matched_pitch_files, expected_note_files])


func _test_wav_playback_path(path: String) -> void:
	var parsed: Dictionary = _parse_wav_pcm16(path)
	_assert(bool(parsed.get("ok", false)), "parsed WAV for AudioStreamWAV construction test")
	if not bool(parsed.get("ok", false)):
		return

	var sr: int = int(parsed.get("sample_rate", 0))
	var channels: int = int(parsed.get("channels", 0))
	var raw_pcm16: PackedByteArray = parsed.get("raw_pcm16", PackedByteArray())
	_assert(sr > 0 and channels >= 1 and channels <= 2, "WAV metadata is valid for AudioStreamWAV")
	_assert(not raw_pcm16.is_empty(), "WAV contains PCM16 data")
	if sr <= 0 or raw_pcm16.is_empty() or channels < 1 or channels > 2:
		return

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sr
	stream.stereo = (channels == 2)
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = raw_pcm16

	# Verify the stream object was correctly built — actual playback is
	# skipped here because Godot headless mode has no real audio driver.
	_assert(stream.mix_rate == sr, "AudioStreamWAV mix_rate set correctly (%d Hz)" % sr)
	_assert(stream.data.size() == raw_pcm16.size(), "AudioStreamWAV data size matches PCM16 bytes")


func _collect_wav_paths(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found

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

	var fmt_found := false
	var data_found := false
	var channels := 0
	var sample_rate := 0
	var bits_per_sample := 0
	var audio_format := 0
	var data_offset := 0
	var data_size := 0

	var p := 12
	while p + 8 <= bytes.size():
		var chunk_id := _read_ascii(bytes, p, 4)
		var chunk_size := _u32le(bytes, p + 4)
		var chunk_data := p + 8
		if chunk_id == "fmt " and chunk_data + chunk_size <= bytes.size():
			audio_format = _u16le(bytes, chunk_data)
			channels = _u16le(bytes, chunk_data + 2)
			sample_rate = _u32le(bytes, chunk_data + 4)
			bits_per_sample = _u16le(bytes, chunk_data + 14)
			fmt_found = true
		elif chunk_id == "data" and chunk_data + chunk_size <= bytes.size():
			data_offset = chunk_data
			data_size = chunk_size
			data_found = true

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

	var raw_pcm16 := bytes.slice(data_offset, data_offset + data_size)
	var frame_count := data_size / (2 * channels)
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	var idx := 0
	for frame_i in frame_count:
		var frame_base := data_offset + frame_i * channels * 2
		var mono := 0.0
		for ch in channels:
			var lo := bytes[frame_base + ch * 2]
			var hi := bytes[frame_base + ch * 2 + 1]
			var s16 := int(lo | (hi << 8))
			if s16 >= 32768:
				s16 -= 65536
			mono += float(s16) / 32768.0
		samples[idx] = mono / float(channels)
		idx += 1

	return {
		"ok": true,
		"sample_rate": sample_rate,
		"channels": channels,
		"samples": samples,
		"raw_pcm16": raw_pcm16
	}


func _estimate_frequency(samples: PackedFloat32Array, sample_rate: int) -> float:
	if samples.size() < 2048 or sample_rate <= 0:
		return 0.0

	var start := mini(sample_rate / 20, samples.size() / 4) # ~50ms skip attack
	var n := mini(4096, samples.size() - start)
	if n < 1024:
		return 0.0

	var min_lag := maxi(1, int(floor(float(sample_rate) / MAX_FREQ_HZ)))
	var max_lag := mini(n - 1, int(ceil(float(sample_rate) / MIN_FREQ_HZ)))
	if max_lag <= min_lag:
		return 0.0

	var best_lag := -1
	var best_corr := -INF

	for lag in range(min_lag, max_lag + 1):
		var corr := 0.0
		for i in range(n - lag):
			corr += samples[start + i] * samples[start + i + lag]
		if corr > best_corr:
			best_corr = corr
			best_lag = lag

	if best_lag <= 0:
		return 0.0
	return float(sample_rate) / float(best_lag)


func _extract_note_from_filename(filename: String) -> String:
	var re := RegEx.new()
	re.compile("([A-G](?:#|b)?[0-8])")
	var matches := re.search_all(filename)
	if matches.is_empty():
		return ""
	# Return the last match — IDMT files end in _<note>.wav so the note is last.
	return matches[matches.size() - 1].get_string(1)


func _note_to_frequency(note: String) -> float:
	if note.length() < 2:
		return 0.0

	var letter := note.substr(0, 1)
	var accidental := ""
	var octave_str := ""
	if note.length() >= 3 and (note.substr(1, 1) == "#" or note.substr(1, 1) == "b"):
		accidental = note.substr(1, 1)
		octave_str = note.substr(2, note.length() - 2)
	else:
		octave_str = note.substr(1, note.length() - 1)

	var semitone_map := {
		"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
	}
	if not semitone_map.has(letter):
		return 0.0
	if not octave_str.is_valid_int():
		return 0.0
	var octave := int(octave_str)
	var semitone := int(semitone_map[letter])
	if accidental == "#":
		semitone += 1
	elif accidental == "b":
		semitone -= 1

	var midi := (octave + 1) * 12 + semitone
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)


func _u16le(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset] | (bytes[offset + 1] << 8))


func _u32le(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset] \
		| (bytes[offset + 1] << 8) \
		| (bytes[offset + 2] << 16) \
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
