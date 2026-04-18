## common.gd — ChartPlayer coordinate formulas shared across all scripts.
##
## Registered globally as ChartCommon.  Access without preloading:
##   var x  := ChartCommon.fret_mid_world_x(fret)
##   var y  := ChartCommon.string_world_y(string_index)
##   var sz := ChartCommon.note_indicator_size(fret)
class_name ChartCommon
extends RefCounted

## Total frets on the virtual guitar neck.
const FRET_COUNT         : int   = 24
## Total strings on the virtual guitar neck.
const STRING_COUNT       : int   = 6
## New simplified coordinate spacing.
const FRET_SPACING       : float = 2.0
const STRING_SPACING     : float = 0.5
const STRING_MARGIN      : float = 0.25
const Z_UNITS_PER_SECOND : float = 1.0
## Total world-unit width of the highway (fret 0 = X 0, fret 24 = X 48).
const FRET_WORLD_WIDTH   : float = float(FRET_COUNT) * FRET_SPACING
## Height of one string slot in world units.
const STRING_SLOT_HEIGHT : float = STRING_SPACING
## Guard against division by zero when FRET_COUNT is 0.
const MIN_VALID_FRET_POS : float = 0.001
## Fallback note size when fret geometry is unavailable.
const DEFAULT_NOTE_INDICATOR_SIZE: Vector2 = Vector2(0.232, 0.4)


# ── Core formula ──────────────────────────────────────────────────────────────

## Linear fret-position formula.
## Returns 0 at fret 0 and advances by FRET_SPACING world units per fret.
static func chart_fret_pos(fret_num: float) -> float:
	return fret_num * FRET_SPACING


# ── X (horizontal) positions ──────────────────────────────────────────────────

## World X of the separator line at the left edge of a fret slot.
## Fret 0 → X = 0, fret 24 → X = FRET_WORLD_WIDTH.
## Use this for camera tracking, fret-line rendering, and range highlighting.
static func fret_separator_world_x(fret_num: int) -> float:
	if float(FRET_COUNT) <= MIN_VALID_FRET_POS:
		return 0.0
	return chart_fret_pos(float(fret_num))


## World X of the centre of a fret slot (between fret_num and fret_num + 1).
## Use this to place a note (finger indicator) inside its fret slot.
static func fret_mid_world_x(fret_num: int) -> float:
	if float(FRET_COUNT) <= MIN_VALID_FRET_POS:
		return 0.0
	return fret_separator_world_x(fret_num + 1) - (FRET_SPACING * 0.5)


# ── Y (string height) ─────────────────────────────────────────────────────────

## World Y for the centre of a string.
## String number formula: STRING_MARGIN + string_number × STRING_SPACING.
## String index 0 remains the top string in-scene, so we map it to string_number 5.
static func string_world_y(str_idx: int) -> float:
	var string_number := clampi(STRING_COUNT - 1 - str_idx, 0, STRING_COUNT - 1)
	return STRING_MARGIN + float(string_number) * STRING_SPACING


## World Y of the separator line *below* str_idx (between str_idx and str_idx + 1).
## Equivalent to string_world_y(str_idx) − STRING_SLOT_HEIGHT / 2.
static func string_separator_y(str_idx: int) -> float:
	return string_world_y(str_idx) - STRING_SLOT_HEIGHT * 0.5


## World Y of the separator line *above* str_idx (between str_idx − 1 and str_idx).
## Equivalent to string_world_y(str_idx) + STRING_SLOT_HEIGHT / 2.
## Use this as the top edge when building a box that must contain str_idx's slot.
static func string_top_separator_y(str_idx: int) -> float:
	return string_world_y(str_idx) + STRING_SLOT_HEIGHT * 0.5


# ── Note indicator geometry ───────────────────────────────────────────────────

## World-unit size (width × height) for a note finger indicator at fret_num.
## Width is one fret slot (FRET_SPACING world units); height = 80 % of STRING_SLOT_HEIGHT,
## so the indicator fits comfortably between strings.
static func note_indicator_size(fret_num: int) -> Vector2:
	if float(FRET_COUNT) <= MIN_VALID_FRET_POS:
		return DEFAULT_NOTE_INDICATOR_SIZE
	var w    := FRET_SPACING
	var h    := STRING_SLOT_HEIGHT * 0.8
	return Vector2(w, h)


# ── Z (time depth) ─────────────────────────────────────────────────────────────

## World Z from song time and note timestamp.
## 1 world unit = 1 second.
static func note_world_z(time_offset: float, song_time: float, strum_z: float = 0.0) -> float:
	return strum_z - (time_offset - song_time) * Z_UNITS_PER_SECOND
