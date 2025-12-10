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
	# Make indicator unshaded so it's visible at night
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
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
	# Pulsing alpha effect
	var pulse := sin(_pulse_time * PULSE_SPEED) * 0.5 + 0.5
	var alpha := BASE_ALPHA + pulse * PULSE_ALPHA
	
	# Main indicator circle only (removed extra rings for performance)
	var fill_color := Color(1.0, 0.0, 0.0, alpha) # Pure red
	draw_circle(Vector2.ZERO, _radius, fill_color)
	
	# Simple ring outline
	var ring_color := Color(1.0, 0.1, 0.1, alpha * 1.5) # Bright red
	draw_arc(Vector2.ZERO, _radius * 0.9, 0, TAU, 16, ring_color, 3.0)
	
	# Simple crosshair (fewer draw calls)
	var cross_color := Color(1.0, 0.2, 0.2, alpha * 2.0) # Light red
	var cross_size := _radius * 0.25
	draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), cross_color, 2.0)
	draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), cross_color, 2.0)
