# Extracted from scripts/player/components/PlayerVisualEffects.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0
var _particles: Array = []

func _ready() -> void:
	z_index = -1
	for i in range(12):
		_particles.append({
			"angle": randf() * TAU,
			"dist": randf_range(30, 60),
			"speed": randf_range(0.5, 1.5),
			"size": randf_range(15, 30),
			"alpha": randf_range(0.3, 0.6)
		})

func _process(delta: float) -> void:
	_time += delta
	for p in _particles:
		p.angle += p.speed * delta
	queue_redraw()

func _draw() -> void:
	for p in _particles:
		var pos = Vector2(cos(p.angle), sin(p.angle)) * p.dist
		var pulse = 0.8 + 0.2 * sin(_time * 3.0 + p.angle)
		var color = Color(0.6, 0.2, 0.9, p.alpha * pulse)
		draw_circle(pos, p.size, color)
	var center_alpha = 0.3 + 0.1 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, 50, Color(0.5, 0.1, 0.8, center_alpha))
