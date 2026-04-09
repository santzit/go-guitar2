# go-guitar2
Rocksmith 2014 like Guitar 3D Game built with **Godot 4.4**.

## Project structure

```
project.godot          – Godot 4.4 project entry-point (main scene: music_play.tscn)
scenes/
  music_play.tscn      – Root Node3D: Camera3D, DirectionalLight3D, Highway, NotePool, Background
  highway.tscn         – HighwaySurface MeshInstance3D (shader-drawn fret lanes) + StrumLine + walls
  note.tscn            – Pooled note BoxMesh with per-string ShaderMaterial
  note_pool.tscn       – Manages up to 128 active note instances
  background.tscn      – WorldEnvironment (procedural sky + bloom)
scripts/
  music_play.gd        – Scans DLC/, loads .psarc via RsBridge, schedules notes, plays audio
  highway.gd           – Runtime fret/string-count config for the highway shader
  note.gd              – Note travel (X=fret, Y=string, Z=time), per-string colour, pool return
  note_pool.gd         – spawn_note / return_note pool API
  rs_bridge.gd         – GDScript wrapper around the RocksmithBridge GDExtension
shaders/
  highway.gdshader     – Fret-lane lines, depth-fade, strum-line glow
  note.gdshader        – Per-string colour + pulsing emission glow
DLC/                   – Drop .psarc CDLC files here for testing (5 songs included)
gdextension/
  rocksmith_bridge.gdextension  – GDExtension manifest
  src/                 – Rust source (godot-rust/gdext + Rocksmith2014.rs)
  bin/                 – Place compiled .so / .dll / .dylib here after building
  README.md            – Build instructions
```

## Audio system 
Use Rust for Audio DSP

Libraries / Projects used:
| Project | Description | Github |
|------|---------|---------|
| **Q** | Audio DSP Library - for note/technique detetion |[cycfi/q](https://github.com/cycfi/q)|
| **vgmstream** | Wwise (.wen) audio |[vgmstream/vgmstream](https://github.com/vgmstream/vgmstream)|
| **G.719 Codec** |  G.719 decoder library for vgmstream | [speech-coders/itu-g-719-codec](https://vocal.com/speech-coders/itu-g-719-codec/)|
| **guitarrix** | Virtual Guitar Amplifier - for Amp / Tones |[brummer10/guitarix](https://github.com/brummer10/guitarix)|
| **Rocksmith2014.rs** | Libraries for creating Rocksmith 2014 custom DLC|[santzit/Rocksmith2014.rs](https://github.com/santzit/Rocksmith2014.rs)|


## Coordinate system

| Axis | Meaning |
|------|---------|
| **X** | Fret number (0 = open, 1–24 = frets) × `FRET_SPACING` |
| **Y** | String index (0 = Low-E … 5 = High-e) × `STRING_SPACING` |
| **Z** | Time — notes spawn at Z = 20 and travel toward Z = 0 (strum line) |

## Quick start

1. Open the project in **Godot 4.4**.
2. The game auto-detects the first `.psarc` in `res://DLC/` on startup.
3. If the GDExtension binary is not built yet, the game uses built-in demo notes.
4. To enable real song data, build the Rust extension (see `gdextension/README.md`).
