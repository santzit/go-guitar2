## test_note_chord_visibility_baseline.gd — baseline render-path checks.
##
## Run headless from the project root:
##   godot --headless --path . --script tests/test_note_chord_visibility_baseline.gd

extends SceneTree

const CHORD_POOL_SCENE: PackedScene = preload("res://scenes/chord_pool.tscn")
const BRIDGE_SCRIPT = preload("res://scripts/goguitar_bridge.gd")
const GAME_STATE_SCRIPT = preload("res://scripts/game_state.gd")
const DLC_DIR := "res://DLC"
const MAX_TEST_EVENTS: int = 24

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	await process_frame
	_run_all()
	_print_summary()
	quit(_fail_count)


func _assert_true(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  " + description)
		_pass_count += 1
	else:
		printerr("  FAIL  " + description)
		_fail_count += 1


func _assert_gt(actual: int, threshold: int, description: String) -> void:
	if actual > threshold:
		print("  PASS  %s  (= %d > %d)" % [description, actual, threshold])
		_pass_count += 1
	else:
		printerr("  FAIL  %s  (expected > %d, got %d)" % [description, threshold, actual])
		_fail_count += 1


func _run_all() -> void:
	print("\n═══════ Note/Chord Visibility Baseline Tests ═══════")

	var psarc_path: String = _find_first_psarc()
	_assert_true(psarc_path != "", "Found at least one DLC .psarc")
	if psarc_path == "":
		return

	var bridge = BRIDGE_SCRIPT.new()
	GAME_STATE_SCRIPT.difficulty_percent = 100.0
	var loaded: bool = bridge.load_psarc_abs(ProjectSettings.globalize_path(psarc_path))
	_assert_true(loaded, "Bridge loads selected PSARC")
	if not loaded:
		return

	var events: Array = bridge.get_play_events()
	_assert_gt(events.size(), 0, "Bridge returns non-empty play events")
	if events.is_empty():
		return

	var pool := CHORD_POOL_SCENE.instantiate() as Node3D
	_assert_true(pool != null, "ChordPool scene instantiates")
	if pool == null:
		return
	root.add_child(pool)

	# Spawn a fixed number of early events from the chart.
	var spawned_events := 0
	for ev in events:
		if spawned_events >= MAX_TEST_EVENTS:
			break
		var t0: float = float(ev.get("time_start", 0.0))
		pool.call(
			"spawn_event",
			ev.get("notes", []),
			t0,
			String(ev.get("chord_name", "")),
			bool(ev.get("show_details", false)),
			String(ev.get("kind", "single")),
			bool(ev.get("force_outline", false)),
			int(ev.get("outline_min_fret", -1)),
			int(ev.get("outline_max_fret", -1)),
			int(ev.get("outline_min_string", -1)),
			int(ev.get("outline_max_string", -1))
		)
		spawned_events += 1

	_assert_gt(spawned_events, 0, "Spawn loop submits at least one event")

	var all_notes: Array = _collect_note_nodes(pool)
	_assert_gt(all_notes.size(), 0, "Spawn path creates note nodes in scene tree")

	var visible_notes := 0
	var mesh_ready_notes := 0
	for note in all_notes:
		if note.visible:
			visible_notes += 1
		var note_marker: MeshInstance3D = note.get_node_or_null("NoteMarker") as MeshInstance3D
		if note_marker != null and note_marker.mesh != null and note_marker.mesh.get_surface_count() > 0:
			mesh_ready_notes += 1

	_assert_gt(visible_notes, 0, "At least one spawned note is visible")
	_assert_gt(mesh_ready_notes, 0, "At least one spawned note has a renderable mesh")

	# Verify tick advances active note depth positions.
	var before_z: float = 0.0
	var after_z: float = 0.0
	var sampled := false
	for note in all_notes:
		if note.visible:
			before_z = note.position.z
			sampled = true
			break
	_assert_true(sampled, "Able to sample a visible note for Z movement")
	if sampled:
		pool.call("tick", 1.5)
		for note in all_notes:
			if note.visible:
				after_z = note.position.z
				break
		_assert_true(after_z != before_z, "Note Z changes after tick(song_time)")


func _collect_note_nodes(root_node: Node) -> Array:
	var out: Array = []
	for child in root_node.get_children():
		if child is Node:
			if child.has_method("setup") and child.get_node_or_null("NoteMarker") != null:
				out.append(child)
			var nested: Array = _collect_note_nodes(child)
			for n in nested:
				out.append(n)
	return out


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


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
