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


## Load a .psarc archive.  Returns true on success.
func load_psarc(path: String) -> bool:
	if _ext == null:
		return false
	return _ext.load_psarc(ProjectSettings.globalize_path(path))


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
## Priority: WEM (decoded via AudioEngine) → OGG (CDLC fallback).
func get_audio_stream() -> AudioStream:
	# ── Try WEM via AudioEngine (official DLC — vgmstream on Linux) ──────────
	var wem := get_wem_bytes()
	if not wem.is_empty() and ClassDB.class_exists("AudioEngine"):
		var eng: Object = ClassDB.instantiate("AudioEngine")
		if eng.open(wem):
			var pcm_bytes: PackedByteArray = eng.decode_all()
			if not pcm_bytes.is_empty():
				var stream := AudioStreamWAV.new()
				stream.format   = AudioStreamWAV.FORMAT_16_BITS
				stream.stereo   = (eng.get_channels() == 2)
				stream.mix_rate = eng.get_sample_rate()
				stream.data     = pcm_bytes
				return stream
		push_warning("RsBridge: AudioEngine could not decode WEM — trying OGG fallback.")

	# ── Try OGG (CDLC) ────────────────────────────────────────────────────────
	var raw := get_audio_bytes()
	if not raw.is_empty():
		return AudioStreamOggVorbis.load_from_buffer(raw)

	return null
