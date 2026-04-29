extends RefCounted
class_name PlayerProfile

## player_profile.gd — Per-player preference data object.
##
## Stores device selection, calibration offsets, monitor settings,
## noise-gate threshold, and gameplay prefs for one player (1 or 2).
##
## PlayerProfile objects are owned by the PlayerManager autoload singleton,
## which persists them to user://player<N>_profile.cfg.
##
## Live audio state (open buses, AudioEffectCapture, Q detector) is NOT stored
## here — that belongs to InputAudioManager.  PlayerProfile is pure data.

# ── Identity ────────────────────────────────────────────────────────────────
## 1 or 2.
var id            : int    = 1
var display_name  : String = "Player 1"

# ── Audio device ─────────────────────────────────────────────────────────────
## OS-level audio input device name returned by AudioServer.get_input_device_list().
## "" = use whatever the OS default is.
var input_device_name : String = ""

## Name of the dedicated Godot audio bus used for this player's capture stream.
## e.g. "P1_In" or "P2_In".  Set by InputAudioManager.
var input_bus_name : String = "P1_In"

# ── Monitor (hear the guitar through speakers) ───────────────────────────────
## When true, the capture bus is NOT muted so the player hears their guitar.
var monitor_enabled   : bool  = false
var monitor_volume_db : float = 0.0      # dB, range -60..+6

# ── Noise gate ───────────────────────────────────────────────────────────────
## Samples below this RMS threshold (0..1 linear) are treated as silence.
## Prevents false detections from ambient noise between played notes.
var noise_gate_threshold : float = 0.02

# ── Calibration ──────────────────────────────────────────────────────────────
## Hardware round-trip latency of the audio input path (mic → buffer → Q) in ms.
## Subtracted from song_time when comparing against note timestamps so that
## a note detected «now» is credited against the event it actually belongs to.
var input_latency_ms : float = 0.0

## Audio-video sync offset in ms (positive = audio arrives late vs video).
## Add this offset when evaluating note-scoring hit windows.
var av_offset_ms : float = 0.0

# ── Gameplay preferences ─────────────────────────────────────────────────────
## 0–100. Maps to DDC difficulty bands: 0–33=Easy, 34–66=Medium, 67–100=Hard.
var difficulty_percent : float = 100.0

## Fraction (0..1) of the standard early/late scoring window.
## 1.0 = default (−100 ms early / +150 ms late).
## < 1.0 = tighter window (advanced mode).
var tolerance_scale : float = 1.0

## Note-highway visual style (for future use).
var highway_style : String = "default"


# ── Serialisation ─────────────────────────────────────────────────────────────

## Populate this profile from a ConfigFile section named "player<id>".
func load_from_cfg(cfg: ConfigFile) -> void:
	var s := "player%d" % id
	display_name          = cfg.get_value(s, "display_name",          display_name)
	input_device_name     = cfg.get_value(s, "input_device_name",     input_device_name)
	input_bus_name        = cfg.get_value(s, "input_bus_name",        input_bus_name)
	monitor_enabled       = cfg.get_value(s, "monitor_enabled",       monitor_enabled)
	monitor_volume_db     = cfg.get_value(s, "monitor_volume_db",     monitor_volume_db)
	noise_gate_threshold  = cfg.get_value(s, "noise_gate_threshold",  noise_gate_threshold)
	input_latency_ms      = cfg.get_value(s, "input_latency_ms",      input_latency_ms)
	av_offset_ms          = cfg.get_value(s, "av_offset_ms",          av_offset_ms)
	difficulty_percent    = cfg.get_value(s, "difficulty_percent",    difficulty_percent)
	tolerance_scale       = cfg.get_value(s, "tolerance_scale",       tolerance_scale)
	highway_style         = cfg.get_value(s, "highway_style",         highway_style)


## Write this profile's values into a ConfigFile section named "player<id>".
func save_to_cfg(cfg: ConfigFile) -> void:
	var s := "player%d" % id
	cfg.set_value(s, "display_name",         display_name)
	cfg.set_value(s, "input_device_name",    input_device_name)
	cfg.set_value(s, "input_bus_name",       input_bus_name)
	cfg.set_value(s, "monitor_enabled",      monitor_enabled)
	cfg.set_value(s, "monitor_volume_db",    monitor_volume_db)
	cfg.set_value(s, "noise_gate_threshold", noise_gate_threshold)
	cfg.set_value(s, "input_latency_ms",     input_latency_ms)
	cfg.set_value(s, "av_offset_ms",         av_offset_ms)
	cfg.set_value(s, "difficulty_percent",   difficulty_percent)
	cfg.set_value(s, "tolerance_scale",      tolerance_scale)
	cfg.set_value(s, "highway_style",        highway_style)
