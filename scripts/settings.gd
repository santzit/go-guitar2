extends Control


func _on_tuner_button_pressed() -> void:
	SceneManager.goto_tuning_list()


func _on_back_button_pressed() -> void:
	SceneManager.goto_main_menu()
