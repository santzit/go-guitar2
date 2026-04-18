extends RefCounted
class_name NoteDetection

const _MAX_FRET_SENTINEL: int = 999

# ═══════ Per-string audio pitch detection (cycfi/Q via QPitchDetector) ════════

## Audio window length in samples passed to Q per detection call.
## At 44 100 Hz → ~93 ms, enough for Q's BACF to complete multiple periods
## even for low E (82 Hz, period ≈ 535 samples).
const FFT_WINDOW: int = 4096

## Highest playable fret on a standard 24-fret guitar neck.
const MAX_FRET: int = 24

## Human-readable label per string for display.
const STRING_LABELS: Array[String] = [
"str 6  E2   82–330 Hz",
"str 5  A2  110–440 Hz",
"str 4  D3  147–587 Hz",
"str 3  G3  196–784 Hz",
"str 2  B3  247–988 Hz",
"str 1  e4  330–1319 Hz",
]

# Cached QPitchDetector instance — created once in _init().
var _q_detector: Object = null

func _init() -> void:
if ClassDB.class_exists("QPitchDetector"):
_q_detector = ClassDB.instantiate("QPitchDetector")
else:
push_error(
"NoteDetection: QPitchDetector GDExtension class not found. " +
"Build the extension and copy the binary to gdextension/bin/."
)


## Detect the pitch on each of the 6 guitar strings simultaneously using
## the cycfi/Q BACF pitch detector (via the QPitchDetector GDExtension class).
##
## samples  – mono PCM-float32 audio buffer (at least FFT_WINDOW samples).
## sr       – sample rate in Hz (typically 44100).
## offset   – first sample index to use within `samples` (default 0).
##
## Returns an Array[Dictionary] of exactly 6 entries (index 0 = string 6 low E,
## index 5 = string 1 high e).  Each entry:
##   { "string_idx": int,   – 0..5
##     "active":     bool,  – true if a pitch was detected in this string's band
##     "hz":         float, – detected frequency in Hz (0.0 when inactive)
##     "midi":       int,   – MIDI note number            (0   when inactive)
##     "note":       String,– e.g. "A3"                   (""  when inactive)
##     "fret":       int }  – 0..24                       (-1  when inactive)
func detect_strings(
samples: PackedFloat32Array, sr: int, offset: int = 0) -> Array[Dictionary]:
if _q_detector == null:
push_error("NoteDetection: QPitchDetector not available — cannot detect strings.")
return _silent_result()

var buf: PackedFloat32Array
if offset == 0:
buf = samples
else:
buf = samples.slice(offset)

var raw: Array = _q_detector.detect_strings(buf, sr)
var result: Array[Dictionary] = []
for entry in raw:
result.append(entry as Dictionary)
return result


## Returns an all-inactive baseline result (6 entries, one per string).
func _silent_result() -> Array[Dictionary]:
var r: Array[Dictionary] = []
for s in 6:
r.append({"string_idx": s, "active": false, "hz": 0.0, "midi": 0, "note": "", "fret": -1})
return r


# ═══════ Chart/event helpers (independent of audio detection) ═════════════════

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
