# Extracted from scripts/characters/MarianController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0
var _duration: float = 5.0
var _star_count: int = 5

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Draw spinning stars around the boss's head
	var radius := 40.0
	for i in range(_star_count):
		var angle := _time * 3.0 + float(i) * TAU / float(_star_count)
		var pos := Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -50)
		_draw_star(pos, 8.0, Color(1.0, 1.0, 0.5, 1.0))

func _draw_star(center: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var angle := float(i) * TAU / 10.0 - PI / 2.0
		var r := size if i % 2 == 0 else size * 0.4
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)
