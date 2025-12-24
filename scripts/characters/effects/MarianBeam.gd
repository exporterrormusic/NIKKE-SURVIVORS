extends Node2D
class_name MarianBeam

## Marian's epic purple laser beam burst
## Aimable continuous beam that follows mouse, deals damage over time
## With upgrades: fires homing missiles, leaves burning trail

signal beam_ended

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
var player_ref: Node2D = null # Reference to player for position tracking
var target_enemy: Node2D = null # For summons: track this enemy instead of mouse
var initial_direction: Vector2 = Vector2.ZERO # Set by controller before adding to scene
var _age: float = 0.0
var _damage_timer: float = 0.0
var _beam_direction: Vector2 = Vector2.RIGHT
var _target_direction: Vector2 = Vector2.RIGHT
var _turn_speed: float = 20.0 # How fast beam follows mouse

# Player level for damage scaling
var player_level: int = 1

# Upgrade states
var missile_upgrade: bool = false # Left upgrade: fire homing missiles
var trail_upgrade: bool = false # Right upgrade: leave burning trail

# "She'll Eat Anything" enhanced mode - 50% wider, brighter purple
var enhanced_mode: bool = false
var _base_beam_width: float = 240.0

var _missile_timer: float = 0.0
var _missiles_per_volley: int = 4
var _missile_volleys_fired: int = 0 # Track volleys (fire at 0.1s and 3.1s)

var _burn_area: Node2D = null # Burn area with rectangular coverage
const BURN_CHARGE_TIME: float = 1.0 # Seconds of continuous coverage needed

# Shader material
var _shader_material: ShaderMaterial = null

# Visual particles
var _particles: Array = []
var _ring_phase: float = 0.0

# Audio
var _beam_audio_player: AudioStreamPlayer2D = null

# Source ID for burst generation
var damage_source: String = "MarianBurst"

func _ready() -> void:
	z_index = 500
	top_level = true
	
	# Check if owned by a summon and override source
	if owner_node and (owner_node.is_in_group("summoned_allies") or owner_node.name.contains("SummonedAlly")):
		damage_source = "summon"
	
	# Start continuous beam audio
	_start_beam_audio()
	
	# Load beam shader
	var shader = load("res://resources/shaders/marian_beam.gdshader")
	if shader:
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = shader
	
	# Assign to effects layer to avoid night darkening
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
			z_index = 500
	
	# Initial direction - use pre-set direction if available, otherwise calculate from mouse
	if initial_direction != Vector2.ZERO:
		_beam_direction = initial_direction.normalized()
		_target_direction = _beam_direction
	elif owner_node:
		var mouse_pos := get_global_mouse_position()
		_beam_direction = (mouse_pos - global_position).normalized()
		_target_direction = _beam_direction

func _process(delta: float) -> void:
	_age += delta
	
	# Apply enhanced mode effects (50% wider beam, brighter colors)
	if enhanced_mode:
		beam_width = _base_beam_width * 1.5
		core_color = Color(1.0, 0.8, 1.0, 1.0)
		inner_color = Color(0.9, 0.5, 1.0, 1.0)
		outer_color = Color(0.7, 0.2, 1.0, 0.9)
	else:
		beam_width = _base_beam_width
	
	# Manual loop check: verify beam sound is playing
	if _beam_sound and is_instance_valid(_beam_sound) and not _beam_sound.playing:
		_beam_sound.play()
	
	if _age >= duration:
		_stop_beam_audio()
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

func _update_beam_direction(_delta: float) -> void:
	# EXACT match of MarianBeamCannon logic
	if not player_ref or not is_instance_valid(player_ref):
		return

	# Calculate aim direction from player to mouse
	var mouse_pos: Vector2 = player_ref.get_global_mouse_position()
	var aim_dir: Vector2 = (mouse_pos - player_ref.global_position).normalized()
	
	if aim_dir == Vector2.ZERO:
		aim_dir = Vector2.RIGHT
		
	# Smoothly rotate beam toward mouse (High responsivness)
	# User requested faster than Crown (4.0), restoring high speed now that jitter is fixed
	if _beam_direction.dot(aim_dir) > -0.99: # Avoid lerping if exact opposite (flip issue)
		_beam_direction = _beam_direction.lerp(aim_dir, 25.0 * _delta).normalized()
	else:
		_beam_direction = _beam_direction.rotated(25.0 * _delta) # Turn manual if behind
		
	_target_direction = aim_dir
	
	# Direct transform update
	rotation = _beam_direction.angle()
	global_position = player_ref.global_position + _beam_direction * 35.0

func _deal_beam_damage() -> void:
	var tree := get_tree()
	if not tree:
		return
	
	var enemies := TargetCache.get_enemies()
	
	# Calculate level-scaled damage (+50% per level)
	var level_mult := 1.0 + (player_level - 1) * 0.5
	var scaled_dps := damage_per_second * level_mult
	
	# Apply enhanced mode multiplier
	if enhanced_mode:
		scaled_dps *= 2.0
		
	var damage_this_tick := int(scaled_dps * damage_tick_interval)
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		# Skip charmed allies (Sin's mind control)
		if enemy.is_in_group("charmed_allies"):
			continue
			
		var enemy_node := enemy as Node2D
		
		# Check if enemy is within beam
		if _is_point_in_beam(enemy_node.global_position):
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage_this_tick, false, _beam_direction, true, damage_source)
			elif "hp" in enemy:
				enemy.hp -= damage_this_tick

func _is_point_in_beam(point: Vector2) -> bool:
	var to_point := point - global_position
	var along_beam := to_point.dot(_beam_direction)
	
	# Must be in front and within range
	if along_beam < 0 or along_beam > beam_range:
		return false
	
	# Check if a boulder blocks the beam before reaching this point
	if _is_boulder_blocking(along_beam):
		return false
	
	# Check perpendicular distance
	var perp: float = abs(to_point.dot(_beam_direction.orthogonal()))
	var width_at_point := beam_width * 0.5 # Half width
	
	return perp <= width_at_point

func _is_boulder_blocking(distance_along_beam: float) -> bool:
	"""Check if any boulder blocks the beam before the given distance."""
	# Skip if Chrono-Intangibility upgrade is active
	var shop = load("res://scripts/ui/ShopMenu.gd")
	# Skip if Chrono-Intangibility upgrade is active AND Wells is in squad
	var player = get_tree().get_first_node_in_group("player")
	if shop and shop.has_character_upgrade("wells", "chrono_intangibility") and player and player.has_method("is_character_in_squad") and player.is_character_in_squad("wells"):
		return false
	
	var boulders := TargetCache.get_boulders()
	
	# Use player position as beam origin since global_position is offset 80px forward
	var beam_origin: Vector2 = global_position
	if player_ref and is_instance_valid(player_ref):
		beam_origin = player_ref.global_position
	
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		
		# Check if beam intersects this boulder
		var to_boulder := boulder_pos - beam_origin
		var along := to_boulder.dot(_beam_direction)
		
		# Boulder must be in front and before our target point (accounting for 80px offset)
		if along < 0 or along > distance_along_beam + 80.0:
			continue
		
		# Check perpendicular distance to beam center line
		var perp: float = abs(to_boulder.dot(_beam_direction.orthogonal()))
		if perp < boulder_radius + beam_width * 0.5:
			return true # Beam is blocked by this boulder
	
	return false

func _is_line_blocked_by_boulder(start: Vector2, end: Vector2, width: float) -> bool:
	# Skip if Chrono-Intangibility upgrade is active
	var shop = load("res://scripts/ui/ShopMenu.gd")
	# Skip if Chrono-Intangibility upgrade is active AND Wells is in squad
	var player = get_tree().get_first_node_in_group("player")
	if shop and shop.has_character_upgrade("wells", "chrono_intangibility") and player and player.has_method("is_character_in_squad") and player.is_character_in_squad("wells"):
		return false
	
	var boulders := TargetCache.get_boulders()
	var to_end := end - start
	var length := to_end.length()
	var direction := to_end.normalized()
	
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		
		# Check if line intersects this boulder
		var to_boulder := boulder_pos - start
		var along := to_boulder.dot(direction)
		
		# Boulder must be in front and before our target point
		if along < -boulder_radius or along > length + boulder_radius:
			continue
		
		# Check perpendicular distance to line
		var perp: float = abs(to_boulder.dot(direction.orthogonal()))
		if perp < boulder_radius + width * 0.5:
			return true # Blocked
			
	return false

func _fire_homing_missiles() -> void:
	# Find the 4 closest enemy targets
	var tree := get_tree()
	if not tree:
		return
	
	var enemies := TargetCache.get_enemies()
	if enemies.is_empty():
		return
	
	# Sort by distance and take closest 4
	var player_pos: Vector2 = global_position
	if player_ref and is_instance_valid(player_ref):
		player_pos = player_ref.global_position
	
	enemies.sort_custom(func(a, b): return a.global_position.distance_squared_to(player_pos) < b.global_position.distance_squared_to(player_pos))
	var targets := enemies.slice(0, mini(_missiles_per_volley, enemies.size()))
	
	# Spawn missiles
	# Play rocket launch sound
	_play_rocket_sound()
	for i in range(targets.size()):
		var target = targets[i]
		if not is_instance_valid(target):
			continue
		
		var missile = ProjectileCache.create_missile()
		get_parent().add_child(missile)
		
		# Spawn from player position with offset
		var angle := float(i) * TAU / float(_missiles_per_volley) + _age
		var offset := Vector2(cos(angle), sin(angle)) * 40.0
		missile.global_position = global_position + offset
		
		# Calculate direction to target for initial velocity
		var dir_to_target: Vector2 = (target.global_position - missile.global_position).normalized()
		
		# Configure ExplosiveProjectile properties
		if "owner_node" in missile and is_instance_valid(owner_node):
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
	_burn_area.z_as_relative = false
	_burn_area.z_index = -5
	_burn_area.global_position = Vector2.ZERO # Keep at origin, use global coords
	
	# PARENTING FIX: Add to World (Player's parent) instead of EffectsLayer
	# EffectsLayer forces high rendering order, ignoring negative Z-index relative to world
	if player_ref and is_instance_valid(player_ref) and player_ref.get_parent():
		player_ref.get_parent().add_child(_burn_area)
	else:
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
'
	script.reload()
	return script

func _exit_tree() -> void:
	pass # Burn area manages itself now

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
	
	# Spawn new particles along beam (Local Space)
	if randf() < 0.8: # 80% chance per frame
		var dist := randf() * beam_range
		var offset := Vector2.UP * randf_range(-beam_width * 0.3, beam_width * 0.3)
		var particle := {
			"pos": Vector2.RIGHT * dist + offset,
			"vel": Vector2.UP * randf_range(-50, 50) + Vector2(0, -30),
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
	var beam_end := Vector2.RIGHT * beam_range
	var perp := Vector2.UP
	
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
			- perp * w,
			beam_end - perp * w * 0.8, # Slightly narrower at end
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
		var ring_center := Vector2.RIGHT * ring_pos
		var ring_size := beam_width * 0.4 * (1.0 - ring_pos / beam_range * 0.3)
		
		var ring_alpha := 0.5 * intensity * (1.0 - ring_pos / beam_range * 0.5)
		var ring_color := Color(inner_color.r, inner_color.g, inner_color.b, ring_alpha)
		
		# Draw ring as ellipse (flattened in beam direction)
		_draw_ring(ring_center, ring_size, ring_color, 2.0)

func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments := 24
	var perp := Vector2.UP
	var prev_pt := center + perp * radius
	
	for i in range(1, segments + 1):
		var angle := TAU * float(i) / float(segments)
		# Flatten ring in beam direction
		var local := Vector2(cos(angle) * 0.3, sin(angle)) * radius
		var pt := center + Vector2.RIGHT * local.x + perp * local.y
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

# --- Audio Functions ---

const BEAM_SOUND_PATH := "res://assets/sounds/sfx/weapons/minigun/beam.wav"
var _beam_sound: AudioStreamPlayer2D = null

@export var beam_volume_db: float = 6.0 # Default to loud (Player/Boss volume)

func _start_beam_audio() -> void:
	# Create beam sound player like MarianBeamCannon does
	if _beam_sound != null:
		return # Already created
	
	_beam_sound = AudioStreamPlayer2D.new()
	_beam_sound.bus = "SFX"
	_beam_sound.max_distance = 2000.0
	_beam_sound.volume_db = beam_volume_db
	add_child(_beam_sound)
	
	# Load standard beam sound
	var beam_audio = load(BEAM_SOUND_PATH)
	if beam_audio:
		_beam_sound.stream = beam_audio
		_beam_sound.play()

func _stop_beam_audio() -> void:
	if _beam_sound and is_instance_valid(_beam_sound):
		_beam_sound.stop()
		_beam_sound.queue_free()
		_beam_sound = null

func _play_rocket_sound() -> void:
	# If volume is reduced (Summon), play locally with attenuation
	if beam_volume_db < 0:
		var sfx = AudioStreamPlayer2D.new()
		sfx.bus = "SFX"
		sfx.volume_db = beam_volume_db
		sfx.max_distance = 2000.0
		# Try to load rocket sound
		var stream = load("res://assets/sounds/sfx/weapons/rocket/fire_rocket.mp3")
		if stream:
			sfx.stream = stream
			add_child(sfx)
			sfx.play()
			sfx.finished.connect(sfx.queue_free)
		else:
			sfx.queue_free()
		return

	# Default behavior (Player/Boss)
	var player = get_tree().get_first_node_in_group("player")
	if player and player.audio_director:
		player.audio_director.play_weapon_fire_sound("rocket")
