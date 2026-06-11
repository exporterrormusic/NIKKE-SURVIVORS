# Extracted from scripts/characters/CrownController.gd (was runtime-compiled embedded source).
extends Node2D

var beam_width: float = 120.0
var beam_length: float = 2000.0
var _time: float = 0.0

func _ready() -> void:
	z_index = 180
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
			z_index = 180

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var pulse: float = 0.85 + sin(_time * 15.0) * 0.15
	var fast_pulse: float = 0.7 + sin(_time * 40.0) * 0.3
	
	# Brilliant saturated gold colors
	var deep_gold: Color = Color(1.0, 0.7, 0.0, 0.6 * pulse)
	var bright_gold: Color = Color(1.0, 0.85, 0.1, 0.8 * pulse)
	var white_hot: Color = Color(1.0, 1.0, 0.6, 0.95 * fast_pulse)
	
	var half_width: float = beam_width * 0.5
	
	# Outer glow (widest, most transparent)
	var outer_rect: Rect2 = Rect2(0, -half_width * 1.5, beam_length, beam_width * 1.5)
	draw_rect(outer_rect, Color(1.0, 0.6, 0.0, 0.2 * pulse))
	
	# Main beam body - deep gold
	var main_rect: Rect2 = Rect2(0, -half_width, beam_length, beam_width)
	draw_rect(main_rect, deep_gold)
	
	# Middle layer - bright gold
	var mid_rect: Rect2 = Rect2(0, -half_width * 0.7, beam_length, beam_width * 0.7)
	draw_rect(mid_rect, bright_gold)
	
	# Core - white hot center
	var core_rect: Rect2 = Rect2(0, -half_width * 0.35, beam_length, beam_width * 0.35)
	draw_rect(core_rect, white_hot)
	
	# Pulsing energy lines along beam
	for i in range(3):
		var y_offset: float = (float(i) - 1.0) * half_width * 0.5
		var line_pulse: float = sin(_time * 25.0 + float(i) * 2.0) * 0.3 + 0.7
		draw_line(Vector2(0, y_offset), Vector2(beam_length, y_offset), 
			Color(1.0, 1.0, 0.8, line_pulse * 0.6), 2.0)
	
	# Glowing edges
	draw_line(Vector2(0, -half_width), Vector2(beam_length, -half_width), white_hot, 4.0)
	draw_line(Vector2(0, half_width), Vector2(beam_length, half_width), white_hot, 4.0)
	
	# Origin flash/flare
	draw_circle(Vector2.ZERO, beam_width * 0.8, Color(1.0, 0.9, 0.3, 0.6 * pulse))
	draw_circle(Vector2.ZERO, beam_width * 0.5, Color(1.0, 0.95, 0.5, 0.8 * pulse))
	draw_circle(Vector2.ZERO, beam_width * 0.25, white_hot)
	
	# Energy particles traveling along beam
	for i in range(10):
		var particle_x: float = fmod(_time * 800.0 + float(i) * 200.0, beam_length)
		var particle_y: float = sin(_time * 10.0 + float(i)) * half_width * 0.3
		var particle_size: float = 8.0 + sin(_time * 15.0 + float(i) * 3.0) * 3.0
		draw_circle(Vector2(particle_x, particle_y), particle_size, white_hot)
