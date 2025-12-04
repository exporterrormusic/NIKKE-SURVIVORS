extends "res://scripts/characters/CharacterController.gd"
class_name RapunzelController
## Rapunzel - Rocket launcher with healing abilities

# Healing cross special state
var cross_timer: float = 0.0
var cross_cooldown: float = 5.0

# Talent states
var special_power_level: int = 0  # Healing power bonus
var special_size_level: int = 0  # Healing radius/duration bonus
var burst_stun_level: int = 0
var burst_invuln_unlocked: bool = false

# Scripts for effects
const RapunzelBurstEffectScript = preload("res://scripts/RapunzelBurstEffect.gd")

func _on_initialize() -> void:
	# Rapunzel has 4 rockets
	max_ammo = 4
	ammo = max_ammo

func _on_process(delta: float) -> void:
	# Update cross cooldown
	if cross_timer > 0:
		cross_timer -= delta
		special_cooldown_changed.emit(get_special_cooldown_progress())

func _perform_attack(direction: Vector2) -> void:
	# Fire homing missile
	var mouse_pos = player.get_global_mouse_position()
	var missile_scene = preload("res://scenes/effects/Missile.tscn")
	var missile = missile_scene.instantiate()
	player.get_parent().add_child(missile)
	missile.global_position = player.global_position + direction * 100
	missile.target_position = mouse_pos
	missile.direction = direction
	missile.explode_at_target = true
	missile.speed = 400
	missile.acceleration = 1500
	missile.max_speed = 3000
	missile.owner_node = player
	missile.ground_fire_enabled = true
	missile.ground_fire_duration = 3.0
	# Use character's base damage with level scaling
	var base_dmg: int = player.calc_damage()
	missile.base_damage = base_dmg
	missile.ground_fire_damage = maxi(int(base_dmg / 3.0), 1)  # Ground fire does 1/3 of missile damage
	missile.ground_fire_radius = 100.0
	
	_play_sound("rocket")

func _can_use_special() -> bool:
	return cross_timer <= 0

func _perform_special(direction: Vector2) -> void:
	# Spawn healing cross
	var cross_scene = load("res://scenes/effects/HealingCross.tscn")
	if cross_scene:
		var cross = cross_scene.instantiate()
		
		# Apply power bonus: 3% base + 7/14.5/22% per level
		var power_bonuses := [0.0, 0.07, 0.145, 0.22]
		cross.heal_percent = 0.03 + power_bonuses[mini(special_power_level, 3)]
		
		# Apply size bonus: 1x base multiplier for radius and lifespan
		var size_multipliers := [1.0, 1.5, 2.5, 4.0]
		var size_mult: float = size_multipliers[mini(special_size_level, 3)]
		cross.heal_radius = 180.0 * size_mult
		cross.lifespan = 9.0 * size_mult
		
		player.get_parent().add_child(cross)
		cross.global_position = player.global_position + direction * 60
	
	# Start cooldown
	cross_timer = cross_cooldown

func _on_burst_start() -> void:
	var effect = RapunzelBurstEffectScript.new()
	effect.owner_node = player
	
	# Stun: 4s base, 8s if talent unlocked
	effect.stun_duration = 8.0 if burst_stun_level > 0 else 4.0
	
	# Invincibility: 8s if talent unlocked
	effect.grant_invuln = burst_invuln_unlocked
	effect.invuln_duration = 8.0
	
	player.get_parent().add_child(effect)
	effect.global_position = player.global_position
	
	# Burst is instant for Rapunzel (effect handles duration)
	burst_active = false
	burst_ended.emit()

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

## Get weapon type name for audio
func _get_weapon_type_name() -> String:
	return "rocket"

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			cross_timer = 0.0  # Refresh cooldown
		"special_power":
			special_power_level = mini(special_power_level + 1, 3)
			cross_timer = 0.0  # Refresh cooldown
		"special_size":
			special_size_level = mini(special_size_level + 1, 3)
			cross_timer = 0.0  # Refresh cooldown
		"burst_stun":
			burst_stun_level = mini(burst_stun_level + 1, 1)
		"burst_invuln":
			burst_invuln_unlocked = true

## Get special cooldown progress
func get_special_cooldown_progress() -> float:
	if cross_timer <= 0:
		return 1.0
	return 1.0 - (cross_timer / cross_cooldown)
