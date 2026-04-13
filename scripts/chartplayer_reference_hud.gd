extends CanvasLayer
class_name ChartPlayerReferenceHud

@onready var _song_tag: Label = $Root/HighwayReference/SongTag
@onready var _runtime_info: Label = $Root/HighwayReference/RuntimeInfo
@onready var _tab_foreground: TextureRect = $Root/HighwayReference/TabForeground
@onready var _vertical_pointer: TextureRect = $Root/HighwayReference/VerticalPointer
@onready var _strum_line: TextureRect = $Root/HighwayReference/StrumLine
@onready var _trail_lines: Array[TextureRect] = [
	$Root/HighwayReference/StringLines/TrailPurple,
	$Root/HighwayReference/StringLines/TrailGreen,
	$Root/HighwayReference/StringLines/TrailOrange,
	$Root/HighwayReference/StringLines/TrailCyan,
	$Root/HighwayReference/StringLines/TrailYellow,
	$Root/HighwayReference/StringLines/TrailRed,
]

var _song_title: String = ""
var _arrangement_name: String = ""
var _total_song_duration_sec: float = 1.0


func set_song_meta(song_name: String, arrangement: String) -> void:
	_song_title = song_name
	_arrangement_name = arrangement
	_song_tag.text = "%s · %s" % [_song_title, _arrangement_name]


func set_reference_lyrics(main_line: String, focus_word: String) -> void:
	# ChartPlayer reference view uses texture-based overlays instead of lyric labels.
	pass


func update_runtime(song_time: float, bpm: float, processed_note_count: int, total_notes: int, root_note: String, song_length_sec: float) -> void:
	_total_song_duration_sec = maxf(song_length_sec, 1.0)
	var progress: float = clampf(song_time / _total_song_duration_sec, 0.0, 1.0)

	var tab_alpha: float = 0.35 + 0.35 * progress
	_tab_foreground.self_modulate.a = tab_alpha

	var pulse: float = 0.5 + 0.5 * sin(song_time * 3.0)
	_vertical_pointer.self_modulate.a = 0.58 + pulse * 0.30
	_strum_line.self_modulate.a = 0.72 + pulse * 0.20

	var hot_idx: int = _root_note_to_index(root_note)
	for i in _trail_lines.size():
		var c := _trail_lines[i].self_modulate
		if i == hot_idx:
			c.a = 1.0
		else:
			c.a = 0.58
		_trail_lines[i].self_modulate = c

	# Keep runtime strings available for optional debugging, but hidden by default
	# to preserve the clean ChartPlayer-like look.
	var note_pct: float = 0.0
	if total_notes > 0:
		note_pct = float(processed_note_count) * 100.0 / float(total_notes)
	_runtime_info.text = "BPM %.1f · %d/%d (%.1f%%) · %s" % [bpm, processed_note_count, total_notes, note_pct, _format_clock(song_time)]


func _root_note_to_index(root_note: String) -> int:
	# Map chromatic pitch classes onto 6 visible string trails.
	# We use pitch-class modulo 6 so adjacent notes usually shift trail index
	# and avoid accidental hard-coded collisions (e.g. E and G on same trail).
	var pitch_class := {
		"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
		"E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
		"Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11,
	}
	if not pitch_class.has(root_note):
		return -1
	return int(pitch_class[root_note]) % _trail_lines.size()


func _format_clock(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	var minutes: int = total / 60
	var secs: int = total % 60
	return "%d:%02d" % [minutes, secs]
