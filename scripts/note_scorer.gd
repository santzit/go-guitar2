extends RefCounted
class_name NoteScorer

## note_scorer.gd — Rocksmith-like per-frame scoring engine.
##
## Architecture (per @clebersantz comment):
##   - Notes and Chords are kept in SEPARATE sorted arrays with independent
##     cursors, matching the Rocksmith data model (Notes list + Chords list).
##   - Each frame, the scorer builds an ExpectedFrettingSnapshot from all
##     events active in [now - EARLY_WINDOW, now + LATE_WINDOW].
##   - When an event's late window expires, it is evaluated against the
##     rolling DetectionResult history to produce HIT / PARTIAL / MISS.
##   - Consumers feed pitch detections via add_detection(); the scorer
##     retains them for HISTORY_SECS before pruning.
##
## String index convention (matching music_play.gd / SNG data):
##   0-based: 0 = low E (String 6 / E2), 5 = high e (String 1 / E4)
##
## PitchDetector GDExtension returns 1-based string numbers:
##   1 = high e (String 1), 6 = low E (String 6)
## Conversion: idx_0based = 6 - string_num_1based

## ── Timing windows ───────────────────────────────────────────────────────────

## How early (before t0) a detection is accepted toward the event.
const EARLY_WINDOW : float = 0.100   # 100 ms

## How late (after t0) a detection is accepted toward the event.
const LATE_WINDOW  : float = 0.150   # 150 ms

## How long detections are kept before being pruned from history.
const HISTORY_SECS : float = LATE_WINDOW + 0.050   # ~200 ms

## ── Score result labels ───────────────────────────────────────────────────────

const RESULT_HIT     : String = "HIT"
const RESULT_PARTIAL : String = "PARTIAL"
const RESULT_MISS    : String = "MISS"

## ── Public score counters ─────────────────────────────────────────────────────

var hits   : int = 0
var misses : int = 0
var total  : int = 0

## Emitted for every scored event.
## ev     — the event Dictionary from _build_play_events()
## result — "HIT", "PARTIAL", or "MISS"
signal note_scored(ev: Dictionary, result: String)

## ── Internal state ────────────────────────────────────────────────────────────

## Single-note events (kind == "single"), sorted by time_start ascending.
var _note_events  : Array = []
## Chord events (kind == "chord"), sorted by time_start ascending.
var _chord_events : Array = []

## Independent cursors for efficient time-based advance.
var _note_cursor  : int = 0
var _chord_cursor : int = 0

## Rolling detection history.
## Each entry: { "time": float, "string": int (1-6), "frequency": float, "periodicity": float }
## Entries are appended chronologically and pruned from the front when stale.
var _detection_history : Array = []


# ── Public API ────────────────────────────────────────────────────────────────

## Initialise the scorer from the unified event list produced by
## music_play._build_play_events().  Events must be sorted by time_start.
func setup(events: Array) -> void:
	_note_events  = []
	_chord_events = []
	_note_cursor  = 0
	_chord_cursor = 0
	_detection_history = []
	hits   = 0
	misses = 0
	total  = 0
	for ev in events:
		if ev.get("kind", "") == "single":
			_note_events.append(ev)
		else:
			_chord_events.append(ev)


## Record one pitch-detection result from the PitchDetector GDExtension.
##
## song_time   — current audio clock in seconds
## string_num  — 1-based string number (1 = high e, 6 = low E)
## frequency   — detected fundamental in Hz
## periodicity — confidence [0.0, 1.0]
func add_detection(
		song_time: float,
		string_num: int,
		frequency: float,
		periodicity: float
) -> void:
	_detection_history.append({
		"time":        song_time,
		"string":      string_num,
		"frequency":   frequency,
		"periodicity": periodicity,
	})


## Advance the scorer to the given song clock.
##
## Call once per frame (from _process).  This:
##   1. Prunes detection history entries older than HISTORY_SECS.
##   2. Scores any single-note events whose late window has expired.
##   3. Scores any chord events whose late window has expired.
func tick(song_time: float) -> void:
	# ── Prune stale detection history ────────────────────────────────────────
	var cutoff : float = song_time - HISTORY_SECS
	var trim   : int   = 0
	while trim < _detection_history.size() \
			and float(_detection_history[trim].get("time", 0.0)) < cutoff:
		trim += 1
	if trim > 0:
		_detection_history = _detection_history.slice(trim)

	# ── Score single-note events ──────────────────────────────────────────────
	while _note_cursor < _note_events.size():
		var ev : Dictionary = _note_events[_note_cursor]
		if float(ev.get("time_start", 0.0)) + LATE_WINDOW > song_time:
			break
		_score_event(ev)
		_note_cursor += 1

	# ── Score chord events ────────────────────────────────────────────────────
	while _chord_cursor < _chord_events.size():
		var ev : Dictionary = _chord_events[_chord_cursor]
		if float(ev.get("time_start", 0.0)) + LATE_WINDOW > song_time:
			break
		_score_event(ev)
		_chord_cursor += 1


## Build an ExpectedFrettingSnapshot from the active-window events at now.
##
## Returns a Dictionary:
##   {
##     "time": float,
##     "expected_strings": Array[int],   # [0..5]: fret, or -1 = silent
##     "source_note_times": Array[float] # timestamps of contributing events
##   }
func get_active_snapshot(song_time: float) -> Dictionary:
	var expected : Array[int]   = [-1, -1, -1, -1, -1, -1]
	var sources  : Array[float] = []

	var t_early : float = song_time - EARLY_WINDOW
	var t_late  : float = song_time + LATE_WINDOW

	# Scan note events near the active window.
	var note_idx : int = maxi(0, _note_cursor - 1)
	while note_idx < _note_events.size():
		var ev : Dictionary = _note_events[note_idx]
		var t0 : float = float(ev.get("time_start", 0.0))
		if t0 > t_late:
			break
		if t0 >= t_early:
			_apply_event_to_snapshot(ev, expected, sources)
		note_idx += 1

	# Scan chord events near the active window.
	var chord_idx : int = maxi(0, _chord_cursor - 1)
	while chord_idx < _chord_events.size():
		var ev : Dictionary = _chord_events[chord_idx]
		var t0 : float = float(ev.get("time_start", 0.0))
		if t0 > t_late:
			break
		if t0 >= t_early:
			_apply_event_to_snapshot(ev, expected, sources)
		chord_idx += 1

	return {
		"time":              song_time,
		"expected_strings":  expected,
		"source_note_times": sources,
	}


## Returns the current accumulated score.
## Keys: "hits" (int), "misses" (int), "total" (int), "pct" (float 0–100).
func get_score() -> Dictionary:
	var pct : float = (float(hits) / float(total) * 100.0) if total > 0 else 0.0
	return {
		"hits":   hits,
		"misses": misses,
		"total":  total,
		"pct":    pct,
	}


# ── Private helpers ───────────────────────────────────────────────────────────

## Build ExpectedFrettingSnapshot from one event and populate expected[]/sources.
func _apply_event_to_snapshot(
		ev:       Dictionary,
		expected: Array,
		sources:  Array
) -> void:
	var t0    : float = float(ev.get("time_start", 0.0))
	var notes : Array = ev.get("notes", [])
	if notes.is_empty():
		return
	sources.append(t0)
	for n in notes:
		var s_idx : int = int(n.get("string", -1))
		var fret  : int = int(n.get("fret",   -1))
		if s_idx >= 0 and s_idx < 6 and fret >= 0:
			# Later event (scanned in time order) always wins for this string.
			expected[s_idx] = fret


## Evaluate one event against the detection history and emit note_scored.
func _score_event(ev: Dictionary) -> void:
	var t0    : float = float(ev.get("time_start", 0.0))
	var notes : Array = ev.get("notes", [])

	# ── Build expected fretting snapshot ─────────────────────────────────────
	# expected[s_idx] = fret (>= 0) if that string should be played, else -1.
	var expected : Array[int] = [-1, -1, -1, -1, -1, -1]
	for n in notes:
		var s_idx : int = int(n.get("string", -1))
		var fret  : int = int(n.get("fret",   -1))
		if s_idx >= 0 and s_idx < 6 and fret >= 0:
			expected[s_idx] = fret

	# Count how many strings are expected to be played.
	var expected_count : int = 0
	for s in 6:
		if expected[s] >= 0:
			expected_count += 1

	# No scoreable strings (open/muted) — skip silently.
	if expected_count == 0:
		return

	# ── Query detection history in [t0 - EARLY_WINDOW, t0 + LATE_WINDOW] ────
	var t_early : float = t0 - EARLY_WINDOW
	var t_late  : float = t0 + LATE_WINDOW

	# hit_strings[s_idx] = true if a detection for that string was found in window.
	var hit_strings : Array[bool] = [false, false, false, false, false, false]
	for det in _detection_history:
		var det_time : float = float(det.get("time", -1.0))
		if det_time < t_early or det_time > t_late:
			continue
		# PitchDetector: 1-based, 1 = high e (s_idx 5), 6 = low E (s_idx 0).
		var snum  : int = int(det.get("string", 0))
		var s_idx : int = 6 - snum
		if s_idx >= 0 and s_idx < 6:
			hit_strings[s_idx] = true

	# ── Evaluate result ───────────────────────────────────────────────────────
	var matched_count : int = 0
	for s in 6:
		if expected[s] >= 0 and hit_strings[s]:
			matched_count += 1

	total += 1
	var result : String
	if matched_count == expected_count:
		hits   += 1
		result  = RESULT_HIT
	elif matched_count > 0:
		hits   += 1   # partial hit still counts toward hit rate
		result  = RESULT_PARTIAL
	else:
		misses += 1
		result  = RESULT_MISS

	note_scored.emit(ev, result)
