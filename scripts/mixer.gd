extends Control
## mixer.gd — Mixer scene: per-bus gain sliders + mute toggles.
##
## Reads/writes GameState.bus_gains_db / bus_mutes and persists them to disk.
## If an RtEngine is running (singleton stored in GameState), changes are also
## applied live via set_bus_gain_db() / set_bus_mute().

const _GameStateScript = preload("res://scripts/game_state.gd")
const _MixerStripScene: PackedScene = preload("res://scenes/mixer_strip.tscn")

## Slider maps 0..1 to this dB range.
const GAIN_MIN_DB: float = -60.0
const GAIN_MAX_DB: float = 6.0

@onready var _strips_container: HBoxContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/Centerer/Strips

## Parallel arrays built in _ready(); index = bus index (0–8).
var _sliders: Array[VSlider] = []
var _mute_buttons: Array[Button] = []

## Block re-entrant _on_slider_changed calls while loading saved state.
var _loading: bool = false


func _ready() -> void:
	_GameStateScript.load_mixer_settings()

	for i in _GameStateScript.BUS_COUNT:
		var strip := _MixerStripScene.instantiate() as VBoxContainer
		var name_lbl := strip.get_node("BusName") as Label
		var slider := strip.get_node("SliderRow/VolumeSlider") as VSlider
		var mute_btn := strip.get_node("MuteButton") as Button

		name_lbl.text = _GameStateScript.BUS_NAMES[i]
		slider.value = _db_to_slider(_GameStateScript.bus_gains_db[i])
		slider.value_changed.connect(_on_slider_changed.bind(i))
		mute_btn.button_pressed = _GameStateScript.bus_mutes[i]
		mute_btn.pressed.connect(_on_mute_pressed.bind(i))

		_update_slider_tooltip(i, slider)

		_strips_container.add_child(strip)
		_sliders.append(slider)
		_mute_buttons.append(mute_btn)

	# Reflect current mute visual state without emitting pressed (toggle already set above).
	_refresh_mute_visuals()


func _on_slider_changed(value: float, bus_idx: int) -> void:
	if _loading:
		return

	var gain_db: float = _slider_to_db(value)
	_GameStateScript.bus_gains_db[bus_idx] = gain_db
	_update_slider_tooltip(bus_idx, _sliders[bus_idx])
	_GameStateScript.save_mixer_settings()
	_apply_to_outputs(bus_idx)


func _on_mute_pressed(bus_idx: int) -> void:
	var muted: bool = _mute_buttons[bus_idx].button_pressed
	_GameStateScript.bus_mutes[bus_idx] = muted
	_refresh_mute_visuals()
	_GameStateScript.save_mixer_settings()
	_apply_to_outputs(bus_idx)


func _refresh_mute_visuals() -> void:
	for i in _GameStateScript.BUS_COUNT:
		var btn := _mute_buttons[i]
		if _GameStateScript.bus_mutes[i]:
			btn.modulate = Color(1.0, 0.5, 0.5)
		else:
			btn.modulate = Color(1.0, 1.0, 1.0)


## Apply a single bus setting to Godot AudioServer and running RtEngine, if available.
func _apply_to_outputs(bus_idx: int) -> void:
	var bus_name := StringName(_GameStateScript.BUS_NAMES[bus_idx])
	var godot_bus_idx: int = AudioServer.get_bus_index(bus_name)
	if godot_bus_idx != -1:
		AudioServer.set_bus_volume_db(godot_bus_idx, _GameStateScript.bus_gains_db[bus_idx])
		AudioServer.set_bus_mute(godot_bus_idx, _GameStateScript.bus_mutes[bus_idx])

	var rt := _get_rt_engine()
	if rt == null:
		return
	rt.set_bus_gain_db(bus_idx, _GameStateScript.bus_gains_db[bus_idx])
	rt.set_bus_mute(bus_idx, _GameStateScript.bus_mutes[bus_idx])


## Try to get a live RtEngine from the scene tree (node named "RtEngine" anywhere).
func _get_rt_engine() -> Object:
	var nodes := get_tree().get_nodes_in_group("rt_engine")
	if nodes.size() > 0:
		return nodes[0]
	# Fallback: look for an autoload or a direct child of root.
	if Engine.has_singleton("RtEngine"):
		return Engine.get_singleton("RtEngine")
	return null


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_menu.tscn")


func _on_reset_button_pressed() -> void:
	_loading = true
	for i in _GameStateScript.BUS_COUNT:
		_GameStateScript.bus_gains_db[i] = 0.0
		_GameStateScript.bus_mutes[i] = false
		_sliders[i].value = _db_to_slider(0.0)
		_update_slider_tooltip(i, _sliders[i])
		_mute_buttons[i].button_pressed = false
	_loading = false

	_refresh_mute_visuals()
	_GameStateScript.save_mixer_settings()
	for i in _GameStateScript.BUS_COUNT:
		_apply_to_outputs(i)


func _slider_to_db(slider_value: float) -> float:
	return lerpf(GAIN_MIN_DB, GAIN_MAX_DB, slider_value)


func _db_to_slider(db_value: float) -> float:
	return clampf((db_value - GAIN_MIN_DB) / (GAIN_MAX_DB - GAIN_MIN_DB), 0.0, 1.0)


func _update_slider_tooltip(bus_idx: int, slider: VSlider) -> void:
	slider.tooltip_text = "%s\n%.1f dB" % [_GameStateScript.BUS_NAMES[bus_idx], _GameStateScript.bus_gains_db[bus_idx]]
