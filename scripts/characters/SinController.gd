extends "res://scripts/characters/CharacterController.gd"
class_name SinController
## Sin - SMG with Charm special and Life Drain burst
## Special: AoE charm that converts normal enemies to fight for you
## Burst: DOT that drains health from all on-screen enemies

# Preload scripts
const SinDebuffEffectScript = preload("res://scripts/characters/effects/SinDebuffEffect.gd")
const SinCharmEffectScript = preload("res://scripts/characters/effects/SinCharmEffect.gd")
const SinMagneticAuraScript = preload("res://scripts/characters/effects/SinMagneticAura.gd")
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

# Charm area indicator
var _charm_indicator: SinCharmAreaIndicator = null

# "Magnetic Personality" upgrade - passive charm aura
var _magnetic_aura: Node2D = null
var _has_magnetic_upgrade: bool = false

# SMG config
var bullet_speed: float = 900.0
var bullets_per_shot: int = 1

# Special config (Charm)
var charm_radius: float = 150.0  # Base AoE radius
var charm_cooldown: float = 10.0  # Base cooldown

# Burst config
const SIN_DOT_INTERVAL := 1.0  # Damage every 1 second
const SIN_DOT_TICKS := 4  # 4 ticks total (4 seconds)
const SIN_HEAL_FRACTION := 0.05  # 5% max HP per enemy damaged per tick

# Burst state
var _burst_targets: Array = []  # Array of {enemy_ref, effect_ref}
var _burst_next_tick_time: float = 0.0  # When next DOT tick occurs
var _burst_ticks_remaining: int = 0  # How many ticks left

# Explosion on death during burst
var burst_explosion_damage: int = 4
const BURST_EXPLOSION_RADIUS := 100.0

# Talent states
var special_size_level: int = 0  # AoE size: 50/100/200%
var captivating_level: int = 0  # Lv1: heal on charm death, Lv2: explode on charm death, Lv3: charm tanks
var burst_charge_on_kill: bool = false  # Killing during burst charges burst
var burst_explode_on_death: bool = false  # Enemies explode on death during burst

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	data.special_cooldown = charm_cooldown
	# Note: Indicator is created lazily in _on_process to ensure scene is ready
	
	# Check for "Magnetic Personality" upgrade
	_has_magnetic_upgrade = ShopMenuScript.has_character_upgrade("sin", "basic_attack")
	if _has_magnetic_upgrade:
		print("[SinController] 'Magnetic Personality' upgrade active - creating aura")
		# Aura will be created lazily when player parent is available

func _create_magnetic_aura() -> void:
	if not _has_magnetic_upgrade:
		return
	if _magnetic_aura and is_instance_valid(_magnetic_aura):
		return
	if not player or not is_instance_valid(player):
		return
	var parent = player.get_parent()
	if not parent or not is_instance_valid(parent):
		return
	
	_magnetic_aura = SinMagneticAuraScript.new()
	_magnetic_aura.name = "SinMagneticAura"
	parent.add_child(_magnetic_aura)
	_magnetic_aura.initialize(player, self)  # Pass controller for talent checks

func _create_charm_indicator() -> void:
	if _charm_indicator and is_instance_valid(_charm_indicator):
		return
	
	# Verify player and parent are valid
	if not player or not is_instance_valid(player):
		push_warning("[SinController] Cannot create indicator: player invalid")
		return
	var parent = player.get_parent()
	if not parent or not is_instance_valid(parent):
		push_warning("[SinController] Cannot create indicator: parent invalid")
		return
	
	print("[SinController] Creating charm indicator...")
	_charm_indicator = SinCharmAreaIndicator.new()
	_charm_indicator.name = "SinCharmIndicator"
	parent.add_child(_charm_indicator)
	_charm_indicator.setup(player, _get_current_charm_radius())
	print("[SinController] Charm indicator created: ", _charm_indicator)

func _get_current_charm_radius() -> float:
	var size_multipliers := [1.0, 1.5, 2.0, 3.0]
	return charm_radius * size_multipliers[mini(special_size_level, 3)]

func _on_process(delta: float) -> void:
	# Update burst DOT
	if burst_active:
		_update_burst_dot(delta)
	
	# Ensure charm indicator exists (created lazily)
	if not _charm_indicator or not is_instance_valid(_charm_indicator):
		_create_charm_indicator()
	
	# Ensure magnetic aura exists if upgrade is active
	if _has_magnetic_upgrade and (not _magnetic_aura or not is_instance_valid(_magnetic_aura)):
		_create_magnetic_aura()
	
	# Update charm indicator visibility
	_update_charm_indicator()

func _update_charm_indicator() -> void:
	if not _charm_indicator or not is_instance_valid(_charm_indicator):
		return
	
	# Show indicator when special is ready and unlocked
	var should_show := special_unlocked and special_timer <= 0
	
	# Debug output (remove later)
	#print("[SinController] Update indicator - unlocked: %s, timer: %.2f, should_show: %s" % [special_unlocked, special_timer, should_show])
	
	if special_unlocked:
		_charm_indicator.set_radius(_get_current_charm_radius())
		if should_show:
			_charm_indicator.show_indicator()
		else:
			_charm_indicator.hide_indicator()
	else:
		_charm_indicator.hide_indicator()

func _can_attack() -> bool:
	return not is_reloading and ammo > 0

func _perform_attack(direction: Vector2) -> void:
	# Fire dual SMG bullets in akimbo style
	
	# Calculate perpendicular offset for dual guns
	var perp := Vector2(-direction.y, direction.x).normalized()
	var gun_offset := 18.0  # Horizontal spacing between the two guns
	
	# Each SMG bullet does 1 base damage (2 total per shot)
	var bullet_damage: int = maxi(player.calc_damage(1.0 / player.get_base_damage()), 1)
	
	# Left gun bullet
	var bullet_left = ProjectileCache.create_smg_bullet()
	player.get_parent().add_child(bullet_left)
	bullet_left.global_position = player.global_position + direction * 30 - perp * gun_offset
	bullet_left.velocity = direction * bullet_speed
	bullet_left.rotation = direction.angle()
	bullet_left.owner_node = player
	bullet_left.base_damage = bullet_damage
	
	# Right gun bullet
	var bullet_right = ProjectileCache.create_smg_bullet()
	player.get_parent().add_child(bullet_right)
	bullet_right.global_position = player.global_position + direction * 30 + perp * gun_offset
	bullet_right.velocity = direction * bullet_speed
	bullet_right.rotation = direction.angle()
	bullet_right.owner_node = player
	bullet_right.base_damage = bullet_damage
	
	_play_sound("smg")

func _can_use_special() -> bool:
	return special_timer <= 0

func _perform_special(_direction: Vector2) -> void:
	# Calculate actual charm radius based on upgrades
	var actual_radius: float = _get_current_charm_radius()
	
	# Get mouse position for AoE center
	var mouse_pos := player.get_global_mouse_position()
	
	# Trigger activation animation on indicator
	if is_instance_valid(_charm_indicator):
		_charm_indicator.trigger_activation()
	
	# Spawn visual indicator (expanding ring)
	_spawn_charm_aoe_visual(mouse_pos, actual_radius)
	
	# Find all normal enemies in radius
	var tree := player.get_tree()
	if tree:
		var enemies := tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy is Node2D:
				continue
			
			# Skip elites and bosses
			if _is_elite_or_boss(enemy):
				continue
			
			# Check if in range
			var dist := (enemy as Node2D).global_position.distance_to(mouse_pos)
			if dist > actual_radius:
				continue
			
			# Charm the enemy
			_charm_enemy(enemy)
	
	# Start cooldown
	special_timer = charm_cooldown
	data.special_cooldown = special_timer  # Update for UI

func _is_elite_or_boss(enemy: Node) -> bool:
	if enemy.has_meta("enemy_tier"):
		var tier = enemy.get_meta("enemy_tier")
		# Tanks can be charmed with captivating level 3
		if tier == "tank" and captivating_level >= 3:
			return false
		if tier in ["elite", "boss", "tank"]:
			return true
	if enemy.is_in_group("elite") or enemy.is_in_group("boss"):
		return true
	return false

func _charm_enemy(enemy: Node) -> void:
	# Skip if already charmed
	if enemy.has_meta("charmed") and enemy.get_meta("charmed"):
		return
	
	# Check if this is a tank (needs force=true with captivating level 3)
	var is_tank := false
	if enemy.has_meta("enemy_tier") and enemy.get_meta("enemy_tier") == "tank":
		is_tank = true
	
	# Mark as charmed
	enemy.set_meta("charmed", true)
	enemy.set_meta("charm_owner", player)
	
	# Add to friendly group, remove from enemies
	enemy.remove_from_group("enemies")
	enemy.add_to_group("charmed_allies")
	
	# Modify enemy behavior - make it attack other enemies
	if enemy.has_method("set_charmed"):
		enemy.set_charmed(player, true, is_tank)  # force=true for tanks
	else:
		# Add purple visual effect as fallback
		var effect = SinCharmEffectScript.new()
		effect.name = "CharmEffect"
		enemy.add_child(effect)

func _spawn_charm_aoe_visual(center: Vector2, radius: float) -> void:
	# Create expanding ring visual
	var visual := Node2D.new()
	visual.set_script(_get_charm_aoe_script())
	visual.set("radius", radius)
	visual.set("color", Color(0.7, 0.2, 0.9, 0.6))  # Purple
	player.get_parent().add_child(visual)
	visual.global_position = center

func _get_charm_aoe_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var radius: float = 150.0
var color: Color = Color(0.7, 0.2, 0.9, 0.6)
var _time: float = 0.0
var _duration: float = 0.5

func _ready() -> void:
	z_index = 100

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	var current_radius := radius * progress
	var alpha := (1.0 - progress) * color.a
	
	# Outer ring
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 64, Color(color.r, color.g, color.b, alpha), 4.0)
	
	# Inner glow
	var inner_alpha := alpha * 0.3
	draw_circle(Vector2.ZERO, current_radius * 0.9, Color(color.r, color.g, color.b, inner_alpha))
"""
	script.reload()
	return script

func _on_burst_start() -> void:
	# Clear any existing burst targets
	_clear_burst_targets()
	
	# Find all enemies on screen
	var tree := player.get_tree()
	if not tree:
		return
	
	var viewport := player.get_viewport()
	if not viewport:
		return
	
	var camera := viewport.get_camera_2d()
	var view_rect: Rect2
	if camera:
		var viewport_size := viewport.get_visible_rect().size
		var cam_pos := camera.global_position
		var half_size := viewport_size / (2.0 * camera.zoom)
		view_rect = Rect2(cam_pos - half_size, half_size * 2.0)
	else:
		view_rect = Rect2(Vector2.ZERO, Vector2(1920, 1080))
	
	var now := Time.get_ticks_msec() * 0.001
	_burst_next_tick_time = now + SIN_DOT_INTERVAL  # First tick after 1 second
	_burst_ticks_remaining = SIN_DOT_TICKS
	
	var enemies := tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_node := enemy as Node2D
		if not view_rect.has_point(enemy_node.global_position):
			continue
		
		# Add debuff effect to enemy
		var effect: Node2D = SinDebuffEffectScript.new()
		enemy_node.add_child(effect)
		effect.position = Vector2.ZERO
		effect.z_index = 5
		
		var target_data: Dictionary = {
			"enemy_ref": weakref(enemy_node),
			"effect_ref": weakref(effect)
		}
		_burst_targets.append(target_data)
	
	# Flash effect
	if player.screen_flash and player.screen_flash.has_method("flash"):
		player.screen_flash.flash(Color(0.7, 0.2, 0.9, 0.3), 0.3)

func _on_burst_end() -> void:
	_clear_burst_targets()

func _on_cleanup() -> void:
	# Clean up charm indicator when controller is destroyed
	if is_instance_valid(_charm_indicator):
		_charm_indicator.queue_free()
		_charm_indicator = null
	# Clean up magnetic aura
	if is_instance_valid(_magnetic_aura):
		_magnetic_aura.queue_free()
		_magnetic_aura = null
	_clear_burst_targets()

func _clear_burst_targets() -> void:
	for entry in _burst_targets:
		if not entry is Dictionary:
			continue
		var effect_ref: WeakRef = entry.get("effect_ref")
		if effect_ref:
			var effect: Node = effect_ref.get_ref()
			if effect and is_instance_valid(effect):
				effect.queue_free()
	_burst_targets.clear()
	_burst_ticks_remaining = 0

func _update_burst_dot(_delta: float) -> void:
	if _burst_ticks_remaining <= 0:
		return
	
	var now := Time.get_ticks_msec() * 0.001
	if not player.get_tree():
		_clear_burst_targets()
		burst_active = false
		burst_ended.emit()
		return
	
	# Clean up dead enemies (but don't process them yet)
	_cleanup_dead_enemies()
	
	# Check if it's time for a DOT tick
	if now < _burst_next_tick_time:
		return
	
	# Process DOT tick
	_burst_next_tick_time = now + SIN_DOT_INTERVAL
	_burst_ticks_remaining -= 1
	
	# Calculate damage (10x Sin's current ATK)
	var damage: int = player.calc_damage() * 10
	var heal_per_enemy := int(round(float(player.max_hp) * SIN_HEAL_FRACTION))
	var enemies_damaged := 0
	
	# Damage all living enemies and count them
	var updated: Array = []
	for entry in _burst_targets:
		if not entry is Dictionary:
			continue
		
		var enemy_ref: WeakRef = entry.get("enemy_ref")
		var enemy: Node = enemy_ref.get_ref() if enemy_ref else null
		
		if enemy == null or not is_instance_valid(enemy):
			# Enemy already dead, skip
			continue
		
		# Deal damage
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, false, Vector2.ZERO, not burst_charge_on_kill)
			enemies_damaged += 1
			
			if burst_charge_on_kill and player.has_method("register_burst_hit"):
				player.register_burst_hit(enemy, false)
		
		# Check if enemy died from this damage
		if not is_instance_valid(enemy) or (enemy.has_method("is_dead") and enemy.is_dead()):
			# Enemy died from this tick - handle explosion
			var effect_ref: WeakRef = entry.get("effect_ref")
			if effect_ref:
				var effect: Node = effect_ref.get_ref()
				if effect and is_instance_valid(effect):
					var death_pos: Vector2 = effect.global_position
					effect.queue_free()
					if burst_explode_on_death:
						_spawn_burst_explosion(death_pos)
		else:
			# Enemy still alive, keep tracking
			updated.append(entry)
	
	_burst_targets = updated
	
	# Heal based on enemies damaged this tick
	if enemies_damaged > 0 and heal_per_enemy > 0:
		var total_heal := heal_per_enemy * enemies_damaged
		player.hp = min(player.hp + total_heal, player.max_hp)
		player._update_health_display(total_heal, false)
	
	# Check if burst is complete
	if _burst_ticks_remaining <= 0:
		_clear_burst_targets()
		burst_active = false
		burst_ended.emit()

func _cleanup_dead_enemies() -> void:
	"""Remove dead enemies from tracking and handle explosions."""
	var updated: Array = []
	for entry in _burst_targets:
		if not entry is Dictionary:
			continue
		
		var enemy_ref: WeakRef = entry.get("enemy_ref")
		var enemy: Node = enemy_ref.get_ref() if enemy_ref else null
		
		if enemy == null or not is_instance_valid(enemy):
			# Enemy died between ticks - handle explosion
			var effect_ref: WeakRef = entry.get("effect_ref")
			if effect_ref:
				var effect: Node = effect_ref.get_ref()
				if effect and is_instance_valid(effect):
					var death_pos: Vector2 = effect.global_position
					effect.queue_free()
					if burst_explode_on_death:
						_spawn_burst_explosion(death_pos)
			continue
		
		updated.append(entry)
	
	_burst_targets = updated

func _spawn_burst_explosion(position: Vector2) -> void:
	# Create explosion at death position
	var tree := player.get_tree()
	if not tree:
		return
	
	# Damage nearby enemies with level scaling
	var enemies := tree.get_nodes_in_group("enemies")
	var level_mult: float = 1.0
	if "level" in player:
		level_mult = 1.0 + (player.level - 1) * 0.5
	var damage := int(burst_explosion_damage * level_mult)
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var dist := (enemy as Node2D).global_position.distance_to(position)
		if dist > BURST_EXPLOSION_RADIUS:
			continue
		
		if enemy.has_method("take_damage"):
			var hit_dir := ((enemy as Node2D).global_position - position).normalized()
			enemy.take_damage(damage, false, hit_dir, true)  # true = from burst
	
	# Visual explosion
	var visual := Node2D.new()
	visual.set_script(_get_explosion_visual_script())
	visual.set("radius", BURST_EXPLOSION_RADIUS)
	visual.set("color", Color(0.7, 0.2, 0.9, 0.8))
	player.get_parent().add_child(visual)
	visual.global_position = position

func _get_explosion_visual_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var radius: float = 100.0
var color: Color = Color(0.7, 0.2, 0.9, 0.8)
var _time: float = 0.0
var _duration: float = 0.3

func _ready() -> void:
	z_index = 200

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	var current_radius := radius * (0.5 + progress * 0.5)
	var alpha := (1.0 - progress) * color.a
	
	# Explosion ring
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 32, Color(color.r, color.g, color.b, alpha), 6.0)
	
	# Inner flash
	var inner_alpha := alpha * 0.5 * (1.0 - progress)
	draw_circle(Vector2.ZERO, current_radius * 0.7, Color(1.0, 0.8, 1.0, inner_alpha))
"""
	script.reload()
	return script

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

## Get attack cooldown for SMG rapid fire
func get_attack_cooldown() -> float:
	return data.attack_cooldown  # 0.08s for rapid SMG fire

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			special_timer = 0.0  # Refresh cooldown
		"special_size":
			special_size_level = mini(special_size_level + 1, 3)
			special_timer = 0.0  # Refresh cooldown
		"special_cooldown":
			captivating_level = mini(captivating_level + 1, 3)
			special_timer = 0.0  # Refresh cooldown
		"burst_charge":
			burst_charge_on_kill = true
		"burst_explode":
			burst_explode_on_death = true

## Check if invincible (Sin doesn't have invincibility)
func is_invincible() -> bool:
	return false

## Get weapon type name for audio
func _get_weapon_type_name() -> String:
	return "SMG"
