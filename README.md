# go-guitar2
Rocksmith 2014 like Guitar 3D Game built with **Godot 4.4**.

## Project structure

```
project.godot          – Godot 4.4 project entry-point (main scene: game_menu.tscn)
scenes/
  game_menu.tscn       – Main menu with Song List, Mixer, and Settings options
  song_list.tscn       – Song picker UI (lists DLC .psarc files and starts gameplay)
  music_play.tscn      – Root Node3D: Camera3D, DirectionalLight3D, Highway, NotePool, Background
  fretboard.tscn       – 6 visible string lines at the strum position (Z=0)
  highway.tscn         – HighwaySurface MeshInstance3D (shader-drawn fret lanes) + StrumLine + walls
  note.tscn            – Pooled note with ChartPlayer Guitar*.png finger indicator sprites
  note_pool.tscn       – Manages up to 128 active note instances
  background.tscn      – WorldEnvironment (procedural sky + bloom)
scripts/
  game_menu.gd         – Opens the song list scene
  song_list.gd         – Populates song list and launches music_play with selected song
  game_state.gd        – Shared selected-song state and DLC scan helper
  music_play.gd        – Loads selected .psarc via RsBridge, schedules notes, plays audio
  highway.gd           – Runtime fret/string-count config for the highway shader
  note.gd              – Note travel (X=fret, Y=string, Z=time), per-string colour, pool return
  note_pool.gd         – spawn_note / return_note pool API
  rs_bridge.gd         – GDScript wrapper around the RocksmithBridge GDExtension
shaders/
  highway.gdshader     – Dark background + 6 UV-masked glowing lanes with per-lane intensity
  note.gdshader        – Per-string colour + pulsing emission glow
assets/textures/chartplayer/ – Copied ChartPlayer Guitar*.png / FingerOutline textures used in-game
ChartPlayer/           – Upstream ChartPlayer source snapshot for reference (temporary)
DLC/                   – Drop .psarc CDLC files here for testing (5 songs included)
gdextension/
  goguitar_bridge.gdextension  – GDExtension manifest
  src/                 – Rust source (godot-rust/gdext + Rocksmith2014.rs)
  bin/                 – Place compiled .so / .dll / .dylib here after building
  README.md            – Build instructions
```

## Audio system 
Use Rust for Audio DSP

Libraries / Projects used:
| Project | Description | Github |
|------|---------|---------|
| **cpal** | Cross-platform audio I/O library in pure Rust  |[RustAudio/cpal](https://github.com/RustAudio/cpal)|
| **Q** | Audio DSP Library - for note/technique detetion |[cycfi/q](https://github.com/cycfi/q)|
| **vgmstream** | Wwise (.wen) audio |[vgmstream/vgmstream](https://github.com/vgmstream/vgmstream)|
| **guitarrix** | (TODO not implemented yet) Virtual Guitar Amplifier - for Amp / Tones |[brummer10/guitarix](https://github.com/brummer10/guitarix)|
| **Rocksmith2014.rs** | Libraries for creating Rocksmith 2014 custom DLC|[santzit/Rocksmith2014.rs](https://github.com/santzit/Rocksmith2014.rs)|


## Coordinate system

| Axis | Meaning |
|------|---------|
| **X** | `scaleLength - scaleLength / 2^(fret/12)` (ChartPlayer-style), normalized to highway width |
| **Y** | `(3 + string_index × 4)` scaled to scene units |
| **Z** | Time — notes spawn at Z = 0 and travel toward Z = 20 (strum line) |

## Quick start

1. Open the project in **Godot 4.4** - https://github.com/godotengine/godot/releases/tag/4.4.1-stable.
2. Open the game menu, click **Song list**, then select a song and press **Play**.
