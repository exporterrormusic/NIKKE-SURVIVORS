# Extracted from scripts/characters/effects/MarianBeam.gd (was runtime-compiled embedded source).
extends Node2D

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
	
	var entry = {corners = corners.duplicate(), time = _current_time, direction = direction, width = width, mask_node = null}
	
	# Add Eraser to Grass Mask
	if GrassMaskManager.instance:
		var mask_poly = Polygon2D.new()
		mask_poly.polygon = PackedVector2Array(corners)
		mask_poly.color = Color.WHITE
		mask_poly.z_index = 0
		GrassMaskManager.instance.add_eraser(mask_poly)
		entry.mask_node = mask_poly
		
	burn_rects.append(entry)
	queue_redraw()

func _process(delta: float) -> void:
	_current_time += delta
	
	# Remove old rects
	var i := 0
	while i < burn_rects.size():
		var age: float = _current_time - burn_rects[i].time
		if age >= point_lifespan:
			# Cleanup mask
			var entry = burn_rects[i]
			if entry.get("mask_node") and is_instance_valid(entry.mask_node):
				entry.mask_node.queue_free()
				
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
	for enemy in TargetCache.get_enemies():
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
					enemy.take_damage(dmg, false, Vector2.ZERO, false, "MarianBurst")
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
