extends CanvasLayer
class_name ChartPlayerReferenceHud

## Foreground waveform starts at 15% filled so the bar remains visible at t=0.
const WAVE_FG_BASE_PROGRESS: float = 0.15
## Foreground waveform additionally fills by this range as song progress advances.
const WAVE_FG_DYNAMIC_RANGE: float = 0.85

@onready var _song_tag: Label = $Root/TopStrip/TopMargin/TopHBox/SongTag
@onready var _bpm_label: Label = $Root/TopStrip/TopMargin/TopHBox/Bpm
@onready var _clock_label: Label = $Root/TopStrip/TopMargin/TopHBox/Clock
@onready var _arrangement_label: Label = $Root/CenterLayer/LeftRail/LeftMargin/LeftVBox/Arrangement
@onready var _root_label: Label = $Root/CenterLayer/LeftRail/LeftMargin/LeftVBox/RootNote
@onready var _note_progress_label: Label = $Root/CenterLayer/RightRail/RightMargin/RightVBox/NotesProgress
@onready var _song_progress_label: Label = $Root/CenterLayer/RightRail/RightMargin/RightVBox/SongProgress
@onready var _transport_label: Label = $Root/BottomStrip/BottomMargin/BottomHBox/Transport
@onready var _lyrics_main: Label = $Root/CenterLayer/HighwayMask/HudMargin/HudVBox/LyricsMain
@onready var _lyrics_focus: Label = $Root/CenterLayer/HighwayMask/HudMargin/HudVBox/LyricsFocus
@onready var _wave_bg: ProgressBar = $Root/CenterLayer/HighwayMask/HudMargin/HudVBox/WaveBack
@onready var _wave_fg: ProgressBar = $Root/CenterLayer/HighwayMask/HudMargin/HudVBox/WaveFront

var _total_song_duration_sec: float = 1.0


func set_song_meta(song_name: String, arrangement: String) -> void:
	_song_tag.text = song_name
	_arrangement_label.text = "Arrangement: %s" % arrangement


func set_reference_lyrics(main_line: String, focus_word: String) -> void:
	_lyrics_main.text = main_line
	_lyrics_focus.text = focus_word


func update_runtime(song_time: float, bpm: float, processed_note_count: int, total_notes: int, root_note: String, song_length_sec: float) -> void:
	_total_song_duration_sec = maxf(song_length_sec, 1.0)
	var progress: float = clampf(song_time / _total_song_duration_sec, 0.0, 1.0)
	_wave_bg.value = progress * 100.0
	_wave_fg.value = (WAVE_FG_BASE_PROGRESS + WAVE_FG_DYNAMIC_RANGE * progress) * 100.0
	_bpm_label.text = "BPM %.1f" % bpm

	var note_pct: float = 0.0
	if total_notes > 0:
		note_pct = float(processed_note_count) * 100.0 / float(total_notes)
	_note_progress_label.text = "Notes: %d/%d  (%.1f%%)" % [processed_note_count, total_notes, note_pct]

	_song_progress_label.text = "Song: %.1f%%" % (progress * 100.0)
	_clock_label.text = "%s / %s" % [_format_clock(song_time), _format_clock(_total_song_duration_sec)]
	if root_note != "":
		var root_text := "Current root: %s" % root_note
		_root_label.text = root_text
		_lyrics_focus.text = root_note
		_transport_label.text = "Tracking lane: %s" % root_note
	else:
		_root_label.text = "Current root: --"
		_transport_label.text = "Tracking lane: --"


func _format_clock(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	var minutes: int = total / 60
	var secs: int = total % 60
	return "%d:%02d" % [minutes, secs]
