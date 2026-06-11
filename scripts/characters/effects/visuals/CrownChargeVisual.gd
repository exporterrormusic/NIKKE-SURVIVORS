# Extracted from scripts/characters/CrownController.gd (was runtime-compiled embedded source).
extends Node2D

var charge_length: float = 175.0
var charge_width: float = 125.0
var _time: float = 0.0
var _particles: Array = []
var _wisps: Array = []

func _ready() -> void:
	z_index = 150
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
			z_index = 150

	# Initialize particle trails
	for i in range(25):
		_particles.append({
			"pos": Vector2(randf_range(-50, 0), randf_range(-30, 30)),
			"vel": Vector2(randf_range(-200, -100), randf_range(-50, 50)),
			"life": randf(),
			"size": randf_range(3, 8)
		})
	# Initialize flowing wisps for edges
	for i in range(12):
		_wisps.append({
			"offset": randf() * TAU,
			"speed": randf_range(3.0, 6.0),
			"amplitude": randf_range(15.0, 35.0),
			"side": 1 if i % 2 == 0 else -1
		})

func _process(delta: float) -> void:
	_time += delta
	for p in _particles:
		p.life -= delta * 2.0
		p.pos += p.vel * delta
		if p.life <= 0:
			p.pos = Vector2(randf_range(0, 50), randf_range(-20, 20))
			p.vel = Vector2(randf_range(-300, -150), randf_range(-80, 80))
			p.life = 1.0
			p.size = randf_range(4, 10)
	queue_redraw()

func _draw() -> void:
	var gold: Color = Color(1.0, 0.8, 0.0, 0.95)
	var white_gold: Color = Color(1.0, 1.0, 0.7, 1.0)
	
	# Hard tip point at the front
	var tip: Vector2 = Vector2(charge_length, 0)
	
	# Draw flowing ethereal edges - curves that get more wavy further from tip
	var num_edge_points: int = 20
	var left_edge: PackedVector2Array = PackedVector2Array()
	var right_edge: PackedVector2Array = PackedVector2Array()
	
	left_edge.append(tip)
	right_edge.append(tip)
	
	for i in range(1, num_edge_points + 1):
		var t: float = float(i) / float(num_edge_points)
		var x_pos: float = charge_length * (1.0 - t)
		# Width expands from tip toward player
		var base_y: float = (30.0 + charge_width * 0.5 * t)
		
		# Flowing wave amplitude increases with distance from tip
		var wave_strength: float = t * t * 25.0
		var wave1: float = sin(_time * 8.0 + t * 6.0) * wave_strength
		var wave2: float = sin(_time * 12.0 + t * 4.0 + 1.5) * wave_strength * 0.5
		var wave3: float = sin(_time * 5.0 + t * 8.0 + 3.0) * wave_strength * 0.3
		var total_wave: float = wave1 + wave2 + wave3
		
		left_edge.append(Vector2(x_pos, -base_y + total_wave))
		right_edge.append(Vector2(x_pos, base_y - total_wave))
	
	# Build polygon from edges
	var poly_points: PackedVector2Array = PackedVector2Array()
	for pt in left_edge:
		poly_points.append(pt)
	for i in range(right_edge.size() - 1, -1, -1):
		poly_points.append(right_edge[i])
	
	# Outer ethereal glow
	var glow_points: PackedVector2Array = PackedVector2Array()
	glow_points.append(tip * 1.1)
	for i in range(1, num_edge_points + 1):
		var t: float = float(i) / float(num_edge_points)
		var x_pos: float = charge_length * (1.0 - t) * 1.05
		var base_y: float = (40.0 + charge_width * 0.6 * t)
		var wave: float = sin(_time * 6.0 + t * 5.0) * t * t * 30.0
		glow_points.append(Vector2(x_pos, -base_y + wave))
	for i in range(num_edge_points, 0, -1):
		var t: float = float(i) / float(num_edge_points)
		var x_pos: float = charge_length * (1.0 - t) * 1.05
		var base_y: float = (40.0 + charge_width * 0.6 * t)
		var wave: float = sin(_time * 6.0 + t * 5.0) * t * t * 30.0
		glow_points.append(Vector2(x_pos, base_y - wave))
	draw_colored_polygon(glow_points, Color(1.0, 0.7, 0.0, 0.25))
	
	# Main V body
	draw_colored_polygon(poly_points, gold)
	
	# Inner bright core
	var core_points: PackedVector2Array = PackedVector2Array()
	core_points.append(tip * 0.9)
	for i in range(1, 12):
		var t: float = float(i) / 12.0
		var x_pos: float = charge_length * (1.0 - t) * 0.8
		var base_y: float = (15.0 + charge_width * 0.2 * t)
		var wave: float = sin(_time * 10.0 + t * 4.0) * t * 10.0
		core_points.append(Vector2(x_pos, -base_y + wave))
	for i in range(11, -1, -1):
		var t: float = float(i) / 12.0
		var x_pos: float = charge_length * (1.0 - t) * 0.8
		var base_y: float = (15.0 + charge_width * 0.2 * t)
		var wave: float = sin(_time * 10.0 + t * 4.0) * t * 10.0
		core_points.append(Vector2(x_pos, base_y - wave))
	var pulse: float = 0.8 + sin(_time * 15.0) * 0.2
	draw_colored_polygon(core_points, Color(1.0, 1.0, 0.8, pulse))
	
	# Glowing tip
	draw_circle(tip, 15.0, white_gold)
	draw_circle(tip, 8.0, Color(1.0, 1.0, 1.0, 1.0))
	draw_circle(tip, 6.0, Color(1.0, 1.0, 1.0, 1.0))
	
	# Flowing edge lines with wisps
	for i in range(left_edge.size() - 1):
		var t: float = float(i) / float(left_edge.size())
		var alpha: float = 1.0 - t * 0.5
		draw_line(left_edge[i], left_edge[i + 1], Color(1.0, 1.0, 0.8, alpha), 3.0 - t * 2.0)
		draw_line(right_edge[i], right_edge[i + 1], Color(1.0, 1.0, 0.8, alpha), 3.0 - t * 2.0)
	
	# Ethereal wisps flowing off edges
	for w in _wisps:
		var wisp_t: float = fmod(_time * w.speed + w.offset, 1.0)
		var edge_idx: int = int(wisp_t * (left_edge.size() - 1))
		var edge: PackedVector2Array = left_edge if w.side > 0 else right_edge
		if edge_idx < edge.size():
			var base_pos: Vector2 = edge[edge_idx]
			var wisp_offset: Vector2 = Vector2(-20, w.side * w.amplitude * sin(_time * 4.0 + w.offset))
			var wisp_alpha: float = sin(wisp_t * PI) * 0.6
			draw_circle(base_pos + wisp_offset, 8.0, Color(1.0, 0.95, 0.6, wisp_alpha))
	
	# Sparkle particles
	for p in _particles:
		var alpha: float = p.life * 0.9
		draw_circle(p.pos, p.size * p.life, Color(1.0, 0.95, 0.5, alpha))
	
	# Ethereal horse
	var horse_pulse: float = 0.5 + sin(_time * 6.0) * 0.3
	var horse_color: Color = Color(1.0, 0.85, 0.3, horse_pulse * 0.7)
	var horse_bright: Color = Color(1.0, 0.95, 0.6, horse_pulse * 0.5)
	draw_circle(Vector2(-60, -5), 30, horse_color)
	draw_circle(Vector2(-55, -25), 12, horse_bright)
	draw_line(Vector2(-60, 5), Vector2(-100, 15), horse_color, 18.0)
	draw_circle(Vector2(-130, 15), 45, horse_color)
	draw_circle(Vector2(-130, 15), 25, horse_bright)
	for i in range(6):
		var mane_y: float = -25 + i * 8
		var wave: float = sin(_time * 8.0 + float(i) * 0.8) * 15.0
		var mane_alpha: float = 0.4 + sin(_time * 12.0 + float(i)) * 0.2
		draw_line(Vector2(-65, mane_y), Vector2(-95 + wave, mane_y - 20 + wave * 0.3), 
			Color(1.0, 0.95, 0.6, mane_alpha), 5.0 - float(i) * 0.5)
