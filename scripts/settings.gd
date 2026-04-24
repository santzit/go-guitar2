extends Control


func _on_tuner_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tuner/tuning_list.tscn")


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_menu.tscn")
