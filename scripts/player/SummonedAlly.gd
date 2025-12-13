extends CharacterBody2D
class_name SummonedAlly

## AI-controlled ally summoned by Commander's burst
## Can be Scarlet, Snow White, or Rapunzel with smart behavior

signal ally_expired
signal ally_died

# Preload effect scripts, scenes, and shaders
const ExplosionEffectScript = preload("res://scripts/effects/ExplosionEffect.gd")
const HologramShader = preload("res://resources/shaders/hologram_ally.gdshader")
const ScarletBurstEffectScript = preload("res://scripts/characters/effects/ScarletBurstEffect.gd")
const SnowWhiteBurstBeamScript = preload("res://scripts/characters/effects/SnowWhiteBurstBeam.gd")
const RapunzelBurstEffectScript = preload("res://scripts/characters/effects/RapunzelBurstEffect.gd")

# Character registry for stats
var _registry: CharacterRegistry = null

# Ally type enum
enum AllyType { SCARLET, SNOW_WHITE, RAPUNZEL }

# Core properties
var ally_type: AllyType = AllyType.SCARLET
var owner_player: Node2D = null
var lifetime: float = 10.0
var _time_alive: float = 0.0
var _has_used_burst: bool = false
var _burst_used_time: float = -1.0
var player_level: int = 1  # Player level for damage scaling

# Stats (will be configured based on ally type)
var max_hp: int = 50
var current_hp: int = 50
var move_speed: float = 160.0
var attack_damage: int = 15
var attack_range: float = 400.0
var attack_cooldown: float = 0.3

# State
var _attack_timer: float = 0.0
var _special_timer: float = 0.0
var _special_cooldown: float = 5.0
var _target_enemy: Node2D = null
var _last_direction: Vector2 = Vector2.DOWN
var _animator: AnimatedSprite2D = null

# Scarlet-specific
var _scarlet_combo_count: int = 0

# Snow White-specific
var _snow_white_ammo: int = 7
var _snow_white_max_ammo: int = 7
var _snow_white_reload_timer: float = 0.0
var _snow_white_turret_placed: bool = false

# Rapunzel-specific
var _rapunzel_ammo: int = 4
var _rapunzel_max_ammo: int = 4
var _rapunzel_reload_timer: float = 0.0
var _rapunzel_special_used: bool = false  # Limit to 1 special per summon

# Visual
var _spawn_effect_timer: float = 0.8  # Longer spawn animation
var _spawn_duration: float = 0.8  # Duration of spawn-in effect
var _despawn_timer: float = 0.0  # Timer for despawn animation
var _despawn_duration: float = 0.6  # Duration of despawn effect
var _is_despawning: bool = false
var _glow_time: float = 0.0
var _shader_material: ShaderMaterial = null

# Health bar visuals
const HEALTH_BAR_WIDTH := 40.0
const HEALTH_BAR_HEIGHT := 8.0
const HEALTH_BAR_OFFSET_Y := -45.0
var _health_bar_bg: ColorRect = null
var _health_bar_fill: ColorRect = null
var _health_bar_label: Node2D = null  # Now uses SummonHPLabel script for world-space text

# AI behavior
var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	z_index = 9
	add_to_group("summoned_allies")
	add_to_group("player_allies")
	
	# Set up collision - use layer 8 for allies (doesn't interact with player layer 1)
	collision_layer = 8  # Unique ally layer
	collision_mask = 4   # Only collide with enemies, not player
	
	# Create animator
	_create_animator()
	
	# Create collision shape
	_create_collision_shape()
	
	# Create health bar
	_create_health_bar()
	
	# Initialize based on type
	_configure_ally_type()
	
	# Start with attack on cooldown to prevent burst fire on spawn
	_attack_timer = attack_cooldown
	# Start with special on cooldown to give time to position
	_special_timer = _special_cooldown * 0.5
	
	current_hp = max_hp
	_update_health_bar()
	_last_position = global_position
	
	set_process(true)
	set_physics_process(true)

func _create_animator() -> void:
	_animator = AnimatedSprite2D.new()
	_animator.centered = true
	_animator.z_index = 10
	
	# Create and apply hologram shader material
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = HologramShader
	_shader_material.set_shader_parameter("spawn_progress", 0.0)
	_shader_material.set_shader_parameter("time", 0.0)
	_shader_material.set_shader_parameter("hologram_color", Color(0.85, 0.9, 1.0, 1.0))
	_shader_material.set_shader_parameter("scanline_speed", 2.0)
	_shader_material.set_shader_parameter("hex_scale", 25.0)
	_shader_material.set_shader_parameter("flicker_intensity", 0.08)
	_shader_material.set_shader_parameter("edge_glow", 1.2)
	_animator.material = _shader_material
	
	_animator.material = _shader_material
	
	add_child(_animator)




func _create_collision_shape() -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	collision.shape = shape
	add_child(collision)

func _create_health_bar() -> void:
	# Background (dark)
	_health_bar_bg = ColorRect.new()
	_health_bar_bg.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_bg.position = Vector2(-HEALTH_BAR_WIDTH / 2.0, HEALTH_BAR_OFFSET_Y)
	_health_bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	_health_bar_bg.z_index = 100
	add_child(_health_bar_bg)
	
	# Fill (silver/white for hologram theme)
	_health_bar_fill = ColorRect.new()
	_health_bar_fill.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_fill.position = Vector2(-HEALTH_BAR_WIDTH / 2.0, HEALTH_BAR_OFFSET_Y)
	_health_bar_fill.color = Color(0.7, 0.85, 1.0, 1.0)  # Light blue/silver
	_health_bar_fill.z_index = 101
	add_child(_health_bar_fill)
	
	# HP text label using custom draw script (like EnemyHPLabel) for world-space rendering
	var hp_label_script = load("res://scripts/effects/SummonHPLabel.gd")
	if hp_label_script:
		_health_bar_label = Node2D.new()
		_health_bar_label.set_script(hp_label_script)
		_health_bar_label.z_index = 102
		# Position at center of health bar
		_health_bar_label.position = Vector2(0, HEALTH_BAR_OFFSET_Y + HEALTH_BAR_HEIGHT / 2.0)
		add_child(_health_bar_label)
		_health_bar_label.setup(self)

func _update_health_bar() -> void:
	if _health_bar_fill:
		var hp_ratio := float(current_hp) / float(max_hp) if max_hp > 0 else 1.0
		_health_bar_fill.size.x = HEALTH_BAR_WIDTH * hp_ratio
		
		# Change color based on health (blue -> orange -> red)
		if hp_ratio > 0.5:
			_health_bar_fill.color = Color(0.7, 0.85, 1.0, 1.0)  # Light blue
		elif hp_ratio > 0.25:
			_health_bar_fill.color = Color(1.0, 0.6, 0.2, 1.0)  # Orange
		else:
			_health_bar_fill.color = Color(1.0, 0.3, 0.3, 1.0)  # Red
	
	if _health_bar_label and _health_bar_label.has_method("update_values"):
		_health_bar_label.update_values(current_hp, max_hp)

func _configure_ally_type() -> void:
	# Get registry for character stats
	_registry = CharacterRegistry.get_instance()
	
	match ally_type:
		AllyType.SCARLET:
			_configure_scarlet()
		AllyType.SNOW_WHITE:
			_configure_snow_white()
		AllyType.RAPUNZEL:
			_configure_rapunzel()

func _configure_scarlet() -> void:
	# HP scales with player level
	var hp_mult := 1.0 + (player_level - 1) * 0.25
	max_hp = int(60 * hp_mult)
	move_speed = 280.0  # Fast melee rusher
	# Damage uses player's full multiplier (level + shop ATK) × weapon base
	attack_damage = _get_scaled_damage(10)  # Scarlet's base_damage
	attack_range = 120.0  # Melee
	attack_cooldown = 1.0  # 1 second between slashes for animation
	_special_cooldown = 3.0
	_load_sprite("scarlet")

func _configure_snow_white() -> void:
	# HP scales with player level
	var hp_mult := 1.0 + (player_level - 1) * 0.25
	max_hp = int(45 * hp_mult)
	move_speed = 200.0  # Mobile sniper
	# Damage uses player's full multiplier (level + shop ATK) × weapon base
	attack_damage = _get_scaled_damage(7)  # Snow White's base_damage
	attack_range = 600.0  # Sniper
	attack_cooldown = 0.5  # Slower sniper shots (was 0.2)
	_special_cooldown = 6.0
	# Get ammo from registry
	var snow_white_data := _registry.get_character("snow_white") if _registry else null
	_snow_white_ammo = snow_white_data.ammo_capacity if snow_white_data else 7
	_snow_white_max_ammo = _snow_white_ammo
	_load_sprite("snow_white")

func _configure_rapunzel() -> void:
	# HP scales with player level
	var hp_mult := 1.0 + (player_level - 1) * 0.25
	max_hp = int(55 * hp_mult)
	move_speed = 220.0  # Mobile launcher
	# Damage uses player's full multiplier (level + shop ATK) × weapon base
	attack_damage = _get_scaled_damage(10)  # Rapunzel's base_damage
	attack_range = 500.0  # Rockets
	attack_cooldown = 1.5  # Slower rockets (was 0.3)
	_special_cooldown = 4.0
	# Get ammo from registry (1.5x base ammo for allies)
	var rapunzel_data := _registry.get_character("rapunzel") if _registry else null
	var base_ammo: int = rapunzel_data.ammo_capacity if rapunzel_data else 4
	_rapunzel_ammo = int(base_ammo * 1.5)
	_rapunzel_max_ammo = _rapunzel_ammo
	_load_sprite("rapunzel")

## Get damage scaled by player's full multiplier (level + shop ATK bonus)
func _get_scaled_damage(base_damage: int) -> int:
	if owner_player and is_instance_valid(owner_player) and owner_player.has_method("calculate_damage"):
		# Use player's calculate_damage to get full scaling (level + shop ATK)
		return owner_player.calculate_damage(base_damage)
	# Fallback: just use level scaling
	var level_mult := 1.0 + (player_level - 1) * 0.25
	return maxi(1, int(base_damage * level_mult))

func _load_sprite(character_id: String) -> void:
	# Map character ID to sprite paths
	var sprite_paths := {
		"scarlet": "res://assets/characters/scarlet/scarlet-sprite.png",
		"snow_white": "res://assets/characters/snow-white/snow-white-sprite.png",
		"rapunzel": "res://assets/characters/rapunzel/rapunzel-sprite.png"
	}
	
	var sprite_path: String = sprite_paths.get(character_id, "")
	if sprite_path.is_empty() or not ResourceLoader.exists(sprite_path):
		return
	
	var texture: Texture2D = load(sprite_path)
	if texture == null:
		return
	
	# Create sprite frames from sheet (3 columns, 4 rows for directional movement)
	var frames := SpriteFrames.new()
	var columns := 3
	var rows := 4
	@warning_ignore("integer_division")
	var frame_width: int = texture.get_width() / columns
	@warning_ignore("integer_division")
	var frame_height: int = texture.get_height() / rows
	
	# Direction mappings: row 0=down, 1=left, 2=right, 3=up
	var directions: Array[String] = ["down", "left", "right", "up"]
	
	for row in range(rows):
		var anim_name: String = directions[row]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, 8.0)
		frames.set_animation_loop(anim_name, true)
		
		for col in range(columns):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
			frames.add_frame(anim_name, atlas)
	
	_animator.sprite_frames = frames
	_animator.scale = Vector2(0.18, 0.18)  # Scale down to match game
	_animator.play("down")

func _process(delta: float) -> void:
	_time_alive += delta
	_glow_time += delta
	
	# Handle despawn animation
	if _is_despawning:
		_despawn_timer -= delta
		if _shader_material:
			# Reverse the spawn animation (1 to 0)
			var despawn_progress := clampf(_despawn_timer / _despawn_duration, 0.0, 1.0)
			_shader_material.set_shader_parameter("spawn_progress", despawn_progress)
			_shader_material.set_shader_parameter("time", _glow_time)
		
		if _despawn_timer <= 0:
			queue_free()
		return  # Don't do anything else while despawning
	
	# Update shader time and spawn animation
	if _shader_material:
		_shader_material.set_shader_parameter("time", _glow_time)
		
		# Animate spawn progress (0 to 1 over spawn duration)
		var spawn_progress := clampf(_time_alive / _spawn_duration, 0.0, 1.0)
		_shader_material.set_shader_parameter("spawn_progress", spawn_progress)
	
	# Spawn effect timer (controls when AI starts acting)
	if _spawn_effect_timer > 0:
		_spawn_effect_timer -= delta
	
	# Check lifetime
	if _time_alive >= lifetime:
		_expire()
		return
	
	# Update timers
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_special_timer = maxf(0.0, _special_timer - delta)
	
	# Type-specific timers
	match ally_type:
		AllyType.SNOW_WHITE:
			if _snow_white_reload_timer > 0:
				_snow_white_reload_timer -= delta
				if _snow_white_reload_timer <= 0:
					_snow_white_ammo = _snow_white_max_ammo
		AllyType.RAPUNZEL:
			if _rapunzel_reload_timer > 0:
				_rapunzel_reload_timer -= delta
				if _rapunzel_reload_timer <= 0:
					_rapunzel_ammo = _rapunzel_max_ammo
	
	# AI decision making
	_update_ai(delta)
	
	# Check if should use burst
	_check_burst_usage()
	
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _spawn_effect_timer > 0:
		return  # Don't move during spawn animation
	
	if _is_despawning:
		velocity = Vector2.ZERO
		return  # Don't move during despawn animation
	
	# Find and pursue target
	_target_enemy = _find_best_target()
	
	if _target_enemy and is_instance_valid(_target_enemy):
		var to_target := _target_enemy.global_position - global_position
		var dist := to_target.length()
		
		# Determine optimal range based on type
		var optimal_range := _get_optimal_range()
		
		if dist > optimal_range:
			# Move toward target
			var move_dir := to_target.normalized()
			velocity = move_dir * move_speed
			_last_direction = move_dir
		elif dist < optimal_range * 0.5 and ally_type != AllyType.SCARLET:
			# Too close - back away (except Scarlet who wants to be close)
			var move_dir := -to_target.normalized()
			velocity = move_dir * move_speed * 0.5
			_last_direction = to_target.normalized()
		else:
			# In range - stop and attack
			velocity = Vector2.ZERO
			_last_direction = to_target.normalized()
	else:
		# No target - follow player loosely
		if owner_player and is_instance_valid(owner_player):
			var to_player := owner_player.global_position - global_position
			if to_player.length() > 150.0:
				velocity = to_player.normalized() * move_speed * 0.7
				_last_direction = to_player.normalized()
			else:
				velocity = Vector2.ZERO
		else:
			velocity = Vector2.ZERO
	
	# Apply separation from other allies
	_apply_separation()
	
	move_and_slide()
	
	# Update animation
	_update_animation()
	
	# Check if stuck
	_check_stuck(delta)

func _get_optimal_range() -> float:
	match ally_type:
		AllyType.SCARLET:
			return 80.0  # Get close for melee
		AllyType.SNOW_WHITE:
			return 400.0  # Keep distance for sniping
		AllyType.RAPUNZEL:
			return 300.0  # Medium range for rockets
	return 200.0

func _find_best_target() -> Node2D:
	var enemies := TargetCache.get_enemies()
	var best_target: Node2D = null
	var best_dist: float = 999999.0
	
	# Always target nearest enemy for aggressive behavior
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_node := enemy as Node2D
		var dist := global_position.distance_to(enemy_node.global_position)
		
		if dist < best_dist:
			best_dist = dist
			best_target = enemy_node
	
	return best_target

func _update_ai(_delta: float) -> void:
	if _spawn_effect_timer > 0:
		return
	
	# Aggressively attack whenever possible
	if _target_enemy and is_instance_valid(_target_enemy):
		var dist := global_position.distance_to(_target_enemy.global_position)
		
		# Attack immediately if cooldown ready (don't wait for perfect range)
		if _attack_timer <= 0:
			# Attack if reasonably close (within 1.5x range)
			if dist <= attack_range * 1.5:
				_perform_attack()
		
		# Use special if cooldown ready and should use it
		if _special_timer <= 0 and _should_use_special():
			_perform_special()
	else:
		# No target - look for any enemy and use special if available
		if _special_timer <= 0 and _should_use_special():
			var tree := get_tree()
			if tree and tree.get_nodes_in_group("enemies").size() > 0:
				_perform_special()

func _perform_attack() -> void:
	if not _target_enemy or not is_instance_valid(_target_enemy):
		return
	
	var direction := (_target_enemy.global_position - global_position).normalized()
	
	match ally_type:
		AllyType.SCARLET:
			_attack_scarlet(direction)
		AllyType.SNOW_WHITE:
			_attack_snow_white(direction)
		AllyType.RAPUNZEL:
			_attack_rapunzel(direction)
	
	_attack_timer = attack_cooldown

func _attack_scarlet(direction: Vector2) -> void:
	# Melee slash attack using the scene
	var slash = ProjectileCache.create_slash()
	
	# Safety check - if scene failed to instantiate, skip this attack
	if slash == null:
		return
	
	slash.rotation = direction.angle()
	slash.base_damage = attack_damage
	slash.owner_node = self  # Set owner for killer_source tracking
	add_child(slash)  # Attach to self
	slash.position = Vector2.ZERO
	
	_scarlet_combo_count += 1

func _attack_snow_white(direction: Vector2) -> void:
	if _snow_white_ammo <= 0:
		# Start reload - fast reload
		if _snow_white_reload_timer <= 0:
			_snow_white_reload_timer = 0.8  # Quick reload
		return
	
	_snow_white_ammo -= 1
	
	# Fire piercing sniper bullet like player Snow White uses
	var bullet = ProjectileCache.create_snow_white_bullet()
	
	# Safety check - if bullet failed to instantiate, skip this attack
	if bullet == null:
		return
	
	# Spawn well outside the ally's collision
	get_parent().add_child(bullet)
	bullet.global_position = global_position + direction * 60
	bullet.velocity = direction * 2200.0  # Same speed as player
	bullet.rotation = direction.angle()
	bullet.owner_node = self
	bullet.base_damage = attack_damage
	bullet.pierce_all = true  # Snow White's signature piercing

func _attack_rapunzel(direction: Vector2) -> void:
	if _rapunzel_ammo <= 0:
		# Start reload - faster reload
		if _rapunzel_reload_timer <= 0:
			_rapunzel_reload_timer = 1.5  # Quick reload
		return
	
	_rapunzel_ammo -= 1
	
	# Fire rocket using Missile scene
	var rocket = ProjectileCache.create_missile()
	
	# Safety check - if scene failed to instantiate, skip this attack
	if rocket == null:
		return
	
	rocket.owner_node = self  # Set self as owner so rocket ignores us
	rocket.direction = direction
	rocket.target_position = _target_enemy.global_position if _target_enemy else global_position + direction * 400
	rocket.speed = 400.0
	
	# Spawn well outside the ally's collision (radius ~24)
	get_parent().add_child(rocket)
	rocket.global_position = global_position + direction * 50

func _should_use_special() -> bool:
	# Use special when:
	# 1. Multiple enemies nearby
	# 2. Target is tough (elite/boss)
	# 3. Haven't used it in a while
	
	var enemies := TargetCache.get_enemies()
	var nearby_count := 0
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		var dist := global_position.distance_to((enemy as Node2D).global_position)
		if dist < 200.0:
			nearby_count += 1
	
	# Scarlet: Use when surrounded by 3+ enemies
	if ally_type == AllyType.SCARLET and nearby_count >= 3:
		return true
	
	# Snow White: Place turret only once (flag prevents spam)
	if ally_type == AllyType.SNOW_WHITE and not _snow_white_turret_placed:
		return true
	
	# Rapunzel: Always spawn healing crosses once per summon (no HP check)
	if ally_type == AllyType.RAPUNZEL and not _rapunzel_special_used:
		return true
	
	return false

func _perform_special() -> void:
	match ally_type:
		AllyType.SCARLET:
			_special_scarlet()
		AllyType.SNOW_WHITE:
			_special_snow_white()
		AllyType.RAPUNZEL:
			_special_rapunzel()
	
	_special_timer = _special_cooldown

func _special_scarlet() -> void:
	# Piercing wave attack like player Scarlet's special
	var direction := _last_direction.normalized()
	if direction.length() < 0.5:
		direction = Vector2.RIGHT
	
	var wave = ProjectileCache.create_scarlet_wave()
	wave.rotation = direction.angle()
	wave.owner_node = self
	wave.pierce_all = true
	wave.damage = attack_damage * 2
	get_parent().add_child(wave)
	wave.global_position = global_position + direction * 30
	wave.velocity = direction.normalized() * 1800

func _special_snow_white() -> void:
	# Find a good position for turret that's spaced from existing turrets
	var spawn_pos := _find_spaced_position("Turret", 120.0)
	
	# Place a turret only (no healing crosses - that's Rapunzel's job)
	var turret = ProjectileCache.create_turret()
	# Upgraded turret with more ammo
	turret.ammo = 12
	turret.max_ammo = 12
	# Mark turret as spawned by summon for killer_source tracking
	turret.spawned_by_summon = true
	turret.spawner_node = self
	
	get_parent().add_child(turret)
	turret.global_position = spawn_pos
	
	_snow_white_turret_placed = true

func _find_spaced_position(node_name_contains: String, min_distance: float) -> Vector2:
	# Find a position that's spaced away from existing nodes with similar names
	var base_pos := global_position
	var best_pos := base_pos
	var best_min_dist := 0.0
	
	# Get all existing similar nodes
	var existing_nodes: Array[Node2D] = []
	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child is Node2D and node_name_contains in child.name:
				existing_nodes.append(child as Node2D)
	
	# If no existing nodes, just use current position
	if existing_nodes.is_empty():
		return base_pos
	
	# Try several candidate positions and pick the one farthest from existing nodes
	var candidates: Array[Vector2] = [base_pos]
	for angle_idx in range(8):
		var angle := TAU * float(angle_idx) / 8.0
		var offset := Vector2(cos(angle), sin(angle)) * min_distance
		candidates.append(base_pos + offset)
	
	for candidate in candidates:
		var min_dist_to_existing := INF
		for existing in existing_nodes:
			var dist := candidate.distance_to(existing.global_position)
			min_dist_to_existing = minf(min_dist_to_existing, dist)
		
		if min_dist_to_existing > best_min_dist:
			best_min_dist = min_dist_to_existing
			best_pos = candidate
	
	# If best position is still too close, offset further
	if best_min_dist < min_distance * 0.5:
		var away_dir := Vector2.ZERO
		for existing in existing_nodes:
			away_dir += (base_pos - existing.global_position).normalized()
		if away_dir.length() > 0.1:
			best_pos = base_pos + away_dir.normalized() * min_distance
	
	return best_pos

func _special_rapunzel() -> void:
	# Spawn healing cross - only once per summon
	var spawn_pos := _find_spaced_position("HealingCross", 80.0)
	
	# Spawn one healing cross
	var heal_item = ProjectileCache.create_healing_cross()
	get_parent().add_child(heal_item)
	heal_item.global_position = spawn_pos
	
	_rapunzel_special_used = true

func _spawn_heal_effect() -> void:
	# Simple heal visual - just queue a redraw, no dynamic script needed
	# The heal effect is shown via the ally's own _draw() pulse
	pass

func _check_burst_usage() -> void:
	if _has_used_burst:
		return
	
	# Don't burst immediately - wait at least 2 seconds
	if _time_alive < 2.0:
		return
	
	var should_burst := false
	var time_remaining := lifetime - _time_alive
	
	# Check for boss nearby - always burst if boss in range
	var enemies := TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		var enemy_node := enemy as Node2D
		var dist := global_position.distance_to(enemy_node.global_position)
		
		# Check if this is a boss or elite
		if enemy_node.has_meta("enemy_tier"):
			var tier: String = enemy_node.get_meta("enemy_tier")
			if tier in ["boss", "elite"] and dist < 400.0:
				should_burst = true
				break
	
	# In last 3 seconds - use burst randomly when good opportunity
	if time_remaining <= 3.0 and time_remaining > 0.5:
		# Count nearby enemies to find best moment
		var nearby_count := 0
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy is Node2D:
				if global_position.distance_to((enemy as Node2D).global_position) < 250.0:
					nearby_count += 1
		
		# Burst if 3+ enemies nearby, or randomly in last 1.5 seconds
		if nearby_count >= 3:
			should_burst = true
		elif time_remaining <= 1.5 and randf() < 0.3:  # 30% chance each frame
			should_burst = true
	
	# Emergency burst if about to expire (last 0.5 seconds)
	if time_remaining <= 0.5:
		should_burst = true
	
	# Use if low HP and might die
	if float(current_hp) / float(max_hp) < 0.25:
		should_burst = true
	
	if should_burst:
		_perform_burst()

func _perform_burst() -> void:
	if _has_used_burst:
		return
	
	_has_used_burst = true
	_burst_used_time = _time_alive
	
	match ally_type:
		AllyType.SCARLET:
			_burst_scarlet()
		AllyType.SNOW_WHITE:
			_burst_snow_white()
		AllyType.RAPUNZEL:
			_burst_rapunzel()

func _burst_scarlet() -> void:
	# Use the same burst effect as the player - hits all enemies on screen
	var effect = ScarletBurstEffectScript.new()
	effect.owner_node = self
	effect.execute_talent = false  # No execution talent for allies
	effect.vuln_talent = false  # No vulnerability talent for allies
	get_parent().add_child(effect)
	effect.global_position = global_position

func _burst_snow_white() -> void:
	# Use the same burst beam as the player - 90° ice beam
	var direction := _last_direction.normalized()
	if direction.length() < 0.5:
		direction = Vector2.RIGHT
	
	var beam = SnowWhiteBurstBeamScript.new()
	beam.owner_node = self
	beam.damage = 50  # Same as player
	beam.beam_range = 1200.0
	beam.beam_angle_degrees = 90.0
	beam.burn_level = 0  # No burn talent for allies
	beam.gauge_on_kill = false  # No gauge refill for allies
	beam.player_level = player_level
	beam.configure(direction)
	get_parent().add_child(beam)
	beam.global_position = global_position

func _burst_rapunzel() -> void:
	# Use the same burst effect as the player - full heal + stun all enemies
	var effect = RapunzelBurstEffectScript.new()
	effect.owner_node = self
	effect.stun_duration = 4.0  # Base stun, no talent upgrade for allies
	effect.grant_invuln = false  # No invulnerability for allies
	get_parent().add_child(effect)
	effect.global_position = global_position

func _spawn_burst_nova(_color: Color, _radius: float) -> void:
	# Burst visual is handled by screen flash if available, or just skip
	# This avoids expensive dynamic script creation
	if owner_player and is_instance_valid(owner_player):
		if "screen_flash" in owner_player and owner_player.screen_flash:
			if owner_player.screen_flash.has_method("flash_custom"):
				owner_player.screen_flash.flash_custom(_color, 0.2)

func _apply_separation() -> void:
	# Avoid overlapping with other allies
	# Avoid overlapping with other allies
	var separation := Vector2.ZERO
	var allies := TargetCache.get_summoned_allies()
	
	for ally in allies:
		if ally == self or not is_instance_valid(ally) or not ally is Node2D:
			continue
		var to_self := global_position - (ally as Node2D).global_position
		var dist := to_self.length()
		if dist < 60.0 and dist > 0:
			separation += to_self.normalized() * (60.0 - dist)
	
	# Also separate from player
	if owner_player and is_instance_valid(owner_player):
		var to_self := global_position - owner_player.global_position
		var dist := to_self.length()
		if dist < 50.0 and dist > 0:
			separation += to_self.normalized() * (50.0 - dist)
	
	velocity += separation * 3.0

func _check_stuck(delta: float) -> void:
	if global_position.distance_to(_last_position) < 2.0:
		_stuck_timer += delta
		if _stuck_timer > 1.0:
			# Teleport to unstuck
			var random_offset := Vector2(randf_range(-50, 50), randf_range(-50, 50))
			global_position += random_offset
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
	_last_position = global_position

func _update_animation() -> void:
	if not _animator or not _animator.sprite_frames:
		return
	
	var anim_name := "down"
	if abs(_last_direction.x) > abs(_last_direction.y):
		anim_name = "right" if _last_direction.x > 0 else "left"
	else:
		anim_name = "down" if _last_direction.y > 0 else "up"
	
	if _animator.sprite_frames.has_animation(anim_name):
		if _animator.animation != anim_name:
			_animator.animation = anim_name
		if not _animator.is_playing():
			_animator.play()

func _draw() -> void:
	# Spawn ring effect (silver/white themed to match hologram)
	if _spawn_effect_timer > 0:
		var spawn_progress := 1.0 - (_spawn_effect_timer / _spawn_duration)
		var ring_radius := 50.0 * spawn_progress
		var alpha := (1.0 - spawn_progress) * 0.9
		
		# Silver/white spawn rings
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 32, Color(0.9, 0.95, 1.0, alpha), 3.0)
		draw_arc(Vector2.ZERO, ring_radius * 0.7, 0, TAU, 32, Color(0.7, 0.85, 1.0, alpha * 0.6), 2.0)
		draw_arc(Vector2.ZERO, ring_radius * 1.3, 0, TAU, 32, Color(0.8, 0.9, 1.0, alpha * 0.4), 2.0)
	
	# Subtle holographic floor glow
	var pulse := 0.5 + 0.3 * sin(_glow_time * 3.0)
	var glow_alpha := 0.1 * pulse
	
	# Always use silver/blue hologram glow regardless of ally type
	draw_circle(Vector2.ZERO, 30.0, Color(0.6, 0.8, 1.0, glow_alpha))

func take_damage(amount: int, _is_crit: bool = false, _direction: Vector2 = Vector2.ZERO, _from_burst: bool = false) -> void:
	current_hp = maxi(0, current_hp - amount)
	_update_health_bar()
	
	if current_hp <= 0:
		_die()

func _die() -> void:
	# Start despawn animation (faster for death)
	if not _is_despawning:
		_is_despawning = true
		_despawn_timer = _despawn_duration * 0.5  # Faster despawn on death
		ally_died.emit()

func _expire() -> void:
	# Use burst if we haven't yet
	if not _has_used_burst:
		_perform_burst()
	
	# Start despawn animation
	if not _is_despawning:
		_is_despawning = true
		_despawn_timer = _despawn_duration
		ally_expired.emit()

## Setup the ally with owner and type
func setup(player: Node2D, type: int, level: int = 1) -> void:
	owner_player = player
	ally_type = type as AllyType
	player_level = level
	# Defer configuration until after _ready() has run
	# This ensures _animator exists before we try to set sprite_frames

## Get ally type name for debug
func get_type_name() -> String:
	match ally_type:
		AllyType.SCARLET:
			return "Scarlet"
		AllyType.SNOW_WHITE:
			return "Snow White"
		AllyType.RAPUNZEL:
			return "Rapunzel"
	return "Unknown"
