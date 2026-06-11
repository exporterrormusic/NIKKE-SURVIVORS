# Extracted from scripts/world/Level.gd (was runtime-compiled embedded source).
extends Node2D

var radius: float = 120.0
var color: Color = Color(1.0, 0.3, 0.6, 0.8)
var _time: float = 0.0
var _duration: float = 0.35

func _ready() -> void:
	z_index = 200

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	var current_radius := radius * (0.5 + progress * 0.5)
	var alpha := (1.0 - progress) * color.a
	
	# Explosion ring
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 32, Color(color.r, color.g, color.b, alpha), 6.0)
	
	# Inner flash
	var inner_alpha := alpha * 0.5 * (1.0 - progress)
	draw_circle(Vector2.ZERO, current_radius * 0.7, Color(1.0, 0.8, 1.0, inner_alpha))
