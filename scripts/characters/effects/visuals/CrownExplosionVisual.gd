# Extracted from scripts/characters/CrownController.gd (was runtime-compiled embedded source).
extends Node2D

var radius: float = 80.0
var _time: float = 0.0
const DURATION: float = 0.5

func _ready() -> void:
	z_index = 200

func _process(delta: float) -> void:
	_time += delta
	if _time >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress: float = _time / DURATION
	var expand: float = 0.3 + progress * 0.7
	var current_radius: float = radius * expand
	
	# Inverse alpha - starts bright, fades out
	var alpha: float = (1.0 - progress) * 1.0
	var flash_alpha: float = (1.0 - progress * progress) * 1.5
	
	# BRILLIANT saturated gold explosion
	var deep_gold: Color = Color(1.0, 0.7, 0.0, alpha)
	var bright_gold: Color = Color(1.0, 0.85, 0.1, alpha)
	var white_hot: Color = Color(1.0, 1.0, 0.5, flash_alpha)
	
	# Outer glow ring
	draw_arc(Vector2.ZERO, current_radius * 1.3, 0, TAU, 48, Color(1.0, 0.6, 0.0, alpha * 0.3), 20.0)
	
	# Main explosion circle - deep gold
	draw_circle(Vector2.ZERO, current_radius, deep_gold)
	
	# Middle ring - bright gold
	draw_circle(Vector2.ZERO, current_radius * 0.75, bright_gold)
	
	# Inner flash - white hot center
	var inner_radius: float = current_radius * 0.4 * (1.0 - progress * 0.5)
	draw_circle(Vector2.ZERO, inner_radius, white_hot)
	
	# Radiating lines
	var num_rays: int = 12
	for i in range(num_rays):
		var angle: float = (float(i) / float(num_rays)) * TAU + _time * 3.0
		var ray_start: Vector2 = Vector2(cos(angle), sin(angle)) * inner_radius
		var ray_end: Vector2 = Vector2(cos(angle), sin(angle)) * current_radius * 1.1
		var ray_alpha: float = alpha * (0.5 + sin(_time * 20.0 + float(i)) * 0.3)
		draw_line(ray_start, ray_end, Color(1.0, 0.9, 0.3, ray_alpha), 3.0)
	
	# Outer ring edge
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 48, white_hot, 4.0 * (1.0 - progress))
	
	# Sparkle particles
	for i in range(8):
		var angle: float = (float(i) / 8.0) * TAU + _time * 5.0
		var dist: float = current_radius * (0.6 + sin(_time * 15.0 + float(i) * 2.0) * 0.3)
		var sparkle_pos: Vector2 = Vector2(cos(angle), sin(angle)) * dist
		var sparkle_size: float = 6.0 * (1.0 - progress)
		draw_circle(sparkle_pos, sparkle_size, white_hot)
