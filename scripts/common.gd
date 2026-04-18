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
## Total world-unit width of the highway (fret 0 = X 0, fret 24 = X 24).
## Kept separate from FRET_COUNT so scene/layout code can read an explicit width.
const FRET_WORLD_WIDTH   : float = 24.0
## Multiplier that maps the raw GetStringHeight value to world units.
const STRING_HEIGHT_SCALE: float = 0.125
## Height of one string slot in world units (= 4 × STRING_HEIGHT_SCALE).
const STRING_SLOT_HEIGHT : float = 4.0 * STRING_HEIGHT_SCALE  # 0.5
## World Y of string 0 (low E, topmost string).
## Must match transform.origin.y of the String0 node in scenes/fretboard.tscn.
const STRING_0_Y : float = 2.7
## Guard against division by zero when FRET_COUNT is 0.
const MIN_VALID_FRET_POS : float = 0.001
## Fallback note size when fret geometry is unavailable.
const DEFAULT_NOTE_INDICATOR_SIZE: Vector2 = Vector2(0.116, 0.06)


# ── Core formula ──────────────────────────────────────────────────────────────

## Linear fret-position formula.
## Returns 0 at fret 0 and advances by 1 world unit per fret.
static func chart_fret_pos(fret_num: float) -> float:
	return fret_num


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
	return chart_fret_pos(float(fret_num)) + 0.5


# ── Y (string height) ─────────────────────────────────────────────────────────

## World Y for the centre of a string.
## String 0 (low E) = top (Y = STRING_0_Y), string 5 (high e) = bottom.
## Formula: STRING_0_Y − str_idx × STRING_SLOT_HEIGHT.
## Matches the transform.origin.y values in scenes/fretboard.tscn (2.7, 2.2, … 0.2).
static func string_world_y(str_idx: int) -> float:
	return STRING_0_Y - float(str_idx) * STRING_SLOT_HEIGHT


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
## Width is one fret slot (1 world unit); height = 80 % of STRING_SLOT_HEIGHT,
## so the indicator fits comfortably between strings.
static func note_indicator_size(fret_num: int) -> Vector2:
	if float(FRET_COUNT) <= MIN_VALID_FRET_POS:
		return DEFAULT_NOTE_INDICATOR_SIZE
	var w    := 1.0
	var h    := STRING_SLOT_HEIGHT * 0.8
	return Vector2(w, h)
