extends Node

## Scarlet ally behavior - Melee DPS with combo slashes

func configure(ally, _registry) -> void:
	var hp_mult := 1.0 + (ally.player_level - 1) * 0.25
	ally.max_hp = int(60 * hp_mult)
	ally.move_speed = 280.0
	ally.attack_damage = ally._get_scaled_damage(10)
	ally.attack_range = 120.0
	ally.attack_cooldown = 1.0
	ally._special_cooldown = 3.0
	ally._apply_wells_speed_boost()
	ally._load_sprite("scarlet")

func attack(ally, direction: Vector2) -> void:
	var slash = ProjectileCache.create_slash()
	if slash == null:
		return
	slash.rotation = direction.angle()
	slash.base_damage = ally.attack_damage
	slash.owner_node = ally
	if "killer_source_override" in slash:
		slash.killer_source_override = "summon"
	ally.add_child(slash)
	slash.position = Vector2.ZERO
	ally._scarlet_combo_count += 1

func should_use_special(ally) -> bool:
	var enemies := TargetCache.get_enemies()
	var nearby_count := 0
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if ally.global_position.distance_to((enemy as Node2D).global_position) < 200.0:
			nearby_count += 1
	return nearby_count >= 3

func perform_special(ally) -> void:
	var direction := ally._last_direction.normalized()
	if direction.length() < 0.5:
		direction = Vector2.RIGHT
	var wave = ProjectileCache.create_scarlet_wave()
	wave.rotation = direction.angle()
	wave.owner_node = ally
	wave.pierce_all = true
	wave.damage = ally.attack_damage * 2
	if "killer_source_override" in wave:
		wave.killer_source_override = "summon"
	ally.get_parent().add_child(wave)
	wave.global_position = ally.global_position + direction * 30
	wave.velocity = direction.normalized() * 1800

func perform_burst(ally) -> void:
	var ScarletBurstEffectScript = preload("res://scripts/characters/effects/ScarletBurstEffect.gd")
	var effect = ScarletBurstEffectScript.new()
	effect.owner_node = ally
	effect.execute_talent = false
	effect.vuln_talent = false
	ally.get_parent().add_child(effect)
	effect.global_position = ally.global_position

func get_optimal_range() -> float:
	return 80.0

func process(ally, _delta: float) -> void:
	pass
