extends Node3D
const ChartCommon = preload("res://scripts/common.gd")
## chord.gd — Unified play-event container for single notes and chords.
##
## Single-note events:
##   - one note slot marker
##   - no chord label / no outline
## Chord events:
##   - multiple note-slot markers
##   - optional chord label
##   - shader outline with glow only on the bottom corners
##
## Coordinate conventions (shared via ChartCommon):
##   X = fret position, Y = string height, Z = time (spawns at -20 → travels to 0)
##
## The border always spans BORDER_FRET_SPAN (4) frets starting from min_fret.
## The interior of the border box is fully transparent (non-edge pixels discarded).

# ── Chord indicator visual: same mesh/color mapping as NoteMarker ────────────
const NOTE_MESH: ArrayMesh = preload("res://assets/models/note.obj")
const STRING_COLORS: Array[Color] = [
	Color(0.98, 0.26, 0.22, 1.0), # red
	Color(0.98, 0.78, 0.16, 1.0), # yellow
	Color(0.20, 0.80, 0.95, 1.0), # cyan
	Color(1.00, 0.55, 0.10, 1.0), # orange
	Color(0.20, 0.88, 0.30, 1.0), # green
	Color(0.72, 0.38, 0.98, 1.0), # purple
]
const NOTE_MARKER_LOCAL_OFFSET: Vector3 = Vector3(0.0, -0.01, 0.08)
const NOTE_MARKER_LOCAL_ROTATION_DEGREES: Vector3 = Vector3(0.0, 90.0, 0.0)

## Project font — Inter 18pt Bold, used for the chord name Label3D.
const _INTER_BOLD: FontFile = preload("res://assets/fonts/Inter_18pt-Bold.ttf")

## Border shader — edge outline + bottom-corner glow.
## The interior is discarded; only border pixels render.
const _BORDER_SHADER_CODE: String = """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled;
uniform float border_u : hint_range(0.01, 0.5) = 0.04;
uniform float border_v : hint_range(0.01, 0.5) = 0.04;
uniform float corner_u : hint_range(0.02, 0.5) = 0.18;
uniform vec4 outline_color : source_color = vec4(0.55, 0.85, 1.0, 0.90);
uniform vec4 corner_glow_color : source_color = vec4(0.70, 0.95, 1.0, 1.0);
uniform float corner_glow_strength : hint_range(0.0, 8.0) = 3.0;
void fragment() {
	bool on_edge = UV.x < border_u || UV.x > 1.0 - border_u
				|| UV.y < border_v || UV.y > 1.0 - border_v;
	if (!on_edge) { discard; }
	bool on_bottom = UV.y < border_v;
	bool on_left_corner = UV.x < corner_u;
	bool on_right_corner = UV.x > 1.0 - corner_u;
	bool glow_corner = on_bottom && (on_left_corner || on_right_corner);
	ALBEDO = outline_color.rgb;
	ALPHA  = outline_color.a;
	EMISSION = glow_corner ? corner_glow_color.rgb * corner_glow_strength : vec3(0.0);
}
"""

## Notes / chords spawn at Z = START_Z and travel toward STRUM_Z = 0.
const START_Z          : float = -20.0
const STRUM_Z          : float =  0.0
const TRAVEL_SPEED     : float =  2.0   # must match note.gd and music_play.gd
const MISS_HOLD        : float =  1.0   # seconds to keep visible after strum
## Chord events span this many frets (first note fret + 3 more).
const BORDER_FRET_SPAN : int   = 4

var time_offset    : float = 0.0
var is_active      : bool  = false
var _miss_until    : float = -1.0

## Lazy-initialised persistent nodes (survive pool reuse).
var _border_mesh   : MeshInstance3D = null
var _chord_label   : Label3D        = null
## Dynamic indicator nodes — freed on each deactivate and recreated in setup.
var _indicators    : Array          = []


## Activate this chord container.
## p_notes:        Array[Dictionary{fret,string}] — the chord's notes
## p_time:         float  — timestamp (seconds)
## p_chord_name:   String — displayed only on first/changed occurrence
## p_show_details: bool   — true = finger indicators + label; false = border only
func setup(
		p_notes: Array,
		p_time: float,
		p_chord_name: String,
		p_show_details: bool,
		p_event_kind: String
) -> void:
	time_offset = p_time
	is_active   = true
	visible     = true
	_miss_until = -1.0
	var is_single_event : bool = (p_event_kind == "single") or (p_notes.size() <= 1)

	# ── Determine extent of notes ──────────────────────────────────────────────
	var min_fret   : int = 999
	var min_string : int = 999
	var max_string : int = -1
	for n in p_notes:
		var f : int = int(n.get("fret", 0))
		var s : int = int(n.get("string", 0))
		if f < min_fret:   min_fret   = f
		if s < min_string: min_string = s
		if s > max_string: max_string = s
	if min_fret == 999 or min_string == 999:
		return

	# ── Container world position ───────────────────────────────────────────────
	# Single-note events use exactly one fret slot; chord events use a 4-fret hand window.
	var fret_span : int = 1 if is_single_event else BORDER_FRET_SPAN
	var left_x   : float = ChartCommon.fret_separator_world_x(min_fret - 1)
	var right_x  : float = ChartCommon.fret_separator_world_x(min_fret - 1 + fret_span)
	var top_y    : float = ChartCommon.string_world_y(min_string)
	var bot_y    : float = ChartCommon.string_world_y(max_string) - ChartCommon.STRING_SLOT_HEIGHT
	var center_x : float = (left_x + right_x) * 0.5
	var center_y : float = (top_y + bot_y) * 0.5
	position = Vector3(center_x, center_y, START_Z)

	var show_outline : bool = not is_single_event
	var show_label   : bool = p_show_details and not is_single_event

	# ── Border box ─────────────────────────────────────────────────────────────
	if show_outline:
		var w : float = right_x - left_x
		var h : float = absf(top_y - bot_y) + ChartCommon.STRING_SLOT_HEIGHT
		_ensure_border(w, h)
		_border_mesh.visible = true
	elif is_instance_valid(_border_mesh):
		_border_mesh.visible = false

	# ── Per-string finger indicators (always rendered for note slots) ──────────
	_clear_indicators()
	for n in p_notes:
		var f : int = int(n.get("fret", 0))
		var s : int = clampi(int(n.get("string", 0)), 0, 5)
		_add_indicator(f, s, center_x, center_y)

	# ── Chord name label (top-left outside the container) ─────────────────────
	_ensure_label()
	_chord_label.visible = show_label
	if show_label:
		_chord_label.text = p_chord_name
		_chord_label.position = Vector3(
			left_x  - center_x - 0.25,
			top_y   - center_y + 0.15,
			0.10
		)


## Create (or reuse) the border MeshInstance3D; resize for current event extents.
func _ensure_border(w: float, h: float) -> void:
	if _border_mesh == null:
		_border_mesh = MeshInstance3D.new()
		_border_mesh.position = Vector3(0.0, 0.0, 0.05)
		add_child(_border_mesh)
	# Convert a target ~2.5 cm world-unit border thickness to UV-space fractions.
	# uv_frac = desired_thickness_m / mesh_dimension_m.
	var bu : float = clampf(0.025 / maxf(w, 0.001), 0.015, 0.12)
	var bv : float = clampf(0.025 / maxf(h, 0.001), 0.015, 0.20)
	var shader := Shader.new()
	shader.code = _BORDER_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("outline_color", Color(0.55, 0.85, 1.0, 0.9))
	mat.set_shader_parameter("corner_glow_color", Color(0.70, 0.95, 1.0, 1.0))
	mat.set_shader_parameter("corner_glow_strength", 3.0)
	mat.set_shader_parameter("border_u", bu)
	mat.set_shader_parameter("border_v", bv)
	mat.set_shader_parameter("corner_u", 0.18)
	var plane := PlaneMesh.new()
	plane.size        = Vector2(w, h)
	plane.orientation = PlaneMesh.FACE_Z
	plane.material    = mat
	_border_mesh.mesh = plane


## Create the chord-name Label3D on first use.
func _ensure_label() -> void:
	if _chord_label == null:
		_chord_label = Label3D.new()
		_chord_label.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
		_chord_label.pixel_size       = 0.005
		_chord_label.font_size        = 48
		_chord_label.font             = _INTER_BOLD
		_chord_label.modulate         = Color(1.0, 1.0, 1.0, 1.0)
		_chord_label.outline_size     = 8
		_chord_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		add_child(_chord_label)


## Add a finger indicator MeshInstance3D child for one string-note.
func _add_indicator(f: int, s: int, center_x: float, center_y: float) -> void:
	var ind := MeshInstance3D.new()
	ind.position = Vector3(
		ChartCommon.fret_mid_world_x(f - 1) - center_x + NOTE_MARKER_LOCAL_OFFSET.x,
		ChartCommon.string_world_y(s)        - center_y + NOTE_MARKER_LOCAL_OFFSET.y,
		NOTE_MARKER_LOCAL_OFFSET.z
	)
	ind.rotation_degrees = NOTE_MARKER_LOCAL_ROTATION_DEGREES
	ind.mesh = NOTE_MESH
	var mat := StandardMaterial3D.new()
	var color: Color = STRING_COLORS[s] if s < STRING_COLORS.size() else Color.WHITE
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	mat.metallic = 0.2
	mat.roughness = 0.08
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.0
	mat.rim_enabled = true
	mat.rim = 0.45
	mat.rim_tint = 0.35
	ind.set_surface_override_material(0, mat)
	add_child(ind)
	_indicators.append(ind)


## Free all per-string indicator children.
func _clear_indicators() -> void:
	for ind in _indicators:
		if is_instance_valid(ind):
			remove_child(ind)
			ind.queue_free()
	_indicators.clear()


## Update Z position every frame from the audio clock.
## Called by ChordPool.tick() so all chords stay in sync with the audio stream.
func tick(p_song_time: float) -> void:
	if not is_active:
		return
	position.z = STRUM_Z - (time_offset - p_song_time) * TRAVEL_SPEED
	if _miss_until < 0.0 and p_song_time >= time_offset:
		_miss_until = p_song_time + MISS_HOLD
	elif _miss_until >= 0.0 and p_song_time >= _miss_until:
		deactivate()


## Deactivate and return to the ChordPool.
func deactivate() -> void:
	is_active   = false
	visible     = false
	_miss_until = -1.0
	_clear_indicators()
	if is_instance_valid(_chord_label):
		_chord_label.visible = false
	var pool := get_parent()
	if pool and pool.has_method("return_chord"):
		pool.return_chord(self)
