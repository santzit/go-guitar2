extends Control

const _GoGuitarBridgeScript = preload("res://scripts/goguitar_bridge.gd")
const _SongListItemScene: PackedScene = preload("res://scenes/song_list_item.tscn")

@onready var _songs_container: VBoxContainer = $MarginContainer/VBoxContainer/SongsScroll/Songs
@onready var _play_btn: Button = $MarginContainer/VBoxContainer/Buttons/PlayButton
@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var _preview_player: AudioStreamPlayer = $PreviewPlayer
@onready var _preview_timer: Timer = $PreviewTimer

var _song_paths: Array[String] = []
var _songs_meta: Array[Dictionary] = []
var _rows: Array = []
var _selected_idx: int = -1
var _preview_idx: int = -1
var _bridge = null


func _ready() -> void:
	_bridge = _GoGuitarBridgeScript.new()
	_reload_song_list()


func _reload_song_list() -> void:
	_clear_rows()
	_song_paths = GameState.list_dlc_psarc_paths()
	_songs_meta.clear()

	if _song_paths.is_empty():
		_status_label.text = "No songs found. Place .psarc files in DLC/"
		_play_btn.disabled = true
		return

	_status_label.text = "Loading song metadata..."
	for p in _song_paths:
		_songs_meta.append(_build_song_metadata(p))

	for i in _songs_meta.size():
		var row = _SongListItemScene.instantiate()
		row.row_pressed.connect(_on_row_pressed)
		row.focus_entered.connect(_on_row_focus_entered.bind(i))
		_songs_container.add_child(row)
		row.setup(i, _songs_meta[i], i == 0)
		_rows.append(row)

	_set_selected(0)
	_status_label.text = "Select a song and press Play."
	_play_btn.disabled = false


func _build_song_metadata(path: String) -> Dictionary:
	var title: String = path.get_file().get_basename()
	var artist: String = "Unknown Artist"
	var year: int = 0
	var tuning_text: String = "E Standard"
	var arrangements: Array[String] = []
	var duration_sec: float = 0.0

	if _bridge.load_psarc_abs(path):
		var meta: Dictionary = {}
		if _bridge.has_method("get_song_metadata"):
			meta = _bridge.get_song_metadata()
		title = String(meta.get("title", title)).strip_edges()
		artist = String(meta.get("artist", artist)).strip_edges()
		year = int(meta.get("year", 0))
		if bool(meta.get("has_lead", false)):
			arrangements.append("Lead")
		if bool(meta.get("has_rhythm", false)):
			arrangements.append("Rhythm")
		if bool(meta.get("has_bass", false)):
			arrangements.append("Bass")

		var sng_info: Dictionary = _bridge.get_sng_info()
		var raw_tuning = sng_info.get("tuning", [])
		tuning_text = _format_tuning(raw_tuning)

		# Duration: use SNG-reported length first (fast, no decode needed).
		# Full WEM decode is not performed here — it is too slow to run for every
		# song in the list and would freeze the UI for several seconds per song.
		duration_sec = float(meta.get("sng_song_length", 0.0))

	if title.is_empty():
		title = path.get_file().get_basename()
	if artist.is_empty():
		artist = "Unknown Artist"
	if year <= 0:
		year = _guess_year(path)
	if arrangements.is_empty():
		arrangements = ["Lead"]

	var details_parts: Array[String] = []
	details_parts.append(_format_duration(duration_sec))
	details_parts.append(str(year) if year > 0 else "----")
	details_parts.append(tuning_text)

	return {
		"path": path,
		"title": title,
		"artist": artist,
		"year": year,
		"tuning": tuning_text,
		"duration_sec": duration_sec,
		"arrangements": " • ".join(arrangements),
		"details": " • ".join(details_parts),
		"percent": "99%",
	}


func _main_track_duration_seconds(wem: PackedByteArray) -> float:
	if wem.is_empty() or not ClassDB.class_exists("AudioEngine"):
		return 0.0
	var eng: Object = ClassDB.instantiate("AudioEngine")
	if not eng.open(wem):
		return 0.0
	var pcm: PackedByteArray = eng.decode_all()
	if pcm.is_empty():
		return 0.0
	var channels: int = max(1, int(eng.get_channels()))
	var rate: int = max(1, int(eng.get_sample_rate()))
	# PCM16 LE => 2 bytes/sample per channel.
	var bytes_per_second: float = float(rate * channels * 2)
	return float(pcm.size()) / maxf(bytes_per_second, 1.0)


func _format_tuning(raw_tuning) -> String:
	if raw_tuning is Array:
		var all_zero: bool = true
		for t in raw_tuning:
			if int(t) != 0:
				all_zero = false
				break
		if all_zero:
			return "E Standard"
		var parts: Array[String] = []
		for t in raw_tuning:
			parts.append(str(int(t)))
		return "Tuning %s" % ",".join(parts)
	return "E Standard"


func _format_duration(sec: float) -> String:
	var total: int = maxi(int(round(sec)), 0)
	var mm: int = total / 60
	var ss: int = total % 60
	return "%02d:%02d" % [mm, ss]


func _guess_year(text: String) -> int:
	var r := RegEx.new()
	if r.compile("(19[0-9]{2}|20[0-9]{2}|2100)") != OK:
		return 0
	var m: RegExMatch = r.search(text)
	if m == null:
		return 0
	return int(m.get_string(1))


func _clear_rows() -> void:
	for row in _rows:
		if is_instance_valid(row):
			row.queue_free()
	_rows.clear()


func _set_selected(index: int, focus_row: bool = true) -> void:
	if index < 0 or index >= _songs_meta.size():
		return
	if _selected_idx == index and not focus_row:
		return
	_selected_idx = index
	for i in _rows.size():
		_rows[i].set_focused(i == _selected_idx)
	if focus_row and _selected_idx >= 0 and _selected_idx < _rows.size():
		_rows[_selected_idx].grab_focus()
	_preview_idx = index
	_stop_preview()
	_preview_timer.start()


func _on_row_pressed(index: int) -> void:
	_set_selected(index)
	_status_label.text = "Select a song and press Play."


func _on_row_focus_entered(index: int) -> void:
	_set_selected(index, false)


func _unhandled_input(event: InputEvent) -> void:
	if _songs_meta.is_empty():
		return
	if event.is_action_pressed("ui_down"):
		_set_selected(mini(_selected_idx + 1, _songs_meta.size() - 1))
		_status_label.text = "Select a song and press Play."
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_set_selected(maxi(_selected_idx - 1, 0))
		_status_label.text = "Select a song and press Play."
		get_viewport().set_input_as_handled()
		return


func _on_back_button_pressed() -> void:
	_stop_preview()
	SceneManager.goto_main_menu()


func _on_play_button_pressed() -> void:
	_stop_preview()
	if _selected_idx < 0 or _selected_idx >= _songs_meta.size():
		_status_label.text = "Select a song first."
		return
	GameState.selected_psarc_path = String(_songs_meta[_selected_idx].get("path", ""))
	SceneManager.goto_music_play()


func _on_preview_timer_timeout() -> void:
	if _preview_idx < 0 or _preview_idx >= _songs_meta.size():
		return
	var path: String = String(_songs_meta[_preview_idx].get("path", ""))
	if path.is_empty():
		return
	_status_label.text = "Loading preview..."
	if _bridge.load_psarc_abs(path):
		var stream: AudioStream = _bridge.get_preview_audio_stream()
		if stream:
			_preview_player.stream = stream
			_preview_player.play()
			_status_label.text = "Preview playing - Press Play to start"
		else:
			_status_label.text = "No preview available - Press Play to start"
	else:
		_status_label.text = "Failed to load preview"


func _stop_preview() -> void:
	_preview_timer.stop()
	if _preview_player.playing:
		_preview_player.stop()
