## test_fretboard_upcoming_markers.gd — verifies upcoming marker rendering on fretboard.
##
## Run headless from the project root:
##   godot --headless --path . --script tests/test_fretboard_upcoming_markers.gd

extends SceneTree

const FRETBOARD_SCENE: PackedScene = preload("res://scenes/fretboard.tscn")
const NOTE_HEAD_POOL_SCENE: PackedScene = preload("res://scenes/note_head_pool.tscn")

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


func _assert_near(actual: float, expected: float, description: String) -> void:
	if is_equal_approx(actual, expected):
		print("  PASS  %s  (= %.3f)" % [description, actual])
		_pass_count += 1
	else:
		printerr("  FAIL  %s  (expected %.3f, got %.3f)" % [description, expected, actual])
		_fail_count += 1


func _run_all() -> void:
	print("\n═══════ Fretboard Upcoming Marker Tests ═══════")

	var note_head_pool := NOTE_HEAD_POOL_SCENE.instantiate() as Node3D
	note_head_pool.name = "NoteHeadPool"
	root.add_child(note_head_pool)

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
			"time_start": 2.3,
			"notes": [
				{"fret": 3, "string": 1},
				{"fret": 5, "string": 2},
			],
		},
		{
			"time_start": 2.6,
			"notes": [{"fret": 7, "string": 3}],
		},
		{
			"time_start": 2.9,
			"notes": [{"fret": 0, "string": 0}],
		},
		{
			"time_start": 3.3,
			"notes": [{"fret": 9, "string": 4}],
		},
		{
			"time_start": 3.7,
			"notes": [{"fret": 11, "string": 5}],
		},
		{
			"time_start": 4.2,
			"notes": [{"fret": 14, "string": 2}],
		},
	]

	fretboard.call("update_upcoming_markers", events, 2.0, 4.0, 0)
	_assert_true(note_head_pool != null, "NoteHeadPool root exists")
	if note_head_pool == null:
		return

	var marker_types: Dictionary = {"single": 0, "chord": 0, "open": 0}
	var marker_styles: Dictionary = {"primary": 0, "upcoming_dim": 0}
	var head_by_fret: Dictionary = {}
	for head in note_head_pool.call("get_active_heads"):
		if head != null and head.has_meta("marker_type"):
			var marker_type: String = String(head.get_meta("marker_type"))
			if marker_types.has(marker_type):
				marker_types[marker_type] = int(marker_types[marker_type]) + 1
		if head != null and head.has_meta("visual_style"):
			var marker_style: String = String(head.get_meta("visual_style"))
			if marker_styles.has(marker_style):
				marker_styles[marker_style] = int(marker_styles[marker_style]) + 1
		if head != null and head.has_meta("fret"):
			head_by_fret[int(head.get_meta("fret"))] = head

	_assert_true(int(marker_types["single"]) > 0, "Renders at least one single-note marker")
	_assert_true(int(marker_types["chord"]) > 0, "Renders chord marker type for chord events")
	_assert_eq(int(marker_types["open"]), 0, "Does not render open-string head markers")
	_assert_eq(int(marker_styles["primary"]), 2, "All notes in the next upcoming chord use primary style")
	_assert_true(int(marker_styles["upcoming_dim"]) > 0, "Secondary upcoming markers use dim style")
	_assert_eq(int(note_head_pool.call("active_count")), 5, "Only <=2s fretted markers are rendered")

	var primary_alpha: float = -1.0
	var primary_glow: float = -1.0
	var secondary_ok: bool = true
	var secondary_seen: int = 0

	for fret in [3, 5, 7, 9, 11]:
		var h: Node3D = head_by_fret.get(fret, null)
		_assert_true(h != null, "Expected marker exists for fret %d" % fret)

	var beyond_window: Node3D = head_by_fret.get(14, null)
	_assert_true(beyond_window == null, "Markers beyond 2s window are not rendered")

	for head in note_head_pool.call("get_active_heads"):
		if head == null:
			continue
		var marker := head.get_node_or_null("NoteMarker") as MeshInstance3D
		var mat := marker.get_surface_override_material(0) as ShaderMaterial if marker != null else null
		_assert_true(mat != null, "Active marker has shader material")
		if mat == null:
			continue
		var c: Color = mat.get_shader_parameter("base_color")
		var ge: float = float(mat.get_shader_parameter("glow_energy"))
		var style: String = String(head.get_meta("visual_style")) if head.has_meta("visual_style") else ""
		if style == "primary":
			primary_alpha = c.a
			primary_glow = ge
		elif style == "upcoming_dim":
			secondary_seen += 1
			if not (is_equal_approx(c.a, 0.22) and is_equal_approx(ge, 0.0)):
				secondary_ok = false

	if primary_alpha >= 0.0:
		_assert_near(primary_alpha, 1.0, "Primary marker remains opaque")
	if primary_glow >= 0.0:
		_assert_near(primary_glow, 2.4, "Primary marker keeps glow")
	_assert_true(secondary_seen > 0, "At least one secondary marker is rendered")
	_assert_true(secondary_ok, "All secondary markers are transparent with no glow")
	_assert_true(
		head_by_fret.get(3, null).get_meta("visual_style") == "primary" and head_by_fret.get(5, null).get_meta("visual_style") == "primary",
		"Closest chord notes remain primary"
	)

	# Markers should be replaced on each update call.
	fretboard.call("update_upcoming_markers", events, 10.0, 1.0, 0)
	_assert_eq(int(note_head_pool.call("active_count")), 0, "Markers clear when no events are upcoming")


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n═══════ Results: %d/%d passed ═══════" % [_pass_count, total])
	if _fail_count > 0:
		printerr("%d test(s) FAILED" % _fail_count)
