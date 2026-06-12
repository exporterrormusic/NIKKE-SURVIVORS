extends Node

## Crown ally behavior - Minigun with golden bullets

func configure(ally, _registry) -> void:
	var hp_mult: float = 1.0 + (ally.player_level - 1) * 0.25
	ally.max_hp = int(70 * hp_mult)
	ally.move_speed = 240.0
	ally.attack_damage = ally._get_scaled_damage(2)
	ally.attack_range = 450.0
	ally.attack_cooldown = 0.08
	ally._special_cooldown = 8.0
	ally._apply_wells_speed_boost()
	ally._load_sprite("crown")

func attack(ally, direction: Vector2) -> void:
	var bs = BulletServer.get_instance()
	if bs:
		var gold_color = Color(1.0, 0.84, 0.0)
		bs.spawn_colored_bullet(ally.global_position + direction * 20, direction * 1100.0, ally.attack_damage, ally, gold_color, "summon")

func should_use_special(ally) -> bool:
	return false

func perform_special(ally) -> void:
	pass

func perform_burst(ally) -> void:
	pass

func get_optimal_range() -> float:
	return 200.0

func process(ally, _delta: float) -> void:
	pass
