extends Control
## note_timeline.gd — Top-HUD song overview bar.
##
## Draws a full-width horizontal strip containing:
##   • A dark background bar
##   • One orange bar per note (X = time / duration, width = sustain width or min 2 px)
##   • A white vertical playhead at the current song time

const BAR_BG_COLOR     := Color(0.12, 0.12, 0.12, 0.88)
const NOTE_COLOR       := Color(1.0,  0.65, 0.0,  0.90)   # amber / orange
const PLAYHEAD_COLOR   := Color(1.0,  1.0,  1.0,  1.0)
const NOTE_MIN_PX      : float = 2.0   # minimum note bar width in pixels
const NOTE_PADDING_PX  : float = 2.0   # vertical inset inside the bar

var _notes          : Array  = []
var _total_duration : float  = 0.0
var _song_time      : float  = 0.0


## Called once when the song is loaded.
## notes         – same Array[Dictionary] used by music_play.gd (keys: time, duration)
## total_duration – total song length in seconds (from AudioStream.get_length or last note)
func setup(notes: Array, total_duration: float) -> void:
	_notes          = notes
	_total_duration = total_duration
	queue_redraw()


## Called every frame from music_play._process().
func update_time(song_time: float) -> void:
	_song_time = song_time
	queue_redraw()


func _draw() -> void:
	var w : float = size.x
	var h : float = size.y

	# Background
	draw_rect(Rect2(0.0, 0.0, w, h), BAR_BG_COLOR)

	if _total_duration <= 0.0 or _notes.is_empty() or w <= 0.0:
		return

	var inv_dur : float = w / _total_duration

	# Note bars
	for note in _notes:
		var t   : float = float(note.get("time",     0.0))
		var dur : float = float(note.get("duration", 0.0))
		var nx  : float = t * inv_dur
		var nw  : float = maxf(dur * inv_dur, NOTE_MIN_PX)
		draw_rect(
			Rect2(nx, NOTE_PADDING_PX, nw, h - NOTE_PADDING_PX * 2.0),
			NOTE_COLOR
		)

	# Playhead
	var px : float = _song_time * inv_dur
	draw_line(Vector2(px, 0.0), Vector2(px, h), PLAYHEAD_COLOR, 2.0)
