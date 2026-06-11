# Extracted from scripts/characters/NayutaController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0

func _ready() -> void:
	z_index = 50
	# Use unscaled time for consistent animation during time dilation
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	# Use real time instead of scaled delta
	var real_delta = _delta
	if Engine.time_scale > 0.01:
		real_delta = _delta / Engine.time_scale
	else:
		real_delta = 1.0 / 60.0
	_time += real_delta
	queue_redraw()

func _draw() -> void:
	# Purple galaxy star effect around debuffed enemy (reduced from 6 to 4 stars)
	var num_stars := 4
	for i in range(num_stars):
		var angle := (TAU / num_stars) * i + _time * 2.0
		var radius := 25.0 + sin(_time * 3.0 + i) * 5.0
		var pos := Vector2(cos(angle), sin(angle)) * radius
		var star_alpha := 0.6 + 0.3 * sin(_time * 4.0 + i * 0.7)
		
		# Draw star shape
		var star_size := 4.0
		draw_circle(pos, star_size, Color(0.7, 0.3, 1.0, star_alpha))
		
		# Twinkle lines removed for performance
	
	# Outer ring (reduced segments from 32 to 16)
	var ring_alpha := 0.3 + 0.1 * sin(_time * 2.0)
	draw_arc(Vector2.ZERO, 35.0, 0, TAU, 16, Color(0.5, 0.2, 0.8, ring_alpha), 2.0)
