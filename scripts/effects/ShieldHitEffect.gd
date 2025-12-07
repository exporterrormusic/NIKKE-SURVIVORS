extends Node2D
class_name ShieldHitEffect

## Quick cyan flash effect when Kilo's shield absorbs damage

const EFFECT_DURATION := 0.3
const RING_RADIUS := 50.0

# Cyan shield colors
const CYAN_CORE := Color(0.2, 1.0, 1.0, 1.0)
const CYAN_OUTER := Color(0.0, 0.8, 0.9, 0.6)

var _time: float = 0.0

func _ready() -> void:
	top_level = true
	z_index = 100
	
	# Unshaded material
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	
	if _time >= EFFECT_DURATION:
		queue_free()

func _draw() -> void:
	var progress: float = _time / EFFECT_DURATION
	var alpha: float = 1.0 - progress
	
	# Expanding ring
	var radius: float = RING_RADIUS * (0.8 + progress * 0.4)
	var ring_color := CYAN_OUTER
	ring_color.a = alpha * 0.8
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, ring_color, 3.0, true)
	
	# Inner glow (fades quickly)
	if progress < 0.5:
		var inner_alpha: float = (0.5 - progress) * 2.0
		var inner_color := CYAN_CORE
		inner_color.a = inner_alpha * 0.4
		draw_circle(Vector2.ZERO, radius * 0.6, inner_color)
	
	# Hexagon pattern (Kilo's tech theme)
	var hex_alpha: float = alpha * 0.6
	var hex_color := CYAN_CORE
	hex_color.a = hex_alpha
	_draw_hexagon(Vector2.ZERO, radius * 0.8, hex_color)

func _draw_hexagon(center: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(6):
		var angle: float = i * TAU / 6.0 - TAU / 12.0
		points.append(center + Vector2(cos(angle), sin(angle)) * size)
	points.append(points[0])
	draw_polyline(points, color, 2.0, true)
