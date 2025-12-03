extends Node2D
class_name CecilDrone
## Cecil's companion drone robot
## Circles around Cecil, fires laser beams at enemies
## Modes: "hunt" (seek enemies) or "shield" (orbit Cecil)

var owner_player: Node2D = null
var drone_index: int = 0
var base_angle_offset: float = 0.0

# Movement
var orbit_radius: float = 90.0  # Larger orbit for shield mode
var orbit_speed: float = 2.5  # Radians per second
var current_angle: float = 0.0
var hunt_speed: float = 300.0

# Combat
var attack_range: float = 250.0
var fire_cooldown: float = 0.8
var _fire_timer: float = 0.0
var laser_damage: int = 3
var laser_speed: float = 600.0

# Multipliers from upgrades
var speed_multiplier: float = 1.0
var damage_multiplier: float = 1.0

# Mode
var _mode: String = "hunt"  # "hunt" or "shield"
var _is_returning: bool = false  # Transitioning back to player for shield mode
var _current_target: Node2D = null

# Callback when drone reaches player for shield mode
var _on_arrived_callback: Callable = Callable()

# Reference to sibling drone for target coordination
var sibling_drone: Node2D = null

# Visual - 50% bigger
var drone_scale: float = 1.5
var _sprite: Sprite2D = null
var _glow: PointLight2D = null

func initialize(player: Node2D, index: int, angle_offset: float, speed_mult: float, damage_mult: float) -> void:
	owner_player = player
	drone_index = index
	base_angle_offset = angle_offset
	current_angle = angle_offset
	speed_multiplier = speed_mult
	damage_multiplier = damage_mult
	
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
	# Find nearest enemy if no target or target is invalid
	if not _current_target or not is_instance_valid(_current_target):
		_current_target = _find_nearest_enemy()
	
	if _current_target and is_instance_valid(_current_target):
		var to_target := _current_target.global_position - global_position
		var dist := to_target.length()
		
		if dist > attack_range:
			# Move toward target
			var move_dir := to_target.normalized()
			global_position += move_dir * hunt_speed * speed_multiplier * delta
		else:
			# In range, try to fire
			if _fire_timer <= 0:
				_fire_laser_at(_current_target)
				_fire_timer = fire_cooldown / speed_multiplier
			
			# Orbit around target slightly
			var orbit_around := _current_target.global_position
			var angle_to_drone := (global_position - orbit_around).angle()
			angle_to_drone += orbit_speed * speed_multiplier * delta
			var desired_pos := orbit_around + Vector2(cos(angle_to_drone), sin(angle_to_drone)) * (attack_range * 0.7)
			global_position = global_position.lerp(desired_pos, 3.0 * delta)
	else:
		# No target, orbit around player
		_orbit_player(delta)

func _process_shield_mode(delta: float) -> void:
	# Move exactly with player in shield mode - no lag
	_orbit_player_instant(delta)
	
	# Still fire at nearby enemies
	if _fire_timer <= 0:
		var target := _find_nearest_enemy()
		if target and global_position.distance_to(target.global_position) <= attack_range:
			_fire_laser_at(target)
			_fire_timer = fire_cooldown / speed_multiplier

func _orbit_player(delta: float) -> void:
	current_angle += orbit_speed * speed_multiplier * delta
	var target_pos := owner_player.global_position + Vector2(cos(current_angle), sin(current_angle)) * orbit_radius
	global_position = global_position.lerp(target_pos, 8.0 * delta)

func _orbit_player_instant(delta: float) -> void:
	# Update angle and move instantly to position (no lerp) for shield mode
	current_angle += orbit_speed * speed_multiplier * delta
	global_position = owner_player.global_position + Vector2(cos(current_angle), sin(current_angle)) * orbit_radius

func _process_returning(delta: float) -> void:
	# Move quickly toward designated orbit position (based on base_angle_offset for proper spacing)
	# Don't modify current_angle during return - it was set to base_angle_offset in set_mode
	var target_pos := owner_player.global_position + Vector2(cos(base_angle_offset), sin(base_angle_offset)) * orbit_radius
	var to_target := target_pos - global_position
	var dist := to_target.length()
	
	if dist < 15.0:
		# Arrived at designated orbit position
		_is_returning = false
		current_angle = base_angle_offset  # Lock to designated angle
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
		
		# Skip charmed enemies
		if enemy.get("_is_charmed") == true:
			continue
		
		var dist := global_position.distance_to(enemy.global_position)
		
		# If sibling is targeting this enemy, add penalty to distance (prefer different targets)
		if sibling_target and enemy == sibling_target:
			dist += 500.0  # Large penalty to prefer different targets
		
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy as Node2D
	
	return nearest

func _fire_laser_at(target: Node2D) -> void:
	if not target or not is_instance_valid(target):
		return
	
	var direction := (target.global_position - global_position).normalized()
	
	# Create laser projectile
	var laser := Node2D.new()
	laser.set_script(_get_laser_script())
	laser.set("direction", direction)
	laser.set("speed", laser_speed * speed_multiplier)
	laser.set("damage", int(laser_damage * damage_multiplier))
	laser.global_position = global_position + direction * 15.0
	
	get_parent().add_child(laser)

func _get_laser_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 600.0
var damage: int = 3
var lifetime: float = 0.0
var max_lifetime: float = 2.0

func _ready() -> void:
	z_index = 45
	rotation = direction.angle()

func _process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Draw larger blue laser beam (50% bigger)
	var length := 30.0
	var width := 6.0
	
	# Core
	draw_line(Vector2.ZERO, Vector2(length, 0), Color(0.7, 0.95, 1.0, 1.0), width)
	# Glow
	draw_line(Vector2.ZERO, Vector2(length, 0), Color(0.3, 0.7, 1.0, 0.5), width * 2)

func _physics_process(_delta: float) -> void:
	# Check for enemy collision
	var space := get_world_2d().direct_space_state
	if not space:
		return
	
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	
	var results := space.intersect_point(query, 8)
	for result in results:
		var collider = result.get(\"collider\")
		if collider and collider.is_in_group(\"enemies\"):
			if collider.has_method(\"take_damage\"):
				collider.take_damage(damage, false, direction)
			queue_free()
			return
"""
	script.reload()
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

func set_multipliers(speed_mult: float, damage_mult: float) -> void:
	speed_multiplier = speed_mult
	damage_multiplier = damage_mult
