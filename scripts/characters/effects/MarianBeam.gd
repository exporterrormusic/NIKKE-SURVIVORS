extends Node2D
class_name MarianBeam

## Marian's epic purple laser beam burst
## Aimable continuous beam that follows mouse, deals damage over time
## With upgrades: fires homing missiles, leaves burning trail

signal beam_ended

# Preload missile scene for homing upgrade
const MissileScene = preload("res://scenes/effects/Missile.tscn")

@export var duration: float = 5.0
@export var beam_range: float = 1500.0
@export var beam_width: float = 240.0
@export var damage_per_second: float = 40.0
@export var damage_tick_interval: float = 0.1

# Colors
var core_color := Color(1.0, 0.9, 1.0, 1.0)
var inner_color := Color(0.8, 0.4, 1.0, 0.95)
var outer_color := Color(0.5, 0.1, 0.9, 0.7)
var edge_color := Color(0.3, 0.0, 0.6, 0.5)

var owner_node: Node = null
var player_ref: Node2D = null  # Reference to player for position tracking
var _age: float = 0.0
var _damage_timer: float = 0.0
var _beam_direction: Vector2 = Vector2.RIGHT
var _target_direction: Vector2 = Vector2.RIGHT
var _turn_speed: float = 4.0  # How fast beam follows mouse

# Upgrade states
var missile_upgrade: bool = false  # Left upgrade: fire homing missiles
var trail_upgrade: bool = false    # Right upgrade: leave burning trail

var _missile_timer: float = 0.0
var _missiles_per_volley: int = 4
var _missile_volleys_fired: int = 0  # Track volleys (fire at 0.1s and 3.1s)

var _burn_area: Node2D = null  # Burn area with rectangular coverage
const BURN_CHARGE_TIME: float = 1.0  # Seconds of continuous coverage needed

# Shader material
var _shader_material: ShaderMaterial = null

# Visual particles
var _particles: Array = []
var _ring_phase: float = 0.0

func _ready() -> void:
	z_index = 500
	
	# Load beam shader
	var shader = load("res://resources/shaders/marian_beam.gdshader")
	if shader:
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = shader
	
	# Initial direction toward mouse
	if owner_node:
		var mouse_pos := get_global_mouse_position()
		_beam_direction = (mouse_pos - global_position).normalized()
		_target_direction = _beam_direction

func _process(delta: float) -> void:
	_age += delta
	
	if _age >= duration:
		beam_ended.emit()
		queue_free()
		return
	
	# Update beam direction to follow mouse
	_update_beam_direction(delta)
	
	# Deal damage
	_damage_timer += delta
	if _damage_timer >= damage_tick_interval:
		_damage_timer = 0.0
		_deal_beam_damage()
	
	# Handle missile upgrade - fire 4 missiles twice during burst (at start and after 3s)
	if missile_upgrade:
		_missile_timer += delta
		# Fire at 0.1s (initial) and 3.1s (second volley)
		if (_missile_volleys_fired == 0 and _age >= 0.1) or (_missile_volleys_fired == 1 and _age >= 3.1):
			_missile_volleys_fired += 1
			_fire_homing_missiles()
	
	# Handle trail upgrade - record beam positions for burn area
	if trail_upgrade:
		_record_burn_positions()
	
	# Update particles
	_update_particles(delta)
	_ring_phase += delta * 8.0
	
	queue_redraw()

func _update_beam_direction(delta: float) -> void:
	# Update position to follow player
	if player_ref and is_instance_valid(player_ref):
		global_position = player_ref.global_position + _beam_direction * 80.0  # Offset further in front of player
	
	# Get mouse position and calculate target direction
	var mouse_pos := get_global_mouse_position()
	var player_pos := global_position
	if player_ref and is_instance_valid(player_ref):
		player_pos = player_ref.global_position
	var to_mouse := mouse_pos - player_pos
	
	if to_mouse.length() > 10.0:
		_target_direction = to_mouse.normalized()
	
	# Smoothly rotate beam toward target
	_beam_direction = _beam_direction.lerp(_target_direction, _turn_speed * delta).normalized()
	
	# Update position again with new direction
	if player_ref and is_instance_valid(player_ref):
		global_position = player_ref.global_position + _beam_direction * 80.0

func _deal_beam_damage() -> void:
	var tree := get_tree()
	if not tree:
		return
	
	var enemies := tree.get_nodes_in_group("enemies")
	var damage_this_tick := int(damage_per_second * damage_tick_interval)
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_node := enemy as Node2D
		
		# Check if enemy is within beam
		if _is_point_in_beam(enemy_node.global_position):
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage_this_tick, false, _beam_direction, true)
			elif "hp" in enemy:
				enemy.hp -= damage_this_tick

func _is_point_in_beam(point: Vector2) -> bool:
	var to_point := point - global_position
	var along_beam := to_point.dot(_beam_direction)
	
	# Must be in front and within range
	if along_beam < 0 or along_beam > beam_range:
		return false
	
	# Check perpendicular distance
	var perp: float = abs(to_point.dot(_beam_direction.orthogonal()))
	var width_at_point := beam_width * 0.5  # Half width
	
	return perp <= width_at_point

func _fire_homing_missiles() -> void:
	# Find the 4 closest enemy targets
	var tree := get_tree()
	if not tree:
		return
	
	var enemies := tree.get_nodes_in_group("enemies")
	if enemies.is_empty():
		return
	
	# Sort by distance and take closest 4
	var player_pos: Vector2 = global_position
	if player_ref and is_instance_valid(player_ref):
		player_pos = player_ref.global_position
	
	enemies.sort_custom(func(a, b): return a.global_position.distance_squared_to(player_pos) < b.global_position.distance_squared_to(player_pos))
	var targets := enemies.slice(0, mini(_missiles_per_volley, enemies.size()))
	
	# Spawn missiles
	for i in range(targets.size()):
		var target = targets[i]
		if not is_instance_valid(target):
			continue
		
		var missile = MissileScene.instantiate()
		get_parent().add_child(missile)
		
		# Spawn from player position with offset
		var angle := float(i) * TAU / float(_missiles_per_volley) + _age
		var offset := Vector2(cos(angle), sin(angle)) * 40.0
		missile.global_position = global_position + offset
		
		# Calculate direction to target for initial velocity
		var dir_to_target: Vector2 = (target.global_position - missile.global_position).normalized()
		
		# Configure ExplosiveProjectile properties
		if "owner_node" in missile:
			missile.owner_node = owner_node
		if "target_node" in missile:
			missile.target_node = target
		if "target_position" in missile:
			missile.target_position = target.global_position
		if "direction" in missile:
			missile.direction = dir_to_target
		if "explode_at_target" in missile:
			missile.explode_at_target = true
		if "speed" in missile:
			missile.speed = 500.0
		if "acceleration" in missile:
			missile.acceleration = 1200.0
		if "max_speed" in missile:
			missile.max_speed = 1500.0
		if "explosion_damage" in missile:
			missile.explosion_damage = 25

func _record_burn_positions() -> void:
	# Create burn area on first frame if needed
	if not _burn_area or not is_instance_valid(_burn_area):
		_create_burn_area()
	
	var delta := get_process_delta_time()
	var base_pos: Vector2 = global_position
	if player_ref and is_instance_valid(player_ref):
		base_pos = player_ref.global_position
	
	# Get the current beam rectangle corners
	var beam_perp := Vector2(-_beam_direction.y, _beam_direction.x)
	var half_width := beam_width * 0.5
	var beam_end := base_pos + _beam_direction * beam_range
	
	# Four corners of beam rectangle
	var corners := [
		base_pos + beam_perp * half_width,
		base_pos - beam_perp * half_width,
		beam_end - beam_perp * half_width,
		beam_end + beam_perp * half_width
	]
	
	# Pass beam rect to burn area for charging
	if _burn_area.has_method("update_beam_coverage"):
		_burn_area.update_beam_coverage(corners, _beam_direction, beam_width, beam_range, base_pos, delta, BURN_CHARGE_TIME)

func _create_burn_area() -> void:
	_burn_area = Node2D.new()
	_burn_area.set_script(_get_burn_area_script())
	_burn_area.z_index = 5
	_burn_area.global_position = Vector2.ZERO  # Keep at origin, use global coords
	get_parent().add_child(_burn_area)

func _get_burn_area_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = 'extends Node2D

# Store burn rectangles with their spawn time
var burn_rects: Array = []  # Array of {corners: Array, time: float, direction: Vector2, width: float}
var point_lifespan: float = 5.0
var _damage_timer: float = 0.0
var _current_time: float = 0.0
var _shader: Shader = null

# Charging system - track how long beam has been in roughly same position
var _charge_time: float = 0.0
var _last_direction: Vector2 = Vector2.ZERO
var _last_base_pos: Vector2 = Vector2.ZERO
var _charging_corners: Array = []

func _ready() -> void:
	_shader = load("res://resources/shaders/purple_fire_trail.gdshader")

func update_beam_coverage(corners: Array, direction: Vector2, width: float, length: float, base_pos: Vector2, delta: float, charge_needed: float) -> void:
	# Check if beam is in roughly same position (allowing for small movement)
	var dir_diff := direction.angle_to(_last_direction)
	var pos_diff := base_pos.distance_to(_last_base_pos)
	
	if abs(dir_diff) < 0.15 and pos_diff < 50.0:
		# Beam is stable, accumulate charge
		_charge_time += delta
		_charging_corners = corners
	else:
		# Beam moved too much, reset charge
		_charge_time = 0.0
		_charging_corners = corners
	
	_last_direction = direction
	_last_base_pos = base_pos
	
	# If charged enough, create burn rectangle
	if _charge_time >= charge_needed:
		_add_burn_rect(_charging_corners, direction, width)
		_charge_time = 0.0

func _add_burn_rect(corners: Array, direction: Vector2, width: float) -> void:
	# Check if overlaps too much with existing burn
	for existing in burn_rects:
		var c0: Vector2 = corners[0]
		var c2: Vector2 = corners[2]
		var center: Vector2 = (c0 + c2) * 0.5
		var ex0: Vector2 = existing.corners[0]
		var ex2: Vector2 = existing.corners[2]
		var ex_center: Vector2 = (ex0 + ex2) * 0.5
		if center.distance_to(ex_center) < width * 0.3:
			return
	
	burn_rects.append({corners = corners.duplicate(), time = _current_time, direction = direction, width = width})
	queue_redraw()

func _process(delta: float) -> void:
	_current_time += delta
	
	# Remove old rects
	var i := 0
	while i < burn_rects.size():
		var age: float = _current_time - burn_rects[i].time
		if age >= point_lifespan:
			burn_rects.remove_at(i)
			queue_redraw()
		else:
			i += 1
	
	if burn_rects.is_empty() and _charge_time <= 0.0:
		queue_free()
		return
	
	_damage_timer += delta
	if _damage_timer >= 0.4:
		_damage_timer = 0.0
		_deal_damage()
	
	# Redraw for fade effect
	if Engine.get_process_frames() % 5 == 0:
		queue_redraw()

func _deal_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		var epos: Vector2 = enemy.global_position
		for br in burn_rects:
			var age: float = _current_time - br.time
			if age >= point_lifespan:
				continue
			if _point_in_rect(epos, br.corners):
				var time_left: float = point_lifespan - age
				var dmg := 4
				if time_left < 1.0:
					dmg = int(4.0 * time_left)
				if dmg > 0 and enemy.has_method("take_damage"):
					enemy.take_damage(dmg, false, Vector2.ZERO)
				break

func _point_in_rect(p: Vector2, corners: Array) -> bool:
	# Check if point is inside the quad - use expanded bounds for damage
	var c0: Vector2 = corners[0]
	var c1: Vector2 = corners[1]
	var c2: Vector2 = corners[2]
	var c3: Vector2 = corners[3]
	
	# Get the center and axes of the rectangle
	var center: Vector2 = (c0 + c2) * 0.5
	var axis1: Vector2 = (c1 - c0).normalized()
	var axis2: Vector2 = (c3 - c0).normalized()
	var half_len1: float = (c1 - c0).length() * 0.5
	var half_len2: float = (c3 - c0).length() * 0.5
	
	# Project point onto axes
	var local: Vector2 = p - center
	var proj1: float = abs(local.dot(axis1))
	var proj2: float = abs(local.dot(axis2))
	
	return proj1 <= half_len1 and proj2 <= half_len2

func _draw() -> void:
	for br in burn_rects:
		var age: float = _current_time - br.time
		var time_left: float = point_lifespan - age
		# Only fade in last 1 second
		var alpha: float = 1.0
		if time_left < 1.0:
			alpha = time_left
		if alpha <= 0.0:
			continue
		
		# Convert corners to local coordinates and create wavy organic shape
		var local_corners: PackedVector2Array = PackedVector2Array()
		for c in br.corners:
			local_corners.append(c - global_position)
		
		# Create organic wavy polygon with many points along edges
		var organic_shape: PackedVector2Array = _make_organic_polygon(local_corners, _current_time, age)
		
		# Draw multiple soft blur layers from outside in
		var blur5: PackedVector2Array = _expand_organic(organic_shape, 50.0)
		draw_colored_polygon(blur5, Color(0.08, 0.015, 0.0, 0.12 * alpha))
		
		var blur4: PackedVector2Array = _expand_organic(organic_shape, 35.0)
		draw_colored_polygon(blur4, Color(0.1, 0.02, 0.0, 0.18 * alpha))
		
		var blur3: PackedVector2Array = _expand_organic(organic_shape, 22.0)
		draw_colored_polygon(blur3, Color(0.12, 0.025, 0.0, 0.25 * alpha))
		
		var blur2: PackedVector2Array = _expand_organic(organic_shape, 12.0)
		draw_colored_polygon(blur2, Color(0.1, 0.02, 0.01, 0.4 * alpha))
		
		var blur1: PackedVector2Array = _expand_organic(organic_shape, 5.0)
		draw_colored_polygon(blur1, Color(0.09, 0.02, 0.01, 0.6 * alpha))
		
		# Draw the burn core
		var base_color := Color(0.07, 0.015, 0.015, 0.8 * alpha)
		draw_colored_polygon(organic_shape, base_color)
		
		# Draw ember glow overlay
		var ember_color := Color(0.35, 0.07, 0.0, 0.35 * alpha)
		draw_colored_polygon(organic_shape, ember_color)

func _make_organic_polygon(corners: PackedVector2Array, time: float, age: float) -> PackedVector2Array:
	# Create organic wavy shape by subdividing edges and adding noise
	var result := PackedVector2Array()
	var num_corners := corners.size()
	var points_per_edge := 8  # More points = smoother waves
	
	for i in range(num_corners):
		var start: Vector2 = corners[i]
		var end: Vector2 = corners[(i + 1) % num_corners]
		var edge_dir: Vector2 = (end - start).normalized()
		var edge_normal: Vector2 = Vector2(-edge_dir.y, edge_dir.x)
		var edge_len: float = (end - start).length()
		
		for j in range(points_per_edge):
			var t: float = float(j) / float(points_per_edge)
			var pos: Vector2 = start.lerp(end, t)
			
			# Add wavy displacement using multiple sine waves
			var wave_seed: float = pos.x * 0.02 + pos.y * 0.015 + time * 0.5
			var wave1: float = sin(wave_seed * 3.0 + age * 0.3) * 8.0
			var wave2: float = sin(wave_seed * 7.0 - time * 0.8) * 4.0
			var wave3: float = sin(wave_seed * 13.0 + age * 0.5) * 2.0
			var displacement: float = wave1 + wave2 + wave3
			
			# Reduce displacement near corners for smoother transitions
			var corner_blend: float = min(t, 1.0 - t) * 4.0
			corner_blend = clamp(corner_blend, 0.0, 1.0)
			displacement *= corner_blend
			
			result.append(pos + edge_normal * displacement)
	
	return result

func _expand_organic(corners: PackedVector2Array, amount: float) -> PackedVector2Array:
	# Expand polygon outward for blur layers
	var center := Vector2.ZERO
	for c in corners:
		center += c
	center /= corners.size()
	
	var expanded := PackedVector2Array()
	for c in corners:
		var dir: Vector2 = (c - center).normalized()
		expanded.append(c + dir * amount)
	return expanded
'
	script.reload()
	return script

func _exit_tree() -> void:
	pass  # Burn area manages itself now

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
	if randf() < 0.8:  # 80% chance per frame
		var dist := randf() * beam_range
		var offset := _beam_direction.orthogonal() * randf_range(-beam_width * 0.3, beam_width * 0.3)
		var particle := {
			"pos": _beam_direction * dist + offset,
			"vel": _beam_direction.orthogonal() * randf_range(-50, 50) + Vector2(0, -30),
			"size": randf_range(3, 8),
			"age": 0.0,
			"lifespan": randf_range(0.3, 0.8),
			"color": Color(0.8, 0.5, 1.0, 0.8) if randf() > 0.3 else Color(1.0, 0.9, 1.0, 0.9)
		}
		_particles.append(particle)

func _draw() -> void:
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

func _draw_beam(intensity: float) -> void:
	var beam_end := _beam_direction * beam_range
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
			beam_end - perp * w * 0.8,  # Slightly narrower at end
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
	# Draw rings traveling along the beam
	var ring_count := 5
	var ring_spacing := beam_range / float(ring_count)
	
	for i in range(ring_count):
		var ring_pos := fmod(_ring_phase * 200.0 + float(i) * ring_spacing, beam_range)
		var ring_center := _beam_direction * ring_pos
		var ring_size := beam_width * 0.4 * (1.0 - ring_pos / beam_range * 0.3)
		
		var ring_alpha := 0.5 * intensity * (1.0 - ring_pos / beam_range * 0.5)
		var ring_color := Color(inner_color.r, inner_color.g, inner_color.b, ring_alpha)
		
		# Draw ring as ellipse (flattened in beam direction)
		_draw_ring(ring_center, ring_size, ring_color, 2.0)

func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments := 24
	var perp := _beam_direction.orthogonal()
	var prev_pt := center + perp * radius
	
	for i in range(1, segments + 1):
		var angle := TAU * float(i) / float(segments)
		# Flatten ring in beam direction
		var local := Vector2(cos(angle) * 0.3, sin(angle)) * radius
		var pt := center + _beam_direction * local.x + perp * local.y
		draw_line(prev_pt, pt, color, width, true)
		prev_pt = pt

func _draw_origin_effect(intensity: float) -> void:
	# Bright burst at beam origin
	var pulse := 0.7 + 0.3 * sin(_age * 10.0)
	
	draw_circle(Vector2.ZERO, beam_width * 0.8 * pulse, Color(outer_color.r, outer_color.g, outer_color.b, 0.3 * intensity))
	draw_circle(Vector2.ZERO, beam_width * 0.5 * pulse, Color(inner_color.r, inner_color.g, inner_color.b, 0.5 * intensity))
	draw_circle(Vector2.ZERO, beam_width * 0.3 * pulse, Color(core_color.r, core_color.g, core_color.b, 0.8 * intensity))
	
	# Rotating energy spokes
	for i in range(6):
		var angle := _age * 3.0 + float(i) * TAU / 6.0
		var spoke_end := Vector2(cos(angle), sin(angle)) * beam_width * 0.6
		var spoke_color := Color(inner_color.r, inner_color.g, inner_color.b, 0.4 * intensity * pulse)
		draw_line(Vector2.ZERO, spoke_end, spoke_color, 3.0, true)
