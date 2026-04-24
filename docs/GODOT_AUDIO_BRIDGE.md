# Godot Audio Bridge — C++/Q SPSC Ring-Buffer DSP Pipeline

## Overview

`GodotAudioBridge` implements a "Godot block I/O" audio pipeline that routes
guitar / microphone input captured by Godot's `AudioEffectCapture` through two
**C++ lock-free SPSC ring buffers** and a dedicated **C++ DSP thread** using
cycfi/q signal-conditioning, then feeds the processed output to an
`AudioStreamGeneratorPlayback` for low-latency monitoring.

The SPSC ring buffers and DSP thread live entirely in C++ (`q_dsp_bridge.cpp`)
and use cycfi/q directly — no Rust implementation for the audio I/O path.

```
Guitar / Microphone (hardware)
       │
       ▼ AudioStreamMicrophone (Godot)
 ┌─────────────────────────────────────┐
 │ AudioServer bus  "GodotBridge_In"   │
 │   AudioEffectCapture                │  ← drained every _process() frame
 └─────────────────────────────────────┘
       │  PackedVector2Array (stereo, f32)
       ▼  stereo → mono  →  PCM-16-LE  (noise-gate applied)
 ┌────────────────────────────────────────────────────────────┐
 │  RtEngine.push_input_pcm(pcm_bytes)                        │
 │      ↓  C++ SPSC in_rb  (std::atomic wait-free)           │
 │  C++ DSP thread  ──►  dc_block (cycfi/q)                  │
 │                  ──►  one_pole_lowpass (cycfi/q)           │
 │      ↓  C++ SPSC out_rb (std::atomic wait-free)           │
 │  RtEngine.pop_output_frames(n)  →  PackedVector2Array      │
 └────────────────────────────────────────────────────────────┘
       │
       ▼
 AudioStreamGeneratorPlayback.push_buffer(frames)
 (low-latency monitoring output)
```

This pipeline is fully independent of the CPAL hardware streams.  You can use
it alongside CPAL (for music + effects) or alone (Godot-only audio I/O).

---

## Architecture Details

### C++ / Q Side (`q_dsp_bridge.cpp`)

The DSP bridge lives entirely in C++ and uses cycfi/q directly:

| Component | Description |
|-----------|-------------|
| `SpscRingBuffer` | Lock-free wait-free SPSC ring buffer (Lamport/Vyukov, `std::atomic`) |
| `QDspBridge::in_rb` | Input ring buffer: GDScript → DSP thread |
| `QDspBridge::out_rb` | Output ring buffer: DSP thread → GDScript |
| `QDspBridge::dc` | `cycfi::q::dc_block` — removes DC offset (20 Hz pole) |
| `QDspBridge::lp` | `cycfi::q::one_pole_lowpass` — 12 kHz anti-alias filter |
| `QDspBridge::dsp_thread` | C++ `std::thread` draining `in_rb` in 128-sample blocks |

The ring buffer uses `std::atomic<uint32_t>` head/tail indices with
**relaxed** loads for the owner index and **acquire/release** for the shared
index, making each push or pop a single CAS-free atomic operation.

Each ring buffer capacity is 48 000 f32 samples (~1 s of mono at 48 kHz).

### Rust → C FFI (`q_dsp_ffi.rs`)

Rust calls into the C++ bridge via a plain-C `extern "C"` interface:

```
q_dsp_create(capacity, sample_rate, block_size, start_dsp_thread) → *mut QDspBridge
q_dsp_destroy(bridge)
q_dsp_push_input_i16(bridge, data, count)  → uint32_t  (samples written)
q_dsp_pop_output_f32(bridge, out, max)     → uint32_t  (samples read)
q_dsp_input_free(bridge)                   → uint32_t  (free slots)
q_dsp_output_avail(bridge)                 → uint32_t  (available samples)
```

The bridge pointer is owned by `RtEngine` (behind a `Mutex<*mut QDspBridge>`),
created in `RtEngine::start()` and destroyed in `RtEngine::stop()`.

All four Godot methods are gated on `#[cfg(q_available)]`.  When Q headers are
absent, the methods return `0` / empty array and print a Godot warning.

### Godot Side (GDScript — `scripts/godot_audio_bridge.gd`)

The `GodotAudioBridge` node ties everything together:

1. Opens a dedicated `AudioServer` capture bus with an `AudioEffectCapture`.
2. Creates an `AudioStreamGenerator` player for the output.
3. On every `_process()` frame:
   - Drains `AudioEffectCapture` → averages L+R to mono → PCM-16-LE bytes.
   - Calls `RtEngine.push_input_pcm(bytes)` → C++ SPSC `in_rb`.
   - Calls `RtEngine.pop_output_frames(n)` ← C++ SPSC `out_rb`.
   - Calls `AudioStreamGeneratorPlayback.push_buffer(frames)` to play back.

---

## RtEngine API

### `push_input_pcm(data: PackedByteArray) -> int`

Push mono **PCM-16-LE** bytes into the C++ SPSC input ring buffer.

- `data` — mono PCM-16 little-endian (2 bytes per sample).
- Returns the number of f32 samples actually written.  Will be less than
  `data.size() / 2` if the ring buffer is full.

### `pop_output_frames(max_frames: int) -> PackedVector2Array`

Pop up to `max_frames` Q-processed stereo frames from the C++ SPSC output buffer.

- Returns a `PackedVector2Array` suitable for
  `AudioStreamGeneratorPlayback.push_buffer()`.
- The C++ DSP produces **mono** output; each frame has L = R (both channels identical).

### `input_rb_free_slots() -> int`

Returns the number of f32 sample slots still free in the C++ SPSC input ring.

### `output_rb_available() -> int`

Returns the number of Q-processed f32 samples ready to pop from the C++ SPSC output ring.

---

## GodotAudioBridge Node API

### Exported properties

| Property          | Type      | Default         | Description |
|-------------------|-----------|-----------------|-------------|
| `auto_tick`       | `bool`    | `true`          | If `true`, `tick()` is called automatically in `_process()`. |
| `capture_bus_name`| `StringName` | `"GodotBridge_In"` | Name of the AudioServer capture bus. |
| `mix_rate`        | `float`   | `0.0`           | Generator mix rate in Hz.  `0` = follow `AudioServer.get_mix_rate()`. |
| `noise_gate`      | `float`   | `0.0`           | Absolute amplitude threshold below which samples are silenced. |

### Signals

| Signal | Arguments | Description |
|--------|-----------|-------------|
| `input_pushed` | `sample_count: int` | Emitted when DI samples are written to the C++ ring buffer. |
| `output_pushed` | `frame_count: int` | Emitted when Q-processed frames are pushed to the generator. |

### Methods

| Method | Description |
|--------|-------------|
| `setup(rt: Object)` | Assign the `RtEngine` instance before `start()`. |
| `start() -> bool` | Open capture bus and generator.  Returns `true` on success. |
| `stop()` | Close capture bus and generator. |
| `tick()` | Drive one frame: push DI input, pull Q-processed output. |
| `is_active() -> bool` | Returns `true` when the pipeline is running. |

---

## Quick Start

```gdscript
extends Node

var rt     : RtEngine
var bridge : GodotAudioBridge

func _ready() -> void:
    rt = RtEngine.new()
    rt.start(1, 48000)          # mono, 48 kHz — also creates Q DSP bridge

    bridge = GodotAudioBridge.new()
    bridge.noise_gate = 0.01    # light noise gate
    add_child(bridge)
    bridge.setup(rt)
    bridge.start()

    bridge.output_pushed.connect(_on_output_pushed)

func _on_output_pushed(n: int) -> void:
    print("Pushed %d Q-processed frames" % n)

func _exit_tree() -> void:
    bridge.stop()
    rt.stop()                   # also destroys Q DSP bridge
```

---

## Build Notes

`q_dsp_bridge.cpp` is compiled by `build.rs` using the `cc` crate whenever Q
headers are present (`include/q/` or `extern/q/q_lib/include/`):

```bash
cd gdextension
cargo build --release
```

The build script compiles `q_dsp_bridge.cpp` separately from the prebuilt
`libq_bridge.a` (which contains only the pitch-detector bridge), so the DSP
bridge is always fresh and never requires updating the prebuilt archive.

When Q headers are absent, `q_available` is not set and all four Godot-block-I/O
methods fall back gracefully (return 0 / empty, print a warning).

---

## References

- [`cycfi/q`](https://github.com/cycfi/q) — Q DSP library (dc_block, one_pole_lowpass)
- `q_bridge/q_dsp_bridge.h` — C API for the DSP bridge
- `q_bridge/q_dsp_bridge.cpp` — C++ implementation with SPSC ring buffers + Q DSP
- `src/q_dsp_ffi.rs` — Rust `extern "C"` bindings
- `src/rt_engine.rs` — `RtEngine` Godot class (`push_input_pcm`, `pop_output_frames`)
- `scripts/godot_audio_bridge.gd` — Godot-side bridge node
