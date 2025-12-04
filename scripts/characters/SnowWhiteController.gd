extends "res://scripts/characters/CharacterController.gd"
class_name SnowWhiteController
## Snow White - Sniper with piercing bullets and turret special

# Turret special state
var turret_charges: int = 0
var turret_max_charges: int = 1
var turret_recharging: bool = false
var turret_timer: float = 0.0
var turret_cooldown: float = 10.0

# Talent states
var special_count_level: int = 0  # +2 max charges per level
var special_capacity_level: int = 0  # +2 turret ammo per level
var burst_burn_level: int = 0
var burst_gauge_unlocked: bool = false

# Scripts for effects
const SnowWhiteBurstBeamScript = preload("res://scripts/characters/effects/SnowWhiteBurstBeam.gd")

func _on_initialize() -> void:
	# Snow White has 7 ammo
	max_ammo = 7
	ammo = max_ammo
	turret_charges = turret_max_charges

func _on_process(delta: float) -> void:
	# Update turret recharge - fully refills all charges when timer expires
	if turret_recharging:
		turret_timer -= delta
		if turret_timer <= 0:
			turret_charges = turret_max_charges  # Refill all charges at once
			turret_recharging = false

func _perform_attack(direction: Vector2) -> void:
	# Fire piercing bullet
	var bullet_scene = preload("res://scenes/effects/Bullet.tscn")
	var bullet = bullet_scene.instantiate()
	player.get_parent().add_child(bullet)
	bullet.global_position = player.global_position + direction * 200  # Spawn far outside player sprite
	bullet.velocity = direction * 2200
	bullet.rotation = direction.angle()  # Sprite child already has PI rotation built-in
	bullet.owner_node = player
	bullet.pierce_all = true  # Snow White's bullets pierce
	# Use character's base damage with level scaling
	bullet.base_damage = player.calc_damage()
	
	_play_sound("sniper")

func _can_use_special() -> bool:
	return turret_charges > 0

## Override use_special to bypass base class special_ready check
## Snow White uses her own charge/recharge system instead
func use_special(direction: Vector2) -> bool:
	if not special_unlocked:
		return false
	if not _can_use_special():
		return false
	
	_perform_special(direction)
	return true

func _perform_special(_direction: Vector2) -> void:
	# Update max charges based on talent
	turret_max_charges = 1 + special_count_level * 2
	
	# Spawn turret
	var turret_scene = preload("res://scenes/effects/Turret.tscn")
	var turret = turret_scene.instantiate()
	
	# Apply capacity bonus
	turret.ammo = 4 + special_capacity_level * 2
	turret.max_ammo = turret.ammo
	
	# Find spawn position
	var spawn_pos = _find_turret_position()
	if spawn_pos != Vector2.ZERO:
		turret.global_position = spawn_pos
		player.get_parent().add_child(turret)
		turret_charges -= 1
		
		# Start recharging
		if not turret_recharging:
			turret_recharging = true
			turret_timer = turret_cooldown

func _on_burst_start() -> void:
	# Get aim direction from player
	var aim_dir = player._get_aim_direction()
	
	var beam = SnowWhiteBurstBeamScript.new()
	beam.owner_node = player
	beam.damage = 50
	beam.beam_range = 1200.0
	beam.beam_angle_degrees = 90.0
	beam.burn_level = burst_burn_level
	beam.gauge_on_kill = burst_gauge_unlocked
	beam.configure(aim_dir)
	player.get_parent().add_child(beam)
	beam.global_position = player.global_position
	
	_play_sound("sniper")
	
	# Burst is instant for Snow White
	burst_active = false
	burst_ended.emit()

func _find_turret_position() -> Vector2:
	# Find a position near the player that doesn't overlap existing turrets
	var base_pos = player.global_position
	var check_radius = 80.0
	var offsets = [
		Vector2(0, -check_radius),
		Vector2(check_radius, 0),
		Vector2(0, check_radius),
		Vector2(-check_radius, 0),
		Vector2(check_radius * 0.7, -check_radius * 0.7),
		Vector2(check_radius * 0.7, check_radius * 0.7),
		Vector2(-check_radius * 0.7, check_radius * 0.7),
		Vector2(-check_radius * 0.7, -check_radius * 0.7),
	]
	
	for offset in offsets:
		var test_pos = base_pos + offset
		var overlap = false
		for turret in player.get_tree().get_nodes_in_group("turrets"):
			if turret.global_position.distance_to(test_pos) < 60:
				overlap = true
				break
		if not overlap:
			return test_pos
	
	return base_pos + Vector2(check_radius, 0)

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			turret_charges = turret_max_charges  # Refresh charges
			turret_timer = 0.0
			turret_recharging = false
		"special_count":
			special_count_level = mini(special_count_level + 1, 3)
			turret_max_charges = 1 + special_count_level * 2
			turret_charges = turret_max_charges  # Refresh charges
			turret_timer = 0.0
			turret_recharging = false
		"special_capacity":
			special_capacity_level = mini(special_capacity_level + 1, 3)
			turret_charges = turret_max_charges  # Refresh charges
			turret_timer = 0.0
			turret_recharging = false
		"burst_burn":
			burst_burn_level = mini(burst_burn_level + 1, 1)
		"burst_gauge":
			burst_gauge_unlocked = true

## Get special cooldown progress (turret recharge)
func get_special_cooldown_progress() -> float:
	if turret_charges >= turret_max_charges:
		return 1.0
	if turret_recharging:
		return 1.0 - (turret_timer / turret_cooldown)
	return 0.0

## Get current turret charges
func get_special_charges() -> int:
	return turret_charges

## Get max turret charges
func get_special_max_charges() -> int:
	return turret_max_charges

## Get weapon type name for audio
func _get_weapon_type_name() -> String:
	return "sniper"
