extends SceneTree
## Per-string note detection unit tests.
##
## Validates NoteDetection.detect_strings() by synthesising known audio signals
## and verifying that each of the 6 guitar strings is detected (or not) in its
## own frequency band.  Also exercises the Score integration so that a chord
## detection → scoring round-trip can be verified.
##
## Run headless:
##   godot --headless --path . --script tests/note-detection/test_note_detection_strings.gd

const NoteDetection = preload("res://scripts/note_detection.gd")
const Score         = preload("res://scripts/score.gd")

var _pass_count := 0
var _fail_count := 0
var _detector   : NoteDetection
var _score      : Score


func _init() -> void:
	_detector = NoteDetection.new()
	_score    = Score.new()
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


# ─── Test runner ─────────────────────────────────────────────────────────────

func _run_all() -> void:
	print("\n═══════ Per-String Note Detection — Unit Tests ═══════")
	print("  NoteDetection.detect_strings() analyses all 6 strings independently,")
	print("  each within its own frequency band (standard tuning):")
	for s in 6:
		print("    %s" % NoteDetection.STRING_LABELS[s])
	print("")

	_test_silence()
	_test_single_e2_open()
	_test_single_e5_high()
	_test_all_open_strings()
	_test_scoring_all_hit()
	_test_scoring_partial_hit()
	_test_scoring_miss()


# ─── Individual tests ─────────────────────────────────────────────────────────

## Silence → every string must be reported inactive.
func _test_silence() -> void:
	print("  ─── silence: all 6 strings inactive ───")
	var samples := PackedFloat32Array()
	samples.resize(NoteDetection.FFT_WINDOW)

	var result := _detector.detect_strings(samples, 44100)

	_assert(result.size() == 6, "silence: returns exactly 6 entries")
	var all_inactive := true
	for entry in result:
		if bool(entry.get("active", false)):
			all_inactive = false
	_assert(all_inactive, "silence: all 6 strings inactive")
	_print_table(result)


## Pure 82.41 Hz sine (E2 open).
## 82.41 Hz is below the lower bound of every string except string 6 (lo = 82 Hz).
## → only string 6 should be active.
func _test_single_e2_open() -> void:
	print("\n  ─── E2 open (82.41 Hz) → only string 6 active, fret 0 ───")
	var sr      := 44100
	var samples := _sine(82.41, sr, NoteDetection.FFT_WINDOW)

	var result := _detector.detect_strings(samples, sr)

	_assert(result.size() == 6, "E2: returns 6 entries")

	var str6 := result[0]
	_assert(bool(str6.get("active", false)),
		"E2: string 6 is active")
	_assert(int(str6.get("fret", -1)) == 0,
		"E2: string 6 fret = 0  (got %d)" % int(str6.get("fret", -1)))
	_assert(str6.get("note", "") == "E2",
		"E2: string 6 note = E2  (got '%s')" % str6.get("note", ""))

	# 82 Hz is below the minimum of strings 5–1 (starts at 110 Hz),
	# so all higher strings must be inactive.
	for s in range(1, 6):
		_assert(not bool(result[s].get("active", false)),
			"E2: string %d inactive (82 Hz is below its band)" % (6 - s))

	_print_table(result)


## Pure 659.26 Hz sine (E5).
## String bands at 659 Hz: str6 max 330 Hz ✗, str5 max 440 Hz ✗, str4 max 587 Hz ✗,
## str3 max 784 Hz ✓, str2 max 988 Hz ✓, str1 max 1319 Hz ✓.
func _test_single_e5_high() -> void:
	print("\n  ─── E5 (659.26 Hz) → strings 3/2/1 active, strings 6/5/4 inactive ───")
	var sr      := 44100
	var samples := _sine(659.26, sr, NoteDetection.FFT_WINDOW)

	var result := _detector.detect_strings(samples, sr)

	_assert(not bool(result[0].get("active", false)),
		"E5: string 6 inactive (above 330 Hz upper limit)")
	_assert(not bool(result[1].get("active", false)),
		"E5: string 5 inactive (above 440 Hz upper limit)")
	_assert(not bool(result[2].get("active", false)),
		"E5: string 4 inactive (above 587 Hz upper limit)")
	_assert(bool(result[3].get("active", false)),
		"E5: string 3 active (196–784 Hz band contains 659 Hz)")
	_assert(bool(result[4].get("active", false)),
		"E5: string 2 active (247–988 Hz band contains 659 Hz)")
	_assert(bool(result[5].get("active", false)),
		"E5: string 1 active (330–1319 Hz band contains 659 Hz)")

	_print_table(result)


## All 6 open strings played simultaneously (equal-amplitude sines).
## Every string must be active and all frets must be within 0–24.
func _test_all_open_strings() -> void:
	print("\n  ─── All 6 open strings (Em) → all active, frets 0–24 ───")
	var sr       := 44100
	var open_hz: Array[float] = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
	var samples  := _mix(open_hz, sr, NoteDetection.FFT_WINDOW)

	var result := _detector.detect_strings(samples, sr)

	_assert(result.size() == 6, "all open: returns 6 entries")

	var all_active    := true
	var all_in_range  := true
	for entry in result:
		if not bool(entry.get("active", false)):
			all_active = false
		var fret: int = int(entry.get("fret", -1))
		if fret < 0 or fret > NoteDetection.MAX_FRET:
			all_in_range = false

	_assert(all_active,   "all open: all 6 strings active")
	_assert(all_in_range, "all open: all detected frets within 0–%d" % NoteDetection.MAX_FRET)
	_print_table(result)


## Scoring — all 6 open strings played; all 6 expected → ratio 1.0.
func _test_scoring_all_hit() -> void:
	print("\n  ─── scoring: all 6 strings played correctly → ratio 1.0 ───")
	_score.reset()
	var sr       := 44100
	var open_hz: Array[float] = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
	var samples  := _mix(open_hz, sr, NoteDetection.FFT_WINDOW)

	var detection := _detector.detect_strings(samples, sr)
	var detected_str: Array[int] = []
	for entry in detection:
		if bool(entry.get("active", false)):
			detected_str.append(int(entry.get("string_idx", -1)))

	# Expected: all 6 strings must be hit.
	var expected: Array = []
	for s in 6:
		expected.append({"string": s})

	var ev    := _score.score_event(expected, detected_str)
	var ratio := float(ev.get("ratio", -1.0))
	_assert(is_equal_approx(ratio, 1.0),
		"score all hit: ratio = 1.0  (got %.2f)" % ratio)
	_print_score(ev)


## Scoring — only string 6 played; all 6 were expected → 1 / 6 matched.
func _test_scoring_partial_hit() -> void:
	print("\n  ─── scoring: only string 6 played, all 6 expected → 1 matched ───")
	_score.reset()
	var sr      := 44100
	var samples := _sine(82.41, sr, NoteDetection.FFT_WINDOW)

	var detection := _detector.detect_strings(samples, sr)
	var detected_str: Array[int] = []
	for entry in detection:
		if bool(entry.get("active", false)):
			detected_str.append(int(entry.get("string_idx", -1)))

	var expected: Array = []
	for s in 6:
		expected.append({"string": s})

	var ev      := _score.score_event(expected, detected_str)
	var matched := int(ev.get("detected_notes", -1))
	_assert(matched == 1,
		"score partial: 1 string matched  (got %d)" % matched)
	_print_score(ev)


## Scoring — silence; all 6 expected → 0 matched, ratio 0.0.
func _test_scoring_miss() -> void:
	print("\n  ─── scoring: silence, 6 expected → ratio 0.0 ───")
	_score.reset()
	var samples := PackedFloat32Array()
	samples.resize(NoteDetection.FFT_WINDOW)

	var detection := _detector.detect_strings(samples, 44100)
	var detected_str: Array[int] = []
	for entry in detection:
		if bool(entry.get("active", false)):
			detected_str.append(int(entry.get("string_idx", -1)))

	var expected: Array = []
	for s in 6:
		expected.append({"string": s})

	var ev    := _score.score_event(expected, detected_str)
	var ratio := float(ev.get("ratio", -1.0))
	_assert(is_equal_approx(ratio, 0.0),
		"score miss: ratio = 0.0  (got %.2f)" % ratio)
	_print_score(ev)


# ─── Signal generators ────────────────────────────────────────────────────────

## Generate `n` samples of a pure sine wave at `hz`.
func _sine(hz: float, sr: int, n: int) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = sin(TAU * hz * float(i) / float(sr))
	return s


## Generate `n` samples of equal-amplitude mixed sines.
func _mix(freqs: Array[float], sr: int, n: int) -> PackedFloat32Array:
	var s     := PackedFloat32Array()
	s.resize(n)
	var scale := 1.0 / float(freqs.size())
	for i in n:
		var v := 0.0
		for hz in freqs:
			v += sin(TAU * hz * float(i) / float(sr))
		s[i] = v * scale
	return s


# ─── Display helpers ──────────────────────────────────────────────────────────

func _print_table(result: Array[Dictionary]) -> void:
	print("    %s  %-22s  %-6s  %-4s  %s" % [
		" ", "string / band", "note", "fret", "freq (Hz)"])
	for entry in result:
		var s: int      = int(entry.get("string_idx", 0))
		var active: bool = bool(entry.get("active", false))
		if active:
			print("    ●  %-22s  %-6s  %-4d  %.2f Hz" % [
				NoteDetection.STRING_LABELS[s],
				entry.get("note", ""),
				int(entry.get("fret", -1)),
				float(entry.get("hz", 0.0))])
		else:
			print("    ○  %-22s  —" % NoteDetection.STRING_LABELS[s])


func _print_score(ev: Dictionary) -> void:
	print("    Score: %d / %d  (ratio %.2f)" % [
		int(ev.get("detected_notes", 0)),
		int(ev.get("expected_notes", 0)),
		float(ev.get("ratio", 0.0))])


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
