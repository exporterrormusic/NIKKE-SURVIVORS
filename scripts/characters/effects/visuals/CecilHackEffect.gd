# Extracted from scripts/characters/CecilController.gd (was runtime-compiled embedded source).
extends Node2D

var duration: float = 1.5
var _time: float = 0.0
var _scale_mult: float = 1.0

func _ready() -> void:
	z_index = 100
	
	# Capture parent scale before reparenting (since we move to EffectsLayer)
	var parent = get_parent()
	if parent is Node2D:
		_scale_mult = maxf(parent.scale.x, parent.scale.y)
	
	# Ensure reasonable scale limits (don't get microscopic or too massive)
	_scale_mult = clampf(_scale_mult, 0.5, 4.0)
	
	# Make unshaded for maximum brightness
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Reparent to EffectsLayer to render on top of enemies
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
			z_index = 100

func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Floating cloud of fluctuating binary - "Data Upload" style
	var font = ThemeDB.fallback_font
	
	# Scale cloud and text with enemy
	var font_size := int(20 * _scale_mult)
	var num_bits := int(16 * sqrt(_scale_mult)) # Add a few more bits for huge enemies
	
	# Cloud dimensions scaled
	var x_range = 70.0 * _scale_mult
	var y_range = 70.0 * _scale_mult 
	var x_offset_base = -35.0 * _scale_mult
	var y_offset_base = -35.0 * _scale_mult # Centered vertically on anchor
	
	for i in range(num_bits):
		# Create a cloud distribution above center
		# Deterministic pseudo-random positions based on index
		var rx = sin(float(i) * 12.9898) * 43758.5453
		var ry = cos(float(i) * 78.233) * 43758.5453
		
		# range scaled
		var x_off = (rx - floor(rx)) * x_range + x_offset_base
		# range scaled
		var y_off = (ry - floor(ry)) * y_range + y_offset_base
		
		# Gentle float up over time (scaled speed) - REDUCED speed to keep it on body
		y_off -= _time * 15.0 * _scale_mult
		
		var pos = Vector2(x_off, y_off)
		
		# Fluctuate bit value rapidly (every ~0.08s)
		var flutter_time = _time + float(i) * 0.3
		var bit_val = int(flutter_time * 12.0)
		var bit = "1" if (bit_val % 2 == 0) else "0"
		
		# Fade out
		var alpha = 1.0 - (_time / duration)
		# Add subtle flicker
		alpha *= 0.7 + (sin(_time * 20.0 + float(i)) * 0.3)
		
		var color = Color(0.2, 0.95, 1.0, alpha)
		if i % 4 == 0:
			color = Color(0.6, 1.0, 0.8, alpha) # Occasional green bit
			
		draw_string(font, pos, bit, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)
