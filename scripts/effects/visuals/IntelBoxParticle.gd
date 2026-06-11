# Extracted from scripts/world/IntelBox.gd (was runtime-compiled embedded source).
extends Node2D

var velocity: Vector2
var lifetime: float = 0.5
var _time: float = 0.0
var color: Color

func _ready() -> void:
	z_index = 100

func _process(delta: float) -> void:
	_time += delta
	global_position += velocity * delta
	velocity *= 0.95
	if _time >= lifetime:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var alpha := 1.0 - (_time / lifetime)
	var draw_color := color
	draw_color.a = alpha
	draw_circle(Vector2.ZERO, 4.0, draw_color)
