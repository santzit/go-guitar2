## test_note_rendering_paths.gd — verifies fretted/open note spawn paths.
##
## Run headless from the project root:
##   godot --headless --path . --script tests/test_note_rendering_paths.gd

extends SceneTree

const NOTE_POOL_SCENE: PackedScene = preload("res://scenes/note_pool.tscn")
const ChartCommon = preload("res://scripts/common.gd")

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	_run_all()
	_print_summary()
	quit(_fail_count)


func _assert_true(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  %s" % description)
		_pass_count += 1
	else:
		printerr("  FAIL  %s" % description)
		_fail_count += 1


func _assert_near(actual: float, expected: float, description: String) -> void:
	if is_equal_approx(actual, expected):
		print("  PASS  %s  (= %.3f)" % [description, actual])
		_pass_count += 1
	else:
		printerr("  FAIL  %s  (expected %.3f, got %.3f)" % [description, expected, actual])
		_fail_count += 1


func _run_all() -> void:
	print("\n═══════ Note Rendering Path Tests ═══════")

	var pool := NOTE_POOL_SCENE.instantiate() as Node3D
	root.add_child(pool)

	var fretted := pool.call("spawn_note", 3, 2, 5.0, 0.5, true) as Node3D
	_assert_true(fretted != null, "spawn_note returns a fretted note instance")
	_assert_true(fretted != null and fretted.visible, "fretted note starts visible")
	_assert_true(fretted != null and not fretted.has_method("is_open_string"), "fretted note uses note.gd path")

	var open_note := pool.call("spawn_note", 0, 1, 5.0, 0.5, false) as Node3D
	_assert_true(open_note != null, "spawn_note returns an open-string instance for fret 0")
	_assert_true(open_note != null and open_note.visible, "open-string note starts visible")
	_assert_true(open_note != null and open_note.has_method("is_open_string") and open_note.call("is_open_string"), "open-string path uses open_string.gd")
	var open_sustain := open_note.get_node_or_null("SustainTrail") as MeshInstance3D if open_note != null else null
	_assert_true(open_sustain != null and open_sustain.visible, "open-string sustain trail is visible for sustained note")
	if open_sustain != null:
		var sustain_mesh := open_sustain.mesh as BoxMesh
		_assert_true(sustain_mesh != null and sustain_mesh.size.z > 0.0, "open-string sustain trail has positive length")

	pool.call("tick", 4.0)
	if fretted != null:
		_assert_near(fretted.position.z, ChartCommon.note_world_z(5.0, 4.0, 0.0), "fretted note z follows audio-clock mapping")
	if open_note != null:
		_assert_near(open_note.position.z, ChartCommon.note_world_z(5.0, 4.0, 0.0), "open-string z follows audio-clock mapping")

	pool.call("clear_notes")
	_assert_true(fretted == null or not fretted.visible, "clear_notes hides fretted notes")
	_assert_true(open_note == null or not open_note.visible, "clear_notes hides open-string notes")


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
