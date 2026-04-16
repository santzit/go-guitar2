## goguitar_bridge.gd  –  GDScript wrapper around the RocksmithBridge GDExtension.
##
## Build the native library first (see gdextension/README.md), then the
## "RocksmithBridge" class will be available and this wrapper will delegate
## to it.  When the extension is absent the wrapper silently no-ops so that
## the rest of the game still runs (demo-mode notes are used instead).
##
## Usage:
##   var bridge := GoGuitarBridge.new()
##   if bridge.load_psarc("res://DLC/song.psarc"):
##       var notes  := bridge.get_notes()          # Array[Dictionary]
##       var stream := bridge.get_audio_stream()   # AudioStream or null
extends RefCounted
class_name GoGuitarBridge

var _ext: Object = null   # native RocksmithBridge instance (may be null)


func _init() -> void:
	if ClassDB.class_exists("RocksmithBridge"):
		_ext = ClassDB.instantiate("RocksmithBridge")
	else:
		push_warning(
			"GoGuitarBridge: RocksmithBridge GDExtension not loaded. " +
			"Build the extension from gdextension/ and copy the binary to " +
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


## Returns raw preview WEM bytes from the song (official DLC — short clip).
func get_preview_wem_bytes() -> PackedByteArray:
	if _ext == null:
		return PackedByteArray()
	if _ext.has_method("get_preview_wem_bytes"):
		return _ext.get_preview_wem_bytes()
	return PackedByteArray()


## Convenience: create a non-looping AudioStream from the preview WEM, or null.
## Intended for the song-list scene where a short clip plays while selecting a song.
func get_preview_audio_stream() -> AudioStream:
	var wem := get_preview_wem_bytes()
	print("GoGuitarBridge: get_preview_audio_stream() — preview WEM bytes: %d" % wem.size())
	if not wem.is_empty():
		var ae_exists := ClassDB.class_exists("AudioEngine")
		if ae_exists:
			var eng: Object = ClassDB.instantiate("AudioEngine")
			var ok: Variant = eng.open(wem)
			if ok:
				var pcm_bytes: PackedByteArray = eng.decode_all()
				if not pcm_bytes.is_empty():
					var stream := AudioStreamWAV.new()
					stream.format    = AudioStreamWAV.FORMAT_16_BITS
					stream.stereo    = (eng.get_channels() == 2)
					stream.mix_rate  = eng.get_sample_rate()
					stream.data      = pcm_bytes
					# Preview clips are played once — no looping.
					stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
					print("GoGuitarBridge: preview AudioStreamWAV created — %d bytes" % pcm_bytes.size())
					return stream
	push_warning("GoGuitarBridge: no preview audio stream available.")
	return null


## Returns raw MAIN WEM bytes from the song (official DLC — full-length backing track).
func get_wem_bytes() -> PackedByteArray:
	if _ext == null:
		return PackedByteArray()
	if _ext.has_method("get_wem_bytes"):
		return _ext.get_wem_bytes()
	return PackedByteArray()


## Returns SNG diagnostic info as a Dictionary:
##   { "start_time": float, "difficulty": int }
## start_time: when the arrangement begins in the WEM (seconds from WEM t=0).
##             Note times are already absolute from WEM t=0 — no offset needed.
## difficulty: difficulty index of the parsed level (highest = master).
func get_sng_info() -> Dictionary:
	if _ext == null or not _ext.has_method("get_sng_info"):
		return {}
	return _ext.get_sng_info()


## Decode WEM bytes into an AudioStreamWAV via the AudioEngine GDExtension.
## Returns null when the AudioEngine class is absent or decoding fails.
func _decode_wem_to_stream(wem: PackedByteArray) -> AudioStream:
	if wem.is_empty():
		return null
	if not ClassDB.class_exists("AudioEngine"):
		push_warning("GoGuitarBridge: AudioEngine class not found.")
		return null
	var eng: Object = ClassDB.instantiate("AudioEngine")
	print("GoGuitarBridge: calling AudioEngine.open() with %d WEM bytes" % wem.size())
	var ok: Variant = eng.open(wem)
	print("GoGuitarBridge: AudioEngine.open() returned: %s" % str(ok))
	if not ok:
		push_warning("GoGuitarBridge: AudioEngine.open() failed.")
		return null
	var pcm_bytes: PackedByteArray = eng.decode_all()
	print("GoGuitarBridge: AudioEngine.decode_all() returned %d PCM bytes  channels=%d  rate=%d" % [
		pcm_bytes.size(), eng.get_channels(), eng.get_sample_rate()])
	if pcm_bytes.is_empty():
		push_warning("GoGuitarBridge: AudioEngine.decode_all() returned empty PCM.")
		return null
	var stream := AudioStreamWAV.new()
	stream.format    = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo    = (eng.get_channels() == 2)
	stream.mix_rate  = eng.get_sample_rate()
	stream.data      = pcm_bytes
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	print("GoGuitarBridge: AudioStreamWAV created — stereo=%s  mix_rate=%d  data=%d bytes" % [
		str(stream.stereo), stream.mix_rate, stream.data.size()])
	return stream


## Convenience: create an AudioStream from the embedded audio data, or null.
## Priority:
##   1. MAIN WEM (full-length backing track) decoded via AudioEngine.
##   2. PREVIEW WEM used as fallback gameplay audio when no MAIN WEM is found.
##   3. OGG raw bytes (CDLC fallback).
func get_audio_stream() -> AudioStream:
	# ── 1. Try MAIN WEM (official DLC — full-length backing track) ────────────
	var wem := get_wem_bytes()
	print("GoGuitarBridge: get_audio_stream() — MAIN WEM bytes: %d" % wem.size())
	if not wem.is_empty():
		var stream := _decode_wem_to_stream(wem)
		if stream:
			return stream
		push_warning("GoGuitarBridge: MAIN WEM decode failed — trying preview WEM fallback.")

	# ── 2. Preview WEM as gameplay audio fallback ─────────────────────────────
	# Covers DLC packages that only contain a single WEM classified as PREVIEW
	# by the BNK parser.  The Rust layer also does this fallback, but we add a
	# belt-and-suspenders check here in GDScript.
	var preview_wem := get_preview_wem_bytes()
	print("GoGuitarBridge: get_audio_stream() — PREVIEW WEM bytes: %d" % preview_wem.size())
	if not preview_wem.is_empty():
		print("GoGuitarBridge: using PREVIEW WEM as gameplay audio fallback.")
		var stream := _decode_wem_to_stream(preview_wem)
		if stream:
			return stream

	# ── 3. OGG (CDLC) ─────────────────────────────────────────────────────────
	var raw := get_audio_bytes()
	print("GoGuitarBridge: OGG fallback — raw bytes: %d" % raw.size())
	if not raw.is_empty():
		return AudioStreamOggVorbis.load_from_buffer(raw)

	push_warning("GoGuitarBridge: no audio stream available (no WEM decoded, no OGG).")
	return null
