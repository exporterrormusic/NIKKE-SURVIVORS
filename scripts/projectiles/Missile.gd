extends Area2D

# Cached ShopMenu reference for intangibility checks
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

var velocity = Vector2.ZERO
var target_pos = Vector2.ZERO
var acceleration = 1000
var max_speed = 1000
var owner_node: Node = null
var killer_source: String = "turret" # For ShielderShield collision detection (Snow White turret missiles)
var create_burning_ground: bool = false # Only true for Rapunzel's missiles

# These match the original simple missile but can be set externally
var direction = Vector2.ZERO
var target_position = Vector2.ZERO
var explode_at_target = false
var speed = 400
var target_node: Node = null

# Damage config
var base_damage: int = 10 # Default explosion damage
var damage: int = 10 # Direct hit damage
var explosion_damage: int = 10 # AOE damage
var explosion_radius: float = 120.0 # AOE radius
var killer_source_override: String = "" # For summoned units
var ground_fire_enabled: bool = false
var ground_fire_duration: float = 3.0
var ground_fire_damage: int = 3
var ground_fire_radius: float = 100.0

# Smoke trail settings
const SMOKE_INTERVAL := 0.03
const SMOKE_LIFETIME := 0.4
const SMOKE_START_SIZE := 6.0
const SMOKE_END_SIZE := 14.0
var _smoke_timer := 0.0
var _smoke_particles: Array = []
var _trail_color := Color(0.5, 0.5, 0.55, 0.6) # Grey smoke
var _fire_color := Color(1.0, 0.5, 0.2, 0.8) # Orange fire core
var _light: PointLight2D = null

# Performance: disable dynamic lights on missiles (expensive with many projectiles)
const ENABLE_MISSILE_LIGHTS := false

func _ready():
	# Make missile unshaded (glows in dark)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	add_to_group("projectiles")
	connect("body_entered", Callable(self, "_on_body_entered"))
	set_process(true)
	
	# Dynamic lights are expensive - disabled by default
	if ENABLE_MISSILE_LIGHTS:
		_light = PointLight2D.new()
		_light.name = "MissileLight"
		_light.color = Color(1.0, 0.6, 0.2) # Orange glow
		_light.energy = 0.7
		_light.texture = _create_light_texture()
		_light.texture_scale = 0.25
		_light.shadow_enabled = false
		add_child(_light)

func _create_light_texture() -> Texture2D:
	# Use cached texture for performance
	return TextureCache.get_light_texture_64()

func _process(delta):
	# Flicker the light (every other frame)
	if _light and Engine.get_process_frames() % 2 == 0:
		_light.energy = 0.6 + randf() * 0.3
	
	# Update smoke trail
	_smoke_timer += delta
	if _smoke_timer >= SMOKE_INTERVAL:
		_smoke_timer = 0.0
		_spawn_smoke_particle()
	
	# Update existing smoke particles
	var i := 0
	while i < _smoke_particles.size():
		var p: Dictionary = _smoke_particles[i]
		p["age"] += delta
		if p["age"] >= SMOKE_LIFETIME:
			_smoke_particles.remove_at(i)
			continue
		# Smoke rises and drifts
		p["pos"] += Vector2(randf_range(-8, 8), -20) * delta
		_smoke_particles[i] = p
		i += 1
	
	# Only redraw every other frame for performance
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()

func _spawn_smoke_particle():
	_smoke_particles.append({
		"pos": global_position,
		"age": 0.0,
		"size_offset": randf_range(-2, 2)
	})

func _draw():
	# Draw smoke trail (in local space, so convert positions)
	for p in _smoke_particles:
		var life_ratio: float = p["age"] / SMOKE_LIFETIME
		var alpha := (1.0 - life_ratio) * 0.5
		var size: float = lerp(SMOKE_START_SIZE, SMOKE_END_SIZE, life_ratio) + p["size_offset"]
		var local_pos: Vector2 = p["pos"] - global_position
		
		# Fire core (fades fast)
		if life_ratio < 0.3:
			var fire_alpha := (1.0 - life_ratio / 0.3) * 0.7
			var fire_col := Color(_fire_color.r * 1.4, _fire_color.g * 1.4, _fire_color.b, fire_alpha)
			draw_circle(local_pos, size * 0.5, fire_col)
		
		# Smoke
		var smoke_col := Color(_trail_color.r, _trail_color.g, _trail_color.b, alpha)
		draw_circle(local_pos, size, smoke_col)

func _physics_process(delta):
	# Apply Global Enemy Time Scale (Bullet Time) - ONLY for non-player projectiles
	var time_scale = 1.0
	var game_manager = get_node_or_null("/root/GameManager")
	if not (owner_node and owner_node.is_in_group("player")):
		time_scale = game_manager.enemy_time_scale if game_manager else 1.0
	delta *= time_scale

	# Update target_pos if we have a valid target_node (for homing)
	if target_node and is_instance_valid(target_node) and target_node is Node2D:
		target_pos = target_node.global_position
	
	var dir = (target_pos - global_position).normalized()
	velocity += dir * acceleration * delta
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed
	position += velocity * delta
	rotation = velocity.angle()
	
	# Check boulder collision - explode if hitting a boulder
	if _check_boulder_collision():
		explode()
		return
	
	# Check if missile reached target - account for enemy scale
	var hit_distance: float = 10.0
	if target_node and is_instance_valid(target_node) and target_node is Node2D:
		var enemy_scale: float = target_node.scale.x if target_node.scale.x > 1.0 else 1.0
		hit_distance = 10.0 + 30.0 * (enemy_scale - 1.0) # Scale hitbox for large enemies
	if global_position.distance_to(target_pos) < hit_distance:
		explode()
	if position.x < -100 or position.x > 2000 or position.y < -100 or position.y > 1200:
		queue_free()

func _check_boulder_collision() -> bool:
	"""Check if missile hit a boulder."""
	# Skip if Chrono-Intangibility upgrade is active AND playing Wells
	var player = get_tree().get_first_node_in_group("player")
	var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
	var playing_wells = false
	if player and player.has_method("is_playing_character"):
		playing_wells = player.is_playing_character("wells")
	
	# DIAGNOSTIC
	if has_upgrade:
		print("[Missile] Intangibility Check: has_upgrade=", has_upgrade, " playing_wells=", playing_wells)
	
	if has_upgrade and playing_wells:
		return false
	
	var boulders := get_tree().get_nodes_in_group("boulders")
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_to(boulder_pos) < boulder_radius:
			return true
	return false

func explode():
	# Play explosion sound
	_play_explosion_sound()
	
	# Create explosion and let it handle damage (including shields)
	var explosion = ProjectileCache.create_explosion()
	explosion.owner_node = owner_node # Pass owner for killer_source tracking
	explosion.killer_source_override = killer_source_override # Pass override info if needed
	
	# Pass dynamic damage to explosion
	# Use explosion_damage if set, otherwise fallback to base_damage
	var final_damage = explosion_damage if explosion_damage > 0 else base_damage
	if explosion.has_method("initialize"):
		explosion.initialize(final_damage, explosion_radius)

	get_parent().add_child(explosion)
	explosion.global_position = global_position
	if explosion.has_method("force_damage_check"):
		explosion.force_damage_check()
	
	# Combat juice camera shake for explosion
	var combat_juice_script = load("res://scripts/systems/CombatJuice.gd")
	if combat_juice_script and combat_juice_script.instance:
		combat_juice_script.camera_shake(5.0)
	
	# Create burning ground effect if enabled (Rapunzel's missiles only)
	if create_burning_ground or ground_fire_enabled:
		_spawn_burning_ground()
	
	call_deferred("queue_free")

func _play_explosion_sound() -> void:
	# Try to find audio director in scene
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		player = get_tree().root.find_child("Player", true, false)
	if player and player.has_node("AudioDirector"):
		var audio = player.get_node("AudioDirector")
		if audio and audio.has_method("play_rocket_explosion_sound"):
			audio.play_rocket_explosion_sound()

func _spawn_burning_ground():
	var fire = ProjectileCache.create_ground_fire()
	get_parent().add_child(fire)
	fire.global_position = global_position
	# Configure burning ground with missile's settings
	fire.radius = ground_fire_radius
	fire.duration = ground_fire_duration
	fire.damage_per_tick = ground_fire_damage
	fire.tick_interval = 0.5
	# Golden/orange color to match Rapunzel's theme
	fire.color = Color(1.0, 0.7, 0.2, 0.5)
	fire.glow_color = Color(1.0, 0.6, 0.1, 0.4)
	fire.ember_color = Color(1.0, 0.8, 0.3, 0.8)

func _on_body_entered(body):
	# Ignore owner and allies
	if body == owner_node:
		return
	if body.is_in_group("summoned_allies"):
		return
	if body.is_in_group("player_allies"):
		return
	if body == get_parent().get_node_or_null("Player"):
		return
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	# Ignore other projectiles
	if body.is_in_group("projectiles"):
		return
	call_deferred("explode")