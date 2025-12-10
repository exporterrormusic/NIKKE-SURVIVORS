extends "res://scripts/characters/CharacterController.gd"
class_name CecilController
## Cecil - SMG with drone robots that switch between hunt/shield modes
## Special: Toggle drones between Hunt (seek & attack) and Shield (protect Cecil) modes
## Burst: Freeze all enemies, hack non-elite/boss to fight for player

# Preload scripts
const CecilDroneScript = preload("res://scripts/characters/effects/CecilDrone.gd")
const CecilShieldScript = preload("res://scripts/characters/effects/CecilShield.gd")

# SMG config (same as Sin)
var bullet_speed: float = 900.0

# Drone state
var _drones: Array = []  # Two CecilDrone instances
var _drone_mode: String = "hunt"  # "hunt" or "shield"
const DRONE_COUNT := 2

# Shield reference
var _shield: Node2D = null

# Upgrade levels
var drone_upgrade_level: int = 0  # 0-3: each level = +50% speed/damage (50/100/200%)
var shield_upgrade_level: int = 0  # 0-3: each level = +1 hit absorbed

# Burst config
const BURST_FREEZE_DURATION := 1.5
const BURST_BOSS_DAMAGE_PERCENT := 0.25  # 25% of max HP

# Burst upgrades
var burst_damage_boost: bool = false  # Hacked enemies do 50% more damage
var burst_boss_damage: bool = false  # Deal 25% max HP to bosses/elites after stun

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	# Short cooldown since it's just a mode toggle
	data.special_cooldown = 0.5

func _on_process(delta: float) -> void:
	# Spawn drones when special is unlocked
	if special_unlocked and _drones.is_empty():
		_spawn_drones()
	
	# Update shield if in shield mode
	if _shield and is_instance_valid(_shield):
		_shield.update_shield(delta)

func _spawn_drones() -> void:
	if not player or not is_instance_valid(player):
		return
	
	var parent = player.get_parent()
	if not parent:
		return
	
	for i in range(DRONE_COUNT):
		var drone = Node2D.new()
		drone.name = "CecilDrone_%d" % i
		drone.set_script(CecilDroneScript)
		parent.add_child(drone)
		
		# Initialize drone - position them on opposite sides (0 and PI)
		var angle_offset = (TAU / DRONE_COUNT) * i  # 0 and PI for 2 drones
		drone.initialize(player, i, angle_offset, _get_drone_speed_multiplier())
		drone.set_mode(_drone_mode)
		
		_drones.append(drone)
	
	# Link sibling drones to each other for target coordination
	if _drones.size() >= 2:
		_drones[0].sibling_drone = _drones[1]
		_drones[1].sibling_drone = _drones[0]
	
	# Create shield (starts inactive)
	_shield = Node2D.new()
	_shield.name = "CecilShield"
	_shield.set_script(CecilShieldScript)
	player.add_child(_shield)
	_shield.initialize(player, _get_max_shield_hits())
	_shield.set_active(false)

func _get_drone_speed_multiplier() -> float:
	# 1.0 base, then +50% per level (1.5, 2.0, 3.0)
	var multipliers := [1.0, 1.5, 2.0, 3.0]
	return multipliers[mini(drone_upgrade_level, 3)]

func _get_max_shield_hits() -> int:
	# 1 base, +1 per upgrade level
	return 1 + shield_upgrade_level

func _can_attack() -> bool:
	return not is_reloading and ammo > 0

func _perform_attack(direction: Vector2) -> void:
	# Fire dual SMG bullets (same as Sin)
	
	var perp := Vector2(-direction.y, direction.x).normalized()
	var gun_offset := 18.0
	
	# Each SMG bullet does 1 base damage (2 total per shot)
	var bullet_damage: int = maxi(player.calc_damage(1.0 / player.get_base_damage()), 1)
	
	# Left gun bullet
	var bullet_left = ProjectileCache.create_smg_bullet()
	player.get_parent().add_child(bullet_left)
	bullet_left.global_position = player.global_position + direction * 45 - perp * gun_offset
	bullet_left.velocity = direction * bullet_speed
	bullet_left.rotation = direction.angle()
	bullet_left.owner_node = player
	bullet_left.base_damage = bullet_damage
	
	# Right gun bullet
	var bullet_right = ProjectileCache.create_smg_bullet()
	player.get_parent().add_child(bullet_right)
	bullet_right.global_position = player.global_position + direction * 45 + perp * gun_offset
	bullet_right.velocity = direction * bullet_speed
	bullet_right.rotation = direction.angle()
	bullet_right.owner_node = player
	bullet_right.base_damage = bullet_damage
	
	_play_sound("smg")

func try_absorb_damage() -> bool:
	"""Try to have shield absorb incoming damage. Returns true if absorbed."""
	if _shield and is_instance_valid(_shield):
		return _shield.absorb_hit()
	return false

func _can_use_special() -> bool:
	return special_timer <= 0 and not _drones.is_empty() and not _is_drones_returning()

func _is_drones_returning() -> bool:
	for drone in _drones:
		if is_instance_valid(drone) and drone.is_returning():
			return true
	return false

var _drones_arrived_count: int = 0

func _perform_special(_direction: Vector2) -> void:
	# Toggle drone mode
	if _drone_mode == "hunt":
		_drone_mode = "shield"
		_drones_arrived_count = 0
		
		# Tell drones to return, shield activates when all arrive
		for drone in _drones:
			if is_instance_valid(drone):
				drone.set_mode(_drone_mode, _on_drone_arrived)
	else:
		_drone_mode = "hunt"
		
		# Update all drones immediately for hunt mode
		for drone in _drones:
			if is_instance_valid(drone):
				drone.set_mode(_drone_mode)
		
		# Deactivate shield immediately when switching to hunt
		if _shield and is_instance_valid(_shield):
			_shield.set_active(false)
	
	# Short cooldown to prevent spam
	special_timer = 0.5

func _on_drone_arrived() -> void:
	_drones_arrived_count += 1
	
	# Activate shield when all drones have arrived
	if _drones_arrived_count >= DRONE_COUNT:
		if _shield and is_instance_valid(_shield):
			_shield.set_active(true)

func _on_burst_start() -> void:
	# Freeze all enemies on screen and apply hacking effect
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
	
	var enemies := tree.get_nodes_in_group("enemies")
	var frozen_enemies: Array = []
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_node := enemy as Node2D
		if not view_rect.has_point(enemy_node.global_position):
			continue
		
		# Freeze the enemy
		if enemy.has_method("apply_stun"):
			enemy.apply_stun(BURST_FREEZE_DURATION)
		
		# Add hacking visual effect
		var hack_fx := Node2D.new()
		hack_fx.name = "HackEffect"
		hack_fx.set_script(_get_hack_effect_script())
		hack_fx.set("duration", BURST_FREEZE_DURATION)
		enemy_node.add_child(hack_fx)
		
		frozen_enemies.append(enemy_node)
	
	# Flash effect
	if player.screen_flash and player.screen_flash.has_method("flash"):
		player.screen_flash.flash(Color(0.2, 0.6, 1.0, 0.4), 0.3)
	
	# After freeze duration, hack non-elite/boss enemies
	var timer := player.get_tree().create_timer(BURST_FREEZE_DURATION)
	timer.timeout.connect(_on_freeze_complete.bind(frozen_enemies))

func _on_freeze_complete(frozen_enemies: Array) -> void:
	for enemy in frozen_enemies:
		if not is_instance_valid(enemy):
			continue
		
		var is_elite := _is_elite_or_boss(enemy)
		
		if is_elite:
			# Deal 25% max HP damage to bosses/elites if upgrade unlocked
			if burst_boss_damage and enemy.has_method("take_damage"):
				var max_hp_val: int = enemy.get("max_hp") if enemy.get("max_hp") else 100
				var damage := int(max_hp_val * BURST_BOSS_DAMAGE_PERCENT)
				enemy.take_damage(damage, false, Vector2.ZERO, true)
		else:
			# Hack (charm) non-elite enemies
			_hack_enemy(enemy)

func _is_elite_or_boss(enemy: Node) -> bool:
	if enemy.has_meta("enemy_tier"):
		var tier = enemy.get_meta("enemy_tier")
		if tier in ["elite", "boss", "tank"]:
			return true
	if enemy.is_in_group("elite") or enemy.is_in_group("boss"):
		return true
	return false

func _hack_enemy(enemy: Node) -> void:
	# Skip if already charmed/hacked
	if enemy.has_meta("charmed") and enemy.get_meta("charmed"):
		return
	
	# Mark as hacked
	enemy.set_meta("charmed", true)
	enemy.set_meta("charm_owner", player)
	enemy.set_meta("hacked_by_cecil", true)
	
	# Apply damage boost if upgrade unlocked
	if burst_damage_boost:
		enemy.set_meta("damage_multiplier", 1.5)
	
	# Add to friendly group, remove from enemies
	enemy.remove_from_group("enemies")
	enemy.add_to_group("charmed_allies")
	
	# Use existing charm system
	if enemy.has_method("set_charmed"):
		enemy.set_charmed(player, true)
	else:
		# Add blue visual effect
		var effect := Node2D.new()
		effect.name = "HackVisual"
		effect.set_script(_get_hack_visual_script())
		enemy.add_child(effect)

func _on_burst_end() -> void:
	pass  # Hacking is permanent, nothing to clean up

func _on_cleanup() -> void:
	# Clean up drones
	for drone in _drones:
		if is_instance_valid(drone):
			drone.queue_free()
	_drones.clear()
	
	# Clean up shield
	if is_instance_valid(_shield):
		_shield.queue_free()
		_shield = null

func _get_hack_effect_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var duration: float = 1.5
var _time: float = 0.0
var _scale_mult: float = 1.0

func _ready() -> void:
	z_index = 100
	
	# Capture parent scale before reparenting (since we move to EffectsLayer)
	var parent = get_parent()
	if parent is Node2D:
		_scale_mult = maxf(parent.scale.x, parent.scale.y)
	
	# Ensure reasonable scale limits (don't get microscopic or too massive)
	_scale_mult = clampf(_scale_mult, 0.5, 4.0)
	
	# Make unshaded for maximum brightness
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Reparent to EffectsLayer to render on top of enemies
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
			z_index = 100

func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Floating cloud of fluctuating binary - "Data Upload" style
	var font = ThemeDB.fallback_font
	
	# Scale cloud and text with enemy
	var font_size := int(20 * _scale_mult)
	var num_bits := int(16 * sqrt(_scale_mult)) # Add a few more bits for huge enemies
	
	# Cloud dimensions scaled
	var x_range = 70.0 * _scale_mult
	var y_range = 70.0 * _scale_mult 
	var x_offset_base = -35.0 * _scale_mult
	var y_offset_base = -35.0 * _scale_mult # Centered vertically on anchor
	
	for i in range(num_bits):
		# Create a cloud distribution above center
		# Deterministic pseudo-random positions based on index
		var rx = sin(float(i) * 12.9898) * 43758.5453
		var ry = cos(float(i) * 78.233) * 43758.5453
		
		# range scaled
		var x_off = (rx - floor(rx)) * x_range + x_offset_base
		# range scaled
		var y_off = (ry - floor(ry)) * y_range + y_offset_base
		
		# Gentle float up over time (scaled speed) - REDUCED speed to keep it on body
		y_off -= _time * 15.0 * _scale_mult
		
		var pos = Vector2(x_off, y_off)
		
		# Fluctuate bit value rapidly (every ~0.08s)
		var flutter_time = _time + float(i) * 0.3
		var bit_val = int(flutter_time * 12.0)
		var bit = "1" if (bit_val % 2 == 0) else "0"
		
		# Fade out
		var alpha = 1.0 - (_time / duration)
		# Add subtle flicker
		alpha *= 0.7 + (sin(_time * 20.0 + float(i)) * 0.3)
		
		var color = Color(0.2, 0.95, 1.0, alpha)
		if i % 4 == 0:
			color = Color(0.6, 1.0, 0.8, alpha) # Occasional green bit
			
		draw_string(font, pos, bit, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)
"""
	script.reload()
	return script

func _get_hack_visual_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var _time: float = 0.0

func _ready() -> void:
	z_index = 10
	# Make unshaded for maximum brightness
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var font = ThemeDB.fallback_font
	var font_size = 14
	var num_bits = 8
	
	# Rotate rings of binary code
	for i in range(num_bits):
		var angle = (TAU / num_bits) * i + _time * 2.5
		var radius = 35.0 + sin(_time * 4.0 + float(i)) * 5.0
		
		var pos = Vector2(cos(angle), sin(angle)) * radius
		# Center the text
		pos -= Vector2(4, 8) 
		
		var alpha = 0.7 + sin(_time * 5.0 + float(i)) * 0.3
		var color = Color(0.1, 0.9, 0.5, alpha) # Matrix Green-ish Blue mix
		if i % 3 == 0:
			color = Color(0.1, 0.9, 1.0, alpha) # Cyan accent
			
		# Flip bits randomly-ish based on time
		var bit = "1" if (int(_time * 10.0 + i) % 2 == 0) else "0"
		
		draw_string(font, pos, bit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		
	# Inner faster ring
	for j in range(6):
		var angle = -(TAU / 6.0) * j - _time * 3.5
		var radius = 20.0
		var pos = Vector2(cos(angle), sin(angle)) * radius - Vector2(4, 8)
		var color = Color(0.1, 1.0, 0.8, 0.8)
		var bit = "0" if (j % 2 == 0) else "1"
		draw_string(font, pos, bit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
"""
	script.reload()
	return script

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

func get_attack_cooldown() -> float:
	return data.attack_cooldown

func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			reset_special_cooldown()
		"special_speed":
			# Overclock - drone speed upgrade
			drone_upgrade_level = mini(drone_upgrade_level + 1, 3)
			# Update existing drones with new speed
			for drone in _drones:
				if is_instance_valid(drone):
					drone.set_speed_multiplier(_get_drone_speed_multiplier())
		"special_shield":
			# Barrier Protocol - shield upgrade
			shield_upgrade_level = mini(shield_upgrade_level + 1, 3)
			# Update shield max hits
			if is_instance_valid(_shield):
				_shield.set_max_hits(_get_max_shield_hits())
		"burst_damage":
			burst_damage_boost = true
		"burst_boss":
			burst_boss_damage = true

func is_invincible() -> bool:
	return false

func _get_weapon_type_name() -> String:
	return "SMG"

## Get current drone mode for UI
func get_drone_mode() -> String:
	return _drone_mode
