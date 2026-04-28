extends Node

const SCENE_MAIN_MENU  : String = "res://scenes/game_menu.tscn"
const SCENE_SETTINGS   : String = "res://scenes/settings/settings.tscn"
const SCENE_SONG_LIST  : String = "res://scenes/song_list.tscn"
const SCENE_MUSIC_PLAY : String = "res://scenes/music_play.tscn"
const SCENE_MIXER      : String = "res://scenes/mixer.tscn"
const SCENE_TUNING_LIST: String = "res://scenes/tuner/tuning_list.tscn"
const SCENE_TUNER      : String = "res://scenes/tuner/tuner_3d.tscn"


func goto_main_menu() -> void:
	_change_to(SCENE_MAIN_MENU)


func goto_settings() -> void:
	_change_to(SCENE_SETTINGS)


func goto_song_list() -> void:
	_change_to(SCENE_SONG_LIST)


func goto_music_play() -> void:
	_change_to(SCENE_MUSIC_PLAY)


func goto_mixer() -> void:
	_change_to(SCENE_MIXER)


func goto_tuning_list() -> void:
	_change_to(SCENE_TUNING_LIST)


func goto_tuner() -> void:
	_change_to(SCENE_TUNER)


func _change_to(path: String) -> void:
	if get_tree() == null:
		return
	get_tree().change_scene_to_file(path)
