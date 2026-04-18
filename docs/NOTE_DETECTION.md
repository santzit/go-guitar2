# Note Detection — cycfi/Q Pitch Detector

GoGuitar2 detects which guitar string the player is playing in real time
using **cycfi/Q**, a C++20 header-only DSP library.

> **Algorithm note:** The vendored Q headers (`gdextension/vendor/q_lib/`) are
> from the **pre-v1.5** tree, which implements the *Binary Autocorrelation
> Function* (BACF) pitch detector.  The Q project's `master` branch is
> actively developing **v1.5**, which **retires BACF** and introduces the
> new **Hz Pitch Detection system** — a more accurate algorithm with
> integrated onset detection.  Technical details are published in Joel de
> Guzman's article series:
>
> - [Pitch Perfect: Enhanced Pitch Detection Techniques Part 1](https://www.cycfi.com/2024/09/pitch-perfect-enhanced-pitch-detection-techniques-part-1/) (Sept 2024)
> - [Pitch Perfect: Enhanced Pitch Detection Techniques Part 2](https://www.cycfi.com/2024/10/pitch-perfect-enhanced-pitch-detection-techniques-part-2/) (Oct 2024)
> - [Pitch Perfect: Audio to MIDI Part 3](https://www.cycfi.com/2024/10/pitch-perfect-audio-to-midi-part-3/) (Oct 2024)
> - Related open-source project: [cycfi/hz_audio_to_midi](https://github.com/cycfi/hz_audio_to_midi)
>
> When Q v1.5 is stable, `q_pitch_ffi.cpp` and the vendored headers should
> be upgraded to use the new **Hz Pitch Detection** API.

---

## Architecture

```
GDScript  NoteDetection.detect_strings(samples, sr)
    │
    ▼  ClassDB.instantiate("QPitchDetector")
Rust GDExtension  QPitchDetector.detect_strings()
    │
    ▼  extern "C" call
C++20 FFI  q_detect_strings()   ← q_pitch_ffi.cpp
    │
    ├─► cycfi::q::pitch_detector  string 6  E2   82–330 Hz
    ├─► cycfi::q::pitch_detector  string 5  A2  110–440 Hz
    ├─► cycfi::q::pitch_detector  string 4  D3  147–587 Hz
    ├─► cycfi::q::pitch_detector  string 3  G3  196–784 Hz
    ├─► cycfi::q::pitch_detector  string 2  B3  247–988 Hz
    └─► cycfi::q::pitch_detector  string 1  e4  330–1319 Hz
```

---

## How the Pitch Detector Works (pre-v1.5 BACF)

The **pre-v1.5** Q `pitch_detector` (currently vendored) is built on the
*Binary Autocorrelation Function* (BACF).  At a high level:

1. Zero-crossings of the incoming signal are collected by a
   `zero_crossing_collector` which tags each edge with its time position.
2. A *period candidate* is obtained by counting samples between successive
   same-direction zero-crossings.
3. A **bitstream ACF** (`bitstream_acf`) computes the autocorrelation of a
   binary encoding of the signal to confirm the period across multiple cycles.
4. The result is the detected fundamental frequency, or `0` if confidence is
   below the hysteresis threshold.

BACF is **monophonic** — it locks on to one fundamental at a time.
When multiple strings sound simultaneously, each detector still returns one
frequency for its band, but polyphonic content lowers detection confidence.

### Upcoming: Q v1.5 Hz Pitch Detection system

The Q project is actively replacing BACF with the new **Hz Pitch Detection
system** (v1.5, currently in development).  The new approach integrates
onset detection and is described in the "Pitch Perfect" article series
linked in the note at the top of this document.  There is also a dedicated
open-source multichannel audio-to-MIDI project built on the new algorithm:
[cycfi/hz_audio_to_midi](https://github.com/cycfi/hz_audio_to_midi).

Once Q v1.5 is released, `q_pitch_ffi.cpp` and the vendored headers should
be upgraded to use the new Hz Pitch Detection API.

---

## Per-String Detectors

Six `cycfi::q::pitch_detector` instances are created **fresh for every
`detect_strings()` call**, one per string:

| String | Note | Open (Hz) | Fret-24 (Hz) |
|--------|------|-----------|--------------|
| 6 | E2 |  82.41 |  329.63 |
| 5 | A2 | 110.00 |  440.00 |
| 4 | D3 | 146.83 |  587.33 |
| 3 | G3 | 196.00 |  784.00 |
| 2 | B3 | 246.94 |  987.77 |
| 1 | e4 | 329.63 | 1318.51 |

All six detectors receive the **same** mono audio buffer.
Hysteresis is set to **−45 dB** (Q's recommended starting value).

---

## Subharmonic Filter

When a pure tone is fed to all six detectors, lower-band detectors can find
integer-octave subharmonics of a higher-band result:

- A 659 Hz (E5) signal → string 6's detector (82–330 Hz) finds 659/8 = 82 Hz.
- Same signal → string 5's detector (110–440 Hz) finds 659/2 = 330 Hz.

A post-processing pass removes these artifacts before returning results:

> For every pair (lo, hi) of active detections, if  
> `log₂(hi.hz / lo.hz)` is within 0.15 of an integer ≥ 1,  
> the lower detection is suppressed as a subharmonic of the higher.

---

## GDScript API

### `NoteDetection` (scripts/note_detection.gd)

```gdscript
var nd := NoteDetection.new()

# Detect pitches on all 6 strings from a mono PCM buffer.
# Returns Array[Dictionary] of exactly 6 entries.
var result := nd.detect_strings(samples: PackedFloat32Array, sr: int, offset: int = 0)
```

Each dictionary in the returned array:

| Key | Type | Value when active | Value when inactive |
|-----|------|-------------------|---------------------|
| `string_idx` | `int` | 0–5 (0 = low E) | 0–5 |
| `active` | `bool` | `true` | `false` |
| `hz` | `float` | detected frequency | `0.0` |
| `midi` | `int` | MIDI note number | `0` |
| `note` | `String` | e.g. `"A3"` | `""` |
| `fret` | `int` | 0–24 | `-1` |

If `QPitchDetector` is not available (extension not built/loaded), an error
is pushed to the Godot Output panel and an all-inactive result is returned.

### Useful constants

```gdscript
NoteDetection.FFT_WINDOW  # int — recommended buffer size (4096 samples)
NoteDetection.MAX_FRET    # int — highest valid fret (24)
NoteDetection.STRING_LABELS  # Array[String] — human-readable band labels
```

### `QPitchDetector` (Rust GDExtension)

```gdscript
var qpd := QPitchDetector.new()
var raw: Array = qpd.detect_strings(samples: PackedFloat32Array, sample_rate: int)
```

`NoteDetection` wraps this class — use `NoteDetection` in game code.

---

## Source Files

| File | Language | Purpose |
|------|----------|---------|
| `scripts/note_detection.gd` | GDScript | Public API; instantiates QPitchDetector |
| `gdextension/src/q_pitch_detector.rs` | Rust | GDExtension class; calls C FFI |
| `gdextension/src/q_pitch_ffi.cpp` | C++20 | Six Q detectors + subharmonic filter |
| `gdextension/src/q_pitch_ffi.h` | C | FFI struct and function declaration |
| `gdextension/vendor/q_lib/` | C++20 | cycfi/Q headers (header-only) |
| `gdextension/vendor/infra-master/` | C++ | cycfi/infra headers (Q dependency) |

---

## Tests

```bash
# Run all per-string note detection tests (headless, no display needed)
./Godot_v4.4.1-stable_linux.x86_64 --headless --path . \
  --script tests/note-detection/test_note_detection_strings.gd
```

**Expected output: 22/22 passed**

Test coverage:

| Test | What is verified |
|------|-----------------|
| `_test_silence` | Zero-amplitude buffer → all 6 strings inactive |
| `_test_single_e2_open` | 82.41 Hz sine → string 6 active (fret 0, note E2), strings 5–1 inactive |
| `_test_single_e5_high` | 659.26 Hz sine → strings 3/2/1 active, strings 6/5/4 suppressed by subharmonic filter |
| `_test_all_open_strings` | Mixed 6-tone signal → 6 entries returned, all active frets in valid range |
| `_test_scoring_all_hit` | Single E2 detected and expected → score ratio 1.0 |
| `_test_scoring_partial_hit` | E2 detected, all 6 expected → 1 matched |
| `_test_scoring_miss` | Silence, all 6 expected → ratio 0.0 |

---

## Known Limitations

- **BACF is monophonic (pre-v1.5)**: with multiple simultaneous strings, some may not be
  detected. In real gameplay players typically pluck one string at a time, so
  this is rarely an issue. The upcoming Q v1.5 **Hz Pitch Detection system** adds onset
  detection, which will further improve multi-string accuracy.
- **Pure sine subharmonics**: clean sine waves trigger subharmonic detection;
  the post-processing filter removes the false positives. Real guitar
  notes have complex overtones that make this far less common.
- **Detection latency**: Q needs several full periods of the signal to
  establish confidence. At 82 Hz (period ≈ 535 samples at 44100 Hz), a
  4096-sample window (~93 ms) gives Q about 7–8 complete periods — enough
  for reliable detection.
