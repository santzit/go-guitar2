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
