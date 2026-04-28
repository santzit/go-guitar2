extends Button

signal row_pressed(index: int)

@onready var _title: Label = $Row/Left/Title
@onready var _artist: Label = $Row/Left/Artist
@onready var _details: Label = $Row/Left/Details
@onready var _arrangements: Label = $Row/Left/Arrangements
@onready var _percent: Label = $Row/Percent

var _index: int = -1


func _ready() -> void:
	pressed.connect(_on_pressed)


func setup(index: int, data: Dictionary, focused: bool) -> void:
	_index = index
	_title.text = String(data.get("title", "Unknown Song"))
	_artist.text = String(data.get("artist", "Unknown Artist"))
	_details.text = String(data.get("details", ""))
	_arrangements.text = String(data.get("arrangements", ""))
	_percent.text = String(data.get("percent", "99%"))
	set_focused(focused)


func set_focused(focused: bool) -> void:
	if focused:
		custom_minimum_size = Vector2(0, 112)
		_title.add_theme_font_size_override("font_size", 30)
		_artist.add_theme_font_size_override("font_size", 20)
		_percent.add_theme_font_size_override("font_size", 30)
		_details.visible = true
		_arrangements.visible = true
		modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		custom_minimum_size = Vector2(0, 74)
		_title.add_theme_font_size_override("font_size", 22)
		_artist.add_theme_font_size_override("font_size", 16)
		_percent.add_theme_font_size_override("font_size", 20)
		_details.visible = false
		_arrangements.visible = false
		modulate = Color(0.88, 0.88, 0.9, 1.0)


func _on_pressed() -> void:
	row_pressed.emit(_index)
