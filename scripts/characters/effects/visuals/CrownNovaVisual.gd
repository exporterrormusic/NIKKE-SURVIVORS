# Extracted from scripts/characters/CrownController.gd (was runtime-compiled embedded source).
extends Node2D

var max_radius: float = 800.0
var _time: float = 0.0
var _angel_wings: Array = []
var _wisps: Array = []
const DURATION: float = 1.5

func _ready() -> void:
	z_index = 200
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
			z_index = 200

	# Create ethereal angel wing tendrils - Diablo 3 style
	for i in range(24):
		var angle: float = (float(i) / 24.0) * TAU
		_angel_wings.append({
			"base_angle": angle,
			"length": randf_range(0.7, 1.0),
			"wave_offset": randf() * TAU,
			"wave_speed": randf_range(4.0, 8.0),
			"width": randf_range(0.8, 1.2),
			"segments": randi_range(8, 12)
		})
	# Floating wisps
	for i in range(40):
		_wisps.append({
			"angle": randf() * TAU,
			"dist": randf(),
			"speed": randf_range(0.5, 2.0),
			"size": randf_range(4.0, 12.0),
			"phase": randf() * TAU
		})

func _process(delta: float) -> void:
	_time += delta
	if _time >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress: float = _time / DURATION
	var ease_progress: float = 1.0 - pow(1.0 - progress, 2.5)
	var current_radius: float = max_radius * ease_progress
	
	# Alpha - bright start, graceful fade
	var alpha: float = sin(progress * PI) * 1.0
	var flash_alpha: float = pow(1.0 - progress, 1.5) * 1.5
	var wing_alpha: float = (1.0 - progress * 0.6) * 0.9
	
	# Massive outer divine glow
	draw_circle(Vector2.ZERO, current_radius * 1.2, Color(1.0, 0.8, 0.3, alpha * 0.2))
	draw_circle(Vector2.ZERO, current_radius, Color(1.0, 0.85, 0.4, alpha * 0.15))
	
	# ANGEL WINGS - flowing ethereal tendrils like Tyrael
	for wing in _angel_wings:
		var base_angle: float = wing.base_angle
		var wave_offset: float = wing.wave_offset
		var wave_speed: float = wing.wave_speed
		var wing_length: float = current_radius * wing.length
		var num_segments: int = wing.segments
		var base_width: float = 25.0 * wing.width
		
		# Draw each wing tendril as a flowing curve
		var prev_pos: Vector2 = Vector2.ZERO
		var prev_width: float = base_width * 0.3
		
		for s in range(num_segments + 1):
			var t: float = float(s) / float(num_segments)
			var seg_dist: float = wing_length * t
			
			# Flowing wave motion - more pronounced further out
			var wave_amp: float = t * t * 40.0
			var wave1: float = sin(_time * wave_speed + wave_offset + t * 4.0) * wave_amp
			var wave2: float = sin(_time * wave_speed * 0.7 + wave_offset + t * 6.0 + 1.5) * wave_amp * 0.5
			var angle_offset: float = (wave1 + wave2) / seg_dist if seg_dist > 10 else 0
			
			var seg_angle: float = base_angle + angle_offset * 0.3
			var seg_pos: Vector2 = Vector2(cos(seg_angle), sin(seg_angle)) * seg_dist
			
			# Width tapers and flows
			var seg_width: float = base_width * (1.0 - t * 0.7) * (0.8 + sin(_time * 6.0 + t * 3.0) * 0.2)
			
			if s > 0:
				# Draw ethereal wing segment
				var seg_alpha: float = wing_alpha * (1.0 - t * 0.5) * (0.7 + sin(_time * 8.0 + t * 2.0) * 0.3)
				
				# Outer glow
				draw_line(prev_pos, seg_pos, Color(1.0, 0.8, 0.3, seg_alpha * 0.3), seg_width * 2.5)
				# Main tendril
				draw_line(prev_pos, seg_pos, Color(1.0, 0.9, 0.5, seg_alpha * 0.7), seg_width * 1.2)
				# Bright core
				draw_line(prev_pos, seg_pos, Color(1.0, 1.0, 0.8, seg_alpha), seg_width * 0.5)
			
			prev_pos = seg_pos
			prev_width = seg_width
		
		# Glowing tip
		var tip_size: float = 8.0 * (0.7 + sin(_time * 10.0 + wave_offset) * 0.3) * (1.0 - progress * 0.5)
		draw_circle(prev_pos, tip_size, Color(1.0, 1.0, 0.9, wing_alpha * 0.8))
	
	# Floating ethereal wisps
	for w in _wisps:
		var wisp_dist: float = current_radius * w.dist * (0.3 + ease_progress * 0.7)
		var wisp_angle: float = w.angle + _time * w.speed * 0.5
		var wisp_pos: Vector2 = Vector2(cos(wisp_angle), sin(wisp_angle)) * wisp_dist
		
		# Wisps float and pulse
		var float_offset: Vector2 = Vector2(
			sin(_time * 3.0 + w.phase) * 15.0,
			cos(_time * 2.5 + w.phase) * 15.0
		)
		wisp_pos += float_offset
		
		var wisp_alpha: float = alpha * (0.4 + sin(_time * 5.0 + w.phase) * 0.3)
		var wisp_size: float = w.size * (0.8 + sin(_time * 8.0 + w.phase) * 0.2)
		
		draw_circle(wisp_pos, wisp_size * 1.5, Color(1.0, 0.85, 0.4, wisp_alpha * 0.3))
		draw_circle(wisp_pos, wisp_size, Color(1.0, 0.95, 0.7, wisp_alpha * 0.7))
		draw_circle(wisp_pos, wisp_size * 0.4, Color(1.0, 1.0, 0.9, wisp_alpha))
	
	# Expanding holy rings
	for i in range(3):
		var ring_delay: float = float(i) * 0.12
		var ring_progress: float = clamp((progress - ring_delay) / (1.0 - ring_delay * 2), 0.0, 1.0)
		var ring_radius: float = max_radius * ring_progress * 0.9
		var ring_alpha: float = alpha * (1.0 - float(i) * 0.25) * (1.0 - ring_progress * 0.3)
		
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 64, Color(1.0, 0.9, 0.5, ring_alpha * 0.4), 12.0 - float(i) * 3.0)
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 64, Color(1.0, 1.0, 0.8, ring_alpha * 0.6), 4.0 - float(i))
	
	# Divine center - holy light core
	var core_pulse: float = 0.8 + sin(_time * 12.0) * 0.2
	var core_size: float = 100.0 * (1.0 - progress * 0.5) * core_pulse
	draw_circle(Vector2.ZERO, core_size * 2.0, Color(1.0, 0.85, 0.4, flash_alpha * 0.3))
	draw_circle(Vector2.ZERO, core_size * 1.3, Color(1.0, 0.9, 0.5, flash_alpha * 0.5))
	draw_circle(Vector2.ZERO, core_size, Color(1.0, 0.95, 0.7, flash_alpha * 0.7))
	draw_circle(Vector2.ZERO, core_size * 0.5, Color(1.0, 1.0, 0.9, flash_alpha * 0.9))
	draw_circle(Vector2.ZERO, core_size * 0.2, Color(1.0, 1.0, 1.0, flash_alpha))
