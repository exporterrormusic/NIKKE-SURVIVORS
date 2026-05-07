extends Node

## Kilo ally behavior - Shotgun with pellet spread

func configure(ally, _registry) -> void:
	var hp_mult := 1.0 + (ally.player_level - 1) * 0.25
	ally.max_hp = int(65 * hp_mult)
	ally.move_speed = 210.0
	ally.attack_damage = ally._get_scaled_damage(3)
	ally.attack_range = 300.0
	ally.attack_cooldown = 0.6
	ally._special_cooldown = 6.0
	ally._apply_wells_speed_boost()
	ally._load_sprite("kilo")

func attack(ally, direction: Vector2) -> void:
	var bs = BulletServer.get_instance()
	if bs:
		var amber_color = Color(1.0, 0.5, 0.0)
		var count = 5
		var spread = 15.0
		for i in range(count):
			var angle_offset = deg_to_rad(spread * (float(i) / (count - 1) - 0.5))
			var final_dir = direction.rotated(angle_offset)
			bs.spawn_colored_bullet(ally.global_position + direction * 20, final_dir * 850.0, ally.attack_damage, ally, amber_color, "summon")

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
