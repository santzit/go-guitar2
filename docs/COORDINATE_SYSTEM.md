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
- Time depth scale: `1.0` world unit = `1.0` second

## Position formulas

- Fret separator X: `fret * fret_spacing`
- Fret midpoint X: `fret_separator(next) - fret_spacing / 2`
- String Y: `margin + string_number * string_spacing`
- Note/chord Z: `strum_z - (event_time - song_time) * 1.0`

## Usage

Always use `ChartCommon` helpers (`fret_separator_world_x`, `fret_mid_world_x`, `string_world_y`, `note_world_z`) instead of reimplementing coordinate math in gameplay scripts.
