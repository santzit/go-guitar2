extends Node
## godot_audio_bridge.gd — SPSC ring-buffer bridge between Godot audio and the native DSP thread.
##
## Implements the "Godot block I/O" audio pipeline described in the issue:
##
##   Godot (AudioEffectCapture)            ──push_input_f32──►  godot_in  SPSC ring
##       ↓ native DSP thread (ToneEngine amp-sim)
##   Godot (AudioStreamGeneratorPlayback)  ◄─pop_output_frames─  godot_out SPSC ring
##
## ## Usage
##
## 1. Add this node to your scene.
## 2. Assign a running `RtEngine` instance to `rt_engine` before `_ready()` fires,
##    or call `setup(rt_engine)` at runtime.
## 3. The node automatically opens a capture bus ("GodotBridge_In") and an
##    AudioStreamPlayer with an AudioStreamGenerator for monitoring output.
##
## ## GDScript example
##
## ```gdscript
## @onready var bridge := $GodotAudioBridge
##
## func _ready() -> void:
##     bridge.setup(rt_engine)           # connect to RtEngine
##     bridge.start()                    # open capture bus + output generator
##
## func _process(_delta: float) -> void:
##     bridge.tick()                     # push DI input + pull processed output
## ```
##
## If you prefer automatic ticking you can set `auto_tick = true` (default),
## in which case `_process()` calls `tick()` automatically.

## Emitted when processed stereo frames are written to the generator playback.
signal output_pushed(frame_count: int)

## Emitted when raw DI f32 samples are pushed to the native ring buffer.
signal input_pushed(sample_count: int)

## Set to false to call tick() manually from your own _process().
@export var auto_tick : bool = true

## Name of the Godot AudioServer capture bus created by this node.
@export var capture_bus_name : StringName = &"GodotBridge_In"

## Mix rate used for the AudioStreamGenerator (0 = follow AudioServer).
@export var mix_rate : float = 0.0

## Noise-gate threshold (absolute f32 value, 0..1).
## Samples below this level are treated as silence and are not pushed.
@export var noise_gate : float = 0.0

# ── Internal state ────────────────────────────────────────────────────────────

var _rt_engine         : Object        = null   # RtEngine GDExtension instance
var _capture_effect    : AudioEffectCapture = null
var _mic_player        : AudioStreamPlayer  = null
var _gen_player        : AudioStreamPlayer  = null
var _playback          : AudioStreamGeneratorPlayback = null
var _bus_idx           : int           = -1
var _active            : bool          = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	pass  # Wait for setup() to be called explicitly or from the owner scene.


func _process(_delta: float) -> void:
	if auto_tick and _active:
		tick()


## Assign the RtEngine instance.  Call before start().
func setup(rt: Object) -> void:
	_rt_engine = rt


## Open the capture bus and the output AudioStreamGenerator.
## Returns true on success.  Safe to call multiple times (idempotent).
func start() -> bool:
	if _active:
		return true

	if _rt_engine == null:
		push_warning("GodotAudioBridge: call setup(rt_engine) before start().")
		return false

	if not _rt_engine.is_running():
		push_warning("GodotAudioBridge: RtEngine is not running — call rt_engine.start() first.")
		return false

	_open_capture_bus()
	_open_generator()

	_active = true
	print("GodotAudioBridge: started (capture bus '%s', mix_rate %.0f Hz)." % [
		capture_bus_name, _effective_mix_rate()])
	return true


## Flush ring buffers and close the capture bus and generator.
func stop() -> void:
	if not _active:
		return

	if _mic_player:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null

	if _gen_player:
		_gen_player.stop()
		_gen_player.queue_free()
		_gen_player = null

	if _bus_idx != -1:
		AudioServer.remove_bus(_bus_idx)
		_bus_idx = -1

	_capture_effect = null
	_playback       = null
	_active         = false
	print("GodotAudioBridge: stopped.")


## Drive one frame of the pipeline.
##
## Call this from _process() (or set auto_tick = true).
## Pushes newly captured DI samples to the native ring buffer, then pulls
## DSP-processed frames from it into the AudioStreamGenerator.
func tick() -> void:
	if not _active or _rt_engine == null:
		return

	_push_input()
	_pull_output()


## Returns true when the bridge is active.
func is_active() -> bool:
	return _active


# ── Internal helpers ──────────────────────────────────────────────────────────

func _push_input() -> void:
	if _capture_effect == null:
		return

	var frames : int = _capture_effect.get_frames_available()
	if frames <= 0:
		return

	var stereo_buf : PackedVector2Array = _capture_effect.get_buffer(frames)
	var f32_buf    : PackedFloat32Array = PackedFloat32Array()
	f32_buf.resize(stereo_buf.size())

	var any_signal := false
	for fi in stereo_buf.size():
		# Use L channel only (guitar DI is mono on L), apply noise gate.
		# Pass f32 directly to C++/Q — no PCM-16 conversion step needed.
		var s : float = clampf(stereo_buf[fi].x, -1.0, 1.0)
		if absf(s) < noise_gate:
			s = 0.0
		else:
			any_signal = true
		f32_buf[fi] = s

	if any_signal or noise_gate <= 0.0:
		var written : int = _rt_engine.push_input_f32(f32_buf)
		if written > 0:
			input_pushed.emit(written)


func _pull_output() -> void:
	if _playback == null:
		return

	var frames_wanted : int = _playback.get_frames_available()
	if frames_wanted <= 0:
		return

	var available : int = _rt_engine.output_rb_available()
	if available <= 0:
		return

	var to_read : int = mini(frames_wanted, available)
	var frames  : PackedVector2Array = _rt_engine.pop_output_frames(to_read)

	if frames.size() > 0:
		_playback.push_buffer(frames)
		output_pushed.emit(frames.size())


func _open_capture_bus() -> void:
	# Re-use an existing bus with the same name if present.
	var existing : int = AudioServer.get_bus_index(capture_bus_name)
	if existing != -1:
		_bus_idx = existing
		for ei in AudioServer.get_bus_effect_count(_bus_idx):
			var fx = AudioServer.get_bus_effect(_bus_idx, ei)
			if fx is AudioEffectCapture:
				_capture_effect = fx
				break
	else:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_bus_idx, capture_bus_name)
		# Mute — we capture only, no speaker feedback.
		AudioServer.set_bus_mute(_bus_idx, true)
		_capture_effect = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_bus_idx, _capture_effect)

	# Start the microphone player on this bus.
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus    = capture_bus_name
		add_child(_mic_player)

	if not _mic_player.playing:
		_mic_player.play()


func _open_generator() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate   = _effective_mix_rate()
	gen.buffer_length = 0.1  # 100 ms latency buffer

	_gen_player = AudioStreamPlayer.new()
	_gen_player.stream = gen
	_gen_player.autoplay = false
	add_child(_gen_player)
	_gen_player.play()

	_playback = _gen_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _effective_mix_rate() -> float:
	return mix_rate if mix_rate > 0.0 else float(AudioServer.get_mix_rate())
