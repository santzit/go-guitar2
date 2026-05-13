extends Node
## input_audio_manager.gd — Runtime audio manager for per-player guitar input.
##
## Reads PlayerProfile objects from PlayerManager to know which audio bus to
## open for each active player, then:
##   1. Creates a dedicated Godot AudioServer bus per player (e.g. "P1_In").
##   2. Attaches an AudioEffectCapture to that bus.
##   3. Starts AudioStreamMicrophone on that bus.
##   4. Each _process() frame: drains captured frames → PCM-16 LE mono bytes →
##      applies noise gate → emits samples_ready(player_id, pcm_bytes).
##
## Consumers (music_play, tuner, mixer …) connect to samples_ready and forward
## the bytes to the Rust cycfi/q PitchDetector FFI.
##
## Registered in project.godot as:
##   InputAudioManager="*res://scripts/input_audio_manager.gd"
##
## This class owns the live audio objects (buses, effects, players).
## Player preferences live in PlayerProfile / PlayerManager.

## Emitted when new PCM samples are available for a player.
## player_id: 1 or 2 (matches PlayerProfile.id)
## pcm_bytes: PCM-16 LE mono — L+R averaged, clamped, 2 bytes/sample.
signal samples_ready(player_id: int, pcm_bytes: PackedByteArray)

## Internal per-player capture state (plain RefCounted — no typed PlayerProfile).
class _PlayerCapture:
	var player_id      : int                    = 1
	var bus_name       : StringName             = &"P1_In"
	var bus_idx        : int                    = -1
	var capture_effect : AudioEffectCapture     = null
	var mic_player     : AudioStreamPlayer      = null
	var active         : bool                   = false
	var last_pcm       : PackedByteArray        = PackedByteArray()
	var noise_gate     : float                  = 0.02   # RMS threshold (0..1)

var _captures : Array = []


func _ready() -> void:
	# Open capture buses for all registered players at game start.
	for profile in PlayerManager.players:
		_open_for_player(profile)


func _process(_delta: float) -> void:
	for cap in _captures:
		if not cap.active or cap.capture_effect == null:
			cap.last_pcm = PackedByteArray()
			continue

		var frames : int = cap.capture_effect.get_frames_available()
		if frames <= 0:
			cap.last_pcm = PackedByteArray()
			continue

		var stereo_buf : PackedVector2Array = cap.capture_effect.get_buffer(frames)
		var pcm_bytes  : PackedByteArray    = PackedByteArray()
		pcm_bytes.resize(stereo_buf.size() * 2)

		var any_signal := false
		for fi in stereo_buf.size():
			var s : float = clampf((stereo_buf[fi].x + stereo_buf[fi].y) * 0.5, -1.0, 1.0)
			# Noise gate: treat very quiet samples as silence.
			if absf(s) < cap.noise_gate:
				s = 0.0
			else:
				any_signal = true
			var s16 : int = clampi(int(s * 32768.0), -32768, 32767)
			pcm_bytes.encode_s16(fi * 2, s16)

		cap.last_pcm = pcm_bytes
		if any_signal:
			samples_ready.emit(cap.player_id, pcm_bytes)


func _exit_tree() -> void:
	for i in range(_captures.size() - 1, -1, -1):
		var cap: _PlayerCapture = _captures[i]
		_shutdown_capture(cap)
	_captures.clear()


# ── Public API ─────────────────────────────────────────────────────────────────

## Returns the most recent PCM bytes captured for the given player id (1 or 2).
## Empty if nothing was captured this frame or the capture is not active.
func get_last_pcm(player_id: int) -> PackedByteArray:
	for cap in _captures:
		if cap.player_id == player_id:
			return cap.last_pcm
	return PackedByteArray()


## Returns true when the capture bus for the given player id is open and streaming.
func is_active(player_id: int) -> bool:
	for cap in _captures:
		if cap.player_id == player_id:
			return cap.active
	return false


## Re-open capture for a player whose profile was updated (e.g. device changed).
## Safe to call at any time; closes the old bus first if necessary.
func refresh_player(player_id: int) -> void:
	var profile = PlayerManager.get_player(player_id)
	if profile == null:
		return
	_close_for_player(player_id)
	_open_for_player(profile)


## Pause capture for a player without removing the bus.
func pause_player(player_id: int) -> void:
	for cap in _captures:
		if cap.player_id == player_id and cap.active:
			if cap.mic_player:
				cap.mic_player.stop()
			cap.active = false
			print("InputAudioManager: capture paused for Player %d." % player_id)
			return


## Resume a previously paused capture.
func resume_player(player_id: int) -> void:
	for cap in _captures:
		if cap.player_id == player_id and not cap.active:
			if cap.mic_player and not cap.mic_player.playing:
				cap.mic_player.play()
			cap.active = true
			print("InputAudioManager: capture resumed for Player %d." % player_id)
			return


# ── Internal helpers ────────────────────────────────────────────────────────────

func _open_for_player(profile) -> void:
	var cap := _PlayerCapture.new()
	cap.player_id  = profile.id
	cap.bus_name   = profile.input_bus_name
	cap.noise_gate = profile.noise_gate_threshold

	# Create or reuse the AudioServer bus.
	var existing_idx : int = AudioServer.get_bus_index(cap.bus_name)
	if existing_idx != -1:
		cap.bus_idx = existing_idx
		for ei in AudioServer.get_bus_effect_count(cap.bus_idx):
			var fx = AudioServer.get_bus_effect(cap.bus_idx, ei)
			if fx is AudioEffectCapture:
				cap.capture_effect = fx
				break
	else:
		cap.bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(cap.bus_idx, cap.bus_name)
		cap.capture_effect = AudioEffectCapture.new()
		AudioServer.add_bus_effect(cap.bus_idx, cap.capture_effect)

	# Apply monitor setting from profile.
	_apply_monitor(cap, profile)

	# Create and start the microphone player.
	cap.mic_player = AudioStreamPlayer.new()
	cap.mic_player.stream = AudioStreamMicrophone.new()
	cap.mic_player.bus    = cap.bus_name
	add_child(cap.mic_player)
	cap.mic_player.play()

	cap.active = true
	_captures.append(cap)

	print("InputAudioManager: Player %d capture bus '%s' ready (bus_idx=%d)." % [
		profile.id, cap.bus_name, cap.bus_idx])


func _close_for_player(player_id: int) -> void:
	for i in _captures.size():
		var cap : _PlayerCapture = _captures[i]
		if cap.player_id != player_id:
			continue
		_shutdown_capture(cap)
		_captures.remove_at(i)
		print("InputAudioManager: Player %d capture bus closed." % player_id)
		return


func _apply_monitor(cap: _PlayerCapture, profile) -> void:
	# Mute = no monitor feedback; unmute = player hears themselves.
	AudioServer.set_bus_mute(cap.bus_idx, not profile.monitor_enabled)
	if profile.monitor_enabled:
		AudioServer.set_bus_volume_db(cap.bus_idx, profile.monitor_volume_db)


func _shutdown_capture(cap: _PlayerCapture) -> void:
	if is_instance_valid(cap.mic_player):
		cap.mic_player.stop()
		cap.mic_player.stream = null
		cap.mic_player.free()
	cap.mic_player = null
	cap.capture_effect = null
	cap.last_pcm = PackedByteArray()
	cap.active = false

	var idx := AudioServer.get_bus_index(cap.bus_name)
	if idx != -1 and idx < AudioServer.bus_count:
		AudioServer.remove_bus(idx)
