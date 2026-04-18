extends SceneTree

const DATASET_DIR := "res://tests/dataset/guitarset/audio/mic"

## Samples used for each autocorrelation analysis window (≈46 ms at 44100 Hz).
const ANALYSIS_WINDOW := 2048
## Maximum evenly-spaced analysis windows evaluated per file.
const MAX_WINDOWS_PER_FILE := 8
## Minimum RMS amplitude to consider a window non-silent.
const MIN_RMS := 0.01
## Guitar frequency bounds for autocorrelation lag search.
## Lower bound matches the lowest open string on a standard guitar (E2 ≈ 82.4 Hz).
const MIN_FREQ_HZ := 80.0
const MAX_FREQ_HZ := 1200.0
## Highest playable fret (standard 24-fret guitar).
const MAX_FRET := 24

## Open-string MIDI note numbers in standard tuning.
## Index 0 → string 6 (lowest, E2); index 5 → string 1 (highest, e4).
const OPEN_STRING_MIDI: Array[int] = [40, 45, 50, 55, 59, 64]
## String frequency ranges for display (open note → fret 24).
const STRING_RANGE_HZ: Array[String] = [
	"E2  82–330 Hz",
	"A2 110–440 Hz",
	"D3 147–587 Hz",
	"G3 196–784 Hz",
	"B3 247–988 Hz",
	"e4 330–1319 Hz",
]
## Chromatic note names (semitone 0 = C).
const NOTE_NAMES: Array[String] = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

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
	print("\n═══════ Guitar String / Fret Note Detection Tests ═══════")
	print("  Standard tuning string frequency ranges:")
	for s in STRING_RANGE_HZ.size():
		print("    string %d  %s" % [6 - s, STRING_RANGE_HZ[s]])
	print("")

	var all_wav_paths: Array[String] = _collect_wav_paths(DATASET_DIR)
	if all_wav_paths.is_empty():
		print("  SKIP  No WAV files found under %s" % DATASET_DIR)
		print("        Dataset: tests/dataset/guitarset/audio/mic/")
		return

	all_wav_paths.sort()
	for path in all_wav_paths:
		_test_file(path)


## Analyse one WAV file: detect pitches across evenly-spaced windows and map
## each pitch to the most natural guitar string and fret position.
func _test_file(path: String) -> void:
	var fname := path.get_file()
	var key := _parse_key_from_filename(fname)
	print("\n  ─── %s  (key: %s) ───" % [fname, key])

	var parsed := _parse_wav_pcm16(path)
	if not bool(parsed.get("ok", false)):
		print("    ERROR: could not decode file")
		_assert(false, "decoded %s" % fname)
		return

	var sr: int = int(parsed.get("sample_rate", 0))
	var channels: int = int(parsed.get("channels", 0))
	_assert(true, "decoded %s  (%d Hz, %d ch)" % [fname, sr, channels])

	var samples: PackedFloat32Array = parsed.get("samples", PackedFloat32Array())
	var total := samples.size()
	var duration_s := float(total) / float(sr)

	# Skip 5 % at each edge to avoid fade-in / fade-out silence.
	var edge := total / 20
	var usable := total - edge * 2
	var hop := maxi(ANALYSIS_WINDOW, usable / MAX_WINDOWS_PER_FILE)

	print("    duration: %.2f s  |  sample rate: %d Hz  |  channels: %d" % [
		duration_s, sr, channels])
	print("    analysis: %d-sample windows, hop %d samples (%.0f ms)" % [
		ANALYSIS_WINDOW, hop, float(hop) / float(sr) * 1000.0])
	print("")
	print("    %-8s  %-10s  %-6s  %-6s  %-4s  %s" % [
		"time(s)", "freq(Hz)", "note", "str", "fret", "string range"])
	print("    %-8s  %-10s  %-6s  %-6s  %-4s  %s" % [
		"────────", "──────────", "──────", "──────", "────", "────────────────"])

	var detected_count := 0
	var all_in_range := true
	var t := edge
	while t + ANALYSIS_WINDOW <= total - edge:
		var rms := _rms(samples, t, ANALYSIS_WINDOW)
		if rms >= MIN_RMS:
			var hz := _estimate_frequency(samples, sr, t, ANALYSIS_WINDOW)
			if hz > 0.0:
				detected_count += 1
				var midi := roundi(_hz_to_midi(hz))
				var note_name := _midi_to_note_name(midi)
				var sf: Array = _midi_to_string_fret(midi)
				var fret_valid: bool = sf[0] >= 0 and sf[1] >= 0 and sf[1] <= MAX_FRET
				if not fret_valid:
					all_in_range = false
				var time_sec := float(t) / float(sr)
				var str_num: int = (6 - int(sf[0])) if sf[0] >= 0 else -1
				var str_str := ("str %d" % str_num) if sf[0] >= 0 else "  ?"
				var fret_str := ("%d" % sf[1]) if fret_valid else "OUT OF RANGE"
				var range_str := STRING_RANGE_HZ[sf[0]] if sf[0] >= 0 else ""
				print("    %-8.3f  %-10.2f  %-6s  %-6s  %-4s  %s" % [
					time_sec, hz, note_name, str_str, fret_str, range_str])
		t += hop

	if detected_count == 0:
		print("    (no pitched windows above RMS threshold %.3f)" % MIN_RMS)

	_assert(detected_count > 0,
		"at least one pitch detected in %s" % fname)
	_assert(all_in_range,
		"all detected pitches within fret 0–%d in %s" % [MAX_FRET, fname])


## Parse the musical key token from a GuitarSet filename.
## e.g. "00_BN1-129-Eb_solo_mic.wav" → "Eb"
func _parse_key_from_filename(fname: String) -> String:
	var parts := fname.get_basename().split("_")
	for part in parts:
		var subs := part.split("-")
		if subs.size() >= 3:
			var candidate: String = subs[subs.size() - 1]
			if candidate.length() >= 1 and candidate.length() <= 2:
				var first := candidate.unicode_at(0)
				if first >= 65 and first <= 71:  # A–G
					return candidate
	return "?"


## Root-mean-square amplitude of `n` samples starting at `offset`.
func _rms(samples: PackedFloat32Array, offset: int, n: int) -> float:
	var sum := 0.0
	for i in n:
		var s: float = samples[offset + i]
		sum += s * s
	return sqrt(sum / float(n))


## Autocorrelation pitch estimator over `n` samples starting at `offset`.
func _estimate_frequency(samples: PackedFloat32Array, sr: int, offset: int, n: int) -> float:
	var min_lag := maxi(1, int(floor(float(sr) / MAX_FREQ_HZ)))
	var max_lag := mini(n - 1, int(ceil(float(sr) / MIN_FREQ_HZ)))
	if max_lag <= min_lag:
		return 0.0
	var best_lag := -1
	var best_corr := -INF
	for lag in range(min_lag, max_lag + 1):
		var corr := 0.0
		var limit := n - lag
		for i in limit:
			corr += samples[offset + i] * samples[offset + i + lag]
		if corr > best_corr:
			best_corr = corr
			best_lag = lag
	if best_lag <= 0 or best_corr <= 0.0:
		return 0.0
	return float(sr) / float(best_lag)


## Convert frequency in Hz to continuous MIDI note number.
## MIDI 69 = A4 = 440 Hz.
func _hz_to_midi(hz: float) -> float:
	if hz <= 0.0:
		return 0.0
	return 69.0 + 12.0 * log(hz / 440.0) / log(2.0)


## Return the note name + octave for a MIDI note number (e.g. MIDI 40 → "E2").
func _midi_to_note_name(midi: int) -> String:
	var semitone := midi % 12
	var octave := midi / 12 - 1
	return NOTE_NAMES[semitone] + str(octave)


## Map a MIDI note to the most natural guitar position (lowest fret possible).
## Returns [string_index, fret] where string_index 0 = string 6 (low E).
## Returns [-1, -1] when the note is outside the guitar's range.
func _midi_to_string_fret(midi: int) -> Array:
	var best_str := -1
	var best_fret := MAX_FRET + 1
	for s in OPEN_STRING_MIDI.size():
		var fret := midi - OPEN_STRING_MIDI[s]
		if fret >= 0 and fret <= MAX_FRET:
			if fret < best_fret:
				best_fret = fret
				best_str = s
	if best_str < 0:
		return [-1, -1]
	return [best_str, best_fret]


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
