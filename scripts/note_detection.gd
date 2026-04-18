extends RefCounted
class_name NoteDetection

const _MAX_FRET_SENTINEL: int = 999

# ═══════ Per-string audio pitch detection ════════════════════════════════════

## DFT window length (samples). At 44 100 Hz → ~93 ms, ~10.8 Hz/bin resolution.
const FFT_WINDOW: int = 4096
## Minimum RMS amplitude below which a window is treated as silence.
const MIN_RMS: float = 0.01
## A string's peak must be at least this fraction of the loudest spectral bin
## in the full guitar range to count as "active".
const STRING_ACTIVE_THRESHOLD: float = 0.15
## Highest playable fret on a standard 24-fret guitar neck.
const MAX_FRET: int = 24

## Open-string MIDI note numbers in standard tuning.
## Index 0 = string 6 (low E2 = MIDI 40); index 5 = string 1 (high e4 = MIDI 64).
const OPEN_STRING_MIDI: Array[int] = [40, 45, 50, 55, 59, 64]
## Open-string frequencies (Hz).
const OPEN_STRING_HZ: Array[float] = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
## Upper frequency for each string (Hz) = frequency at fret 24 (~2 octaves above open).
const STRING_FREQ_MAX: Array[float] = [329.63, 440.00, 587.33, 784.00, 987.77, 1318.51]
## Human-readable label per string for display.
const STRING_LABELS: Array[String] = [
	"str 6  E2   82–330 Hz",
	"str 5  A2  110–440 Hz",
	"str 4  D3  147–587 Hz",
	"str 3  G3  196–784 Hz",
	"str 2  B3  247–988 Hz",
	"str 1  e4  330–1319 Hz",
]
## Chromatic note names (index 0 = C).
const NOTE_NAMES: Array[String] = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]


## Detect the note being played on each of the 6 guitar strings simultaneously.
##
## samples  – mono PCM-float32 audio buffer.
## sr       – sample rate in Hz (typically 44100).
## offset   – first sample index to use within `samples` (default 0).
##
## Returns an Array[Dictionary] of exactly 6 entries (index 0 = string 6 low E,
## index 5 = string 1 high e).  Each entry:
##   { "string_idx": int,   – 0..5
##     "active":     bool,  – true if a note was detected in this string's band
##     "hz":         float, – detected frequency (0.0 when inactive)
##     "midi":       int,   – MIDI note number   (0   when inactive)
##     "note":       String,– e.g. "A3"          (""  when inactive)
##     "fret":       int }  – 0..24              (-1  when inactive)
func detect_strings(
		samples: PackedFloat32Array, sr: int, offset: int = 0) -> Array[Dictionary]:
	var n := mini(FFT_WINDOW, samples.size() - offset)
	if n < 256 or _audio_rms(samples, offset, n) < MIN_RMS:
		return _silent_result()

	# Apply Hann window to reduce spectral leakage.
	var windowed := PackedFloat32Array()
	windowed.resize(n)
	for i in n:
		windowed[i] = samples[offset + i] * (0.5 * (1.0 - cos(TAU * i / (n - 1))))

	# Compute magnitude spectrum for the full guitar range in one DFT pass.
	var min_bin := maxi(1, int(floor(OPEN_STRING_HZ[0] * n / sr)))
	var max_bin := mini(n / 2 - 1, int(ceil(STRING_FREQ_MAX[5] * n / sr)))
	var mags    := _dft_magnitude(windowed, min_bin, max_bin, n)

	# Global maximum magnitude used for relative per-string thresholding.
	var global_max := 0.0
	for m in mags:
		if m > global_max:
			global_max = m
	if global_max <= 0.0:
		return _silent_result()

	var result: Array[Dictionary] = []
	for s in 6:
		result.append(_detect_one_string(mags, s, min_bin, sr, n, global_max))
	return result


## Build the "all inactive" baseline result (6 entries, one per string).
func _silent_result() -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for s in 6:
		r.append({
			"string_idx": s, "active": false,
			"hz": 0.0, "midi": 0, "note": "", "fret": -1,
		})
	return r


## Detect the dominant pitch for string `s` within its frequency band.
## Uses parabolic interpolation for sub-bin frequency accuracy.
func _detect_one_string(
		mags:       Array[float],
		s:          int,
		min_bin:    int,
		sr:         int,
		n:          int,
		global_max: float) -> Dictionary:
	var silent := {"string_idx": s, "active": false, "hz": 0.0, "midi": 0, "note": "", "fret": -1}
	var bin_hz  := float(sr) / float(n)
	# Map this string's Hz range to indices within the `mags` array.
	var lo_idx  := maxi(0,             int(floor(OPEN_STRING_HZ[s]   / bin_hz)) - min_bin)
	var hi_idx  := mini(mags.size()-1, int(ceil( STRING_FREQ_MAX[s]  / bin_hz)) - min_bin)
	if lo_idx >= hi_idx:
		return silent

	# Find the strongest spectral bin in this string's band.
	var best_mag := 0.0
	var best_idx := lo_idx
	for b in range(lo_idx, hi_idx + 1):
		if mags[b] > best_mag:
			best_mag = mags[b]
			best_idx = b

	if best_mag < global_max * STRING_ACTIVE_THRESHOLD:
		return silent

	# Parabolic interpolation around the peak bin for sub-bin accuracy.
	var precise_idx := float(best_idx)
	if best_idx > 0 and best_idx < mags.size() - 1:
		var alpha := mags[best_idx - 1]
		var beta  := mags[best_idx]
		var gamma := mags[best_idx + 1]
		var denom := alpha - 2.0 * beta + gamma
		if abs(denom) > 1e-12:
			precise_idx += 0.5 * (alpha - gamma) / denom

	var hz   := (precise_idx + float(min_bin)) * bin_hz
	var midi := roundi(69.0 + 12.0 * log(hz / 440.0) / log(2.0))
	var fret := clampi(midi - OPEN_STRING_MIDI[s], 0, MAX_FRET)
	return {
		"string_idx": s,
		"active":     true,
		"hz":         hz,
		"midi":       midi,
		"note":       _midi_note_name(midi),
		"fret":       fret,
	}


## Root-mean-square amplitude over `n` samples starting at `offset`.
func _audio_rms(samples: PackedFloat32Array, offset: int, n: int) -> float:
	var sum := 0.0
	for i in n:
		var v: float = samples[offset + i]
		sum += v * v
	return sqrt(sum / float(n))


## Hann-windowed DFT magnitude for bins [min_bin, max_bin] using the
## unit-circle rotation method (2 trig calls per bin, 4 multiply-adds per sample).
func _dft_magnitude(
		windowed: PackedFloat32Array,
		min_bin:  int,
		max_bin:  int,
		n:        int) -> Array[float]:
	var mags: Array[float] = []
	mags.resize(max_bin - min_bin + 1)
	for k_idx in mags.size():
		var k     := min_bin + k_idx
		var theta := -TAU * k / float(n)
		var cos_t := cos(theta)
		var sin_t := sin(theta)
		var re    := 0.0
		var im    := 0.0
		var c     := 1.0   # cos(theta * 0) = 1
		var s     := 0.0   # sin(theta * 0) = 0
		for i in n:
			re += windowed[i] * c
			im += windowed[i] * s
			# Rotate (c, s) by theta: equivalent to multiplying by e^(i*theta).
			var c2 := c * cos_t - s * sin_t
			s = c * sin_t + s * cos_t
			c = c2
		mags[k_idx] = sqrt(re * re + im * im)
	return mags


## Note name and octave for a MIDI note number (e.g. MIDI 57 → "A3").
func _midi_note_name(midi: int) -> String:
	return NOTE_NAMES[midi % 12] + str(midi / 12 - 1)


func build_play_events(
	src_notes: Array,
	fret_count: int,
	chord_group_threshold: float,
	get_note_name: Callable,
	last_chord_sig: String
) -> Dictionary:
	var events: Array = []
	var note_index: int = 0
	var next_chord_sig: String = last_chord_sig
	while note_index < src_notes.size():
		var nd : Dictionary = src_notes[note_index]
		var t0 : float = float(nd.get("time", 0.0))
		var group: Array = [nd]
		var group_end_index: int = note_index + 1
		while group_end_index < src_notes.size() \
				and absf(float(src_notes[group_end_index].get("time", 0.0)) - t0) < chord_group_threshold:
			group.append(src_notes[group_end_index])
			group_end_index += 1

		var valid_notes: Array = []
		var max_duration: float = 0.0
		var min_fret: int = _MAX_FRET_SENTINEL
		for gn in group:
			var f: int = int(gn.get("fret", 0))
			var s: int = int(gn.get("string", 0))
			if f < 1 or f > fret_count or s < 0 or s > 5:
				continue
			var dur: float = maxf(float(gn.get("duration", 0.25)), 0.0)
			valid_notes.append({"fret": f, "string": s, "duration": dur})
			max_duration = maxf(max_duration, dur)
			min_fret = mini(min_fret, f)

		if not valid_notes.is_empty():
			var event_kind: String = "single" if valid_notes.size() == 1 else "chord"
			var hand_start: int = maxi(min_fret - 1, 1)
			var hand_end: int = mini(hand_start + 3, fret_count)
			var chord_name: String = ""
			var show_details: bool = false
			if event_kind == "chord":
				var sig := chord_signature(valid_notes)
				show_details = (sig != next_chord_sig)
				next_chord_sig = sig
				var root_f: int = int(valid_notes[0].get("fret", 0))
				var root_s: int = int(valid_notes[0].get("string", 0))
				chord_name = String(get_note_name.call(root_f, root_s))

			events.append({
				"time_start": t0,
				"time_end": t0 + max_duration,
				"hand_fret_start": hand_start,
				"hand_fret_end": hand_end,
				"notes": valid_notes,
				"kind": event_kind,
				"chord_name": chord_name,
				"show_details": show_details
			})

		note_index = group_end_index

	return {
		"events": events,
		"last_chord_sig": next_chord_sig
	}


func chord_signature(notes: Array) -> String:
	var parts : Array[String] = []
	for n in notes:
		parts.append("%d:%d" % [int(n.get("fret", 0)), int(n.get("string", 0))])
	parts.sort()
	return ",".join(parts)


func sort_notes_by_fret(notes: Array) -> Array:
	var sorted : Array = notes.duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("fret", -1)) < int(b.get("fret", -1)))
	return sorted
