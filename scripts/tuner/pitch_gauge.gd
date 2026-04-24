extends Control
class_name PitchGauge

const ARC_START_DEG: float = 210.0
const ARC_END_DEG: float = 330.0
const TICK_COUNT: int = 25
const CENTER_Y_RATIO: float = 0.9
const RADIUS_X_RATIO: float = 0.42
const RADIUS_Y_RATIO: float = 0.85
const MAJOR_TICK_LENGTH: float = 22.0
const MINOR_TICK_LENGTH: float = 13.0
const NEEDLE_RADIUS_OFFSET: float = 28.0
const NEEDLE_WIDTH: float = 7.0
const HUB_RADIUS: float = 7.0
const ARC_COLOR: Color = Color(0.86, 0.62, 0.14, 0.95)
const MAJOR_TICK_COLOR: Color = Color(0.37, 0.95, 0.60, 0.9)
const MINOR_TICK_COLOR: Color = Color(0.94, 0.66, 0.16, 0.8)
const NEEDLE_IDLE_COLOR: Color = Color(0.66, 0.7, 0.74)
const NEEDLE_IN_TUNE_COLOR: Color = Color(0.4, 1.0, 0.5)
const NEEDLE_LOW_COLOR: Color = Color(0.45, 0.75, 1.0)
const NEEDLE_HIGH_COLOR: Color = Color(1.0, 0.52, 0.35)
const HUB_COLOR: Color = Color(0.92, 0.92, 0.92, 0.95)

@export var min_cents: float = -50.0
@export var max_cents: float = 50.0

var _cents_value: float = 0.0
var _has_signal: bool = false
var _in_tune: bool = false


func set_meter_value(cents: float, has_signal: bool, in_tune: bool) -> void:
	_cents_value = clampf(cents, min_cents, max_cents)
	_has_signal = has_signal
	_in_tune = in_tune
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * CENTER_Y_RATIO)
	var radius := minf(size.x * RADIUS_X_RATIO, size.y * RADIUS_Y_RATIO)
	var start_angle: float = deg_to_rad(ARC_START_DEG)
	var end_angle: float = deg_to_rad(ARC_END_DEG)

	draw_arc(center, radius, start_angle, end_angle, 80, ARC_COLOR, 3.0, true)

	for i in range(TICK_COUNT):
		var t: float = float(i) / float(TICK_COUNT - 1)
		var angle: float = lerpf(start_angle, end_angle, t)
		var dir := Vector2(cos(angle), sin(angle))
		var is_major: bool = i % 4 == 0
		var inner: float = radius - (MAJOR_TICK_LENGTH if is_major else MINOR_TICK_LENGTH)
		var color := MAJOR_TICK_COLOR if is_major else MINOR_TICK_COLOR
		draw_line(center + dir * inner, center + dir * radius, color, 2.0, true)

	var needle_angle: float = remap(_cents_value, min_cents, max_cents, start_angle, end_angle)
	var needle_color: Color = NEEDLE_IDLE_COLOR
	if _has_signal:
		if _in_tune:
			needle_color = NEEDLE_IN_TUNE_COLOR
		elif _cents_value < 0.0:
			needle_color = NEEDLE_LOW_COLOR
		else:
			needle_color = NEEDLE_HIGH_COLOR
	var needle_dir := Vector2(cos(needle_angle), sin(needle_angle))
	draw_line(center, center + needle_dir * (radius - NEEDLE_RADIUS_OFFSET), needle_color, NEEDLE_WIDTH, true)
	draw_circle(center, HUB_RADIUS, HUB_COLOR)
