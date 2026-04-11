extends Control

const _RsBridgeScript = preload("res://scripts/rs_bridge.gd")

@onready var _song_list     : ItemList         = $MarginContainer/VBoxContainer/SongList
@onready var _play_btn      : Button           = $MarginContainer/VBoxContainer/Buttons/PlayButton
@onready var _status_label  : Label            = $MarginContainer/VBoxContainer/StatusLabel
@onready var _preview_player: AudioStreamPlayer = $PreviewPlayer
@onready var _preview_timer : Timer            = $PreviewTimer

var _song_paths       : Array[String] = []
## Index of the song whose preview is pending / currently playing.
var _preview_idx      : int           = -1
## RsBridge instance reused between preview loads to avoid repeated allocations.
var _bridge           = null


func _ready() -> void:
	_bridge = _RsBridgeScript.new()
	_reload_song_list()


func _reload_song_list() -> void:
	_song_list.clear()
	_song_paths = GameState.list_dlc_psarc_paths()

	for p in _song_paths:
		_song_list.add_item(p.get_file())

	if _song_paths.is_empty():
		_status_label.text = "No songs found. Place .psarc files in DLC/"
		_play_btn.disabled = true
		return

	_song_list.select(0)
	_status_label.text = "Select a song and press Play."
	_play_btn.disabled = false


# ── Signals ──────────────────────────────────────────────────────────────────

func _on_play_button_pressed() -> void:
	_stop_preview()
	var idxs := _song_list.get_selected_items()
	if idxs.is_empty():
		_status_label.text = "Select a song first."
		return

	var selected_song_idx: int = idxs[0]
	if selected_song_idx < 0 or selected_song_idx >= _song_paths.size():
		_status_label.text = "Invalid song selection."
		return

	GameState.selected_psarc_path = _song_paths[selected_song_idx]
	get_tree().change_scene_to_file("res://scenes/music_play.tscn")


## Called when the user clicks a different entry in the ItemList.
## Stops any running preview, records the pending index, then starts the
## 1-second debounce timer so fast scrolling doesn't trigger a PSARC load
## on every keystroke.
func _on_song_list_item_selected(index: int) -> void:
	_stop_preview()
	_preview_idx = index
	_preview_timer.start()
	_status_label.text = "Select a song and press Play."


## Fired 1 second after the last selection change.  Loads the PSARC and
## starts the preview clip so the player can hear the song before committing.
func _on_preview_timer_timeout() -> void:
	if _preview_idx < 0 or _preview_idx >= _song_paths.size():
		return

	var path: String = _song_paths[_preview_idx]
	_status_label.text = "Loading preview…"

	if _bridge.load_psarc_abs(path):
		var stream: AudioStream = _bridge.get_preview_audio_stream()
		if stream:
			_preview_player.stream = stream
			_preview_player.play()
			_status_label.text = "♪ Preview playing — Press Play to start"
		else:
			_status_label.text = "No preview available — Press Play to start"
	else:
		_status_label.text = "Select a song and press Play."


# ── Helpers ───────────────────────────────────────────────────────────────────

func _stop_preview() -> void:
	_preview_timer.stop()
	if _preview_player.playing:
		_preview_player.stop()
