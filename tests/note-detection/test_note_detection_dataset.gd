extends SceneTree

const DATASET_DIR := "res://tests/dataset/guitarset/audio/mic"
## Maximum number of files to decode during the decode test.
const MAX_DECODE_FILES := 10

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
		print("        Dataset: tests/dataset/guitarset/audio/mic/")
		return

	all_wav_paths.sort()
	var scan_paths: Array[String] = all_wav_paths.slice(0, mini(MAX_DECODE_FILES, all_wav_paths.size()))

	_test_wav_decode(scan_paths)
	_test_wav_playback_path(scan_paths[0])


func _test_wav_decode(wav_paths: Array[String]) -> void:
	var decoded_count := 0
	for path in wav_paths:
		var parsed: Dictionary = _parse_wav_pcm16(path)
		if bool(parsed.get("ok", false)):
			decoded_count += 1
	_assert(decoded_count > 0, "decoded at least one dataset WAV file (%d/%d)" % [decoded_count, wav_paths.size()])


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
