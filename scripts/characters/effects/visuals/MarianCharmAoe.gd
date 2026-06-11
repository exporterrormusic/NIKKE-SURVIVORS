# Extracted from scripts/characters/MarianController.gd (was runtime-compiled embedded source).
extends Node2D

var radius: float = 150.0
var color: Color = Color(0.3, 0.5, 1.0, 0.6)
var _time: float = 0.0
var _duration: float = 0.5

func _ready() -> void:
	z_index = 100

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	var current_radius := radius * progress
	var alpha := (1.0 - progress) * color.a
	
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 64, Color(color.r, color.g, color.b, alpha), 4.0)
	draw_circle(Vector2.ZERO, current_radius * 0.9, Color(color.r, color.g, color.b, alpha * 0.3))
