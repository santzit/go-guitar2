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


## Returns raw OGG bytes from the song.
## Convert with AudioStreamOggVorbis.load_from_buffer(bytes) in Godot 4.
func get_audio_bytes() -> PackedByteArray:
	if _ext == null:
		return PackedByteArray()
	return _ext.get_audio_bytes()


## Convenience: create an AudioStream from the embedded audio data, or null.
func get_audio_stream() -> AudioStream:
	var raw := get_audio_bytes()
	if raw.is_empty():
		return null
	# AudioStreamOggVorbis.load_from_buffer is the Godot 4 API.
	if ResourceLoader.exists("res://"):   # sanity-check engine is available
		return AudioStreamOggVorbis.load_from_buffer(raw)
	return null
