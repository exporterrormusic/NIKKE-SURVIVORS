extends "res://scripts/characters/CharacterController.gd"
class_name RapunzelController
## Rapunzel - Rocket launcher with healing abilities

# Healing cross special state
var cross_timer: float = 0.0
var cross_cooldown: float = 5.0

# Talent states
var special_power_level: int = 0 # Healing power bonus
var special_size_level: int = 0 # Healing radius/duration bonus
var burst_stun_level: int = 0
var burst_turrets_unlocked: bool = false # "6,000? Really?" talent - spawns 20 turrets

# Scripts for effects
const RapunzelBurstEffectScript = preload("res://scripts/characters/effects/RapunzelBurstEffect.gd")

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	pass

func _on_process(delta: float) -> void:
	# Update cross cooldown
	if cross_timer > 0:
		cross_timer -= delta
		special_cooldown_changed.emit(get_special_cooldown_progress())

func _perform_attack(direction: Vector2) -> void:
	# Fire homing missile
	var mouse_pos = player.get_global_mouse_position()
	var missile = ProjectileCache.create_missile()
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
	missile.damage = base_dmg
	missile.explosion_damage = base_dmg
	missile.ground_fire_damage = maxi(int(base_dmg / 3.0), 1) # Ground fire does 1/3 of missile damage
	missile.ground_fire_radius = 120.0
	
	_play_sound("rocket")

func _can_use_special() -> bool:
	return cross_timer <= 0

## Override use_special to bypass base class special_ready check
## Rapunzel uses cross_timer instead of special_timer for cooldown
func use_special(direction: Vector2) -> bool:
	if not special_unlocked:
		return false
	if not _can_use_special():
		return false
	_perform_special(direction)
	return true

func _perform_special(direction: Vector2) -> void:
	# Spawn healing cross
	var cross = ProjectileCache.create_healing_cross()
	
	# Apply power bonus: 3% base + 7/14.5/22% per level
	var power_bonuses := [0.0, 0.07, 0.145, 0.22]
	cross.heal_percent = 0.03 + power_bonuses[mini(special_power_level, 3)]
	
	# Apply size bonus: 1x base multiplier for radius only
	var size_multipliers := [1.0, 1.5, 2.5, 4.0]
	var size_mult: float = size_multipliers[mini(special_size_level, 3)]
	cross.heal_radius = 180.0 * size_mult
	cross.lifespan = 9.0 # Fixed duration, not affected by size talent
	
	player.get_parent().add_child(cross)
	cross.global_position = player.global_position + direction * 60
	
	# Check for Burning Sensation upgrade
	if ShopMenuScript.has_character_upgrade("rapunzel", "burning_sensation"):
		cross.burn_enabled = true
	
	# Start cooldown
	cross_timer = cross_cooldown

func _on_burst_start() -> void:
	var effect = RapunzelBurstEffectScript.new()
	effect.owner_node = player
	
	# Stun: 4s base, 8s if talent unlocked
	effect.stun_duration = 8.0 if burst_stun_level > 0 else 4.0
	
	# Invincibility: 8s by default (was talent-gated)
	effect.grant_invuln = true
	effect.invuln_duration = 8.0
	
	# "6,000? Really?" talent: spawn 20 turrets around map edges
	effect.spawn_turrets = burst_turrets_unlocked
	effect.turret_owner_level = player.level if "level" in player else 1
	
	player.get_parent().add_child(effect)
	effect.global_position = player.global_position
	
	# Burst is instant for Rapunzel (effect handles duration)
	burst_active = false
	burst_ended.emit()

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			cross_timer = 0.0 # Refresh cooldown
		"special_power":
			special_power_level = mini(special_power_level + 1, 3)
			cross_timer = 0.0 # Refresh cooldown
		"special_size":
			special_size_level = mini(special_size_level + 1, 3)
			cross_timer = 0.0 # Refresh cooldown
		"burst_stun":
			burst_stun_level = mini(burst_stun_level + 1, 1)
		"burst_turrets":
			burst_turrets_unlocked = true

## Get special cooldown progress
func get_special_cooldown_progress() -> float:
	if cross_timer <= 0:
		return 1.0
	return 1.0 - (cross_timer / cross_cooldown)
