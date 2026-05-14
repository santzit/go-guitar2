extends RefCounted
class_name EventLifecycle

var _time_offset: float = 0.0
var _duration: float = 0.0
var _sustain_min_secs: float = 0.0
var _allow_sustain: bool = false

var _has_sustain: bool = false
var _crossed: bool = false
var _finished: bool = false


func setup(
		p_time_offset: float,
		p_duration: float,
		p_sustain_min_secs: float,
		p_allow_sustain: bool = true
) -> void:
	_time_offset = p_time_offset
	_duration = maxf(p_duration, 0.0)
	_sustain_min_secs = maxf(p_sustain_min_secs, 0.0)
	_allow_sustain = p_allow_sustain
	_has_sustain = _allow_sustain and _duration >= _sustain_min_secs
	_crossed = false
	_finished = false


func advance(song_time: float) -> Dictionary:
	var crossed_now := false
	var finished_now := false

	if not _crossed and song_time >= _time_offset:
		_crossed = true
		crossed_now = true

	if not _finished and song_time >= _end_time():
		_finished = true
		finished_now = true

	return {
		"crossed_now": crossed_now,
		"is_crossed": _crossed,
		"has_sustain": _has_sustain,
		"remaining_secs": maxf(_end_time() - song_time, 0.0),
		"finished_now": finished_now,
		"is_finished": _finished,
	}


func _end_time() -> float:
	return _time_offset + (_duration if _has_sustain else 0.0)
