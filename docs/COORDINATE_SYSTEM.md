# Coordinate System (GoGuitar2)

This project uses a single shared coordinate source in:

- `res://scripts/common.gd` (`ChartCommon`)

## Constants

- Frets: `24`
- Strings: `6`
- Fret spacing: `2.0` world units
- String spacing: `0.5` world units
- String margin (top/bottom): `0.25` world units
- Fretboard/highway X length: `48.0` world units (`24 * 2.0`)
- Highway depth: `30.0` world units (notes spawn at `-30` -> strum at `0`)
- Note lookahead: `3.0` seconds
- Time depth scale: `10.0` world units = `1.0` second (`HIGHWAY_DEPTH / NOTE_LOOKAHEAD_SECS`)

## Position formulas

- Fret separator X: `fret * fret_spacing`
- Fret midpoint X: `fret_separator(next) - fret_spacing / 2`
- String Y: `margin + string_number * string_spacing`
- Note/chord Z: `strum_z - (event_time - song_time) * Z_UNITS_PER_SECOND`

## Usage

Always use `ChartCommon` helpers (`fret_separator_world_x`, `fret_mid_world_x`, `string_world_y`, `note_world_z`) instead of reimplementing coordinate math in gameplay scripts.

## Highway camera framing

- `scripts/CameraController.gd` keeps a fixed low pitch (`20°`) and tracks the horizontal center of active targets.
- Zoom/dolly depth is calculated from horizontal target span + safe-zone padding using horizontal frustum width (`fov` + viewport aspect).
- When targets spread apart, the camera increases zoom distance (pulls back); when clustered, it reduces zoom distance (dollies forward).
