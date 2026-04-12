extends CanvasLayer

@onready var _wave_bg: ProgressBar = $Root/TopPanel/TopVBox/WaveformBackground
@onready var _wave_fg: ProgressBar = $Root/TopPanel/TopVBox/WaveformForeground
@onready var _lyrics_main: Label = $Root/TopPanel/TopVBox/LyricsMain
@onready var _lyrics_focus: Label = $Root/TopPanel/TopVBox/LyricsFocus
@onready var _song_info: Label = $Root/BottomPanel/BottomHBox/SongInfo
@onready var _bpm_label: Label = $Root/BottomPanel/BottomHBox/Bpm
@onready var _progress_label: Label = $Root/BottomPanel/BottomHBox/Progress
@onready var _time_label: Label = $Root/BottomPanel/BottomHBox/Time

var _song_length_sec: float = 1.0


func set_song_meta(song_name: String, arrangement: String) -> void:
	_song_info.text = "%s\n%s" % [song_name, arrangement]


func set_reference_lyrics(main_line: String, focus_word: String) -> void:
	_lyrics_main.text = main_line
	_lyrics_focus.text = focus_word


func update_runtime(song_time: float, bpm: float, spawned_notes: int, total_notes: int, root_note: String, song_length_sec: float) -> void:
	_song_length_sec = maxf(song_length_sec, 1.0)
	var progress: float = clampf(song_time / _song_length_sec, 0.0, 1.0)
	_wave_bg.value = progress * 100.0
	_wave_fg.value = (0.20 + 0.80 * progress) * 100.0
	_bpm_label.text = "BPM: %.1f" % bpm

	var note_pct: float = 0.0
	if total_notes > 0:
		note_pct = float(spawned_notes) * 100.0 / float(total_notes)
	_progress_label.text = "%d/%d (%.1f%%)" % [spawned_notes, total_notes, note_pct]

	_time_label.text = _format_clock(song_time)
	if root_note != "":
		_lyrics_focus.text = root_note


func _format_clock(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	var minutes: int = total / 60
	var secs: int = total % 60
	return "%d:%02d" % [minutes, secs]
