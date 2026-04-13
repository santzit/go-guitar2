extends CanvasLayer
class_name ChartPlayerReferenceHud

const TAB_BASE_ALPHA: float = 0.35
const TAB_DYNAMIC_ALPHA: float = 0.35
const POINTER_PULSE_HZ: float = 3.0
const POINTER_BASE_ALPHA: float = 0.58
const POINTER_PULSE_ALPHA: float = 0.30
const STRUM_BASE_ALPHA: float = 0.72
const STRUM_PULSE_ALPHA: float = 0.20
const TRAIL_ACTIVE_ALPHA: float = 1.0
const TRAIL_INACTIVE_ALPHA: float = 0.58
const ROOT_NOTE_PITCH_CLASS := {
	"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
	"E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
	"Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11,
}

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

var _total_song_duration_sec: float = 1.0
var _last_hot_idx: int = -2


func set_song_meta(song_name: String, arrangement: String) -> void:
	_song_tag.text = "%s · %s" % [song_name, arrangement]


func set_reference_lyrics(main_line: String, focus_word: String) -> void:
	# Intentionally empty: ChartPlayer reference view does not render lyric labels.
	pass


func update_runtime(song_time: float, bpm: float, processed_note_count: int, total_notes: int, root_note: String, song_length_sec: float) -> void:
	_total_song_duration_sec = maxf(song_length_sec, 1.0)
	var progress: float = clampf(song_time / _total_song_duration_sec, 0.0, 1.0)

	var tab_alpha: float = TAB_BASE_ALPHA + TAB_DYNAMIC_ALPHA * progress
	_tab_foreground.self_modulate.a = tab_alpha

	var pulse: float = 0.5 + 0.5 * sin(song_time * TAU * POINTER_PULSE_HZ)
	_vertical_pointer.self_modulate.a = POINTER_BASE_ALPHA + pulse * POINTER_PULSE_ALPHA
	_strum_line.self_modulate.a = STRUM_BASE_ALPHA + pulse * STRUM_PULSE_ALPHA

	var hot_idx: int = _root_note_to_index(root_note)
	if hot_idx != _last_hot_idx:
		_set_trail_alpha(_last_hot_idx, TRAIL_INACTIVE_ALPHA)
		_set_trail_alpha(hot_idx, TRAIL_ACTIVE_ALPHA)
		_last_hot_idx = hot_idx

	# Keep runtime strings available for optional debugging, but hidden by default
	# to preserve the clean ChartPlayer-like look.
	var note_pct: float = 0.0
	if total_notes > 0:
		note_pct = float(processed_note_count) * 100.0 / float(total_notes)
	_runtime_info.text = "BPM %.1f · %d/%d (%.1f%%) · %s" % [bpm, processed_note_count, total_notes, note_pct, _format_clock(song_time)]


func _root_note_to_index(root_note: String) -> int:
	# Map chromatic pitch classes onto 6 visible string trails.
	# This intentionally compresses 12 semitones into 6 lanes via modulo,
	# so deterministic collisions exist (e.g. C# pitch 1 and G pitch 7 -> lane 1).
	if not ROOT_NOTE_PITCH_CLASS.has(root_note):
		return -1
	return int(ROOT_NOTE_PITCH_CLASS[root_note]) % _trail_lines.size()


func _set_trail_alpha(idx: int, alpha: float) -> void:
	if idx < 0 or idx >= _trail_lines.size():
		return
	var c := _trail_lines[idx].self_modulate
	c.a = alpha
	_trail_lines[idx].self_modulate = c


func _format_clock(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	var minutes: int = total / 60
	var secs: int = total % 60
	return "%d:%02d" % [minutes, secs]
