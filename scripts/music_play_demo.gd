extends Node3D
## music_play_demo.gd — standalone demo scene controller.
##
## Cycles through frets 1–24 sequentially, holding each lane for FRET_DURATION
## seconds.  The camera smoothly pans and zooms to follow the active lane.
## No Rocksmith library, no DLC files required.

# -- Highway / note constants ------------------------------------------------
const FRET_COUNT     : int   = 24
const STRING_COUNT   : int   = 6
const FRET_SPACING   : float = 1.0   # must match note.gd FRET_SPACING
const TRAVEL_SPEED   : float = 8.0   # must match note.gd TRAVEL_SPEED
const START_Z        : float = 20.0  # must match note.gd START_Z
const LEAD_TIME      : float = START_Z / TRAVEL_SPEED  # = 2.5 s

# -- Spawn rhythm ------------------------------------------------------------
## Seconds between chord spawns on the active fret lane.
const BEAT_INTERVAL  : float = 0.30

# -- Sequential fret demo ----------------------------------------------------
## How long each fret is shown before advancing to the next.
const FRET_DURATION  : float = 3.0

# -- Camera follow -----------------------------------------------------------
## FOV (degrees) when zoomed in on a single lane.
const CAM_FOV_ZOOM   : float = 40.0
## Camera height and back-offset stay constant while panning.
const CAM_Y          : float = 6.0
const CAM_Z          : float = -8.0
## Smoothing speed (higher = snappier follow).
const CAM_LERP_SPEED : float = 3.0

# -- Screenshot capture -------------------------------------------------------
const SCREENSHOT_TIMES : Array  = [3.0, 6.0, 9.0, 12.0, 15.0]
const SCREENSHOT_DIR   : String = "user://screenshots"

# -- Delta cap (keeps camera lerp stable on slow software renderers) ----------
const MAX_DELTA : float = 0.05

# -- Scene references --------------------------------------------------------
@onready var _pool   : Node3D   = $NotePool
@onready var _camera : Camera3D = $Camera3D

# -- State -------------------------------------------------------------------
var _beat_timer    : float = 0.0
var _fret_timer    : float = 0.0
var _current_fret  : int   = 1
var _start_wall_ms : int   = 0
var _shot_idx      : int   = 0
var _demo_time     : float = 0.0  # virtual song clock (wall-clock seconds, for tick())


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SCREENSHOT_DIR)
	)
	_start_wall_ms = Time.get_ticks_msec()
	# Snap camera directly to fret 1 on startup (no slow initial pan).
	_camera.position.x = _fret_world_x(_current_fret)
	_camera.fov        = CAM_FOV_ZOOM


func _process(delta: float) -> void:
	var clamped_delta := minf(delta, MAX_DELTA)
	_demo_time += clamped_delta

	# Drive all active note positions from the virtual clock (mirrors how
	# music_play.gd uses the audio clock so note movement stays consistent).
	_pool.tick(_demo_time)

	# ── Advance to the next fret every FRET_DURATION seconds ──────────────
	_fret_timer += clamped_delta
	if _fret_timer >= FRET_DURATION:
		_fret_timer -= FRET_DURATION
		_current_fret = (_current_fret % FRET_COUNT) + 1   # 1 → 2 → … → 24 → 1

	# ── Spawn a full chord (all strings) on the active fret every beat ────
	_beat_timer += clamped_delta
	if _beat_timer >= BEAT_INTERVAL:
		_beat_timer -= BEAT_INTERVAL
		_spawn_fret_chord(_current_fret)

	# ── Smooth camera pan to the active fret lane ─────────────────────────
	var target_x := _fret_world_x(_current_fret)
	_camera.position.x = lerp(_camera.position.x, target_x, clamped_delta * CAM_LERP_SPEED)

	# ── Screenshots at real wall-clock times ──────────────────────────────
	if _shot_idx < SCREENSHOT_TIMES.size():
		var wall_sec := (Time.get_ticks_msec() - _start_wall_ms) / 1000.0
		if wall_sec >= SCREENSHOT_TIMES[_shot_idx]:
			_take_screenshot(_shot_idx + 1)
			_shot_idx += 1


# -- Helpers -----------------------------------------------------------------

## World X centre of a fret lane.  Matches note.gd setup() formula:
##   X = (FRET_COUNT - fret + 0.5) * FRET_SPACING
func _fret_world_x(f: int) -> float:
	return (FRET_COUNT - f + 0.5) * FRET_SPACING


## Spawn one note on every string for the given fret (full chord).
## time_offset = _demo_time + LEAD_TIME so notes start at START_Z and reach
## the strum line exactly LEAD_TIME seconds later — matching note.gd tick() maths.
func _spawn_fret_chord(f: int) -> void:
	for s in STRING_COUNT:
		var dur : float = randf_range(0.20, 0.50)
		_pool.spawn_note(f, s, _demo_time + LEAD_TIME, dur)


func _take_screenshot(num: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path     := SCREENSHOT_DIR + "/music_play_%d.png" % num
	var abs_path := ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	print("Screenshot saved: " + abs_path)
