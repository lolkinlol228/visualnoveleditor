extends Control

const ICON_COLOR: Color = Color(1.0, 0.92, 0.82, 1.0)
const ARC_POINTS: int = 96
const TOOTH_COUNT: int = 8

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var icon_size: Vector2 = size
	var side: float = min(icon_size.x, icon_size.y)
	if side <= 0.0:
		return

	var center: Vector2 = icon_size * 0.5
	var line_width: float = max(1.15, side * 0.038)
	var inner_radius: float = side * 0.105
	var root_radius: float = side * 0.255
	var tooth_radius: float = side * 0.335
	var tooth_step: float = TAU / float(TOOTH_COUNT)
	var points: PackedVector2Array = PackedVector2Array()

	for i in range(TOOTH_COUNT):
		var angle: float = float(i) * tooth_step
		points.append(center + Vector2(cos(angle - tooth_step * 0.42), sin(angle - tooth_step * 0.42)) * root_radius)
		points.append(center + Vector2(cos(angle - tooth_step * 0.22), sin(angle - tooth_step * 0.22)) * tooth_radius)
		points.append(center + Vector2(cos(angle + tooth_step * 0.22), sin(angle + tooth_step * 0.22)) * tooth_radius)
		points.append(center + Vector2(cos(angle + tooth_step * 0.42), sin(angle + tooth_step * 0.42)) * root_radius)
	points.append(points[0])

	draw_polyline(points, ICON_COLOR, line_width, true)
	draw_arc(center, inner_radius, 0.0, TAU, ARC_POINTS, ICON_COLOR, line_width, true)
