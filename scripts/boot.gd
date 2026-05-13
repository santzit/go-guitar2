extends Node
## boot.gd — Boot scene script.
##
## Runs once at game startup. Responsibilities:
##   1. Apply window / audio driver settings (volume, input enable).
##   2. Ensure PlayerManager profiles are loaded (autoload already called _ready,
##      but we can call save() to flush defaults if this is a first run).
##   3. Probe the Rust GDExtension so later scenes can assume it is ready.
##   4. Transition to the main menu after a short minimum splash (≤ 2 seconds).
##
## Scene tree expected:
##   Boot (Node) [this script]
##   └─ UI (CanvasLayer)
##      └─ LoadingLabel (Label) — "Loading…"

const MENU_SCENE   : String  = "res://scenes/game_menu.tscn"
const MIN_WAIT_SEC : float   = 0.5   # Minimum splash time (shows "Loading…")
const MAX_WAIT_SEC : float   = 2.0   # Hard cap before we give up and continue

## Emitted (unused by default) if you want other nodes to know boot finished.
signal boot_finished

@onready var _loading_label : Label = $UI/LoadingLabel

var _elapsed   : float = 0.0
var _ready_ok  : bool  = false


func _ready() -> void:
	_loading_label.text = "Loading…"
	_apply_audio_settings()
	_probe_gdextension()
	_ready_ok = true


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= MIN_WAIT_SEC and _ready_ok:
		_go_to_menu()
	elif _elapsed >= MAX_WAIT_SEC:
		push_warning("Boot: timed out — proceeding to menu anyway.")
		_go_to_menu()


# ── Internal helpers ──────────────────────────────────────────────────────────

func _apply_audio_settings() -> void:
	# Sync AudioServer bus volumes from PlayerManager profiles.
	# Master / Music / SFX volumes would go here when a GameSettings autoload
	# is added. For now we only log readiness.
	var mix_rate : int = int(round(AudioServer.get_mix_rate()))
	print("Boot: AudioServer mix_rate=%d Hz, bus_count=%d." % [mix_rate, AudioServer.bus_count])


func _probe_gdextension() -> void:
	# Verify the Rust GDExtension classes needed by gameplay are loaded.
	# We do NOT crash if it is missing — gameplay will simply run without live
	# pitch detection (demo / song-playback mode).
	if ClassDB.class_exists("RSAPI_SNG"):
		print("Boot: RSAPI_SNG GDExtension — OK.")
	else:
		push_warning("Boot: RSAPI_SNG GDExtension not found — running without it.")

	if ClassDB.class_exists("PitchDetector"):
		print("Boot: PitchDetector GDExtension — OK.")
	else:
		push_warning("Boot: PitchDetector GDExtension not found — pitch detection disabled.")

	if ClassDB.class_exists("QEngine"):
		print("Boot: QEngine GDExtension — OK.")
	else:
		push_warning("Boot: QEngine GDExtension not found — music_play live detection disabled.")


func _go_to_menu() -> void:
	set_process(false)
	boot_finished.emit()
	SceneManager.goto_main_menu()
