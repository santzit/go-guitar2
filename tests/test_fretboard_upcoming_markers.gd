## test_fretboard_upcoming_markers.gd — verifies upcoming marker rendering on fretboard.
##
## Run headless from the project root:
##   godot --headless --path . --script tests/test_fretboard_upcoming_markers.gd

extends SceneTree

const FRETBOARD_SCENE: PackedScene = preload("res://scenes/fretboard.tscn")

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	await process_frame
	await _run_all()
	_print_summary()
	quit(_fail_count)


func _assert_true(condition: bool, description: String) -> void:
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


func _run_all() -> void:
	print("\n═══════ Fretboard Upcoming Marker Tests ═══════")

	var fretboard := FRETBOARD_SCENE.instantiate() as Node3D
	root.add_child(fretboard)
	await process_frame

	# Startup glow should be reset to zero on all strings.
	for i in 6:
		var mi := fretboard.get_node_or_null("String%d" % i) as MeshInstance3D
		_assert_true(mi != null, "String%d mesh exists" % i)
		if mi == null:
			continue
		var mat := mi.get_surface_override_material(0) as ShaderMaterial
		_assert_true(mat != null, "String%d has shader material" % i)
		if mat != null:
			_assert_eq(float(mat.get_shader_parameter("glow_intensity")), 0.0, "String%d glow starts at 0" % i)

	var events: Array = [
		{
			"time_start": 3.0,
			"notes": [{"fret": 3, "string": 1}],
		},
		{
			"time_start": 3.2,
			"notes": [
				{"fret": 5, "string": 2},
				{"fret": 7, "string": 3},
			],
		},
		{
			"time_start": 3.4,
			"notes": [{"fret": 0, "string": 0}],
		},
	]

	fretboard.call("update_upcoming_markers", events, 2.0, 4.0, 0)
	var markers := fretboard.get_node_or_null("UpcomingMarkers") as Node3D
	_assert_true(markers != null, "UpcomingMarkers root exists")
	if markers == null:
		return

	var marker_types: Dictionary = {"single": 0, "chord": 0, "open": 0}
	for child in markers.get_children():
		if child.has_meta("marker_type"):
			var marker_type: String = String(child.get_meta("marker_type"))
			if marker_types.has(marker_type):
				marker_types[marker_type] = int(marker_types[marker_type]) + 1

	_assert_true(int(marker_types["single"]) > 0, "Renders at least one single-note marker")
	_assert_true(int(marker_types["chord"]) > 0, "Renders at least one chord-group marker")
	_assert_eq(int(marker_types["open"]), 0, "Does not render open-string head markers")

	# Markers should be replaced on each update call.
	fretboard.call("update_upcoming_markers", events, 10.0, 1.0, 0)
	_assert_eq(markers.get_child_count(), 0, "Markers clear when no events are upcoming")


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
