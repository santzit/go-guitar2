extends Control

@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel


func _on_song_list_button_pressed() -> void:
	SceneManager.goto_song_list()


func _on_mixer_button_pressed() -> void:
	SceneManager.goto_mixer()


func _on_settings_button_pressed() -> void:
	SceneManager.goto_settings()
