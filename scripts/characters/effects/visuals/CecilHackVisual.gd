# Extracted from scripts/characters/CecilController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0

func _ready() -> void:
	z_index = 10
	# Make unshaded for maximum brightness
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var font = ThemeDB.fallback_font
	var font_size = 14
	var num_bits = 8
	
	# Rotate rings of binary code
	for i in range(num_bits):
		var angle = (TAU / num_bits) * i + _time * 2.5
		var radius = 35.0 + sin(_time * 4.0 + float(i)) * 5.0
		
		var pos = Vector2(cos(angle), sin(angle)) * radius
		# Center the text
		pos -= Vector2(4, 8) 
		
		var alpha = 0.7 + sin(_time * 5.0 + float(i)) * 0.3
		var color = Color(0.1, 0.9, 0.5, alpha) # Matrix Green-ish Blue mix
		if i % 3 == 0:
			color = Color(0.1, 0.9, 1.0, alpha) # Cyan accent
			
		# Flip bits randomly-ish based on time
		var bit = "1" if (int(_time * 10.0 + i) % 2 == 0) else "0"
		
		draw_string(font, pos, bit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		
	# Inner faster ring
	for j in range(6):
		var angle = -(TAU / 6.0) * j - _time * 3.5
		var radius = 20.0
		var pos = Vector2(cos(angle), sin(angle)) * radius - Vector2(4, 8)
		var color = Color(0.1, 1.0, 0.8, 0.8)
		var bit = "0" if (j % 2 == 0) else "1"
		draw_string(font, pos, bit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
