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
		drone.initialize(player, i, angle_offset, _get_drone_speed_multiplier(), _get_drone_damage_multiplier())
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

func _get_drone_damage_multiplier() -> float:
	# Same as speed multiplier
	return _get_drone_speed_multiplier()

func _get_max_shield_hits() -> int:
	# 1 base, +1 per upgrade level
	return 1 + shield_upgrade_level

func _can_attack() -> bool:
	return not is_reloading and ammo > 0

# Preload the bullet shader
var _bullet_shader: Shader = null

func _get_bullet_shader() -> Shader:
	if not _bullet_shader:
		_bullet_shader = load("res://resources/shaders/cecil_bullet.gdshader")
	return _bullet_shader

func _perform_attack(direction: Vector2) -> void:
	# Fire dual SMG bullets (same as Sin)
	var bullet_scene = preload("res://scenes/effects/SMGBullet.tscn")
	var shader := _get_bullet_shader()
	
	var perp := Vector2(-direction.y, direction.x).normalized()
	var gun_offset := 18.0
	
	# Each SMG bullet does 1 base damage (2 total per shot)
	var bullet_damage: int = maxi(player.calc_damage(1.0 / player.get_base_damage()), 1)
	
	# Left gun bullet
	var bullet_left = bullet_scene.instantiate()
	player.get_parent().add_child(bullet_left)
	bullet_left.global_position = player.global_position + direction * 45 - perp * gun_offset
	bullet_left.velocity = direction * bullet_speed
	bullet_left.rotation = direction.angle()
	bullet_left.owner_node = player
	bullet_left.base_damage = bullet_damage
	_apply_bullet_shader(bullet_left, shader)
	
	# Right gun bullet
	var bullet_right = bullet_scene.instantiate()
	player.get_parent().add_child(bullet_right)
	bullet_right.global_position = player.global_position + direction * 45 + perp * gun_offset
	bullet_right.velocity = direction * bullet_speed
	bullet_right.rotation = direction.angle()
	bullet_right.owner_node = player
	bullet_right.base_damage = bullet_damage
	_apply_bullet_shader(bullet_right, shader)
	
	_play_sound("smg")

func _apply_bullet_shader(bullet: Node, shader: Shader) -> void:
	if not shader:
		return
	# Find the Sprite2D child and apply the shader
	var sprite := bullet.get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		sprite.material = mat
		sprite.modulate = Color.WHITE  # Reset modulate so shader controls colors

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

func _ready() -> void:
	z_index = 100

func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Static electrical effect
	var num_sparks := 8
	for i in range(num_sparks):
		var angle := (TAU / num_sparks) * i + _time * 5.0
		var radius := 25.0 + sin(_time * 10.0 + i) * 8.0
		var pos := Vector2(cos(angle), sin(angle)) * radius
		
		# Draw spark line
		var spark_end := pos + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		var alpha := 0.8 * (1.0 - _time / duration)
		draw_line(pos, spark_end, Color(0.3, 0.7, 1.0, alpha), 2.0)
		
		# Draw small circle at spark
		draw_circle(pos, 3.0, Color(0.5, 0.9, 1.0, alpha))
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

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	# Blue circuit-like glow around hacked enemy
	var num_lines := 6
	for i in range(num_lines):
		var angle := (TAU / num_lines) * i + _time * 2.0
		var radius := 20.0 + sin(_time * 3.0 + i * 0.5) * 5.0
		var pos := Vector2(cos(angle), sin(angle)) * radius
		var alpha := 0.5 + sin(_time * 4.0 + i) * 0.2
		draw_circle(pos, 2.0, Color(0.3, 0.7, 1.0, alpha))
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
			special_timer = 0.0
		"drone_upgrade":
			drone_upgrade_level = mini(drone_upgrade_level + 1, 3)
			# Update existing drones
			for drone in _drones:
				if is_instance_valid(drone):
					drone.set_multipliers(_get_drone_speed_multiplier(), _get_drone_damage_multiplier())
		"shield_upgrade":
			shield_upgrade_level = mini(shield_upgrade_level + 1, 3)
			# Update shield max hits
			if is_instance_valid(_shield):
				_shield.set_max_hits(_get_max_shield_hits())
		"burst_damage_boost":
			burst_damage_boost = true
		"burst_boss_damage":
			burst_boss_damage = true

func is_invincible() -> bool:
	return false

func _get_weapon_type_name() -> String:
	return "SMG"

## Get current drone mode for UI
func get_drone_mode() -> String:
	return _drone_mode
