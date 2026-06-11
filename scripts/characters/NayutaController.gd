extends "res://scripts/characters/CharacterController.gd"
class_name NayutaController
## Nayuta - SMG (Subject One)
# Special: Reality Distortion
# Burst: Convergence

func get_is_automatic() -> bool:
	return true

# Preload scripts
const NayutaCloneScript = preload("res://scripts/characters/effects/NayutaClone.gd")

# SMG config (same as Sin/Cecil)
var bullet_speed: float = 900.0

# Clone state
var _active_clones: Array = [] # Array of WeakRef to active clones
var _weapon_pool: Array[String] = ["smg"] # Available weapons for clones

# Clone upgrade levels (heal on death)
var clone_heal_level: int = 0 # 0=none, 1=20%, 2=35%, 3=50%
var _heal_percentages: Array[float] = [0.0, 0.20, 0.35, 0.50]

# Clone weapon upgrades (adds to pool)
var clone_weapon_level: int = 0 # 0=smg only, 1=+sword, 2=+rocket, 3=+sniper

# Burst config
var burst_damage: int = 50 # Base burst damage

# Burst upgrades
var burst_stun_bosses: bool = false # Stun bosses/elites for 8s
var burst_debuff_bosses: bool = false # Bosses/elites take 50% more damage
const BURST_STUN_DURATION := 8.0
const BURST_DEBUFF_MULTIPLIER := 1.5

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	# Clone summon cooldown
	data.special_cooldown = 8.0

func _on_process(_delta: float) -> void:
	# Clean up dead clone references
	_cleanup_clones()

func _cleanup_clones() -> void:
	for i in range(_active_clones.size() - 1, -1, -1):
		var ref: WeakRef = _active_clones[i]
		var clone: Node = ref.get_ref() if ref else null
		if clone == null or not is_instance_valid(clone):
			_active_clones.remove_at(i)

func _can_attack() -> bool:
	return not is_reloading and ammo > 0

func _perform_attack(direction: Vector2) -> void:
	# Fire dual SMG bullets (same as Sin/Cecil) - using pooled bullets
	var perp := Vector2(-direction.y, direction.x).normalized()
	var gun_offset := 18.0
	
	# Each SMG bullet does 1 base damage (2 total per shot)
	var bullet_damage: int = maxi(player.calc_damage(1.0 / player.get_base_damage()), 1)
	
	# Left gun bullet (pooled)
	var left_pos := player.global_position + direction * 45 - perp * gun_offset
	EffectPool.smg_bullet(player.get_parent(), left_pos, direction * bullet_speed, bullet_damage, player)
	
	# Right gun bullet (pooled)
	var right_pos := player.global_position + direction * 45 + perp * gun_offset
	EffectPool.smg_bullet(player.get_parent(), right_pos, direction * bullet_speed, bullet_damage, player)
	
	_play_sound("smg")

func _can_use_special() -> bool:
	return special_timer <= 0

func _perform_special(_direction: Vector2) -> void:
	# Summon a clone
	_summon_clone()
	
	# Set cooldown
	special_timer = data.special_cooldown

# Max active clones
const MAX_CLONES := 15

func _summon_clone() -> void:
	if not player or not is_instance_valid(player):
		return
	
	var parent = player.get_parent()
	if not parent:
		return
		
	# Clean up dead list first
	_cleanup_clones()
	
	# Enforce clone limit (15) - Despawn oldest if full
	if _active_clones.size() >= MAX_CLONES:
		# FIFO - Remove the first (oldest) valid clone
		var oldest_ref: WeakRef = _active_clones.pop_front()
		var oldest_clone = oldest_ref.get_ref() if oldest_ref else null
		if oldest_clone and is_instance_valid(oldest_clone):
			oldest_clone.queue_free()
	
	# Pick random weapon from pool
	var weapon: String = _weapon_pool[randi() % _weapon_pool.size()]
	
	# Get player level for scaling (default to 1)
	var player_level: int = player.get("level") if "level" in player else 1
	
	# Calculate clone stats (25% HP, 1/5 attack, scales with player level)
	# HP scales: base 25% of player HP, +25% per level
	var hp_level_mult := 1.0 + (player_level - 1) * 0.25
	var clone_hp: int = maxi(1, int((player.max_hp / 4) * hp_level_mult))
	var clone_attack: float = 0.2 # 1/5 damage multiplier
	
	# Create clone (CharacterBody2D required for NayutaClone)
	var clone = CharacterBody2D.new()
	clone.name = "NayutaClone_%d" % Time.get_ticks_msec()
	clone.set_script(NayutaCloneScript)
	
	# CRITICAL: Set collision layers BEFORE adding to scene tree
	# Layer 8 (value 8) = Allies layer, detected by EnemyLaser mask
	clone.collision_layer = 8 # Allies layer
	clone.collision_mask = 5 # World (1) + Enemies (4)
	
	# Spawn with Commander-style visual effect
	var spawn_offset := Vector2(randf_range(-60, 60), randf_range(-60, 60))
	
	parent.add_child(clone)
	clone.global_position = player.global_position + spawn_offset
	
	# Initialize clone with weapon from pool and player level for scaling
	# Use call() to ensure proper method resolution after set_script
	clone.call("initialize", player, weapon, clone_hp, clone_attack, clone_heal_level > 0, player_level)
	
	# Connect signals
	clone.clone_died.connect(_on_clone_died.bind(clone))
	
	_active_clones.append(weakref(clone))
	
	# Clone summon is silent - no sound effect

func _on_clone_died(clone: Node2D) -> void:
	# Handle clone death healing
	if clone_heal_level > 0 and player and is_instance_valid(player):
		var heal_percent := _heal_percentages[mini(clone_heal_level, 3)]
		var heal_amount := int(player.max_hp * heal_percent)
		
		# The clone handles the sparkle travel effect
		# We just need to heal when sparkles arrive
		clone.set_meta("heal_owner_amount", heal_amount)
		clone.set_meta("heal_owner_ref", weakref(player))

func _on_burst_start() -> void:
	# Galaxy explosion - damages all enemies on screen
	_perform_galaxy_burst()
	
	# Nayuta's burst is instant, not sustained - immediately end burst state
	# This allows rapid re-triggering if the player has enough burst gauge
	burst_active = false
	burst_timer = 0.0
	burst_ended.emit()

func _perform_galaxy_burst() -> void:
	var tree := player.get_tree()
	if not tree:
		return
	
	var viewport := player.get_viewport()
	if not viewport:
		return
	
	# Get view rect
	# (view_rect calculation inferred from context, assuming similar structure to others)
	# Assuming loop starts around line 155-160 in full file
	# I will replace the loop header if I can see it, but I don't see it in the previous snippet.
	# I need to view Nayuta again to be safe.
	pass
	var camera := viewport.get_camera_2d()
	var view_rect: Rect2
	if camera:
		var viewport_size := viewport.get_visible_rect().size
		var cam_pos := camera.global_position
		var half_size := viewport_size / (2.0 * camera.zoom)
		view_rect = Rect2(cam_pos - half_size, half_size * 2.0)
	else:
		view_rect = Rect2(Vector2.ZERO, Vector2(1920, 1080))
	
	# Calculate damage based on player level/attack
	var damage: int = burst_damage
	if "level" in player:
		damage = int(damage * (1.0 + (player.level - 1) * 0.5))
	
	# Damage all enemies on screen
	var enemies := TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_node := enemy as Node2D
		if not view_rect.has_point(enemy_node.global_position):
			continue
		
		# Check if elite/boss
		var is_elite := _is_elite_or_boss(enemy_node)
		
		# Deal damage
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, false, Vector2.ZERO, true, "NayutaBurst")
		
		# Apply boss/elite effects
		if is_elite:
			if burst_stun_bosses:
				_apply_stun(enemy_node, BURST_STUN_DURATION)
			
			if burst_debuff_bosses:
				_apply_galaxy_debuff(enemy_node)
	
	# Create galaxy explosion visual
	_spawn_galaxy_explosion()
	
	# Screen flash
	if player.screen_flash and player.screen_flash.has_method("flash"):
		player.screen_flash.flash(Color(0.4, 0.2, 0.8, 0.5), 0.4)

func _is_elite_or_boss(enemy: Node) -> bool:
	if enemy.has_meta("enemy_tier"):
		var tier = enemy.get_meta("enemy_tier")
		if tier in ["elite", "boss", "tank"]:
			return true
	if enemy.is_in_group("elite") or enemy.is_in_group("boss"):
		return true
	return false

func _apply_stun(enemy: Node2D, duration: float) -> void:
	if enemy.has_method("apply_stun"):
		enemy.apply_stun(duration)
	else:
		# Manual stun
		enemy.set_meta("nayuta_stunned", true)
		enemy.set_meta("nayuta_stun_end", Time.get_ticks_msec() * 0.001 + duration)
		if "velocity" in enemy:
			enemy.set_meta("pre_stun_velocity", enemy.velocity)
			enemy.velocity = Vector2.ZERO

func _apply_galaxy_debuff(enemy: Node2D) -> void:
	# Mark enemy as taking 50% more damage
	enemy.set_meta("nayuta_debuffed", true)
	enemy.set_meta("damage_multiplier_incoming", BURST_DEBUFF_MULTIPLIER)
	
	# Add visual effect
	var effect := Node2D.new()
	effect.name = "GalaxyDebuffEffect"
	effect.set_script(_get_galaxy_debuff_script())
	enemy.add_child(effect)

func _spawn_galaxy_explosion() -> void:
	# Create the galaxy explosion visual at player position
	var explosion := Node2D.new()
	explosion.name = "GalaxyExplosion"
	explosion.set_script(_get_galaxy_explosion_script())
	explosion.global_position = player.global_position
	player.get_parent().add_child(explosion)

func _get_galaxy_explosion_script() -> GDScript:
	var script := preload("res://scripts/characters/effects/visuals/NayutaGalaxyExplosion.gd")
	return script

func _get_galaxy_debuff_script() -> GDScript:
	var script := preload("res://scripts/characters/effects/visuals/NayutaGalaxyDebuff.gd")
	return script

func _on_burst_end() -> void:
	pass

func _on_cleanup() -> void:
	# Note: Clones are NOT cleaned up on character switch
	# They persist and expire on their own timers
	# Only clean up dead clone references
	_cleanup_clones()

func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			reset_special_cooldown()
		"special_heal":
			clone_heal_level = mini(clone_heal_level + 1, 3)
			reset_special_cooldown()
		"special_weapon":
			clone_weapon_level = mini(clone_weapon_level + 1, 3)
			_update_weapon_pool()
			reset_special_cooldown()
		"burst_stun":
			burst_stun_bosses = true
		"burst_debuff":
			burst_debuff_bosses = true

func _update_weapon_pool() -> void:
	# Reset pool
	_weapon_pool = ["smg"]
	
	# Add weapons based on level
	if clone_weapon_level >= 1:
		_weapon_pool.append("sword")
	if clone_weapon_level >= 2:
		_weapon_pool.append("rocket")
	if clone_weapon_level >= 3:
		_weapon_pool.append("sniper")

func _get_weapon_type_name() -> String:
	return "SMG"

## Get active clone count for UI
func get_clone_count() -> int:
	_cleanup_clones()
	return _active_clones.size()

## Get the current weapon pool for clones (used by Duplicity upgrade)
func get_weapon_pool() -> Array[String]:
	return _weapon_pool.duplicate()
