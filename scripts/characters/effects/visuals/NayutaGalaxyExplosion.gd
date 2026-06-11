# Extracted from scripts/characters/NayutaController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0
var _duration: float = 1.5
var _max_radius: float = 800.0

func _ready() -> void:
	z_index = 100
	# Use unscaled time so burst plays at full speed during time dilation
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	# Use real time instead of scaled delta for consistent animation speed
	var real_delta = _delta
	if Engine.time_scale > 0.01:
		real_delta = _delta / Engine.time_scale
	else:
		real_delta = 1.0 / 60.0  # Fallback during complete freeze
	
	_time += real_delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	var radius := _max_radius * ease(progress, 0.3)
	var alpha := 1.0 - progress
	
	# Deep purple galaxy colors
	var inner_color := Color(0.6, 0.2, 1.0, alpha * 0.8)
	var mid_color := Color(0.4, 0.1, 0.8, alpha * 0.5)
	var outer_color := Color(0.2, 0.05, 0.5, alpha * 0.3)
	
	# Draw expanding circles
	draw_circle(Vector2.ZERO, radius * 0.3, inner_color)
	draw_circle(Vector2.ZERO, radius * 0.6, mid_color)
	draw_circle(Vector2.ZERO, radius, outer_color)
	
	# Draw swirling stars (reduced from 30 to 15 for performance)
	var num_stars := 15
	for i in range(num_stars):
		var angle := (TAU / num_stars) * i + _time * 3.0 + i * 0.2
		var star_dist := radius * (0.3 + 0.6 * (float(i) / num_stars))
		var star_pos := Vector2(cos(angle), sin(angle)) * star_dist
		var star_size := 3.0 + sin(_time * 5.0 + i) * 2.0
		var star_alpha := alpha * (0.5 + 0.5 * sin(_time * 4.0 + i * 0.5))
		draw_circle(star_pos, star_size, Color(1.0, 0.8, 1.0, star_alpha))
	
	# Draw spiral arms (reduced from 3 to 2 arms, 20 to 12 segments for performance)
	for arm in range(2):
		var arm_base_angle := (TAU / 2.0) * arm + _time * 2.0
		for seg in range(12):
			var seg_progress := float(seg) / 12.0
			var spiral_angle := arm_base_angle + seg_progress * PI
			var spiral_radius := radius * seg_progress * 0.9
			var pos := Vector2(cos(spiral_angle), sin(spiral_angle)) * spiral_radius
			var seg_alpha := alpha * (1.0 - seg_progress) * 0.6
			draw_circle(pos, 4.0 - seg_progress * 2.0, Color(0.8, 0.5, 1.0, seg_alpha))
