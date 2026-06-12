extends Node

## Rapunzel ally behavior - Rocket launcher with healing crosses

var ammo: int = 6
var max_ammo: int = 6
var reload_timer: float = 0.0
var special_used: bool = false

func configure(ally, registry) -> void:
	var hp_mult: float = 1.0 + (ally.player_level - 1) * 0.25
	ally.max_hp = int(55 * hp_mult)
	ally.move_speed = 220.0
	ally.attack_damage = ally._get_scaled_damage(15)
	ally.attack_range = 500.0
	ally.attack_cooldown = 1.5
	ally._special_cooldown = 4.0
	var data = registry.get_character("rapunzel") if registry else null
	var base_ammo: int = data.ammo_capacity if data else 4
	ammo = int(base_ammo * 1.5)
	if ally._shop_script and ally._shop_script.has_character_upgrade("snow_white", "master_mechanic"):
		ammo *= 2
		print("[AllyRapunzel] Master Mechanic boost (Ammo: %d)" % ammo)
	max_ammo = ammo
	ally._apply_wells_speed_boost()
	ally._load_sprite("rapunzel")

func attack(ally, direction: Vector2) -> void:
	if ammo <= 0:
		if reload_timer <= 0:
			reload_timer = 1.5
		return
	ammo -= 1
	var rocket = ProjectileCache.create_missile()
	if rocket == null:
		return
	rocket.owner_node = ally
	if "killer_source_override" in rocket:
		rocket.killer_source_override = "summon"
	rocket.direction = direction
	var target = ally._target_enemy
	rocket.target_position = target.global_position if target else ally.global_position + direction * 400
	rocket.speed = 400.0
	ally.get_parent().add_child(rocket)
	rocket.global_position = ally.global_position + direction * 50

func should_use_special(ally) -> bool:
	return not special_used

func perform_special(ally) -> void:
	var spawn_pos: Vector2 = ally._find_spaced_position("HealingCross", 80.0)
	var heal_item = ProjectileCache.create_healing_cross()
	ally.get_parent().add_child(heal_item)
	heal_item.global_position = spawn_pos
	special_used = true

func perform_burst(ally) -> void:
	var RapunzelBurstEffectScript = preload("res://scripts/characters/effects/RapunzelBurstEffect.gd")
	var effect = RapunzelBurstEffectScript.new()
	effect.owner_node = ally
	effect.stun_duration = 4.0
	effect.grant_invuln = false
	ally.get_parent().add_child(effect)
	effect.global_position = ally.global_position

func get_optimal_range() -> float:
	return 300.0

func process(ally, delta: float) -> void:
	if reload_timer > 0:
		reload_timer -= delta
		if reload_timer <= 0:
			ammo = max_ammo
