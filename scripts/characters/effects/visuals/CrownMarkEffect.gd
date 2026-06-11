# Extracted from scripts/characters/CrownController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0
const DURATION: float = 1.5

func _ready() -> void:
	z_index = 10
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 10

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var progress: float = _time / DURATION
	var pulse: float = 0.6 + sin(_time * 18.0) * 0.4
	var fast_pulse: float = 0.5 + sin(_time * 30.0) * 0.5
	
	# Brilliant saturated gold
	var deep_gold: Color = Color(1.0, 0.7, 0.0, 0.7 * pulse)
	var bright_gold: Color = Color(1.0, 0.85, 0.1, 0.9 * pulse)
	var white_hot: Color = Color(1.0, 1.0, 0.5, fast_pulse)
	
	# Growing radius as explosion approaches
	var base_radius: float = 25.0 + progress * 20.0
	
	# Outer glow ring
	draw_arc(Vector2.ZERO, base_radius * 1.3, 0, TAU, 32, 
		Color(1.0, 0.6, 0.0, 0.3 * pulse), 8.0)
	
	# Main pulsing ring
	draw_arc(Vector2.ZERO, base_radius, 0, TAU, 32, bright_gold, 4.0)
	
	# Inner bright ring
	draw_arc(Vector2.ZERO, base_radius * 0.7, 0, TAU, 24, white_hot, 2.0)
	
	# Center glow
	draw_circle(Vector2.ZERO, base_radius * 0.4, deep_gold)
	draw_circle(Vector2.ZERO, base_radius * 0.2, white_hot)
	
	# Rotating sparkles
	var num_sparkles: int = 6
	for i in range(num_sparkles):
		var angle: float = (float(i) / float(num_sparkles)) * TAU + _time * 4.0
		var sparkle_dist: float = base_radius * 0.85
		var sparkle_pos: Vector2 = Vector2(cos(angle), sin(angle)) * sparkle_dist
		var sparkle_size: float = 4.0 + sin(_time * 20.0 + float(i) * 2.0) * 2.0
		draw_circle(sparkle_pos, sparkle_size, white_hot)
