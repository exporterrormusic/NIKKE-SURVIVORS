# Extracted from scripts/characters/effects/SinWishEffect.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0
var _duration: float = 0.3

func _ready() -> void:
	z_index = 100

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress = _time / _duration
	var radius = 30.0 + progress * 50.0
	var alpha = 1.0 - progress
	draw_circle(Vector2.ZERO, radius, Color(0.6, 0.2, 0.9, alpha * 0.8))
	draw_circle(Vector2.ZERO, radius * 0.6, Color(0.8, 0.4, 1.0, alpha))
