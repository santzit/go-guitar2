# Godot Audio Bridge — SPSC Ring-Buffer DSP Pipeline

## Overview

`GodotAudioBridge` implements a "Godot block I/O" audio pipeline that routes
guitar / microphone input captured by Godot's `AudioEffectCapture` through the
native RT DSP thread (running `ToneEngine` amp-simulation) and feeds the
processed output to an `AudioStreamGeneratorPlayback` for low-latency monitoring.

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
 ┌─────────────────────────────────────────────────────────┐
 │  RtEngine.push_input_pcm(pcm_bytes)                     │
 │      ↓  godot_in  SPSC ring buffer (rtrb)               │
 │  RT engine thread  ──►  ToneEngine.process_block()      │
 │      ↓  godot_out SPSC ring buffer (rtrb)               │
 │  RtEngine.pop_output_frames(n)  →  PackedVector2Array   │
 └─────────────────────────────────────────────────────────┘
       │
       ▼
 AudioStreamGeneratorPlayback.push_buffer(frames)
 (low-latency monitoring output)
```

This pipeline is fully independent of the CPAL hardware streams.  You can use
it alongside CPAL (for music + effects) or alone (Godot-only audio I/O).

---

## Architecture Details

### Native Side (Rust)

Two dedicated **SPSC ring buffers** are allocated inside `EngineCore::start()`:

| Ring buffer       | Direction                 | Capacity      |
|-------------------|---------------------------|---------------|
| `godot_in`        | GDScript → engine thread  | `GODOT_RB_CAPACITY` = 48 000 f32 (~1 s mono) |
| `godot_out`       | engine thread → GDScript  | `GODOT_RB_CAPACITY` = 48 000 f32             |
The RT engine thread (see `audio_engine_core::engine_thread`) drains
`godot_in` in complete `BLOCK_SIZE`-sample blocks, passes each block through
`ToneEngine::process_block()`, and writes the result to `godot_out`.

Both paths use [`rtrb`](https://docs.rs/rtrb) — a lock-free, wait-free SPSC
ring buffer — ensuring the RT thread is never blocked by the GDScript main
thread and vice-versa.

### Godot Side (GDScript)

The `GodotAudioBridge` node (`scripts/godot_audio_bridge.gd`) ties everything
together:

1. Opens a dedicated `AudioServer` capture bus with an `AudioEffectCapture`.
2. Creates an `AudioStreamGenerator` player for the output.
3. On every `_process()` frame:
   - Drains `AudioEffectCapture` → averages L+R to mono → PCM-16-LE bytes.
   - Calls `RtEngine.push_input_pcm(bytes)` to feed the `godot_in` ring.
   - Calls `RtEngine.pop_output_frames(n)` to drain the `godot_out` ring.
   - Calls `AudioStreamGeneratorPlayback.push_buffer(frames)` to play the
     processed signal.

---

## RtEngine API

### `push_input_pcm(data: PackedByteArray) -> int`

Push mono **PCM-16-LE** bytes into the `godot_in` SPSC ring buffer.

- `data` — mono PCM-16 little-endian (2 bytes per sample).  Typically obtained
  by averaging the L and R channels from `AudioEffectCapture.get_buffer()`.
- Returns the number of f32 samples actually written.  Will be less than
  `data.size() / 2` if the ring buffer is full (i.e., the DSP thread has not
  consumed fast enough).

### `pop_output_frames(max_frames: int) -> PackedVector2Array`

Pop up to `max_frames` ToneEngine-processed stereo frames from the `godot_out`
ring buffer.

- `max_frames` — maximum number of stereo frames to return.  Pass
  `playback.get_frames_available()` to avoid over-filling the generator.
- Returns a `PackedVector2Array` suitable for
  `AudioStreamGeneratorPlayback.push_buffer()`.
- The engine produces **mono** output; each frame has L = R (identical channels).

### `input_rb_free_slots() -> int`

Returns the number of f32 sample slots still available in the `godot_in` ring.

### `output_rb_available() -> int`

Returns the number of processed f32 samples ready to pop from `godot_out`.

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
| `input_pushed` | `sample_count: int` | Emitted when DI samples are written to the native ring buffer. |
| `output_pushed` | `frame_count: int` | Emitted when processed frames are pushed to the generator. |

### Methods

| Method | Description |
|--------|-------------|
| `setup(rt: Object)` | Assign the `RtEngine` instance before `start()`. |
| `start() -> bool` | Open capture bus and generator.  Returns `true` on success. |
| `stop()` | Close capture bus and generator. |
| `tick()` | Drive one frame: push DI input, pull processed output. |
| `is_active() -> bool` | Returns `true` when the pipeline is running. |

---

## Quick Start

```gdscript
extends Node

var rt     : RtEngine
var bridge : GodotAudioBridge

func _ready() -> void:
    rt = RtEngine.new()
    rt.start(1, 48000)          # mono, 48 kHz

    bridge = GodotAudioBridge.new()
    bridge.noise_gate = 0.01    # light noise gate
    add_child(bridge)
    bridge.setup(rt)
    bridge.start()

    # Connect to output signal (optional)
    bridge.output_pushed.connect(_on_output_pushed)

func _on_output_pushed(n: int) -> void:
    print("Pushed %d processed frames" % n)

func _exit_tree() -> void:
    bridge.stop()
    rt.stop()
```

---

## Integration with PitchDetector

The `GodotAudioBridge` pushes raw DI bytes into the native DSP ring buffer.
You can also connect those same bytes to the `PitchDetector` Godot class for
tuning/note detection:

```gdscript
extends Node

var rt     : RtEngine
var bridge : GodotAudioBridge
var pd     : PitchDetector

func _ready() -> void:
    rt = RtEngine.new()
    rt.start(1, 48000)

    pd = PitchDetector.new()
    pd.start(48000)

    bridge = GodotAudioBridge.new()
    add_child(bridge)
    bridge.setup(rt)
    bridge.start()

func _process(_delta: float) -> void:
    # Use InputAudioManager or AudioInput to get raw PCM bytes.
    var bytes : PackedByteArray = AudioInput.get_last_pcm_bytes()

    # Push to DSP thread (ToneEngine monitoring output).
    rt.push_input_pcm(bytes)

    # Also feed the pitch detector directly.
    var events := pd.process_samples(bytes)
    for ev in events:
        print("String %d  %.1f Hz  (%.2f)" % [ev["string"], ev["frequency"], ev["periodicity"]])

    # Pull processed output to AudioStreamGeneratorPlayback.
    bridge.tick()
```

---

## References

- [`rtrb`](https://docs.rs/rtrb) — lock-free SPSC ring buffer used internally
- [`cycfi/q`](https://github.com/cycfi/q) — C++ DSP library (pitch detection)
- `src/audio_engine_core.rs` — ring buffer allocation and engine thread
- `src/rt_engine.rs` — `RtEngine` Godot class (`push_input_pcm`, `pop_output_frames`)
- `src/tone_engine.rs` — `ToneEngine` DSP (currently passthrough mock)
- `scripts/godot_audio_bridge.gd` — Godot-side bridge node
