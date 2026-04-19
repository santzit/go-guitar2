# Q FFI — Rust Bindings for cycfi/q Pitch Detection

## Overview

The `cycfi/q` library is a header-only C++ DSP library providing high-quality
monophonic pitch detection using zero-crossing analysis and autocorrelation.

This integration exposes Q's `pitch_detector` to Godot via a three-layer stack:

```
GDScript
  └─ PitchDetector  (Godot GDExtension class — src/pitch_detector.rs)
       └─ GuitarPitchDetector  (safe Rust wrapper — src/pitch_detector.rs)
            └─ StringDetector × 6  (unsafe FFI calls — src/q_ffi.rs)
                 └─ q_bridge.cpp  (C++ wrapper — q_bridge/)
                      └─ cycfi::q::pitch_detector  (header-only C++)
```

---

## Guitar String Frequency Ranges — Standard E Tuning

Each of the six strings gets its own `pitch_detector` instance covering the
fundamental frequency range from the open string to the 24th fret:

| String | Note    | Open Hz  | 24th fret Hz | Detector range (Hz) |
|--------|---------|----------|--------------|---------------------|
|   6    | E2 (Low E) | 82.4  | 329.6        |  73.4 – 350.0       |
|   5    | A2      | 110.0    | 440.0        |  98.0 – 470.0       |
|   4    | D3      | 146.8    | 587.3        | 130.8 – 620.0       |
|   3    | G3      | 196.0    | 784.0        | 174.6 – 830.0       |
|   2    | B3      | 246.9    | 987.8        | 220.0 – 1050.0      |
|   1    | E4 (High e) | 329.6 | 1318.5     | 293.7 – 1400.0      |

Ranges include a small safety margin below the open string and above the 24th
fret to account for slight pitch drift and bends.

When multiple detectors fire simultaneously, the one with the highest
**periodicity** (confidence score) wins.  Results below `MIN_PERIODICITY = 0.6`
are discarded.

---

## Setup

### 1. Initialise Git Submodules

The Q and infra header trees are tracked as Git submodules.  After cloning the
repository run:

```bash
git submodule update --init --recursive
```

This populates:
- `gdextension/extern/q/`     — https://github.com/cycfi/q
- `gdextension/extern/infra/` — https://github.com/cycfi/infra (Q dependency)

### 2. Build the GDExtension

```bash
cd gdextension
cargo build --release
cp target/release/libgodot_goguitar_rs.so bin/
```

When the submodules are present `build.rs` automatically compiles
`q_bridge/q_bridge.cpp` (C++17) via the `cc` crate and emits
`cargo:rustc-cfg=q_available`, which enables the `q_ffi` and `pitch_detector`
modules.

> **Note:** Without the submodules the build succeeds but the `PitchDetector`
> Godot class will not be registered.  The build log will print a warning.

---

## Godot API — `PitchDetector`

### Lifecycle

```gdscript
var pd := PitchDetector.new()
pd.start(48000)     # allocate 6 Q detectors at 48 kHz
# … feed samples …
pd.stop()           # free all detectors
```

### `start(sample_rate: int) -> bool`

Allocate all six pitch detectors.  Returns `true` on success.  Safe to call
again to restart with a different sample rate.

### `stop()`

Free all detectors.

### `is_running() -> bool`

Returns `true` while detectors are allocated.

### `process_samples(data: PackedByteArray) -> Array[Dictionary]`

Feed a block of **mono PCM-16-LE** bytes at the sample rate passed to `start()`.

Returns an array of dictionaries — one per detection event:

```gdscript
{ "string": int,       # guitar string, 1 (high e) – 6 (low E)
  "frequency": float,  # detected fundamental in Hz
  "periodicity": float # confidence [0.0 – 1.0] }
```

### `get_last_result() -> Dictionary`

Returns the most recent detection (may be stale if no pitch was detected):

```gdscript
{ "detected":    bool,
  "string":      int,   # 1–6
  "frequency":   float,
  "periodicity": float }
```

### `get_string_ranges() -> Array[Dictionary]`  *(static)*

Returns the six string configuration entries:

```gdscript
{ "string": int, "name": String, "min_hz": float, "max_hz": float }
```

### `get_min_periodicity() -> float`  *(static)*

Returns the minimum confidence threshold (`0.6`).

---

## Integration with RtEngine

Connect the DI input ring buffer to `PitchDetector.process_samples()`:

```gdscript
extends Node

var rt  : RtEngine
var pd  : PitchDetector

func _ready() -> void:
    rt = RtEngine.new()
    rt.start(1, 48000)            # 1 ch mono DI input
    rt.start_streams("default", "default")

    pd = PitchDetector.new()
    pd.start(48000)

func _process(_delta: float) -> void:
    # Pop raw bytes from the DI input ring buffer (your implementation)
    var bytes := rt.pop_input_pcm()
    pd.process_samples(bytes)

    var r := pd.get_last_result()
    if r["detected"]:
        print("String %d  %.2f Hz  (confidence %.2f)" % [
            r["string"], r["frequency"], r["periodicity"]])
```

---

## C++ Bridge API (`q_bridge/q_bridge.h`)

| Function | Description |
|----------|-------------|
| `q_pd_create(min_hz, max_hz, sr, hysteresis_db)` | Allocate a detector |
| `q_pd_destroy(pd)` | Free a detector |
| `q_pd_process(pd, sample)` | Feed one f32 sample; returns `true` when ready |
| `q_pd_get_frequency(pd)` | Latest frequency in Hz (also caches periodicity) |
| `q_pd_get_periodicity(pd)` | Latest confidence in [0, 1] |

---

## References

- [cycfi/q](https://github.com/cycfi/q) — Q DSP library
- [cycfi/infra](https://github.com/cycfi/infra) — Q infrastructure headers
- [Q pitch detector docs](https://cycfi.github.io/q/docs/reference/pitch_detector)
