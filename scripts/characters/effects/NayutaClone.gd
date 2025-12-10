extends CharacterBody2D
class_name NayutaClone

## Nayuta's summoned clone
## Has 1/2 HP and attack of player
## Fights until killed, then dissolves into gold sparkles
## If heal upgrade: sparkles travel to player and heal them

signal clone_died

# Preload hologram shader
const HologramShader = preload("res://resources/shaders/hologram_ally.gdshader")

# Character registry for stats
var _registry: CharacterRegistry = null

# Core properties
var owner_player: Node2D = null
var weapon_type: String = "smg"  # smg, sword, rocket, sniper
var max_hp: int = 5
var current_hp: int = 5
var attack_multiplier: float = 0.5
var should_heal_on_death: bool = false
var player_level: int = 1  # Player level for damage/HP scaling

# Movement
var move_speed: float = 180.0
var _target_enemy: Node2D = null
var _last_direction: Vector2 = Vector2.DOWN

# Combat (varies by weapon type)
var attack_range: float = 400.0
var attack_cooldown: float = 0.08
var _attack_timer: float = 0.0

# Ammo (for ranged weapons)
var ammo: int = 30
var max_ammo: int = 30
var _reload_timer: float = 0.0
var reload_time: float = 2.0
var _is_reloading: bool = false

# Visual
var _animator: AnimatedSprite2D = null
var _shader_material: ShaderMaterial = null
var _spawn_timer: float = 0.8
var _spawn_duration: float = 0.8
var _glow_time: float = 0.0
var _is_dying: bool = false
var _death_timer: float = 0.0
var _death_duration: float = 1.0

# Health bar
var _health_bar_bg: ColorRect = null
var _health_bar_fill: ColorRect = null
var _health_bar_label: Node2D = null  # Now uses SummonHPLabel script for world-space text
const HEALTH_BAR_WIDTH := 40.0
const HEALTH_BAR_HEIGHT := 8.0
const HEALTH_BAR_OFFSET_Y := -45.0

# SMG burst fire control (2s shoot, 2s pause)
var _smg_burst_timer: float = 0.0
var _smg_is_paused: bool = false
const SMG_FIRE_DURATION := 2.0
const SMG_PAUSE_DURATION := 2.0

# Death sparkles
var _sparkles: Array = []  # Array of {pos, vel, life}
var _sparkles_traveling: bool = false

func _ready() -> void:
	z_index = 9
	add_to_group("nayuta_clones")
	add_to_group("player_allies")
	
	# Collision setup - use layer 8 (allies) so we don't collide with player
	# Layer 1 = player/world, Layer 4 = enemies, Layer 8 = allies
	# Mask: World (1), Enemies (4), Boulders (4)
	collision_layer = 8  # Allies layer
	collision_mask = 5   # Collide with World (1) and Enemies/Boulders (4)
	
	# Create visual components
	_create_animator()
	_create_collision_shape()
	_create_health_bar()
	
	# Configure weapon
	_configure_weapon()
	
	current_hp = max_hp
	
	set_process(true)
	set_physics_process(true)

func _create_animator() -> void:
	_animator = AnimatedSprite2D.new()
	_animator.centered = true
	_animator.z_index = 10
	
	# Apply hologram shader for Commander-style spawn effect
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = HologramShader
	_shader_material.set_shader_parameter("spawn_progress", 0.0)
	_shader_material.set_shader_parameter("time", 0.0)
	_shader_material.set_shader_parameter("hologram_color", Color(1.0, 0.85, 0.5, 1.0))  # Golden tint for Nayuta
	_shader_material.set_shader_parameter("scanline_speed", 2.0)
	_shader_material.set_shader_parameter("hex_scale", 25.0)
	_shader_material.set_shader_parameter("flicker_intensity", 0.08)
	_shader_material.set_shader_parameter("edge_glow", 1.2)
	_animator.material = _shader_material
	
	add_child(_animator)
	
	# Load Nayuta sprite
	_load_sprite()

func _load_sprite() -> void:
	var sprite_path := "res://assets/characters/nayuta/nayuta-sprite.png"
	if not ResourceLoader.exists(sprite_path):
		# Try alternate path
		sprite_path = "res://assets/nayuta.png"
		if not ResourceLoader.exists(sprite_path):
			return
	
	var texture: Texture2D = load(sprite_path)
	if texture == null:
		return
	
	# Create sprite frames (assuming 3 columns, 4 rows for directional movement)
	var frames := SpriteFrames.new()
	var columns := 3
	var rows := 4
	@warning_ignore("integer_division")
	var frame_width: int = texture.get_width() / columns
	@warning_ignore("integer_division")
	var frame_height: int = texture.get_height() / rows
	
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
	_animator.scale = Vector2(0.18, 0.18)
	_animator.play("down")

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
	
	# Fill (green)
	_health_bar_fill = ColorRect.new()
	_health_bar_fill.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_fill.position = Vector2(-HEALTH_BAR_WIDTH / 2.0, HEALTH_BAR_OFFSET_Y)
	_health_bar_fill.color = Color(0.3, 0.9, 0.3, 1.0)  # Green
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
		
		# Change color based on health (green -> orange -> red)
		if hp_ratio > 0.5:
			_health_bar_fill.color = Color(0.3, 0.9, 0.3, 1.0)  # Green
		elif hp_ratio > 0.25:
			_health_bar_fill.color = Color(1.0, 0.6, 0.2, 1.0)  # Orange
		else:
			_health_bar_fill.color = Color(1.0, 0.3, 0.3, 1.0)  # Red
	
	if _health_bar_label and _health_bar_label.has_method("update_values"):
		_health_bar_label.update_values(current_hp, max_hp)

func _configure_weapon() -> void:
	# Get registry for character stats
	_registry = CharacterRegistry.get_instance()
	
	# Clone weapons are 3x slower than player versions (except SMG which uses burst fire)
	# Ammo/reload values come from registry
	match weapon_type:
		"smg":
			var nayuta_data := _registry.get_character("nayuta")
			attack_range = 350.0
			attack_cooldown = 0.08  # Normal fire rate, burst system handles pauses
			max_ammo = nayuta_data.ammo_capacity if nayuta_data else 30
			ammo = max_ammo
			reload_time = nayuta_data.reload_time if nayuta_data else 2.0
		"sword":
			attack_range = 100.0
			attack_cooldown = 0.9  # 0.3 * 3
			max_ammo = -1  # Melee, no ammo
		"rocket":
			var rapunzel_data := _registry.get_character("rapunzel")
			attack_range = 450.0
			attack_cooldown = 1.5  # 0.5 * 3
			max_ammo = rapunzel_data.ammo_capacity if rapunzel_data else 4
			ammo = max_ammo
			reload_time = rapunzel_data.reload_time if rapunzel_data else 3.0
		"sniper":
			var snow_white_data := _registry.get_character("snow_white")
			attack_range = 600.0
			attack_cooldown = 1.05  # 0.35 * 3
			max_ammo = snow_white_data.ammo_capacity if snow_white_data else 7
			ammo = max_ammo
			reload_time = snow_white_data.reload_time if snow_white_data else 1.5

func _process(delta: float) -> void:
	_glow_time += delta
	
	# Handle death animation
	if _is_dying:
		_process_death(delta)
		return
	
	# Spawn effect
	if _spawn_timer > 0:
		_spawn_timer -= delta
	
	# Update shader
	if _shader_material:
		_shader_material.set_shader_parameter("time", _glow_time)
		var spawn_progress := clampf(1.0 - (_spawn_timer / _spawn_duration), 0.0, 1.0)
		_shader_material.set_shader_parameter("spawn_progress", spawn_progress)
	
	# Combat timers
	_attack_timer = maxf(0.0, _attack_timer - delta)
	
	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0:
			_is_reloading = false
			ammo = max_ammo
	
	# SMG burst fire timing (2s fire, 1s pause)
	if weapon_type == "smg":
		_smg_burst_timer += delta
		if _smg_is_paused:
			if _smg_burst_timer >= SMG_PAUSE_DURATION:
				_smg_is_paused = false
				_smg_burst_timer = 0.0
		else:
			if _smg_burst_timer >= SMG_FIRE_DURATION:
				_smg_is_paused = true
				_smg_burst_timer = 0.0
	
	# AI and combat
	_update_ai(delta)
	
	# Update health bar
	_update_health_bar()
	
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if _spawn_timer > 0 or _is_dying:
		velocity = Vector2.ZERO
		return
	
	# Find target
	_target_enemy = _find_best_target()
	
	if _target_enemy and is_instance_valid(_target_enemy):
		var to_target := _target_enemy.global_position - global_position
		var dist := to_target.length()
		
		# Optimal range based on weapon
		var optimal_range := attack_range * 0.8
		if weapon_type == "sword":
			optimal_range = 60.0  # Get close for melee
		
		if dist > optimal_range:
			var move_dir := to_target.normalized()
			velocity = move_dir * move_speed
			_last_direction = move_dir
		elif dist < optimal_range * 0.4 and weapon_type != "sword":
			# Too close, back away (except melee)
			var move_dir := -to_target.normalized()
			velocity = move_dir * move_speed * 0.5
			_last_direction = to_target.normalized()
		else:
			velocity = Vector2.ZERO
			_last_direction = to_target.normalized()
	else:
		# No target - follow player
		if owner_player and is_instance_valid(owner_player):
			var to_player := owner_player.global_position - global_position
			if to_player.length() > 150.0:
				velocity = to_player.normalized() * move_speed * 0.7
				_last_direction = to_player.normalized()
			else:
				velocity = Vector2.ZERO
		else:
			velocity = Vector2.ZERO
	
	# Separation from other clones and player
	_apply_separation()
	
	move_and_slide()
	_update_animation()

func _find_best_target() -> Node2D:
	var tree := get_tree()
	if not tree:
		return null
	
	var enemies := tree.get_nodes_in_group("enemies")
	var best_target: Node2D = null
	var best_dist: float = 999999.0
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		# Skip charmed enemies (they're friendly now)
		if enemy.is_in_group("charmed_allies"):
			continue
		
		# Skip dead or dying enemies
		if enemy.get("_is_dying") == true:
			continue
		if enemy.get("is_dying") == true:
			continue
		if enemy.get("current_hp") != null and enemy.get("current_hp") <= 0:
			continue
		if enemy.get("hp") != null and enemy.get("hp") <= 0:
			continue
		# Also check if enemy is queued for deletion
		if enemy.is_queued_for_deletion():
			continue
		
		var dist := global_position.distance_to((enemy as Node2D).global_position)
		if dist < best_dist:
			best_dist = dist
			best_target = enemy as Node2D
	
	return best_target

func _update_ai(_delta: float) -> void:
	if _spawn_timer > 0:
		return
	
	if _target_enemy and is_instance_valid(_target_enemy):
		var dist := global_position.distance_to(_target_enemy.global_position)
		
		if _attack_timer <= 0 and dist <= attack_range:
			_perform_attack()

func _perform_attack() -> void:
	if not _target_enemy or not is_instance_valid(_target_enemy):
		return
	
	# Double-check target is still valid (not dead/dying)
	if _target_enemy.get("_is_dying") == true or _target_enemy.get("is_dying") == true:
		_target_enemy = null
		return
	if _target_enemy.get("current_hp") != null and _target_enemy.get("current_hp") <= 0:
		_target_enemy = null
		return
	if _target_enemy.get("hp") != null and _target_enemy.get("hp") <= 0:
		_target_enemy = null
		return
	if _target_enemy.is_queued_for_deletion():
		_target_enemy = null
		return
	
	# SMG pause check - don't fire during pause phase
	if weapon_type == "smg" and _smg_is_paused:
		return
	
	# Check ammo for ranged weapons
	if max_ammo > 0 and ammo <= 0:
		if not _is_reloading:
			_is_reloading = true
			_reload_timer = reload_time
		return
	
	var direction := (_target_enemy.global_position - global_position).normalized()
	
	match weapon_type:
		"smg":
			_attack_smg(direction)
		"sword":
			_attack_sword(direction)
		"rocket":
			_attack_rocket(direction)
		"sniper":
			_attack_sniper(direction)
	
	_attack_timer = attack_cooldown

func _attack_smg(direction: Vector2) -> void:
	ammo -= 1
	
	var bullet = ProjectileCache.create_smg_bullet()
	get_parent().add_child(bullet)
	bullet.global_position = global_position + direction * 30
	bullet.velocity = direction * 900.0
	bullet.rotation = direction.angle()
	bullet.owner_node = self
	# SMG base damage 2, scaled by player's full multiplier × attack_multiplier (0.5)
	bullet.base_damage = maxi(1, int(_get_scaled_damage(2) * attack_multiplier))

func _attack_sword(direction: Vector2) -> void:
	var slash = ProjectileCache.create_slash()
	slash.rotation = direction.angle()
	slash.owner_node = self
	# Sword base damage 10, scaled by player's full multiplier × attack_multiplier (0.5)
	slash.base_damage = maxi(1, int(_get_scaled_damage(10) * attack_multiplier))
	add_child(slash)
	slash.position = Vector2.ZERO

func _attack_rocket(direction: Vector2) -> void:
	ammo -= 1
	
	var rocket = ProjectileCache.create_missile()
	rocket.owner_node = self
	rocket.direction = direction
	rocket.target_position = _target_enemy.global_position if _target_enemy else global_position + direction * 400
	rocket.speed = 400.0
	# Rocket base damage 10, scaled by player's full multiplier × attack_multiplier (0.5)
	rocket.damage = maxi(1, int(_get_scaled_damage(10) * attack_multiplier))
	rocket.explosion_damage = rocket.damage
	
	get_parent().add_child(rocket)
	rocket.global_position = global_position + direction * 40

func _attack_sniper(direction: Vector2) -> void:
	ammo -= 1
	
	var bullet = ProjectileCache.create_bullet()
	get_parent().add_child(bullet)
	bullet.global_position = global_position + direction * 50
	bullet.velocity = direction * 1650.0
	bullet.rotation = direction.angle()
	bullet.owner_node = self
	# Sniper base damage 15, scaled by player's full multiplier × attack_multiplier (0.5)
	bullet.base_damage = maxi(1, int(_get_scaled_damage(15) * attack_multiplier))
	bullet.pierce_all = true

## Get damage scaled by player's full multiplier (level + shop ATK bonus)
func _get_scaled_damage(base_damage: int) -> int:
	if owner_player and is_instance_valid(owner_player) and owner_player.has_method("calculate_damage"):
		return owner_player.calculate_damage(base_damage)
	# Fallback: just use level scaling
	var level_mult := 1.0 + (player_level - 1) * 0.25
	return maxi(1, int(base_damage * level_mult))

func _apply_separation() -> void:
	var tree := get_tree()
	if not tree:
		return
	
	var separation := Vector2.ZERO
	
	# Separate from other clones
	var clones := tree.get_nodes_in_group("nayuta_clones")
	for clone in clones:
		if clone == self or not is_instance_valid(clone) or not clone is Node2D:
			continue
		var to_self := global_position - (clone as Node2D).global_position
		var dist := to_self.length()
		if dist < 50.0 and dist > 0:
			separation += to_self.normalized() * (50.0 - dist)
	
	# Separate from player
	if owner_player and is_instance_valid(owner_player):
		var to_self := global_position - owner_player.global_position
		var dist := to_self.length()
		if dist < 40.0 and dist > 0:
			separation += to_self.normalized() * (40.0 - dist)
	
	velocity += separation * 3.0

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

func _process_death(delta: float) -> void:
	_death_timer += delta
	
	# Phase 1: Dissolve into sparkles
	if _death_timer < _death_duration * 0.5:
		# Hide animator progressively
		if _animator:
			_animator.modulate.a = 1.0 - (_death_timer / (_death_duration * 0.5))
		
		# Spawn sparkles
		if _sparkles.size() < 30:
			for i in range(3):
				var sparkle := {
					"pos": Vector2(randf_range(-20, 20), randf_range(-30, 30)),
					"vel": Vector2(randf_range(-50, 50), randf_range(-80, -20)),
					"life": 1.0,
					"size": randf_range(3, 6)
				}
				_sparkles.append(sparkle)
	
	# Phase 2: Sparkles float/travel
	else:
		if _animator:
			_animator.visible = false
		
		# Check if should travel to player
		if should_heal_on_death and not _sparkles_traveling:
			_sparkles_traveling = true
		
		# Update sparkles
		for sparkle in _sparkles:
			sparkle.life -= delta * 0.5
			
			if _sparkles_traveling and owner_player and is_instance_valid(owner_player):
				# Travel toward player
				var to_player: Vector2 = owner_player.global_position - (global_position + sparkle.pos)
				sparkle.vel = sparkle.vel.lerp(to_player.normalized() * 400.0, delta * 5.0)
				sparkle.pos += sparkle.vel * delta
				
				# Check if reached player
				if to_player.length() < 30.0:
					sparkle.life = 0.0
			else:
				# Float upward
				sparkle.vel.y -= 50.0 * delta
				sparkle.pos += sparkle.vel * delta
		
		# Remove dead sparkles
		_sparkles = _sparkles.filter(func(s): return s.life > 0)
	
	# End death sequence
	if _death_timer >= _death_duration and _sparkles.is_empty():
		# Apply heal if applicable
		if should_heal_on_death and has_meta("heal_owner_amount") and has_meta("heal_owner_ref"):
			var heal_amount: int = get_meta("heal_owner_amount")
			var player_ref: WeakRef = get_meta("heal_owner_ref")
			var player_node: Node = player_ref.get_ref() if player_ref else null
			if player_node and is_instance_valid(player_node):
				if player_node.has_method("heal"):
					player_node.heal(heal_amount)
				elif "hp" in player_node and "max_hp" in player_node:
					player_node.hp = mini(player_node.hp + heal_amount, player_node.max_hp)
		
		queue_free()
	
	queue_redraw()

func _draw() -> void:
	# Spawn effect
	if _spawn_timer > 0:
		var spawn_progress := 1.0 - (_spawn_timer / _spawn_duration)
		var ring_radius := 50.0 * spawn_progress
		var alpha := (1.0 - spawn_progress) * 0.9
		
		# Golden spawn rings for Nayuta
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 32, Color(1.0, 0.85, 0.4, alpha), 3.0)
		draw_arc(Vector2.ZERO, ring_radius * 0.7, 0, TAU, 32, Color(1.0, 0.9, 0.5, alpha * 0.6), 2.0)
	
	# Death sparkles
	if _is_dying:
		for sparkle in _sparkles:
			var alpha: float = float(sparkle.life)
			var color := Color(1.0, 0.85, 0.3, alpha)  # Gold sparkles
			draw_circle(sparkle.pos, sparkle.size * alpha, color)
			
			# Add glow
			draw_circle(sparkle.pos, sparkle.size * alpha * 1.5, Color(1.0, 0.9, 0.5, alpha * 0.3))
	
	# Subtle floor glow when alive
	if not _is_dying:
		var pulse := 0.5 + 0.3 * sin(_glow_time * 3.0)
		var glow_alpha := 0.1 * pulse
		draw_circle(Vector2.ZERO, 25.0, Color(1.0, 0.85, 0.4, glow_alpha))

func take_damage(amount, _is_crit = false, _direction = Vector2.ZERO, _from_burst = false, _source = "") -> void:
	if _is_dying:
		return
	
	# Ensure amount is an integer
	var dmg: int = int(amount)
	current_hp = maxi(0, current_hp - dmg)
	_update_health_bar()
	
	if current_hp <= 0:
		_die()

func heal(amount: int) -> void:
	if _is_dying:
		return
	
	var prev_hp = current_hp
	current_hp = mini(current_hp + amount, max_hp)
	var actual_heal = current_hp - prev_hp
	
	if actual_heal > 0:
		_update_health_bar()
		
		# Spawn floating heal number
		var FloatingNumber = preload("res://scripts/effects/FloatingDamageNumber.gd")
		if get_parent():
			FloatingNumber.spawn_heal(get_parent(), global_position + Vector2(0, -50), actual_heal)

func _die() -> void:
	if _is_dying:
		return
	
	_is_dying = true
	_death_timer = 0.0
	velocity = Vector2.ZERO
	
	# Hide health bar
	if _health_bar_bg:
		_health_bar_bg.visible = false
	if _health_bar_fill:
		_health_bar_fill.visible = false
	if _health_bar_label:
		_health_bar_label.visible = false
	
	clone_died.emit()

func initialize(player: Node2D, weapon: String, hp: int, atk_mult: float, heal_on_death: bool, level: int) -> void:
	owner_player = player
	weapon_type = weapon
	max_hp = hp
	current_hp = hp
	attack_multiplier = atk_mult
	should_heal_on_death = heal_on_death
	player_level = level
	
	# Reconfigure weapon stats after setting weapon_type
	_configure_weapon()
