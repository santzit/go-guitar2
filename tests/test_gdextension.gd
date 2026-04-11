## test_gdextension.gd — validates the GoGuitar2 GDExtension at runtime.
##
## Run headless from the project root:
##   Godot_v4.4.1-stable_linux.x86_64 --headless --path . --script tests/test_gdextension.gd
##
## Exit code  0 → all tests passed
## Exit code  1 → one or more tests failed

extends SceneTree

const DLC_DIR := "res://DLC"

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	_run_all()
	_print_summary()
	quit(_fail_count > 0)


# ── Test runner helpers ────────────────────────────────────────────────────────

func _assert(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  " + description)
		_pass_count += 1
	else:
		printerr("  FAIL  " + description)
		_fail_count += 1


func _assert_eq(actual, expected, description: String) -> void:
	if actual == expected:
		print("  PASS  %s  (= %s)" % [description, str(actual)])
		_pass_count += 1
	else:
		printerr("  FAIL  %s  (expected %s, got %s)" % [description, str(expected), str(actual)])
		_fail_count += 1


func _assert_gt(actual: int, threshold: int, description: String) -> void:
	if actual > threshold:
		print("  PASS  %s  (= %d > %d)" % [description, actual, threshold])
		_pass_count += 1
	else:
		printerr("  FAIL  %s  (expected > %d, got %d)" % [description, threshold, actual])
		_fail_count += 1


func _section(name: String) -> void:
	print("\n── %s ──" % name)


# ── Tests ─────────────────────────────────────────────────────────────────────

func _run_all() -> void:
	print("\n═══════ GoGuitar2 GDExtension Tests ═══════")
	_test_class_registration()
	_test_psarc_parsing()
	_test_note_fields()
	_test_audio_engine()


## 1. GDExtension class registration -----------------------------------------

func _test_class_registration() -> void:
	_section("Class Registration")
	_assert(ClassDB.class_exists("RocksmithBridge"),
		"RocksmithBridge class is registered in ClassDB")
	_assert(ClassDB.class_exists("AudioEngine"),
		"AudioEngine class is registered in ClassDB")

	if ClassDB.class_exists("RocksmithBridge"):
		var bridge: Object = ClassDB.instantiate("RocksmithBridge")
		_assert(bridge != null,
			"RocksmithBridge can be instantiated")
		_assert(bridge.has_method("load_psarc"),
			"RocksmithBridge has load_psarc() method")
		_assert(bridge.has_method("get_notes"),
			"RocksmithBridge has get_notes() method")
		_assert(bridge.has_method("get_wem_bytes"),
			"RocksmithBridge has get_wem_bytes() method")

	if ClassDB.class_exists("AudioEngine"):
		var audio_engine: Object = ClassDB.instantiate("AudioEngine")
		_assert(audio_engine != null,
			"AudioEngine can be instantiated")
		_assert(audio_engine.has_method("set_music_gain_db"),
			"AudioEngine has set_music_gain_db() method")
		_assert(audio_engine.has_method("set_master_gain_db"),
			"AudioEngine has set_master_gain_db() method")
		_assert(audio_engine.has_method("set_music_mute"),
			"AudioEngine has set_music_mute() method")
		_assert(audio_engine.has_method("set_master_mute"),
			"AudioEngine has set_master_mute() method")


## 2. PSARC loading and note parsing -----------------------------------------

func _test_psarc_parsing() -> void:
	_section("PSARC Parsing")

	if not ClassDB.class_exists("RocksmithBridge"):
		printerr("  SKIP  RocksmithBridge not available — skipping PSARC tests")
		return

	var psarc_path: String = _find_first_psarc()
	if psarc_path == "":
		printerr("  SKIP  No .psarc found in %s — skipping parse tests" % DLC_DIR)
		return

	print("  INFO  Using PSARC: " + psarc_path)
	var bridge: Object = ClassDB.instantiate("RocksmithBridge")
	var ok: bool = bridge.load_psarc(ProjectSettings.globalize_path(psarc_path))
	_assert(ok, "load_psarc() returns true for '%s'" % psarc_path.get_file())

	if not ok:
		return

	var notes: Array = bridge.get_notes()
	_assert_gt(notes.size(), 0, "get_notes() returns at least one note")

	var wem: PackedByteArray = bridge.get_wem_bytes()
	_assert_gt(wem.size(), 0, "get_wem_bytes() returns non-empty bytes")

	print("  INFO  Notes: %d   WEM: %d bytes" % [notes.size(), wem.size()])


## 3. Note dictionary field types and ranges ---------------------------------

func _test_note_fields() -> void:
	_section("Note Field Validation")

	if not ClassDB.class_exists("RocksmithBridge"):
		printerr("  SKIP  RocksmithBridge not available")
		return

	var psarc_path: String = _find_first_psarc()
	if psarc_path == "":
		printerr("  SKIP  No .psarc found")
		return

	var bridge: Object = ClassDB.instantiate("RocksmithBridge")
	if not bridge.load_psarc(ProjectSettings.globalize_path(psarc_path)):
		printerr("  SKIP  Could not load PSARC for field validation")
		return

	var notes: Array = bridge.get_notes()
	if notes.is_empty():
		printerr("  SKIP  No notes returned")
		return

	var first: Dictionary = notes[0]
	_assert(first.has("time"),     "Note dictionary has 'time' key")
	_assert(first.has("fret"),     "Note dictionary has 'fret' key")
	_assert(first.has("string"),   "Note dictionary has 'string' key")
	_assert(first.has("duration"), "Note dictionary has 'duration' key")

	# All notes: validate ranges.
	var frets_out_of_range := 0
	var strings_out_of_range := 0
	var negative_time_count := 0
	for nd: Dictionary in notes:
		var f: int = nd["fret"]
		var s: int = nd["string"]
		var t: float = nd["time"]
		if f < 0 or f > 24:
			frets_out_of_range += 1
		if s < 0 or s > 5:
			strings_out_of_range += 1
		if t < 0.0:
			negative_time_count += 1

	_assert_eq(frets_out_of_range, 0,
		"No notes with fret out of range [0..24]")
	_assert_eq(strings_out_of_range, 0,
		"No notes with string out of range [0..5]")
	_assert_eq(negative_time_count, 0,
		"No notes with negative time")

	# Check notes are time-sorted.
	var prev_time := -1.0
	var unsorted_count := 0
	for nd: Dictionary in notes:
		var t: float = nd["time"]
		if t < prev_time:
			unsorted_count += 1
		prev_time = t
	_assert_eq(unsorted_count, 0, "Notes are in ascending time order")


## 4. AudioEngine WEM decoding -----------------------------------------------

func _test_audio_engine() -> void:
	_section("AudioEngine (WEM Decode)")

	if not ClassDB.class_exists("AudioEngine"):
		printerr("  SKIP  AudioEngine not available")
		return

	if not ClassDB.class_exists("RocksmithBridge"):
		printerr("  SKIP  RocksmithBridge not available")
		return

	var psarc_path: String = _find_first_psarc()
	if psarc_path == "":
		printerr("  SKIP  No .psarc found")
		return

	var bridge: Object = ClassDB.instantiate("RocksmithBridge")
	if not bridge.load_psarc(ProjectSettings.globalize_path(psarc_path)):
		printerr("  SKIP  Could not load PSARC for audio test")
		return

	var wem: PackedByteArray = bridge.get_wem_bytes()
	if wem.is_empty():
		printerr("  SKIP  No WEM bytes in PSARC")
		return

	var eng: Object = ClassDB.instantiate("AudioEngine")
	var ok: bool = eng.open(wem)
	_assert(ok, "AudioEngine.open() succeeds with WEM bytes")

	if not ok:
		return

	var channels: int = eng.get_channels()
	var rate: int = eng.get_sample_rate()
	_assert(channels >= 1 and channels <= 2,
		"AudioEngine.get_channels() returns 1 or 2 (got %d)" % channels)
	_assert(rate > 0,
		"AudioEngine.get_sample_rate() > 0 (got %d)" % rate)

	var pcm: PackedByteArray = eng.decode_all()
	_assert_gt(pcm.size(), 0, "AudioEngine.decode_all() returns PCM bytes")
	print("  INFO  PCM: %d bytes  ch=%d  rate=%d" % [pcm.size(), channels, rate])

	var muted_eng: Object = ClassDB.instantiate("AudioEngine")
	muted_eng.set_music_mute(true)
	var muted_ok: bool = muted_eng.open(wem)
	_assert(muted_ok, "AudioEngine.open() succeeds when music bus is muted")
	if muted_ok:
		var muted_pcm: PackedByteArray = muted_eng.decode_all()
		var has_non_zero := false
		var bytes_to_check: int = mini(32768, muted_pcm.size())
		for i in range(bytes_to_check):
			var b: int = muted_pcm[i]
			if b != 0:
				has_non_zero = true
				break
		_assert(not has_non_zero, "Muted Music bus outputs silent PCM (sampled bytes)")


# ── Summary ───────────────────────────────────────────────────────────────────

func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_first_psarc() -> String:
	var dir := DirAccess.open(DLC_DIR)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.to_lower().ends_with(".psarc"):
			dir.list_dir_end()
			return DLC_DIR.path_join(name)
		name = dir.get_next()
	dir.list_dir_end()
	return ""
