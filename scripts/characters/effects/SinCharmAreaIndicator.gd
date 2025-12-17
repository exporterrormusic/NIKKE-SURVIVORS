extends Node2D
class_name SinCharmAreaIndicator
## Visual indicator for Sin's charm ability area of effect
## Shows purple circle at mouse position when special is ready
## Digital glitch effect when appearing, bigger animation on activation

# Configuration
var radius: float = 150.0
var base_color: Color = Color(0.6, 0.15, 0.85, 0.5)  # Purple, more visible
var edge_color: Color = Color(0.8, 0.3, 1.0, 0.8)  # Brighter purple edge

# State
var _is_visible: bool = false
var _activation_progress: float = 0.0
var _activation_duration: float = 0.4
var _is_activating: bool = false

# Glitch effect state
var _glitch_time: float = 0.0
var _glitch_duration: float = 0.25
var _is_glitching: bool = false
var _glitch_segments: Array = []  # Random segment offsets for glitch
var _glitch_intensity: float = 1.0

# Idle animation
var _idle_time: float = 0.0
var _pulse_speed: float = 2.0

# Reference to follow mouse
var _player: Node2D = null

func _ready() -> void:
	z_index = 50  # Above ground, below UI
	visible = false

func setup(player: Node2D, initial_radius: float) -> void:
	_player = player
	radius = initial_radius

func set_radius(new_radius: float) -> void:
	radius = new_radius
	queue_redraw()

func _process(delta: float) -> void:
	# Update position to mouse
	if _player and is_instance_valid(_player):
		global_position = _player.get_global_mouse_position()
	
	# Update idle animation
	_idle_time += delta * _pulse_speed
	
	# Update glitch effect
	if _is_glitching:
		_glitch_time += delta
		if _glitch_time >= _glitch_duration:
			_is_glitching = false
			_glitch_time = 0.0
			_glitch_segments.clear()
		queue_redraw()
	
	# Update activation animation
	if _is_activating:
		_activation_progress += delta / _activation_duration
		if _activation_progress >= 1.0:
			_is_activating = false
			_activation_progress = 0.0
			visible = _is_visible  # Restore normal visibility state
		queue_redraw()
	elif _is_visible:
		# PERFORMANCE: Only redraw every 3rd frame during idle state
		if Engine.get_process_frames() % 3 == 0:
			queue_redraw()

func show_indicator() -> void:
	if _is_visible:
		return
	
	_is_visible = true
	visible = true
	
	# Trigger glitch appear effect
	_start_glitch(0.6)  # Subtle glitch
	
	queue_redraw()

func hide_indicator() -> void:
	if not _is_visible:
		return
	
	_is_visible = false
	visible = false
	_is_glitching = false
	_glitch_time = 0.0
	_glitch_segments.clear()

func trigger_activation() -> void:
	## Called when special is actually used - show activation animation
	_is_activating = true
	_activation_progress = 0.0
	visible = true  # Keep visible during activation
	
	# Trigger intense glitch
	_start_glitch(1.5)  # More intense glitch

func _start_glitch(intensity: float) -> void:
	_is_glitching = true
	_glitch_time = 0.0
	_glitch_intensity = intensity
	_glitch_duration = 0.15 + intensity * 0.1
	
	# Generate random segment data for glitch effect
	_glitch_segments.clear()
	var num_segments := int(8 + intensity * 6)
	for i in range(num_segments):
		var segment := {
			"angle_start": randf() * TAU,
			"angle_span": randf() * 0.5 + 0.2,
			"offset": Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 15.0 * intensity,
			"scale": randf_range(0.9, 1.1),
			"alpha_mult": randf_range(0.5, 1.5),
			"time_offset": randf() * 0.1
		}
		_glitch_segments.append(segment)

func _draw() -> void:
	if not _is_visible and not _is_activating:
		return
	
	# Calculate pulse effect
	var pulse := sin(_idle_time) * 0.1 + 1.0
	var current_radius := radius * pulse
	
	# Activation expansion
	var activation_scale := 1.0
	var activation_alpha := 1.0
	if _is_activating:
		var t := _activation_progress
		activation_scale = 1.0 + t * 0.5  # Expand outward
		activation_alpha = 1.0 - t  # Fade out
		current_radius *= activation_scale
	
	# Main circle fill
	var fill_alpha := base_color.a * activation_alpha
	if _is_glitching:
		# Flicker during glitch
		var glitch_progress := _glitch_time / _glitch_duration
		var flicker := 1.0 + sin(glitch_progress * 50) * 0.3 * (1.0 - glitch_progress)
		fill_alpha *= flicker
	
	var fill_color := Color(base_color.r, base_color.g, base_color.b, fill_alpha)
	
	# Draw glitched segments or normal circle
	if _is_glitching and not _glitch_segments.is_empty():
		_draw_glitched_circle(current_radius, fill_color, activation_alpha)
	else:
		# Normal circle
		draw_circle(Vector2.ZERO, current_radius, fill_color)
		
		# Edge ring
		var edge_alpha := edge_color.a * activation_alpha
		draw_arc(Vector2.ZERO, current_radius, 0, TAU, 64, Color(edge_color.r, edge_color.g, edge_color.b, edge_alpha), 2.0)
		
		# Inner decorative rings
		_draw_inner_rings(current_radius, activation_alpha)
	
	# Activation burst effect
	if _is_activating:
		_draw_activation_burst(current_radius)

func _draw_glitched_circle(current_radius: float, fill_color: Color, activation_alpha: float) -> void:
	var glitch_progress := _glitch_time / _glitch_duration
	var decay := 1.0 - glitch_progress  # Effect fades over time
	
	# Draw base circle with slight offset
	var base_offset := Vector2(sin(glitch_progress * 30) * 5, cos(glitch_progress * 25) * 5) * decay * _glitch_intensity
	draw_circle(base_offset, current_radius, fill_color)
	
	# Draw glitched arc segments with RGB separation
	for segment in _glitch_segments:
		var seg_progress: float = glitch_progress - float(segment["time_offset"])
		if seg_progress < 0 or seg_progress > 1:
			continue
		
		var seg_decay: float = (1.0 - seg_progress) * decay
		var offset: Vector2 = Vector2(segment["offset"]) * seg_decay
		var seg_radius: float = current_radius * float(segment["scale"])
		var seg_alpha: float = float(segment["alpha_mult"]) * activation_alpha * seg_decay
		
		# Chromatic aberration - offset RGB channels
		var red_offset := offset + Vector2(3, 0) * _glitch_intensity
		var blue_offset := offset - Vector2(3, 0) * _glitch_intensity
		
		# Red channel arc
		draw_arc(red_offset, seg_radius, segment["angle_start"], segment["angle_start"] + segment["angle_span"], 
			16, Color(1.0, 0.2, 0.5, seg_alpha * 0.4), 3.0)
		
		# Blue channel arc
		draw_arc(blue_offset, seg_radius, segment["angle_start"], segment["angle_start"] + segment["angle_span"], 
			16, Color(0.3, 0.5, 1.0, seg_alpha * 0.4), 3.0)
		
		# Main purple arc
		draw_arc(offset, seg_radius, segment["angle_start"], segment["angle_start"] + segment["angle_span"], 
			16, Color(edge_color.r, edge_color.g, edge_color.b, seg_alpha), 2.0)
	
	# Scanline effect
	var num_lines := 8
	for i in range(num_lines):
		var y_offset := (float(i) / num_lines - 0.5) * current_radius * 2
		var line_alpha := 0.15 * decay * sin(glitch_progress * 20 + i)
		if line_alpha > 0:
			var half_width := sqrt(max(0, current_radius * current_radius - y_offset * y_offset))
			draw_line(
				Vector2(-half_width, y_offset) + base_offset, 
				Vector2(half_width, y_offset) + base_offset, 
				Color(1, 1, 1, line_alpha), 
				1.0
			)

func _draw_inner_rings(current_radius: float, activation_alpha: float) -> void:
	# Rotating dashed inner ring
	var rotation_offset := _idle_time * 0.5
	var inner_radius := current_radius * 0.7
	var dash_count := 12
	var dash_angle := TAU / dash_count * 0.6
	
	for i in range(dash_count):
		var start_angle := (float(i) / dash_count) * TAU + rotation_offset
		var ring_alpha := edge_color.a * 0.4 * activation_alpha
		draw_arc(Vector2.ZERO, inner_radius, start_angle, start_angle + dash_angle, 8, 
			Color(edge_color.r, edge_color.g, edge_color.b, ring_alpha), 1.5)
	
	# Small center indicator
	var center_radius := current_radius * 0.15
	var center_alpha := edge_color.a * 0.3 * activation_alpha
	draw_circle(Vector2.ZERO, center_radius, Color(edge_color.r, edge_color.g, edge_color.b, center_alpha))

func _draw_activation_burst(current_radius: float) -> void:
	var t := _activation_progress
	
	# Multiple expanding rings
	for i in range(3):
		var ring_delay: float = i * 0.15
		var ring_t: float = clampf((t - ring_delay) / (1.0 - ring_delay), 0.0, 1.0)
		if ring_t <= 0:
			continue
		
		var ring_radius: float = current_radius * (0.5 + ring_t * 0.8)
		var ring_alpha: float = (1.0 - ring_t) * 0.8
		var ring_width: float = 3.0 - ring_t * 2.0
		
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 48, 
			Color(1.0, 0.7, 1.0, ring_alpha), max(ring_width, 0.5))
	
	# Central flash
	var flash_alpha := (1.0 - t * t) * 0.5
	draw_circle(Vector2.ZERO, current_radius * 0.3 * (1.0 - t), Color(1.0, 0.9, 1.0, flash_alpha))
