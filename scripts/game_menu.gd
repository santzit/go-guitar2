extends Control

@onready var _song_list: ItemList = $MarginContainer/VBoxContainer/SongList
@onready var _play_btn: Button = $MarginContainer/VBoxContainer/Buttons/PlayButton
@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel

var _song_paths: Array[String] = []


func _ready() -> void:
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


func _on_play_button_pressed() -> void:
	var idxs := _song_list.get_selected_items()
	if idxs.is_empty():
		_status_label.text = "Select a song first."
		return

	var idx: int = idxs[0]
	if idx < 0 or idx >= _song_paths.size():
		_status_label.text = "Invalid song selection."
		return

	GameState.selected_psarc_path = _song_paths[idx]
	get_tree().change_scene_to_file("res://scenes/music_play.tscn")
