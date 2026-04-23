# Audio Input Integration — Godot AudioServer → cycfi/q

## Overview

GoGuitar2 captures guitar or microphone input using Godot's built-in
`AudioEffectCapture` API and routes the raw PCM stream to the **cycfi/q**
BACF pitch detector running inside the Rust GDExtension.  The pipeline is
kept alive for the entire game session by two Autoload singletons so that
the tuner, mixer, and gameplay scenes all share the same hardware input
without re-opening the audio device.

```
Guitar / Microphone (hardware)
       │
       ▼ AudioStreamMicrophone (Godot)
 ┌─────────────────────────┐
 │ AudioServer capture bus │  "GuitarInput" (legacy) or "P1_In" / "P2_In"
 │  AudioEffectCapture     │  ← ring buffer drained every _process() frame
 └─────────────────────────┘
       │  PackedVector2Array (stereo, f32 per channel)
       ▼
  stereo → mono (L+R average)
  noise gate (RMS < threshold → 0.0)
  quantise → PCM-16 LE (2 bytes per sample)
       │  PackedByteArray
       ▼
 samples_ready(player_id, pcm_bytes)   ← GDScript signal
       │
       ▼
 PitchDetector.process_samples(pcm_bytes)   ← Rust GDExtension FFI
       │
       ▼
 6 × BiquadBandpass (per-string IIR filter)
 6 × cycfi::q::pitch_detector (BACF algorithm)
       │
       ▼
 Array[{ string, frequency, periodicity }]  ← detection events
```

---

## Architecture — Three Layers

### 1. `AudioInput` — Legacy Global Singleton (`scripts/audio_input.gd`)

A minimal autoload that opens a single `"GuitarInput"` bus once and emits
`samples_available(pcm_bytes)` every frame.  Suitable for single-player
scenes (tuner, mixer) that just need raw PCM bytes.

```gdscript
# project.godot
[autoload]
AudioInput="*res://scripts/audio_input.gd"
```

**API**

| Method / Signal | Description |
|---|---|
| `signal samples_available(pcm_bytes: PackedByteArray)` | Emitted each frame when new samples are captured |
| `get_last_pcm_bytes() → PackedByteArray` | Poll the most recent frame (empty if nothing captured) |
| `is_active() → bool` | Returns `true` when the capture bus is streaming |
| `open()` | Re-open the bus after `close()` |
| `close()` | Pause streaming without removing the bus |

### 2. `PlayerManager` — Profile Autoload (`scripts/player_manager.gd`)

Owns one `PlayerProfile` per player.  Loaded from `user://players.cfg` at
game startup.  Supplies per-player settings (bus name, noise gate, latency
offset) to `InputAudioManager`.

```gdscript
# project.godot
[autoload]
PlayerManager="*res://scripts/player_manager.gd"
```

### 3. `InputAudioManager` — Per-Player Runtime Autoload (`scripts/input_audio_manager.gd`)

The recommended entry point for gameplay scenes.  Creates one dedicated
capture bus per player (`P1_In`, `P2_In`), applies noise gating from the
player's `PlayerProfile`, and emits `samples_ready(player_id, pcm_bytes)`.

```gdscript
# project.godot
[autoload]
InputAudioManager="*res://scripts/input_audio_manager.gd"
```

**API**

| Method / Signal | Description |
|---|---|
| `signal samples_ready(player_id: int, pcm_bytes: PackedByteArray)` | Emitted per player when new samples pass the noise gate |
| `get_last_pcm(player_id) → PackedByteArray` | Poll the most recent frame for a player |
| `is_active(player_id) → bool` | Returns `true` when that player's bus is streaming |
| `refresh_player(player_id)` | Re-open the bus after a profile change (e.g. device swap) |
| `pause_player(player_id)` | Pause streaming without removing the bus |
| `resume_player(player_id)` | Resume a paused capture |

---

## PCM Format

All audio data is delivered as **PCM-16 LE mono** bytes:

| Property | Value |
|---|---|
| Channels | 1 (mono — L+R averaged) |
| Bit depth | 16-bit signed integer |
| Byte order | Little-endian |
| Sample rate | `AudioServer.get_mix_rate()` (typically 44 100 or 48 000 Hz) |
| Bytes per sample | 2 |

The conversion from Godot's stereo float buffer:

```gdscript
var s   : float = clampf((stereo_buf[fi].x + stereo_buf[fi].y) * 0.5, -1.0, 1.0)
var s16 : int   = clampi(int(s * 32768.0), -32768, 32767)
pcm_bytes.encode_s16(fi * 2, s16)
```

---

## PlayerProfile — Per-Player Audio Settings

`PlayerProfile` (`scripts/player_profile.gd`) is a pure-data `RefCounted`
object.  It decouples player preferences from the live audio objects.

| Field | Type | Default | Description |
|---|---|---|---|
| `id` | `int` | `1` | Player index (1 or 2) |
| `display_name` | `String` | `"Player 1"` | Human-readable name |
| `input_device_name` | `String` | `""` | OS device name (`""` = system default) |
| `input_bus_name` | `String` | `"P1_In"` | Godot AudioServer bus for this player |
| `monitor_enabled` | `bool` | `false` | Hear own guitar through speakers |
| `monitor_volume_db` | `float` | `0.0` | Monitor volume in dB |
| `noise_gate_threshold` | `float` | `0.02` | RMS amplitude below which samples are zeroed (0–1) |
| `input_latency_ms` | `float` | `0.0` | Hardware round-trip latency offset (ms) |
| `av_offset_ms` | `float` | `0.0` | Audio-video sync offset (ms) |
| `difficulty_percent` | `float` | `100.0` | DDC difficulty (0–100) |
| `tolerance_scale` | `float` | `1.0` | Scoring window multiplier (1.0 = default) |

Profiles are persisted to `user://players.cfg` by `PlayerManager.save()`.

---

## Connecting to the Audio Stream

### Signal (push model — recommended)

```gdscript
func _ready() -> void:
    InputAudioManager.samples_ready.connect(_on_samples)

func _on_samples(player_id: int, pcm_bytes: PackedByteArray) -> void:
    if player_id != 1:
        return
    # Forward to cycfi/q pitch detector
    var detections : Array = _pitch_detector.process_samples(pcm_bytes)
    for d in detections:
        print("String %d  %.2f Hz  (periodicity %.2f)" % [
            d["string"], d["frequency"], d["periodicity"]])

func _exit_tree() -> void:
    InputAudioManager.samples_ready.disconnect(_on_samples)
```

### Polling (pull model)

```gdscript
func _process(_delta: float) -> void:
    var pcm := InputAudioManager.get_last_pcm(1)
    if pcm.size() > 0:
        _pitch_detector.process_samples(pcm)
```

---

## Integrating with `PitchDetector` (Rust GDExtension)

`PitchDetector` is the Godot class exposed by the Rust GDExtension.  It
wraps six cycfi/q `pitch_detector` instances (one per guitar string) with
per-string **biquad bandpass pre-filters** to reduce cross-string false
positives.

### Lifecycle

```gdscript
var _pd : PitchDetector

func _ready() -> void:
    if ClassDB.class_exists(&"PitchDetector"):
        _pd = PitchDetector.new()
        _pd.start(AudioServer.get_mix_rate())
    InputAudioManager.samples_ready.connect(_on_samples)

func _on_samples(player_id: int, pcm_bytes: PackedByteArray) -> void:
    if player_id != 1 or _pd == null:
        return
    var events : Array = _pd.process_samples(pcm_bytes)
    for ev in events:
        print("String %d  %.2f Hz  periodicity=%.3f" % [
            ev["string"], ev["frequency"], ev["periodicity"]])

func _exit_tree() -> void:
    InputAudioManager.samples_ready.disconnect(_on_samples)
    if _pd:
        _pd.stop()
```

### `PitchDetector` API summary

| Method | Description |
|---|---|
| `start(sample_rate: int) → bool` | Allocate all 6 Q detectors at the given sample rate |
| `stop()` | Free all detectors |
| `is_running() → bool` | Returns `true` while detectors are allocated |
| `process_samples(data: PackedByteArray) → Array[Dictionary]` | Feed PCM-16 LE mono; returns detection events |
| `get_last_result() → Dictionary` | Most recent detection (may be stale) |

Detection event dictionary:

```gdscript
{
    "string":      int,    # 1 (high e) – 6 (low E)
    "frequency":   float,  # detected fundamental in Hz
    "periodicity": float   # confidence [0.0 – 1.0]
}
```

Only events with `periodicity >= 0.6` are returned.

---

## Bandpass Pre-filters

Each string's signal is pre-filtered by a 2nd-order IIR biquad bandpass
filter (Audio EQ Cookbook, constant-0 dB peak-gain topology) before being
fed into its Q detector.  This dramatically reduces false detections from
adjacent strings that share overtones.

| String | Note | Filter centre (Hz) | Band (Hz) |
|---|---|---|---|
| 6 | E2 (Low E) | ≈ 160 | 73.4 – 350.0 |
| 5 | A2 | ≈ 214 | 98.0 – 470.0 |
| 4 | D3 | ≈ 285 | 130.8 – 620.0 |
| 3 | G3 | ≈ 381 | 174.6 – 830.0 |
| 2 | B3 | ≈ 480 | 220.0 – 1 050.0 |
| 1 | E4 (High e) | ≈ 641 | 293.7 – 1 400.0 |

Centre frequency = √(min × max); bandwidth = max − min.

> **Note:** The ranges overlap intentionally.  The BACF algorithm combined
> with the periodicity threshold is robust enough to resolve the ambiguity;
> the bandpass filters serve as a first-pass attenuator, not a hard gate.

---

## Latency Budget

| Stage | Typical latency |
|---|---|
| Hardware input buffer (OS driver) | 1 – 5 ms |
| Godot `_process()` drain interval | ~16 ms (60 fps) |
| cycfi/q BACF minimum window (E2, 82.4 Hz) | ~24 ms (≥ 2 cycles) |
| **Total round-trip (detection)** | **~40 – 50 ms** |

The `input_latency_ms` field on `PlayerProfile` can compensate for
hardware-specific delays when evaluating note-scoring hit windows.

To minimise the Godot drain interval, lower **Project Settings → Audio →
Driver → Audio Buffer Size** (e.g. 256 samples at 44 100 Hz ≈ 5.8 ms).

---

## Project Settings

The following settings are required for microphone capture to work:

```ini
# project.godot
[audio]
driver/enable_input=true

[autoload]
AudioInput="*res://scripts/audio_input.gd"
PlayerManager="*res://scripts/player_manager.gd"
InputAudioManager="*res://scripts/input_audio_manager.gd"
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No samples emitted | `audio/driver/enable_input` not set | Add `audio/driver/enable_input=true` to `project.godot` |
| All samples are zero | Noise gate threshold too high | Lower `PlayerProfile.noise_gate_threshold` (default 0.02) |
| No `PitchDetector` class | GDExtension not built, `libq_bridge.a` missing, or cycfi/q headers unavailable | Add `gdextension/lib/<platform>/libq_bridge.a`, or run `git submodule update --init --recursive`, then rebuild |
| High false-positive rate | Bandpass filter not aligned to tuning | Verify string tuning is standard E; check `STRING_RANGES` in `src/bandpass.rs` |
| Detection lags behind video | `input_latency_ms` not calibrated | Set `PlayerProfile.input_latency_ms` from the in-game calibration screen |

---

## See Also

- [`docs/Q_FFI.md`](Q_FFI.md) — Rust/C++ FFI layer, `PitchDetector` full API reference, build instructions
- [`scripts/audio_input.gd`](../scripts/audio_input.gd) — legacy single-player capture singleton
- [`scripts/input_audio_manager.gd`](../scripts/input_audio_manager.gd) — per-player capture manager
- [`scripts/player_profile.gd`](../scripts/player_profile.gd) — per-player settings data object
- [`scripts/player_manager.gd`](../scripts/player_manager.gd) — profile persistence autoload
- [Godot 4 — Recording with Microphone](https://docs.godotengine.org/en/stable/tutorials/audio/recording_with_microphone.html)
- [cycfi/q](https://github.com/cycfi/q) — BACF pitch detection library
