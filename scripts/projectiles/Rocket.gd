extends Area2D

# Cached ShopMenu reference
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

var velocity = Vector2.ZERO
var acceleration = 500
var max_speed = 1200
var player
var owner_node: Node = null # Track who fired this rocket
var killer_source: String = "rocket" # For ShielderShield collision detection
var killer_source_override: String = "" # Override killer_source if set (for summon-spawned turrets)
var target_enemy = null
var last_target_pos = Vector2.ZERO
var time = 0.0

# Dynamic damage from launcher
var damage: int = 1
var explosion_damage: int = 1
var explosion_radius: float = 60.0

# Smoke trail settings - rockets have more intense trails
const SMOKE_INTERVAL := 0.025
const SMOKE_LIFETIME := 0.5
const SMOKE_START_SIZE := 5.0
const SMOKE_END_SIZE := 18.0
var _smoke_timer := 0.0
var _smoke_particles: Array = []
var _trail_color := Color(0.45, 0.45, 0.5, 0.7) # Grey smoke
var _fire_color := Color(1.0, 0.6, 0.15, 0.9) # Orange-yellow fire
var _light: PointLight2D = null
var _has_exploded := false # Prevent multiple explosions
var reduced_smoke := false # For turret rockets - spawn 75% fewer particles

# Performance: disable dynamic lights on rockets (expensive with many projectiles)
const ENABLE_ROCKET_LIGHTS := false
var is_intangible: bool = false
var _intangibility_checked: bool = false


# Performance flags
var homing_enabled: bool = true
var target_node: Node = null # Compatibility with Turret.gd
var exhaust_enabled: bool = true
var trail_enabled: bool = true
var smoke_enabled: bool = true
var lightweight_mode: bool = false

## Reset rocket state for pooling reuse
func reset() -> void:
	velocity = Vector2.ZERO
	acceleration = 500
	max_speed = 1200
	owner_node = null
	killer_source = "rocket"
	killer_source_override = ""
	target_enemy = null
	last_target_pos = Vector2.ZERO
	time = 0.0
	_smoke_timer = 0.0
	reduced_smoke = false
	_intangibility_checked = false
	is_intangible = false
	
	# Reset flags to defaults
	homing_enabled = true
	target_node = null
	exhaust_enabled = true
	trail_enabled = true
	smoke_enabled = true
	lightweight_mode = false
		
	visible = true
	set_process(true)
	set_physics_process(true)
	set_deferred("monitoring", true)
	
	collision_mask = 15 # Layers 1,2,3,4 (includes enemy hitbox layer 4)
	monitorable = false

func _check_intangibility() -> void:
	# Check for Intangibility Upgrade (Once per spawn, deferred via physics checks)
	var p = get_tree().get_first_node_in_group("player")
	var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
	var in_squad = false
	if p and p.has_method("is_character_in_squad"):
		in_squad = p.is_character_in_squad("wells") or p.is_character_in_squad("Wells")
	
	# DIAGNOSTIC: Always print to help debug
	# print("[Rocket] Intangibility Check: has_upgrade=", has_upgrade, " in_squad=", in_squad, " player=", p)
	
	if has_upgrade and in_squad:
		# print("[Rocket] Intangibility ACTIVE - will phase through boulders")
		is_intangible = true
	else:
		# print("[Rocket] Intangibility INACTIVE - will hit boulders")
		is_intangible = false

func _ready():
	# Make rocket unshaded (glows in dark)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Layer 1(1) = World, Layer 2(2) = Player, Layer 3(4) = Enemies
	# Rocket should hit World + Enemies (1 | 4 = 5) and maybe Player/OldEnemies (2)?
	# Let's set mask to 5 (World + Enemies) to be safe, or 7 to include layer 2.
	# Given ModularEnemy might be on 4, we need 4.
	collision_mask = 15 # Layers 1,2,3,4 (includes enemy hitbox layer 4)
	
	add_to_group("projectiles")
	connect("body_entered", Callable(self, "_on_body_entered"))
	player = get_parent().get_node_or_null("Player")
	
	# Select initial target - MOVED TO _process to allow lazy loading and property overrides
	# This prevents wasted CPU when homing_enabled is set to false externally immediately after spawn
	if player:
		last_target_pos = player.global_position # default fallback
	
	set_process(true)
	
	# Dynamic lights are expensive - disabled by default
	if ENABLE_ROCKET_LIGHTS:
		_light = PointLight2D.new()
		_light.name = "RocketLight"
		_light.color = Color(1.0, 0.5, 0.15) # Orange-red glow
		_light.energy = 1.0
		_light.texture = _create_light_texture()
		_light.texture_scale = 0.35
		_light.shadow_enabled = false
		add_child(_light)

func _create_light_texture() -> Texture2D:
	# Use cached texture for performance
	return TextureCache.get_light_texture_64()

func _process(delta):
	# Flicker the light intensely (every other frame)
	if _light and Engine.get_process_frames() % 2 == 0:
		_light.energy = 0.8 + randf() * 0.5
	
	# Update smoke trail - reduced_smoke = spawn every 4th particle only
	_smoke_timer += delta
	var smoke_interval := SMOKE_INTERVAL * (4.0 if reduced_smoke else 1.0)
	if _smoke_timer >= smoke_interval:
		_smoke_timer = 0.0
		# Respect smoke_enabled flag
		if smoke_enabled:
			_spawn_smoke_particle()
	
	# Update existing smoke particles
	var i := 0
	while i < _smoke_particles.size():
		var p: Dictionary = _smoke_particles[i]
		p["age"] += delta
		if p["age"] >= SMOKE_LIFETIME:
			_smoke_particles.remove_at(i)
			continue
		# Smoke rises and spreads
		p["pos"] += Vector2(randf_range(-12, 12), randf_range(-25, -10)) * delta
		_smoke_particles[i] = p
		i += 1
	
	# Only redraw every other frame for performance, or less often in lightweight mode
	var frame_mod = 3 if lightweight_mode else 2
	if Engine.get_process_frames() % frame_mod == 0:
		queue_redraw()

func _spawn_smoke_particle():
	_smoke_particles.append({
		"pos": global_position,
		"age": 0.0,
		"size_offset": randf_range(-3, 3)
	})

func _draw():
	if not visible:
		return
		
	# Draw smoke trail (in local space)
	if trail_enabled:
		for p in _smoke_particles:
			var life_ratio: float = p["age"] / SMOKE_LIFETIME
			var alpha := (1.0 - life_ratio) * 0.6
			var size: float = lerp(SMOKE_START_SIZE, SMOKE_END_SIZE, life_ratio) + p["size_offset"]
			var local_pos: Vector2 = p["pos"] - global_position
			
			# Bright fire core (fades quickly)
			if life_ratio < 0.35:
				var fire_alpha := (1.0 - life_ratio / 0.35) * 0.8
				var fire_col := Color(_fire_color.r * 1.5, _fire_color.g * 1.5, _fire_color.b, fire_alpha)
				draw_circle(local_pos, size * 0.6, fire_col)
			
			# Smoke puff
			var smoke_col := Color(_trail_color.r, _trail_color.g, _trail_color.b, alpha)
			draw_circle(local_pos, size, smoke_col)

func _physics_process(delta):
	# Apply Global Enemy Time Scale (Bullet Time) - ONLY for non-player projectiles
	var time_scale = 1.0
	var game_manager = get_node_or_null("/root/GameManager")
	if not (owner_node and owner_node.is_in_group("player")):
		time_scale = game_manager.enemy_time_scale if game_manager else 1.0
	
	var dt = delta * time_scale
	
	# Lazy init intangibility to ensure Player group is populated
	if not _intangibility_checked:
		_check_intangibility()
		_intangibility_checked = true
		
		# Perform initial targeting ONLY if homing is enabled and no explicit target set
		# This respects flags set by Turret.gd immediately after spawn
		if homing_enabled and (target_enemy == null) and (target_node == null):
			_find_initial_target()

	time += dt
	var target_pos = last_target_pos
	
	# Priority to target_node (set by optimizations) then target_enemy (legacy)
	if target_node and is_instance_valid(target_node):
		target_pos = target_node.global_position
		last_target_pos = target_pos
	elif target_enemy and is_instance_valid(target_enemy):
		target_pos = target_enemy.global_position
		last_target_pos = target_pos
		
	# Move towards target_pos
	acceleration = min(acceleration + 6000 * dt, 8000)
	var dir = (target_pos - global_position).normalized()
	velocity += dir * acceleration * dt
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed
	position += velocity * dt
	rotation = velocity.angle() # point towards movement direction
	
	# Check boulder collision - explode on impact
	if _check_boulder_collision():
		call_deferred("explode")
		return
	
	# Check if missile reached target - account for enemy scale
	# Scale hit distance by enemy scale for better feel
	# No enemy ref here, so just use basic distance or check if close to global pos
	if time > 3.0 or global_position.distance_to(target_pos) < 30:
		call_deferred("explode")
	if position.x < -100 or position.x > 2000 or position.y < -100 or position.y > 1200:
		ProjectileCache.return_to_pool(self)

func _find_initial_target() -> void:
	var closest_enemy = null
	var min_dist = INF
	# Optimize: TargetCache avoids expensive tree traversal
	var enemies = TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not (enemy is Node2D):
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			closest_enemy = enemy
	if closest_enemy:
		target_enemy = closest_enemy
		last_target_pos = closest_enemy.global_position
	elif player:
		last_target_pos = player.global_position # fallback

func _check_boulder_collision() -> bool:
	"""Check if rocket hit a boulder."""
	# Skip if Chrono-Intangibility upgrade is active
	if is_intangible:
		return false
	
	var boulders := TargetCache.get_boulders()
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = 150.0 # Default
		if boulder.get("boulder_size") != null:
			boulder_radius = boulder.boulder_size * 0.5
		
		# Optimization: Squared distance check
		var dist_sq = global_position.distance_squared_to(boulder_pos)
		if dist_sq < boulder_radius * boulder_radius:
			return true
	return false


func _on_body_entered(body):
	if body == player:
		return
	# Ignore other projectiles (rockets, missiles, etc.)
	if body.is_in_group("projectiles"):
		return
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	# Only damage enemies - skip friendly units (allies, clones, turrets, etc.)
	if not body.is_in_group("enemies"):
		return
	# IMPACT DAMAGE REMOVED: Rely on Explosion for damage to avoid double-hits/text.
	# The explosion spawns immediately and will hit this body.
	call_deferred("explode")

func explode():
	if _has_exploded:
		return
	_has_exploded = true
	var explosion = ProjectileCache.create_explosion()
	explosion.owner_node = owner_node # Pass owner for killer_source tracking
	explosion.killer_source_override = killer_source_override # Pass override too
	
	# Pass dynamic damage to explosion
	if explosion.has_method("initialize"):
		explosion.initialize(explosion_damage, explosion_radius)
	
	get_parent().add_child(explosion)
	explosion.global_position = global_position
	ProjectileCache.return_to_pool(self)