extends Node

## Snow White ally behavior - Sniper with piercing shots and turret

var ammo: int = 7
var max_ammo: int = 7
var reload_timer: float = 0.0
var turret_placed: bool = false

func configure(ally, registry) -> void:
	var hp_mult := 1.0 + (ally.player_level - 1) * 0.25
	ally.max_hp = int(45 * hp_mult)
	ally.move_speed = 200.0
	ally.attack_damage = ally._get_scaled_damage(7)
	ally.attack_range = 600.0
	ally.attack_cooldown = 0.5
	ally._special_cooldown = 6.0
	var data = registry.get_character("snow_white") if registry else null
	ammo = data.ammo_capacity if data else 7
	if ally._shop_script and ally._shop_script.has_character_upgrade("snow_white", "master_mechanic"):
		ammo *= 2
		print("[AllySnowWhite] Master Mechanic boost (Ammo: %d)" % ammo)
	max_ammo = ammo
	ally._apply_wells_speed_boost()
	ally._load_sprite("snow_white")

func attack(ally, direction: Vector2) -> void:
	if ammo <= 0:
		if reload_timer <= 0:
			reload_timer = 0.8
		return
	ammo -= 1
	var bullet = ProjectileCache.create_snow_white_bullet()
	if bullet == null:
		return
	ally.get_parent().add_child(bullet)
	bullet.global_position = ally.global_position + direction * 60
	bullet.velocity = direction * 2200.0
	bullet.rotation = direction.angle()
	bullet.owner_node = ally
	if "killer_source_override" in bullet:
		bullet.killer_source_override = "summon"
	bullet.base_damage = ally.attack_damage
	bullet.pierce_all = true

func should_use_special(ally) -> bool:
	return not turret_placed

func perform_special(ally) -> void:
	var spawn_pos := ally._find_spaced_position("Turret", 120.0)
	var turret = ProjectileCache.create_turret()
	turret.ammo = 12
	turret.max_ammo = 12
	if "killer_source_override" in turret:
		turret.killer_source_override = "summon"
	turret.spawned_by_summon = true
	turret.spawner_node = ally
	ally.get_parent().add_child(turret)
	turret.global_position = spawn_pos
	turret_placed = true

func perform_burst(ally) -> void:
	var SnowWhiteBurstBeamScript = preload("res://scripts/characters/effects/SnowWhiteBurstBeam.gd")
	var direction := ally._last_direction.normalized()
	if direction.length() < 0.5:
		direction = Vector2.RIGHT
	var beam = SnowWhiteBurstBeamScript.new()
	beam.owner_node = ally
	beam.damage = 50
	beam.beam_range = 1200.0
	beam.beam_angle_degrees = 90.0
	beam.burn_level = 0
	beam.gauge_on_kill = false
	beam.player_level = ally.player_level
	beam.configure(direction)
	ally.get_parent().add_child(beam)
	beam.global_position = ally.global_position

func get_optimal_range() -> float:
	return 400.0

func process(ally, delta: float) -> void:
	if reload_timer > 0:
		reload_timer -= delta
		if reload_timer <= 0:
			ammo = max_ammo
