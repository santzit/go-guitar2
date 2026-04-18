# Rocksmith2014.rs API (High-Level)

GoGuitar2 uses pure Rust crates from `santzit/Rocksmith2014.rs`:

- `rocksmith2014-psarc`
- `rocksmith2014-sng`

No .NET/CLR bridge is required.

## Main flow used in this repo

1. Open `.psarc` container.
2. Locate arrangement SNG data and audio assets (WEM).
3. Decode/decrypt SNG.
4. Read note/chord/timing data for the selected difficulty level.
5. Convert to game dictionaries consumed by Godot scripts.

## Structures used by gameplay

From `RocksmithBridge` output (GDScript dictionaries/arrays):

- Note entries:
  - `time: float`
  - `fret: int`
  - `string: int`
  - `duration: float`
- SNG info:
  - `difficulty`
  - `start_time`
  - `capo`
  - `tuning` (per-string semitone offsets)

## Reading timing, notes, chords, levels

- Timing comes from note/chord timestamps in SNG.
- Chords are represented by grouping notes with near-identical timestamps.
- Sustains are represented with `duration`.
- Difficulty is selected before loading (`set_difficulty`) and reflected in parsed note density/content.

## GoGuitar2 integration points

- Rust: `gdextension/src/rsapi.rs`, `gdextension/src/goguitar_bridge.rs`
- Godot wrapper: `scripts/goguitar_bridge.gd`
- Gameplay consumer: `scripts/music_play.gd`

---

## Live Note Detection — cycfi/Q (QPitchDetector)

Guitar string note detection uses **cycfi/Q** (`v1.5-dev`, header-only C++20),
compiled into the Rust GDExtension and exposed as the `QPitchDetector` class.

### Architecture

```
GDScript (NoteDetection.detect_strings)
  └─► QPitchDetector.detect_strings()   [Godot GDExtension class — Rust]
        └─► q_detect_strings()          [C FFI — q_pitch_ffi.cpp]
              └─► cycfi::q::pitch_detector × 6   [C++20 BACF algorithm]
```

### Algorithm

- **BACF** (Binary Autocorrelation Function) — Q's pitch detection method.
- Six independent `q::pitch_detector` instances, one per guitar string,
  each scoped to its open-string … fret-24 frequency band.
- Samples are fed sequentially per string, then the detected frequency is
  read after the full buffer is consumed.
- Hysteresis: **−45 dB** (Q's recommended default).

### Vendored dependencies

| Library | Location | Notes |
|---------|----------|-------|
| `cycfi/q` | `gdextension/vendor/q_lib/` | Header-only C++20 |
| `cycfi/infra` | `gdextension/vendor/infra-master/` | Q's companion utility lib |

### QPitchDetector GDScript API

```gdscript
var qpd := QPitchDetector.new()
var result := qpd.detect_strings(samples: PackedFloat32Array, sample_rate: int)
# Returns Array of 6 Dictionaries:
# { string_idx, active, hz, midi, note, fret }
```

### NoteDetection.detect_strings (GDScript wrapper)

`NoteDetection.detect_strings(samples, sr, offset)` delegates entirely to
`QPitchDetector`. No GDScript DFT fallback — Q is required.
