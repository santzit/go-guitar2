extends Control

@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel


func _on_song_list_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/song_list.tscn")


func _on_mixer_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/mixer.tscn")


func _on_settings_button_pressed() -> void:
	_status_label.text = "Settings: coming soon."
