extends Control


func _on_song_list_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/song_list.tscn")
