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
## Total world-unit width of the highway (fret 0 = X 0, fret 24 = X 24).
const FRET_WORLD_WIDTH   : float = 24.0
## Multiplier that maps the raw GetStringHeight value to world units.
const STRING_HEIGHT_SCALE: float = 0.125
## Height of one string slot in world units (= 4 × STRING_HEIGHT_SCALE).
const STRING_SLOT_HEIGHT : float = 4.0 * STRING_HEIGHT_SCALE  # 0.5
## Guard against division by zero when FRET_COUNT is 0.
const MIN_VALID_FRET_POS : float = 0.001


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
## String 0 (low E) = top, string 5 (high e) = bottom.
## Formula: (3 + (5 - str_idx) × 4) × STRING_HEIGHT_SCALE.
static func string_world_y(str_idx: int) -> float:
	return (3.0 + float(5 - str_idx) * 4.0) * STRING_HEIGHT_SCALE


# ── Note indicator geometry ───────────────────────────────────────────────────

## World-unit size (width × height) for a note finger indicator at fret_num.
## Width is one fret slot (1 world unit); height = 80 % of STRING_SLOT_HEIGHT,
## so the indicator fits comfortably between strings.
static func note_indicator_size(fret_num: int) -> Vector2:
	if float(FRET_COUNT) <= MIN_VALID_FRET_POS:
		return Vector2(0.116, 0.06)
	var w    := 1.0
	var h    := STRING_SLOT_HEIGHT * 0.8
	return Vector2(w, h)
