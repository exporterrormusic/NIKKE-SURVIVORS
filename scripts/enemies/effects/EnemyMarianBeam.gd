extends Node2D
class_name EnemyMarianBeam

## Enemy version of Marian's beam - targets a node instead of following mouse
## Used by Future Marian boss enemy

signal beam_ended

@export var duration: float = 4.0
@export var beam_range: float = 2000.0
@export var beam_width: float = 80.0  # Narrower beam (normal attack, not burst)
@export var damage_per_second: float = 3.3  # ~0.5 damage per tick
@export var damage_tick_interval: float = 0.15
@export var charge_time: float = 1.5  # Charge-up before firing

# Colors (purple-tinted for Future Marian)
var core_color := Color(0.9, 0.7, 1.0, 1.0)
var inner_color := Color(0.7, 0.3, 1.0, 0.95)
var outer_color := Color(0.5, 0.1, 0.9, 0.7)
var edge_color := Color(0.3, 0.0, 0.6, 0.5)

var owner_enemy: Node2D = null
var target_node: Node2D = null
var initial_direction: Vector2 = Vector2.RIGHT

var _age: float = 0.0
var _damage_timer: float = 0.0
var _beam_direction: Vector2 = Vector2.RIGHT
var _target_direction: Vector2 = Vector2.RIGHT
var _turn_speed: float = 0.8  # Slow turn so player can dodge
var _is_charging: bool = true  # Start in charging phase

# Visual effects
var _particles: Array = []
var _ring_phase: float = 0.0

func _ready() -> void:
	z_index = 100
	
	# Initial direction
	if initial_direction != Vector2.ZERO:
		_beam_direction = initial_direction.normalized()
		_target_direction = _beam_direction

func _process(delta: float) -> void:
	_age += delta
	
	# Charge-up phase
	if _is_charging:
		if _age >= charge_time:
			_is_charging = false
			_age = 0.0  # Reset age for beam duration
		queue_redraw()
		return
	
	if _age >= duration:
		beam_ended.emit()
		queue_free()
		return
	
	# Update beam direction to slowly track target
	_update_beam_direction(delta)
	
	# Follow owner position
	if owner_enemy and is_instance_valid(owner_enemy):
		global_position = owner_enemy.global_position + _beam_direction * 40.0
	
	# Deal damage to player
	_damage_timer += delta
	if _damage_timer >= damage_tick_interval:
		_damage_timer = 0.0
		_deal_beam_damage()
	
	# Update particles
	_update_particles(delta)
	_ring_phase += delta * 8.0
	
	queue_redraw()

func _update_beam_direction(delta: float) -> void:
	if target_node and is_instance_valid(target_node):
		var to_target := target_node.global_position - global_position
		if to_target.length() > 10.0:
			_target_direction = to_target.normalized()
	
	# Slowly rotate toward target (makes it dodgeable)
	_beam_direction = _beam_direction.lerp(_target_direction, _turn_speed * delta).normalized()

func _deal_beam_damage() -> void:
	# Only damage the player
	if not target_node or not is_instance_valid(target_node):
		return
	
	var damage_this_tick := int(damage_per_second * damage_tick_interval)
	
	# Check if player is in beam
	if _is_point_in_beam(target_node.global_position):
		if target_node.has_method("take_damage"):
			target_node.take_damage(damage_this_tick)

func _is_point_in_beam(point: Vector2) -> bool:
	var to_point := point - global_position
	var along_beam := to_point.dot(_beam_direction)
	
	# Must be in front and within actual visual range
	var current_range := _get_beam_end_distance()
	if along_beam < 0 or along_beam > current_range:
		return false
	
	# Check perpendicular distance
	var perp: float = abs(to_point.dot(_beam_direction.orthogonal()))
	var width_at_point := beam_width * 0.5
	
	return perp <= width_at_point

func _get_beam_end_distance() -> float:
	"""Calculate the effective beam length, stopping at the first boulder collision."""
	var effective_range := beam_range
	var boulders := TargetCache.get_boulders()
	
	# Use owner position as beam origin
	var beam_origin: Vector2 = global_position
	if owner_enemy and is_instance_valid(owner_enemy):
		beam_origin = owner_enemy.global_position
	
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		
		# Perform a simplified raycast logic against the boulder
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		var hit_radius := boulder_radius + beam_width * 0.5
		
		var to_boulder := boulder_pos - beam_origin
		var along := to_boulder.dot(_beam_direction)
		
		# If boulder is behind us or too far, skip
		if along < 0 or along > effective_range + hit_radius:
			continue
			
		# Check if we are aiming at it (perpendicular distance)
		var perp: float = abs(to_boulder.dot(_beam_direction.orthogonal()))
		if perp < hit_radius:
			# We hit this boulder!
			# The hit point is roughly 'along' minus the part of the boulder facing us
			# Use circle intersection approximation to find exact hit distance
			var dist_to_hit := along - sqrt(max(0, hit_radius*hit_radius - perp*perp))
			if dist_to_hit < effective_range:
				effective_range = max(0, dist_to_hit)
	
	# Subtract offset (since global_position is 40px ahead of owner)
	# beam_range is relative to global_position, but along calculation was from owner
	# So if we hit at 500 from owner, and we are at 40 from owner, our draw length is 460
	if owner_enemy and is_instance_valid(owner_enemy):
		var offset_dist := global_position.distance_to(beam_origin)
		effective_range = max(0, effective_range - offset_dist)
		
	return effective_range

func _is_boulder_blocking(distance_along_beam: float) -> bool:
	# Deprecated: use _get_beam_end_distance() instead for unified logic
	return false

func _update_particles(delta: float) -> void:
	# Update existing particles
	for i in range(_particles.size() - 1, -1, -1):
		var p = _particles[i]
		p["age"] += delta
		if p["age"] >= p["lifespan"]:
			_particles.remove_at(i)
			continue
		p["pos"] += p["vel"] * delta
		_particles[i] = p
	
	# Spawn new particles along beam
	if randf() < 0.7:
		var dist := randf() * beam_range
		var offset := _beam_direction.orthogonal() * randf_range(-beam_width * 0.3, beam_width * 0.3)
		var particle := {
			"pos": _beam_direction * dist + offset,
			"vel": _beam_direction.orthogonal() * randf_range(-50, 50) + Vector2(0, -30),
			"size": randf_range(3, 7),
			"age": 0.0,
			"lifespan": randf_range(0.3, 0.6),
			"color": Color(1.0, 0.4, 0.5, 0.8) if randf() > 0.3 else Color(1.0, 0.8, 0.8, 0.9)
		}
		_particles.append(particle)

func _draw() -> void:
	# Draw charge-up effect during charging phase
	if _is_charging:
		var charge_progress := _age / charge_time
		_draw_charge_up(charge_progress)
		return
	
	var progress := _age / duration
	var intensity := 1.0
	
	# Fade in at start, fade out at end
	if progress < 0.1:
		intensity = progress / 0.1
	elif progress > 0.85:
		intensity = (1.0 - progress) / 0.15
	
	# Draw the beam layers
	_draw_beam(intensity)
	
	# Draw particles
	_draw_particles(intensity)
	
	# Draw energy rings
	_draw_energy_rings(intensity)
	
	# Draw origin burst effect
	_draw_origin_effect(intensity)

func _draw_charge_up(progress: float) -> void:
	# Growing energy orb at origin
	var orb_size := 20.0 + progress * 60.0
	var pulse := sin(_age * 15.0) * 0.2 + 0.8
	
	# Outer glow
	draw_circle(Vector2.ZERO, orb_size * 1.5, Color(outer_color.r, outer_color.g, outer_color.b, 0.2 * pulse))
	draw_circle(Vector2.ZERO, orb_size * 1.2, Color(inner_color.r, inner_color.g, inner_color.b, 0.4 * pulse))
	draw_circle(Vector2.ZERO, orb_size, Color(core_color.r, core_color.g, core_color.b, 0.7 * pulse))
	
	# Draw charging line preview (thin line showing where beam will fire)
	var line_alpha := progress * 0.5
	var line_length := beam_range * progress
	var line_end := _beam_direction * line_length
	draw_line(Vector2.ZERO, line_end, Color(inner_color.r, inner_color.g, inner_color.b, line_alpha), 3.0, true)
	
	# Energy sparks converging to center
	for i in range(6):
		var angle := TAU * float(i) / 6.0 + _age * 3.0
		var dist := (1.0 - progress) * 80.0 + 20.0
		var spark_pos := Vector2(cos(angle), sin(angle)) * dist
		draw_circle(spark_pos, 4.0 + progress * 4.0, Color(inner_color.r, inner_color.g, inner_color.b, 0.6))

func _draw_beam(intensity: float) -> void:
	var current_range := _get_beam_end_distance()
	var beam_end := _beam_direction * current_range
	var perp := _beam_direction.orthogonal()
	
	# Multiple layers from outer to inner
	var layers := [
		{"width": beam_width * 1.2, "color": edge_color},
		{"width": beam_width * 1.0, "color": outer_color},
		{"width": beam_width * 0.7, "color": inner_color},
		{"width": beam_width * 0.4, "color": core_color},
	]
	
	for layer in layers:
		var w: float = layer["width"] * 0.5
		var c: Color = layer["color"]
		c.a *= intensity
		
		# Create beam polygon
		var points := PackedVector2Array([
			perp * w,
			-perp * w,
			beam_end - perp * w * 0.8,
			beam_end + perp * w * 0.8,
		])
		
		var colors := PackedColorArray([c, c, c, c])
		draw_polygon(points, colors)
	
	# Draw bright edge lines
	var edge_c := Color(inner_color.r, inner_color.g, inner_color.b, 0.6 * intensity)
	draw_line(perp * beam_width * 0.5, beam_end + perp * beam_width * 0.4, edge_c, 3.0, true)
	draw_line(-perp * beam_width * 0.5, beam_end - perp * beam_width * 0.4, edge_c, 3.0, true)

func _draw_particles(intensity: float) -> void:
	for p in _particles:
		var alpha: float = (1.0 - float(p["age"]) / float(p["lifespan"])) * intensity
		var c: Color = p["color"]
		c.a *= alpha
		draw_circle(p["pos"], p["size"], c)

func _draw_energy_rings(intensity: float) -> void:
	var current_range := _get_beam_end_distance()
	var ring_count := 4
	var ring_spacing := beam_range / float(ring_count) # Keep spacing constant to avoid jitter
	
	for i in range(ring_count):
		var ring_pos := fmod(_ring_phase * 200.0 + float(i) * ring_spacing, beam_range)
		if ring_pos > current_range: continue # Don't draw past block
		
		var ring_center := _beam_direction * ring_pos
		var ring_size := beam_width * 0.35 * (1.0 - ring_pos / beam_range * 0.3)
		
		var ring_alpha := 0.4 * intensity * (1.0 - ring_pos / beam_range * 0.5)
		var ring_color := Color(inner_color.r, inner_color.g, inner_color.b, ring_alpha)
		
		_draw_ring(ring_center, ring_size, ring_color, 2.0)

func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments := 20
	var perp := _beam_direction.orthogonal()
	var prev_pt := center + perp * radius
	
	for i in range(1, segments + 1):
		var angle := TAU * float(i) / float(segments)
		var local := Vector2(cos(angle) * 0.3, sin(angle)) * radius
		var pt := center + _beam_direction * local.x + perp * local.y
		draw_line(prev_pt, pt, color, width, true)
		prev_pt = pt

func _draw_origin_effect(intensity: float) -> void:
	var pulse := 0.7 + 0.3 * sin(_age * 10.0)
	
	draw_circle(Vector2.ZERO, beam_width * 0.6 * pulse, Color(outer_color.r, outer_color.g, outer_color.b, 0.3 * intensity))
	draw_circle(Vector2.ZERO, beam_width * 0.4 * pulse, Color(inner_color.r, inner_color.g, inner_color.b, 0.5 * intensity))
	draw_circle(Vector2.ZERO, beam_width * 0.25 * pulse, Color(core_color.r, core_color.g, core_color.b, 0.8 * intensity))
