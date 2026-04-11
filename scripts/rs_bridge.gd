## rs_bridge.gd  –  GDScript wrapper around the RocksmithBridge GDExtension.
##
## Build the native library first (see gdextension/README.md), then the
## "RocksmithBridge" class will be available and this wrapper will delegate
## to it.  When the extension is absent the wrapper silently no-ops so that
## the rest of the game still runs (demo-mode notes are used instead).
##
## Usage:
##   var bridge := RsBridge.new()
##   if bridge.load_psarc("res://DLC/song.psarc"):
##       var notes  := bridge.get_notes()          # Array[Dictionary]
##       var stream := bridge.get_audio_stream()   # AudioStream or null
extends RefCounted
class_name RsBridge

var _ext: Object = null   # native RocksmithBridge instance (may be null)


func _init() -> void:
	if ClassDB.class_exists("RocksmithBridge"):
		_ext = ClassDB.instantiate("RocksmithBridge")
	else:
		push_warning(
			"RsBridge: RocksmithBridge GDExtension not loaded. " +
			"Build the extension from gdextension/src/ and copy the binary to " +
			"gdextension/bin/.  Running in demo-note mode."
		)


## Load a .psarc archive from a res:// or user:// Godot path.
## The path is converted to an absolute filesystem path before being passed
## to the native bridge (needed when running from the editor).
func load_psarc(path: String) -> bool:
	if _ext == null:
		return false
	return _ext.load_psarc(ProjectSettings.globalize_path(path))


## Load a .psarc archive from an already-absolute filesystem path.
## Use this when the path was resolved outside Godot's virtual filesystem
## (e.g. next to the executable or in user data).
func load_psarc_abs(abs_path: String) -> bool:
	if _ext == null:
		return false
	return _ext.load_psarc(abs_path)


## Returns notes as an Array of Dictionaries:
##   { "time": float, "fret": int, "string": int, "duration": float }
func get_notes() -> Array:
	if _ext == null:
		return []
	return _ext.get_notes()


## Returns raw OGG bytes from the song (CDLC only).
func get_audio_bytes() -> PackedByteArray:
	if _ext == null:
		return PackedByteArray()
	return _ext.get_audio_bytes()


## Returns raw WEM bytes from the song (official DLC).
func get_wem_bytes() -> PackedByteArray:
	if _ext == null:
		return PackedByteArray()
	if _ext.has_method("get_wem_bytes"):
		return _ext.get_wem_bytes()
	return PackedByteArray()


## Convenience: create an AudioStream from the embedded audio data, or null.
## Priority: WEM (decoded via AudioEngine on Linux/Windows) → OGG (CDLC fallback).
func get_audio_stream() -> AudioStream:
	# ── Try WEM via AudioEngine (official DLC — vgmstream on Linux + Windows) ─
	var wem := get_wem_bytes()
	print("RsBridge: get_audio_stream() — WEM bytes: %d" % wem.size())
	if not wem.is_empty():
		var ae_exists := ClassDB.class_exists("AudioEngine")
		print("RsBridge: AudioEngine class exists: %s" % str(ae_exists))
		if ae_exists:
			var eng: Object = ClassDB.instantiate("AudioEngine")
			print("RsBridge: calling AudioEngine.open() with %d WEM bytes" % wem.size())
			var ok: Variant = eng.open(wem)
			print("RsBridge: AudioEngine.open() returned: %s" % str(ok))
			if ok:
				var pcm_bytes: PackedByteArray = eng.decode_all()
				print("RsBridge: AudioEngine.decode_all() returned %d PCM bytes  channels=%d  rate=%d" % [
					pcm_bytes.size(), eng.get_channels(), eng.get_sample_rate()])
				if not pcm_bytes.is_empty():
					var stream := AudioStreamWAV.new()
					stream.format   = AudioStreamWAV.FORMAT_16_BITS
					stream.stereo   = (eng.get_channels() == 2)
					stream.mix_rate = eng.get_sample_rate()
					stream.data     = pcm_bytes
					# Rocksmith WEM audio is a looping backing track.  vgmstream
					# decodes one loop pass (often ~28 s) then stops.  Enable
					# Godot WAV loop-forward so it repeats for the full song.
					var channels : int = 2 if stream.stereo else 1
					var total_frames : int = pcm_bytes.size() / (channels * 2)
					stream.loop_mode  = AudioStreamWAV.LOOP_FORWARD
					stream.loop_begin = 0
					stream.loop_end   = total_frames
					print("RsBridge: AudioStreamWAV created — stereo=%s  mix_rate=%d  data=%d bytes  loop_frames=%d" % [
						str(stream.stereo), stream.mix_rate, stream.data.size(), total_frames])
					return stream
				push_warning("RsBridge: AudioEngine.decode_all() returned empty PCM — trying OGG fallback.")
			else:
				push_warning("RsBridge: AudioEngine.open() failed — trying OGG fallback.")
		else:
			push_warning("RsBridge: AudioEngine class not found — trying OGG fallback.")

	# ── Try OGG (CDLC) ────────────────────────────────────────────────────────
	var raw := get_audio_bytes()
	print("RsBridge: OGG fallback — raw bytes: %d" % raw.size())
	if not raw.is_empty():
		return AudioStreamOggVorbis.load_from_buffer(raw)

	push_warning("RsBridge: no audio stream available (no WEM decoded, no OGG).")
	return null
