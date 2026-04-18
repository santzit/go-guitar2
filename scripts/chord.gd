extends Node3D
const ChartCommon = preload("res://scripts/common.gd")
## chord.gd — Unified play-event container for single notes and chords.
##
## Single-note events:
##   - one note slot marker (a real Note from ChordPool's NotePool)
##   - no chord label / no outline
## Chord events:
##   - multiple note-slot markers (real Note instances from ChordPool's NotePool)
##   - optional chord label
##   - shader outline with glow only on the bottom corners
##
## Coordinate conventions (shared via ChartCommon):
##   X = fret position, Y = string height, Z = time (spawns at -20 → travels to 0)
##
## Note markers are borrowed from ChordPool's NotePool (get_parent().spawn_note()).
## They are returned to the pool when this chord container deactivates.
## The chord container itself (border + label) still moves as a Node3D in Z;
## the individual Note instances are parented to NotePool and manage their own Z.

## Project font — Inter 18pt Bold, used for the chord name Label3D.
const _INTER_BOLD: FontFile = preload("res://assets/fonts/Inter_18pt-Bold.ttf")

## Border shader — bottom-corner glow only.
## Glow touches the bottom edge of the chord box (UV.y == 1.0), which aligns
## with the highway string-separator lines underneath the chord.
## Color matches the highway separator lines (vec4(0.55, 0.85, 1.00, 1.0)).
## Each corner fades outward (horizontally) and upward (away from the bottom edge).
const _BORDER_SHADER_CODE: String = """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled;
uniform float border_v : hint_range(0.01, 0.5) = 0.07;
uniform float corner_u : hint_range(0.02, 0.5) = 0.22;
uniform vec4 corner_glow_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float corner_glow_strength : hint_range(0.0, 8.0) = 3.0;
void fragment() {
	bool on_bottom       = UV.y > (1.0 - border_v);
	bool in_left_corner  = UV.x < corner_u;
	bool in_right_corner = UV.x > 1.0 - corner_u;
	if (!on_bottom || (!in_left_corner && !in_right_corner)) { discard; }
	float h_t = in_left_corner ? (1.0 - UV.x / corner_u) : ((UV.x - (1.0 - corner_u)) / corner_u);
	float v_t = (UV.y - (1.0 - border_v)) / border_v;
	float intensity = h_t * v_t;
	ALBEDO    = corner_glow_color.rgb;
	ALPHA     = corner_glow_color.a * intensity;
	EMISSION  = corner_glow_color.rgb * corner_glow_strength * intensity;
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
## Borrowed Note instances from ChordPool's NotePool — returned on deactivate.
var _indicators    : Array          = []


## Activate this chord container.
## p_notes:        Array[Dictionary{fret,string,duration}] — the event's notes
## p_time:         float  — timestamp (seconds)
## p_chord_name:   String — displayed only on first/changed occurrence
## p_show_details: bool   — true = label visible (chords only)
## p_event_kind:   String — "single" or "chord"
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

	# ── Container world position (for border / label anchor) ──────────────────
	# Single-note events use exactly one fret slot; chord events use a 4-fret hand window.
	var fret_span : int = 1 if is_single_event else BORDER_FRET_SPAN
	var left_x   : float = ChartCommon.fret_separator_world_x(min_fret - 1)
	var right_x  : float = ChartCommon.fret_separator_world_x(min_fret - 1 + fret_span)
	var top_y    : float = ChartCommon.string_world_y(min_string)
	var bot_y    : float = ChartCommon.string_world_y(max_string)
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

	# ── Note markers — borrowed from ChordPool's NotePool ─────────────────────
	_clear_indicators()
	var chord_pool := get_parent()
	if chord_pool and chord_pool.has_method("spawn_note"):
		for n in p_notes:
			var f   : int   = int(n.get("fret", 0))
			var s   : int   = clampi(int(n.get("string", 0)), 0, 5)
			var dur : float = float(n.get("duration", 0.25))
			var note_node : Node3D = chord_pool.spawn_note(f, s, p_time, dur)
			if note_node:
				_indicators.append(note_node)

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
	# Convert desired glow height (~5% of chord height) to UV fraction.
	# Kept deliberately thin to resemble the highway separator line thickness.
	var bv : float = clampf(0.05 / maxf(h, 0.001), 0.03, 0.12)
	var shader := Shader.new()
	shader.code = _BORDER_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# Use the same colour as highway fret-separator lines.
	mat.set_shader_parameter("corner_glow_color", Color(0.55, 0.85, 1.0, 1.0))
	mat.set_shader_parameter("corner_glow_strength", 3.0)
	mat.set_shader_parameter("border_v", bv)
	mat.set_shader_parameter("corner_u", 0.22)
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


## Return all borrowed Note instances to ChordPool's NotePool.
func _clear_indicators() -> void:
	for ind in _indicators:
		if is_instance_valid(ind) and ind.has_method("deactivate"):
			ind.deactivate()
	_indicators.clear()


## Update Z position every frame from the audio clock (for border + label).
## Note instances are ticked independently by ChordPool → NotePool.tick().
## Called by ChordPool.tick() so border/label stay in sync with the audio stream.
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
