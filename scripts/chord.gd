extends Node3D
## chord.gd — Chord container: bordered box spanning 4 frets × all involved strings.
##
## For the first occurrence (or chord change): renders per-string finger indicators
## + chord name label to the top-right outside the container.
## For repeated chords: renders only the border outline.
##
## Coordinate conventions (shared via ChartCommon):
##   X = fret position, Y = string height, Z = time (spawns at -20 → travels to 0)
##
## The border always spans BORDER_FRET_SPAN (4) frets starting from min_fret.

# ── Guitar note textures (string 0 top → string 5 bottom) ──────────────────
# Order: Red, Yellow, Cyan(Blue), Orange, Green, Purple
const STRING_TEXTURES: Array[Texture2D] = [
	preload("res://assets/textures/chartplayer/GuitarRed.png"),
	preload("res://assets/textures/chartplayer/GuitarYellow.png"),
	preload("res://assets/textures/chartplayer/GuitarCyan.png"),
	preload("res://assets/textures/chartplayer/GuitarOrange.png"),
	preload("res://assets/textures/chartplayer/GuitarGreen.png"),
	preload("res://assets/textures/chartplayer/GuitarPurple.png"),
]

## Finger indicator shader — same as note.gd: circular texture with transparent
## background, spherical billboard so the plane always faces the camera.
const _FINGER_SHADER_CODE: String = """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled;
uniform sampler2D albedo_texture : source_color, hint_default_white;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	if (tex.a < 0.01) { discard; }
	ALBEDO = tex.rgb;
	ALPHA  = tex.a;
}
"""

## Project font — Inter 18pt Bold, used for the chord name Label3D.
const _INTER_BOLD: FontFile = preload("res://assets/fonts/Inter_18pt-Bold.ttf")

## Border shader — renders only the edge pixels of the PlaneMesh as a white
## outline rectangle; the interior is discarded (fully transparent).
## border_u / border_v are the UV-space fractions occupied by the border on
## each axis and are computed per-chord so the physical thickness is ~3 cm.
const _BORDER_SHADER_CODE: String = """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled;
uniform float border_u : hint_range(0.01, 0.5) = 0.04;
uniform float border_v : hint_range(0.01, 0.5) = 0.04;
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
void fragment() {
	bool on_edge = UV.x < border_u || UV.x > 1.0 - border_u
				|| UV.y < border_v || UV.y > 1.0 - border_v;
	if (!on_edge) { discard; }
	ALBEDO = border_color.rgb;
	ALPHA  = border_color.a;
}
"""

## Notes / chords spawn at Z = START_Z and travel toward STRUM_Z = 0.
const START_Z          : float = -20.0
const STRUM_Z          : float =  0.0
const TRAVEL_SPEED     : float =  2.0   # must match note.gd and music_play.gd
const MISS_HOLD        : float =  1.0   # seconds to keep visible after strum
## Border always spans exactly this many frets (first note fret + 3 more).
const BORDER_FRET_SPAN : int   = 4

var time_offset    : float = 0.0
var is_active      : bool  = false
var _miss_until    : float = -1.0

## Lazy-initialised persistent nodes (survive pool reuse).
var _border_mesh   : MeshInstance3D = null
var _chord_label   : Label3D        = null
## Fret cached to skip redundant border resizes.
var _last_min_fret : int            = -1

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
		p_show_details: bool
) -> void:
	time_offset = p_time
	is_active   = true
	visible     = true
	_miss_until = -1.0

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
	# X centre of the 4-fret window; Y centre between top and bottom strings.
	var left_x   : float = ChartCommon.fret_separator_world_x(min_fret)
	var right_x  : float = ChartCommon.fret_separator_world_x(min_fret + BORDER_FRET_SPAN)
	var top_y    : float = ChartCommon.string_world_y(min_string)
	var bot_y    : float = ChartCommon.string_world_y(max_string)
	var center_x : float = (left_x + right_x) * 0.5
	var center_y : float = (top_y + bot_y) * 0.5
	position = Vector3(center_x, center_y, START_Z)

	# ── Border box ─────────────────────────────────────────────────────────────
	var w : float = right_x - left_x
	var h : float = absf(top_y - bot_y) + ChartCommon.STRING_SLOT_HEIGHT
	_ensure_border(min_fret, w, h)

	# ── Per-string finger indicators (only on first / changed chord) ───────────
	_clear_indicators()
	if p_show_details:
		for n in p_notes:
			var f : int = int(n.get("fret", 0))
			var s : int = clampi(int(n.get("string", 0)), 0, 5)
			_add_indicator(f, s, center_x, center_y)

	# ── Chord name label (top-right outside the container) ─────────────────────
	_ensure_label()
	_chord_label.visible = p_show_details
	if p_show_details:
		_chord_label.text = p_chord_name
		_chord_label.position = Vector3(
			right_x - center_x + 0.25,
			top_y   - center_y + 0.15,
			0.10
		)


## Create (or reuse) the border MeshInstance3D; resize when the fret changes.
func _ensure_border(min_fret: int, w: float, h: float) -> void:
	if _border_mesh == null:
		_border_mesh = MeshInstance3D.new()
		_border_mesh.position = Vector3(0.0, 0.0, 0.05)
		var shader := Shader.new()
		shader.code = _BORDER_SHADER_CODE
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("border_color", Color(1.0, 1.0, 1.0, 1.0))
		_border_mesh.set_surface_override_material(0, mat)
		add_child(_border_mesh)

	if min_fret != _last_min_fret:
		_last_min_fret = min_fret
		var plane := PlaneMesh.new()
		plane.size        = Vector2(w, h)
		plane.orientation = PlaneMesh.FACE_Z
		_border_mesh.mesh = plane
		# Compute UV border fraction that maps to ~2.5 cm world-unit thickness.
		var bu : float = clampf(0.025 / w, 0.015, 0.12)
		var bv : float = clampf(0.025 / maxf(h, 0.001), 0.015, 0.20)
		var mat := _border_mesh.get_surface_override_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("border_u", bu)
			mat.set_shader_parameter("border_v", bv)


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
		ChartCommon.fret_mid_world_x(f) - center_x,
		ChartCommon.string_world_y(s)   - center_y,
		0.08
	)
	var plane := PlaneMesh.new()
	plane.size        = ChartCommon.note_indicator_size(f)
	plane.orientation = PlaneMesh.FACE_Z
	ind.mesh = plane
	var shader := Shader.new()
	shader.code = _FINGER_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_texture", STRING_TEXTURES[s])
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
