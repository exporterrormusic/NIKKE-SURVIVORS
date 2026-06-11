extends Node2D
class_name CecilDrone
## Cecil's companion drone robot
## Circles around Cecil, fires laser beams at enemies
## Modes: "hunt" (seek enemies) or "shield" (orbit Cecil)

var owner_player: Node2D = null
var drone_index: int = 0
var base_angle_offset: float = 0.0

# Movement
var orbit_radius: float = 90.0 # Larger orbit for shield mode
var orbit_speed: float = 2.5 # Radians per second
var current_angle: float = 0.0
var hunt_speed: float = 400.0 # Faster hunting speed

# Combat
var attack_range: float = 400.0 # Much longer range
var fire_cooldown: float = 0.92 # Balanced firing rate (35% slower than 0.6)
var _fire_timer: float = 0.0
var laser_speed: float = 800.0 # Faster projectiles

# Multipliers from upgrades
var speed_multiplier: float = 1.0

# Mode
var _mode: String = "hunt" # "hunt" or "shield"
var _is_returning: bool = false # Transitioning back to player for shield mode
var _current_target: Node2D = null

# Callback when drone reaches player for shield mode
var _on_arrived_callback: Callable = Callable()

# Reference to sibling drone for target coordination
var sibling_drone: Node2D = null

# Visual - 50% bigger
var drone_scale: float = 1.5
var _sprite: Sprite2D = null
var _glow: PointLight2D = null

func initialize(player: Node2D, index: int, angle_offset: float, speed_mult: float) -> void:
	owner_player = player
	drone_index = index
	base_angle_offset = angle_offset
	current_angle = angle_offset
	speed_multiplier = speed_mult
	
	# Start at orbit position
	if owner_player:
		global_position = owner_player.global_position + Vector2(cos(current_angle), sin(current_angle)) * orbit_radius

func _ready() -> void:
	z_index = 50
	
	# Create drone visual (small blue circle robot) - 50% bigger
	_sprite = Sprite2D.new()
	_sprite.texture = _create_drone_texture()
	_sprite.scale = Vector2(drone_scale, drone_scale)
	add_child(_sprite)
	
	# Add glow
	_glow = PointLight2D.new()
	_glow.color = Color(0.3, 0.7, 1.0)
	_glow.energy = 0.8
	_glow.texture = _create_light_texture()
	_glow.texture_scale = 0.3 * drone_scale
	add_child(_glow)

func _create_drone_texture() -> Texture2D:
	# Create a simple drone texture (small blue circle with details)
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	var center := Vector2(12, 12)
	
	for x in range(24):
		for y in range(24):
			var pos := Vector2(x, y)
			var dist := pos.distance_to(center)
			
			if dist <= 10:
				# Main body
				var alpha := 1.0 if dist <= 8 else (10 - dist) / 2.0
				if dist <= 6:
					# Inner bright core
					img.set_pixel(x, y, Color(0.5, 0.9, 1.0, alpha))
				else:
					# Outer ring
					img.set_pixel(x, y, Color(0.2, 0.5, 0.9, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	
	return ImageTexture.create_from_image(img)

func _create_light_texture() -> Texture2D:
	return TextureCache.get_light_texture_64()

func _process(delta: float) -> void:
	if not owner_player or not is_instance_valid(owner_player):
		queue_free()
		return
	
	_fire_timer -= delta
	
	# Handle returning to player
	if _is_returning:
		_process_returning(delta)
		return
	
	match _mode:
		"hunt":
			_process_hunt_mode(delta)
		"shield":
			_process_shield_mode(delta)
	
	# Rotate sprite to face movement direction or target
	if _current_target and is_instance_valid(_current_target):
		var dir := (_current_target.global_position - global_position).angle()
		_sprite.rotation = dir

func _process_hunt_mode(delta: float) -> void:
	# AGGRESSIVE AI: Always seek nearest enemy, fire immediately when in range
	# No complex distance constraints - just hunt and kill
	# Always find the best target (fast re-evaluation)
	_current_target = _find_nearest_enemy()
	
	if _current_target and is_instance_valid(_current_target):
		var to_target := _current_target.global_position - global_position
		var dist := to_target.length()
		
		# If in range, FIRE and hold position
		if dist <= attack_range:
			if _fire_timer <= 0:
				_fire_laser_at(_current_target)
				_fire_timer = fire_cooldown / speed_multiplier
			# Slight drift toward target to stay close
			global_position += to_target.normalized() * 50.0 * delta
		else:
			# Chase target aggressively - move fast!
			var chase_speed := hunt_speed * 1.5 * speed_multiplier
			global_position += to_target.normalized() * chase_speed * delta
		
		# Rotate to face target
		_sprite.rotation = to_target.angle()
	else:
		# No enemies - orbit player loosely
		_orbit_player(delta)
	
	# Soft tether to player - if too far, drift back
	var dist_to_owner := global_position.distance_to(owner_player.global_position)
	if dist_to_owner > 600.0:
		var pull := (owner_player.global_position - global_position).normalized()
		global_position += pull * 200.0 * delta

func _process_shield_mode(delta: float) -> void:
	# Move exactly with player in shield mode - no lag
	# Drones do NOT fire in shield mode - they focus on protection
	_orbit_player_instant(delta)

func _orbit_player(delta: float) -> void:
	current_angle += orbit_speed * speed_multiplier * delta
	var target_pos := owner_player.global_position + Vector2(cos(current_angle), sin(current_angle)) * orbit_radius
	global_position = global_position.lerp(target_pos, 8.0 * delta)

func _orbit_player_instant(delta: float) -> void:
	# Update angle and move instantly to position (no lerp) for shield mode
	current_angle += orbit_speed * speed_multiplier * delta
	global_position = owner_player.global_position + Vector2(cos(current_angle), sin(current_angle)) * orbit_radius

func _clamp_to_screen() -> void:
	# Keep drone visible on screen with some margin
	var viewport := get_viewport()
	if not viewport:
		return
	
	var camera := viewport.get_camera_2d()
	if not camera:
		return
	
	var screen_size := viewport.get_visible_rect().size
	var camera_pos := camera.global_position
	var margin := 50.0
	
	var min_x := camera_pos.x - screen_size.x / 2.0 + margin
	var max_x := camera_pos.x + screen_size.x / 2.0 - margin
	var min_y := camera_pos.y - screen_size.y / 2.0 + margin
	var max_y := camera_pos.y + screen_size.y / 2.0 - margin
	
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, min_y, max_y)

func _process_returning(delta: float) -> void:
	# Move quickly toward designated orbit position (based on base_angle_offset for proper spacing)
	# Don't modify current_angle during return - it was set to base_angle_offset in set_mode
	var target_pos := owner_player.global_position + Vector2(cos(base_angle_offset), sin(base_angle_offset)) * orbit_radius
	var to_target := target_pos - global_position
	var dist := to_target.length()
	
	if dist < 15.0:
		# Arrived at designated orbit position
		_is_returning = false
		current_angle = base_angle_offset # Lock to designated angle
		global_position = target_pos
		if _on_arrived_callback.is_valid():
			_on_arrived_callback.call()
			_on_arrived_callback = Callable()
	else:
		# Move toward target position fast
		var move_speed := hunt_speed * 2.0 * speed_multiplier
		global_position += to_target.normalized() * move_speed * delta

func _find_nearest_enemy() -> Node2D:
	var tree := get_tree()
	if not tree:
		return null
	
	var nearest: Node2D = null
	var nearest_dist := INF
	
	# Get sibling drone's target to avoid targeting same enemy
	var sibling_target: Node2D = null
	if sibling_drone and is_instance_valid(sibling_drone):
		var target_ref = sibling_drone.get("_current_target")
		if target_ref and is_instance_valid(target_ref):
			sibling_target = target_ref
	
	var enemies := tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		# Skip charmed enemies (they're friendly now)
		if enemy.is_in_group("charmed_allies"):
			continue
		
		var dist := global_position.distance_to(enemy.global_position)
		
		# If sibling is targeting this enemy, add penalty to distance (prefer different targets)
		if sibling_target and enemy == sibling_target:
			dist += 500.0 # Large penalty to prefer different targets
		
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy as Node2D
	
	return nearest

func _fire_laser_at(target: Node2D) -> void:
	if not target or not is_instance_valid(target):
		return
	
	# AIM PREDICTION: Lead the target based on its velocity
	var target_pos := target.global_position
	var target_velocity := Vector2.ZERO
	
	# Get target's velocity if available
	if target is CharacterBody2D:
		target_velocity = (target as CharacterBody2D).velocity
	elif "velocity" in target:
		target_velocity = target.velocity
	elif "_velocity" in target:
		target_velocity = target._velocity
	
	# Calculate time for laser to reach target
	var dist := global_position.distance_to(target_pos)
	var bullet_speed := laser_speed * speed_multiplier
	var time_to_target := dist / bullet_speed
	
	# Predict where target will be
	var predicted_pos := target_pos + target_velocity * time_to_target * 0.8 # 0.8 = slight undershoot for accuracy
	
	var direction := (predicted_pos - global_position).normalized()
	
	# Calculate damage as 50% of player's damage
	var laser_damage: int = 3 # Fallback
	if owner_player and is_instance_valid(owner_player) and owner_player.has_method("calc_damage"):
		laser_damage = maxi(1, int(owner_player.calc_damage() * 0.5))
	
	# Create laser projectile
	var laser := Node2D.new()
	laser.set_script(_get_laser_script())
	laser.set("direction", direction)
	laser.set("speed", bullet_speed)
	laser.set("damage", laser_damage)
	laser.global_position = global_position + direction * 15.0
	
	get_parent().add_child(laser)

func _get_laser_script() -> GDScript:
	var script := preload("res://scripts/characters/effects/visuals/CecilDroneLaser.gd")
	return script

func set_mode(mode: String, on_arrived: Callable = Callable()) -> void:
	if mode == "shield" and _mode != "shield":
		# Start returning to player before activating shield mode
		_is_returning = true
		_on_arrived_callback = on_arrived
		_current_target = null
		# Reset to base angle offset for perfect opposite positioning
		current_angle = base_angle_offset
	else:
		_is_returning = false
	_mode = mode

func is_returning() -> bool:
	return _is_returning

func set_speed_multiplier(speed_mult: float) -> void:
	speed_multiplier = speed_mult
