extends Control
## mixer.gd — Mixer scene: per-bus gain sliders + mute toggles.
##
## Reads/writes GameState.bus_gains_db / bus_mutes and persists them to disk.
## If an RtEngine is running (singleton stored in GameState), changes are also
## applied live via set_bus_gain_db() / set_bus_mute().

const _GameStateScript = preload("res://scripts/game_state.gd")

## Minimum and maximum dB for the sliders.
const GAIN_MIN_DB : float = -60.0
const GAIN_MAX_DB : float =  6.0

@onready var _sliders_container : VBoxContainer = $MarginContainer/VBoxContainer/BusRows

## Parallel arrays built in _ready(); index = bus index (0–8).
var _sliders : Array[HSlider] = []
var _mute_buttons : Array[Button] = []
var _labels : Array[Label] = []
var _value_labels : Array[Label] = []

## Block re-entrant _on_slider_changed calls while loading saved state.
var _loading : bool = false


func _ready() -> void:
	_GameStateScript.load_mixer_settings()

	for i in _GameStateScript.BUS_COUNT:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Bus name label (fixed width)
		var name_lbl := Label.new()
		name_lbl.text = _GameStateScript.BUS_NAMES[i]
		name_lbl.custom_minimum_size = Vector2(160, 0)
		row.add_child(name_lbl)
		_labels.append(name_lbl)

		# Mute button
		var mute_btn := Button.new()
		mute_btn.text = "M"
		mute_btn.toggle_mode = true
		mute_btn.button_pressed = _GameStateScript.bus_mutes[i]
		mute_btn.custom_minimum_size = Vector2(40, 0)
		mute_btn.pressed.connect(_on_mute_pressed.bind(i))
		row.add_child(mute_btn)
		_mute_buttons.append(mute_btn)

		# Gain slider
		var slider := HSlider.new()
		slider.min_value = GAIN_MIN_DB
		slider.max_value = GAIN_MAX_DB
		slider.step = 0.1
		slider.value = _GameStateScript.bus_gains_db[i]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider_changed.bind(i))
		row.add_child(slider)
		_sliders.append(slider)

		# dB value label (shows current slider value)
		var val_lbl := Label.new()
		val_lbl.text = "%.1f dB" % _GameStateScript.bus_gains_db[i]
		val_lbl.custom_minimum_size = Vector2(72, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		_value_labels.append(val_lbl)

		_sliders_container.add_child(row)

	# Reflect current mute visual state without emitting pressed (toggle already set above).
	_refresh_mute_visuals()


func _on_slider_changed(value: float, bus_idx: int) -> void:
	if _loading:
		return
	_GameStateScript.bus_gains_db[bus_idx] = value
	_value_labels[bus_idx].text = "%.1f dB" % value
	_GameStateScript.save_mixer_settings()
	# Apply live if an RtEngine is present.
	_apply_to_rt(bus_idx)


func _on_mute_pressed(bus_idx: int) -> void:
	var muted : bool = _mute_buttons[bus_idx].button_pressed
	_GameStateScript.bus_mutes[bus_idx] = muted
	_refresh_mute_visuals()
	_GameStateScript.save_mixer_settings()
	_apply_to_rt(bus_idx)


func _refresh_mute_visuals() -> void:
	for i in _GameStateScript.BUS_COUNT:
		var btn := _mute_buttons[i]
		if _GameStateScript.bus_mutes[i]:
			btn.modulate = Color(1.0, 0.4, 0.4)  # red tint = muted
		else:
			btn.modulate = Color(1.0, 1.0, 1.0)


## Apply a single bus setting to the running RtEngine, if available.
func _apply_to_rt(bus_idx: int) -> void:
	var rt = _get_rt_engine()
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
		_GameStateScript.bus_mutes[i]    = false
		_sliders[i].value = 0.0
		_value_labels[i].text = "0.0 dB"
		_mute_buttons[i].button_pressed = false
	_loading = false
	_refresh_mute_visuals()
	_GameStateScript.save_mixer_settings()
	# Apply all buses to RT.
	var rt := _get_rt_engine()
	if rt != null:
		_GameStateScript.apply_mixer_to_rt_engine(rt)
