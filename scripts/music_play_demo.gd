extends Node3D
## music_play_demo.gd — standalone demo scene controller.
##
## Spawns random notes continuously through the 24-lane highway.
## No Rocksmith library, no DLC files required.

# -- Highway / note constants ------------------------------------------------
const FRET_COUNT     : int   = 24
const STRING_COUNT   : int   = 6
const TRAVEL_SPEED   : float = 8.0
const START_Z        : float = 20.0

# -- Spawn rhythm ------------------------------------------------------------
## Average notes per second (Poisson-like: each beat spawns 1–CHORD_MAX notes)
const BEAT_INTERVAL  : float = 0.30   # seconds between beats
const CHORD_MAX      : int   = 3      # max simultaneous notes per beat

# -- Screenshot capture -------------------------------------------------------
const SCREENSHOT_TIMES : Array  = [30.0, 60.0, 90.0, 120.0, 150.0]
const SCREENSHOT_DIR   : String = "user://screenshots"

# -- Delta cap (keeps notes on-screen on slow software renderers) -------------
const MAX_DELTA : float = 0.05

# -- Scene references --------------------------------------------------------
@onready var _pool   : Node3D = $NotePool
@onready var _highway: Node3D = $Highway

# -- State -------------------------------------------------------------------
var _beat_timer    : float = 0.0
var _start_wall_ms : int   = 0
var _shot_idx      : int   = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SCREENSHOT_DIR)
	)
	_start_wall_ms = Time.get_ticks_msec()
	randomize()


func _process(delta: float) -> void:
	var clamped_delta := minf(delta, MAX_DELTA)

	# ── Spawn a random chord every BEAT_INTERVAL seconds ──────────────────
	_beat_timer += clamped_delta
	if _beat_timer >= BEAT_INTERVAL:
		_beat_timer -= BEAT_INTERVAL
		_spawn_random_chord()

	# ── Screenshots at real wall-clock times ──────────────────────────────
	if _shot_idx < SCREENSHOT_TIMES.size():
		var wall_sec := (Time.get_ticks_msec() - _start_wall_ms) / 1000.0
		if wall_sec >= SCREENSHOT_TIMES[_shot_idx]:
			_take_screenshot(_shot_idx + 1)
			_shot_idx += 1


# -- Helpers -----------------------------------------------------------------

func _spawn_random_chord() -> void:
	var count := randi_range(1, CHORD_MAX)
	# Pick distinct strings to avoid stacking notes on the same string.
	var strings := range(STRING_COUNT)
	strings.shuffle()
	for i in count:
		var fret   := randi_range(0, FRET_COUNT - 1)
		var string := strings[i]
		var dur    := randf_range(0.15, 0.40)
		_pool.spawn_note(fret, string, 0.0, dur)


func _take_screenshot(num: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path     := SCREENSHOT_DIR + "/music_play_%d.png" % num
	var abs_path := ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	print("Screenshot saved: " + abs_path)
