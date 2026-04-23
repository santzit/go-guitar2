extends Control

const _GameStateScript = preload("res://scripts/game_state.gd")
const DEFAULT_NOTES: Array[String] = ["E2", "A2", "D3", "G3", "B3", "E4"]

const TUNING_PRESETS: Array[Dictionary] = [
	{"name": "E Standard", "notes": ["E2", "A2", "D3", "G3", "B3", "E4"]},
	{"name": "Drop D", "notes": ["D2", "A2", "D3", "G3", "B3", "E4"]},
	{"name": "Eb Standard", "notes": ["D#2", "G#2", "C#3", "F#3", "A#3", "D#4"]},
	{"name": "D Standard", "notes": ["D2", "G2", "C3", "F3", "A3", "D4"]},
	{"name": "Drop C", "notes": ["C2", "G2", "C3", "F3", "A3", "D4"]},
	{"name": "Open G", "notes": ["D2", "G2", "D3", "G3", "B3", "D4"]},
	{"name": "Open D", "notes": ["D2", "A2", "D3", "F#3", "A3", "D4"]},
]

@onready var _preset_list: ItemList = $Panel/MarginContainer/VBoxContainer/PresetList
@onready var _notes_label: Label = $Panel/MarginContainer/VBoxContainer/NotesLabel


func _ready() -> void:
	for preset in TUNING_PRESETS:
		_preset_list.add_item(String(preset.get("name", "Unknown")))
	_preset_list.select(0)
	_update_notes_preview(0)


func _on_preset_list_item_selected(index: int) -> void:
	_update_notes_preview(index)


func _on_preset_list_item_activated(index: int) -> void:
	_start_tuner(index)


func _on_start_button_pressed() -> void:
	var selected: PackedInt32Array = _preset_list.get_selected_items()
	var idx: int = selected[0] if selected.size() > 0 else 0
	_start_tuner(idx)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")


func _start_tuner(index: int) -> void:
	if index < 0 or index >= TUNING_PRESETS.size():
		return
	var preset: Dictionary = TUNING_PRESETS[index]
	var notes_untyped: Array = preset.get("notes", DEFAULT_NOTES)
	var notes_typed: Array[String] = []
	for n in notes_untyped:
		notes_typed.append(String(n))
	_GameStateScript.selected_tuning_name = String(preset.get("name", "E Standard"))
	_GameStateScript.selected_tuning_notes = notes_typed
	get_tree().change_scene_to_file("res://scenes/tuner/tuner.tscn")


func _update_notes_preview(index: int) -> void:
	if index < 0 or index >= TUNING_PRESETS.size():
		_notes_label.text = ""
		return
	var notes: PackedStringArray = PackedStringArray(TUNING_PRESETS[index].get("notes", []))
	_notes_label.text = "Target notes: %s" % " ".join(notes)
