extends Node2D
class_name BossMissileIndicator

## Red semi-transparent circle that appears on ground showing where a missile will land

var _radius := 80.0
var _pulse_time := 0.0
var _redraw_frame := 0
const PULSE_SPEED := 4.0
const BASE_ALPHA := 0.25
const PULSE_ALPHA := 0.15

func _ready() -> void:
	# Make indicator unshaded but MIX blend for visibility on day maps
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func initialize(radius: float) -> void:
	_radius = radius

func _process(delta: float) -> void:
	_pulse_time += delta
	# Only redraw every 3rd frame for performance
	_redraw_frame += 1
	if _redraw_frame % 3 == 0:
		queue_redraw()

func _draw() -> void:
	# Pulsing alpha effect - DARK RED
	var pulse := sin(_pulse_time * PULSE_SPEED) * 0.3 + 0.7 # 0.4 to 1.0 range
	
	# Main indicator circle - Semi-transparent dark red
	var fill_color := Color(0.5, 0.0, 0.0, 0.6) 
	draw_circle(Vector2.ZERO, _radius, fill_color)
	
	# Simple ring outline - Solid dark red
	var ring_color := Color(0.8, 0.0, 0.0, 0.9) 
	draw_arc(Vector2.ZERO, _radius * 0.9, 0, TAU, 32, ring_color, 4.0)
	
	# Crosshair - Dark Red
	var cross_color := Color(0.6, 0.0, 0.0, 0.8 * pulse) 
	var cross_size := _radius * 0.4
	draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), cross_color, 4.0)
	draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), cross_color, 4.0)
