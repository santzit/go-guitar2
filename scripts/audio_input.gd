extends Node
## audio_input.gd — Global guitar / microphone input singleton.
##
## Opens the AudioServer capture bus exactly once when the game launches and
## keeps it alive across all scenes (music_play, tuner, mixer, …).
##
## Any scene that needs guitar/mic samples can either:
##   a) Connect to:  AudioInput.samples_available(pcm_bytes: PackedByteArray)
##   b) Poll via:    AudioInput.get_last_pcm_bytes() → PackedByteArray
##
## The bus is muted so no raw microphone audio leaks to the speakers.
## The singleton is registered in project.godot under [autoload]:
##   AudioInput="*res://scripts/audio_input.gd"

## Emitted every _process() frame in which new samples were captured.
## pcm_bytes: PCM-16 LE mono — stereo L+R averaged, clamped to [-1, 1],
## quantised to signed 16-bit little-endian (2 bytes per sample).
signal samples_available(pcm_bytes: PackedByteArray)

const BUS_NAME : StringName = &"GuitarInput"

var _capture_effect : AudioEffectCapture = null
var _mic_player     : AudioStreamPlayer  = null
var _bus_idx        : int                = -1
var _active         : bool               = false
## Last captured PCM bytes — updated each frame; empty when nothing was captured.
var _last_pcm       : PackedByteArray    = PackedByteArray()


func _ready() -> void:
	_open()


func _process(_delta: float) -> void:
	if not _active or _capture_effect == null:
		return

	var frames : int = _capture_effect.get_frames_available()
	if frames <= 0:
		_last_pcm = PackedByteArray()
		return

	var stereo_buf : PackedVector2Array = _capture_effect.get_buffer(frames)
	var pcm_bytes  : PackedByteArray    = PackedByteArray()
	pcm_bytes.resize(stereo_buf.size() * 2)   # 2 bytes per 16-bit mono sample
	for fi in stereo_buf.size():
		# Average L+R to mono then quantise to signed 16-bit LE.
		var s   : float = clampf((stereo_buf[fi].x + stereo_buf[fi].y) * 0.5, -1.0, 1.0)
		var s16 : int   = clampi(int(s * 32768.0), -32768, 32767)
		pcm_bytes.encode_s16(fi * 2, s16)

	_last_pcm = pcm_bytes
	samples_available.emit(pcm_bytes)


## Returns the PCM-16 LE mono bytes that were captured in the most recent frame.
## Empty if no samples were available or the capture bus is not active.
## Use this for polling instead of the signal when the caller already has its
## own _process() and does not want to manage a signal connection.
func get_last_pcm_bytes() -> PackedByteArray:
	return _last_pcm


## Returns true when the capture bus is open and streaming.
func is_active() -> bool:
	return _active


## Re-open the capture bus if it was previously closed. Safe to call multiple times.
func open() -> void:
	if _active:
		return
	_open()


## Pause microphone streaming without destroying the bus.
## Call open() to resume.
func close() -> void:
	if not _active:
		return
	if _mic_player:
		_mic_player.stop()
	_active = false
	_last_pcm = PackedByteArray()
	print("AudioInput: capture paused.")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _open() -> void:
	# Re-use the bus if another call already created it (e.g. scene reload).
	var existing_idx : int = AudioServer.get_bus_index(BUS_NAME)
	if existing_idx != -1:
		_bus_idx = existing_idx
		# Retrieve the existing AudioEffectCapture from the bus.
		for ei in AudioServer.get_bus_effect_count(_bus_idx):
			var fx = AudioServer.get_bus_effect(_bus_idx, ei)
			if fx is AudioEffectCapture:
				_capture_effect = fx
				break
	else:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		# Mute the bus — we only want to capture, not play back to speakers.
		AudioServer.set_bus_mute(_bus_idx, true)
		_capture_effect = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_bus_idx, _capture_effect)

	# Create the AudioStreamMicrophone player if it does not exist yet.
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus    = BUS_NAME
		add_child(_mic_player)

	if not _mic_player.playing:
		_mic_player.play()

	_active = true
	print("AudioInput: capture bus '%s' ready (bus_idx=%d, mix_rate=%d Hz)." % [
		BUS_NAME, _bus_idx, AudioServer.get_mix_rate()])
