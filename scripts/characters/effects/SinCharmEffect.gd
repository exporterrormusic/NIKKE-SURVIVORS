extends Node2D
class_name SinCharmEffect

## Visual effect attached to charmed enemies
## Purple tint and heart icon showing they are friendly

@export var heart_offset: float = 40.0
@export var pulse_speed: float = 2.0
@export var glow_intensity: float = 0.4

var _time: float = 0.0

func _ready() -> void:
	set_process(true)
	
	# Apply purple tint to parent enemy
	var parent := get_parent()
	if parent:
		# Find sprite and apply modulation
		var sprite = parent.get_node_or_null("Sprite2D")
		if sprite == null:
			sprite = parent.get_node_or_null("AnimatedSprite2D")
		if sprite == null:
			# Try finding any sprite child
			for child in parent.get_children():
				if child is Sprite2D or child is AnimatedSprite2D:
					sprite = child
					break
		
		if sprite:
			sprite.modulate = Color(0.8, 0.5, 1.0, 1.0)  # Purple tint
	
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta * pulse_speed
	queue_redraw()

func _draw() -> void:
	var pulse := (sin(_time * 2.0) + 1.0) * 0.5
	_draw_heart(pulse)
	_draw_glow(pulse)

func _draw_heart(pulse: float) -> void:
	var heart_pos := Vector2(0.0, -heart_offset)
	var heart_scale := 1.0 + pulse * 0.2
	
	# Heart glow
	var glow_alpha := 0.3 + pulse * 0.2
	draw_circle(heart_pos, 16.0 * heart_scale, Color(0.9, 0.3, 0.9, glow_alpha))
	
	# Simple heart shape using circles and triangle
	var heart_color := Color(0.9, 0.3, 0.7, 0.9)
	var size := 8.0 * heart_scale
	
	# Two top circles
	draw_circle(heart_pos + Vector2(-size * 0.5, 0.0), size * 0.6, heart_color)
	draw_circle(heart_pos + Vector2(size * 0.5, 0.0), size * 0.6, heart_color)
	
	# Bottom triangle
	var points := PackedVector2Array()
	points.append(heart_pos + Vector2(-size, 0.0))
	points.append(heart_pos + Vector2(size, 0.0))
	points.append(heart_pos + Vector2(0.0, size * 1.2))
	draw_colored_polygon(points, heart_color)

func _draw_glow(pulse: float) -> void:
	# Subtle purple glow around the enemy
	var alpha := glow_intensity * (0.5 + pulse * 0.5)
	var color := Color(0.7, 0.2, 0.9, alpha)
	
	# Draw multiple layers for soft glow effect
	for i in range(3):
		var radius := 50.0 + float(i) * 15.0
		var layer_alpha := alpha * (1.0 - float(i) * 0.3)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(color.r, color.g, color.b, layer_alpha), 3.0)

func _exit_tree() -> void:
	# Remove purple tint when effect is removed
	var parent := get_parent()
	if parent:
		var sprite = parent.get_node_or_null("Sprite2D")
		if sprite == null:
			sprite = parent.get_node_or_null("AnimatedSprite2D")
		if sprite == null:
			for child in parent.get_children():
				if child is Sprite2D or child is AnimatedSprite2D:
					sprite = child
					break
		
		if sprite:
			sprite.modulate = Color.WHITE  # Reset to normal
