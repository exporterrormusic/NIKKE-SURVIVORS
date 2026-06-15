extends "res://scripts/characters/CharacterController.gd"
class_name SnowWhiteController
## Snow White - Sniper with piercing bullets and turret special

# Shop upgrade reference


# Turret special state
var turret_charges: int = 0
var turret_max_charges: int = 2 # Start with 2 turrets (More Turrets adds +1/level -> max 5)
var turret_recharging: bool = false
var turret_timer: float = 0.0
var turret_cooldown: float = 10.0

# Skill-tree talent state (turret upgrades)
var defensive_line_unlocked: bool = false
var incendiary_level: int = 0          # 0-3 -> 2x/4x/6x rocket dmg burn (missiles)
var armor_piercing_level: int = 0      # 0-3 -> 2x/4x/6x damage-taken mark (missiles)
var permanent_emplacement: bool = false
var detonation_unlocked: bool = false
var _active_turrets: Array = []        # FIFO list of live permanent turrets

const TURRET_AURA_RADIUS := 160.0      # large aura (~5x the turret's drawn radius)
const TURRET_RELOAD_TIME := 6.0

# Attack-tree talent state
var _has_afterburn: bool = false       # Afterburn: bullets leave a fire trail
var weak_point_level: int = 0          # 0-3 -> x2/x4/x6 damage taken (permanent mark)
var explosive_level: int = 0           # 0-3 -> 10/25/50% explode-on-kill chance
var burning_level: int = 0             # 0-3 -> Burning DoT rank (applied via the trail)
var inferno_level: int = 0             # 0-3 -> Inferno slow rank (applied via the trail)
var charging_unlocked: bool = false    # Charging: hold-to-fire a wide shot
var unyielding_unlocked: bool = false  # Unyielding: bullet kills can heal you
var pending_charge_ratio: float = 0.0  # 0..1, set by PlayerInputHandler on a charged release

const WEAK_POINT_MULTS := [2.0, 4.0, 6.0]
const EXPLOSIVE_CHANCES := [0.10, 0.25, 0.50]
const EXPLOSION_RADIUS := 100.0
const MAX_CHARGE_WIDTH := 5.0          # bullet/trail width multiplier at full charge
const CHARGE_MUZZLE_DIST := 95.0       # how far ahead of the player the charge orb sits

# Muzzle charge-up visual (Charging talent)
const SnowWhiteChargeEffectScript = preload("res://scripts/characters/effects/SnowWhiteChargeEffect.gd")
var _charge_effect: Node2D = null

# Talent states (special / burst)
var special_count_level: int = 0 # +2 max charges per level
var special_capacity_level: int = 0 # +2 turret ammo per level
var burst_burn_level: int = 0          # Incendiary Rounds rank (0-3)
var burst_gauge_level: int = 0         # Fully Active rank (0-3)
var focused_fire_unlocked: bool = false
var pierce_through_level: int = 0      # Pierce Through rank (0-3)
var burst_stun_level: int = 0          # Stunned rank (0-3)
var century_prep_unlocked: bool = false
var goddess_no_yield_unlocked: bool = false
var pending_burst_charge: float = 0.0  # 0..1 from Focused Fire hold

const BURST_DMG_MULT := 10.0           # burst base damage = calc_damage x this (at full 90deg)
const BURST_BASE_ARC := 90.0
const BURST_MIN_ARC := 15.0
const SnowWhiteCenturyBarrageScript = preload("res://scripts/characters/effects/CenturyTurretBarrage.gd")
const SnowWhiteBurstPreviewScript = preload("res://scripts/characters/effects/SnowWhiteBurstChargePreview.gd")
var _burst_preview: Node2D = null

# Scripts for effects
const SnowWhiteBurstBeamScript = preload("res://scripts/characters/effects/SnowWhiteBurstBeam.gd")

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	turret_cooldown = data.special_cooldown
	turret_charges = turret_max_charges

	# Afterburn (fire trail) may already be owned if re-initialized; ranked attack
	# talents start at 0 and are tracked via apply_talent() as they're purchased.
	_has_afterburn = has_upgrade("snow_white", "afterburn")

func _on_process(delta: float) -> void:
	# Update turret recharge - fully refills all charges when timer expires
	if turret_recharging:
		turret_timer -= delta
		if turret_timer <= 0:
			turret_charges = turret_max_charges # Refill all charges at once
			turret_recharging = false

func _perform_attack(direction: Vector2) -> void:
	# Always use the Snow White bullet so it can carry the attack-talent payloads
	# (Weak Point, Explosive Rounds, Afterburn trail, Burning, Inferno, Charging).
	var bullet = ProjectileCache.create_snow_white_bullet()
	player.get_parent().add_child(bullet)
	bullet.global_position = player.global_position + direction * 200
	bullet.velocity = direction * 2200
	bullet.rotation = direction.angle()
	bullet.owner_node = player
	bullet.pierce_all = true
	bullet.max_range = 0.0
	bullet.base_damage = player.calc_damage()
	bullet.killer_source = "sniper"

	# Afterburn: leave a fire trail that carries the Burning/Inferno ranks.
	bullet.leave_burn_trail = _has_afterburn
	bullet.burning_level = burning_level
	bullet.inferno_level = inferno_level

	# Weak Point: mark hit enemies to take amplified damage from all sources.
	if weak_point_level > 0:
		bullet.weak_point_mult = WEAK_POINT_MULTS[weak_point_level - 1]

	# Charging: a charged release widens the bullet and its fire trail (up to 3x).
	if pending_charge_ratio > 0.0:
		var width_factor: float = 1.0 + (MAX_CHARGE_WIDTH - 1.0) * clampf(pending_charge_ratio, 0.0, 1.0)
		bullet.scale = Vector2(1.0, width_factor) # widen perpendicular to travel
		bullet.trail_width_mult = width_factor
	pending_charge_ratio = 0.0

	# The shot consumed any charge; drop the muzzle orb.
	_clear_charge_visual()

	_play_sound("sniper")


## Charging talent changes the normal attack to hold-to-charge, release-to-fire.
func is_charge_attack_enabled() -> bool:
	return charging_unlocked


## Focused Fire: hold the burst key to charge a narrowed, higher-damage cone.
func is_burst_charge_enabled() -> bool:
	return focused_fire_unlocked

func set_pending_burst_charge(ratio: float) -> void:
	pending_burst_charge = clampf(ratio, 0.0, 1.0)


## Show/update the ghost-arc burst preview (ratio 0..1). ratio <= 0 removes it.
## Driven each frame by PlayerInputHandler while the burst key is held.
func update_burst_charge_visual(ratio: float) -> void:
	if ratio <= 0.0:
		_clear_burst_charge_visual()
		return
	if _burst_preview == null or not is_instance_valid(_burst_preview):
		_burst_preview = SnowWhiteBurstPreviewScript.new()
		player.get_parent().add_child(_burst_preview)
	_burst_preview.global_position = player.global_position
	var arc: float = lerpf(BURST_BASE_ARC, BURST_MIN_ARC, clampf(ratio, 0.0, 1.0))
	_burst_preview.set_charge(player.aim_direction, arc, ratio >= 1.0)


func _clear_burst_charge_visual() -> void:
	if _burst_preview and is_instance_valid(_burst_preview):
		_burst_preview.queue_free()
	_burst_preview = null

## A Goddess Who Cannot Yield: fraction of the burst gauge consumed on use.
func get_burst_consume_fraction() -> float:
	if not goddess_no_yield_unlocked:
		return 1.0
	var r := randf()
	if r < 0.25:
		return 0.0 # consume nothing - gauge stays full
	elif r < 0.5:
		return 0.5 # consume half
	return 1.0     # consume all


## Show/update the muzzle charge orb (ratio 0..1). ratio <= 0 removes it.
## Called every frame by PlayerInputHandler while the attack button is held.
func update_charge_visual(ratio: float) -> void:
	if ratio <= 0.0:
		_clear_charge_visual()
		return
	if _charge_effect == null or not is_instance_valid(_charge_effect):
		_charge_effect = SnowWhiteChargeEffectScript.new()
		player.add_child(_charge_effect)
	_charge_effect.position = player.aim_direction * CHARGE_MUZZLE_DIST
	_charge_effect.set_ratio(ratio)


func _clear_charge_visual() -> void:
	if _charge_effect and is_instance_valid(_charge_effect):
		_charge_effect.queue_free()
	_charge_effect = null

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
	# Update max charges based on talent (base 2, +1 per More Turrets level -> max 5)
	turret_max_charges = 2 + special_count_level

	# Permanent Emplacement: enforce the active-turret cap by retiring the oldest
	# (which Detonates if that talent is owned) to make room for the new one.
	if permanent_emplacement:
		_active_turrets = _active_turrets.filter(func(t): return is_instance_valid(t))
		while _active_turrets.size() >= turret_max_charges:
			var oldest = _active_turrets.pop_front()
			if is_instance_valid(oldest) and oldest.has_method("request_despawn"):
				oldest.request_despawn()

	# Spawn turret
	var turret = ProjectileCache.create_turret()

	# Apply capacity bonus
	turret.ammo = 4 + special_capacity_level * 2
	turret.max_ammo = turret.ammo

	# Hand over the turret-upgrade talent payloads
	_configure_turret(turret)

	# Find spawn position
	var spawn_pos = _find_turret_position()
	if spawn_pos != Vector2.ZERO:
		turret.global_position = spawn_pos
		player.get_parent().add_child(turret)
		if permanent_emplacement:
			_active_turrets.append(turret)
		turret_charges -= 1

		# Start recharging
		if not turret_recharging:
			turret_recharging = true
			turret_timer = turret_cooldown


## Push the current turret-upgrade talent state onto a freshly created turret.
func _configure_turret(turret) -> void:
	turret.defensive_line = defensive_line_unlocked
	turret.aura_radius = TURRET_AURA_RADIUS
	turret.incendiary_level = incendiary_level
	turret.armor_piercing_level = armor_piercing_level
	turret.permanent = permanent_emplacement
	turret.detonation = detonation_unlocked
	turret.reload_time = TURRET_RELOAD_TIME

func _on_burst_start() -> void:
	# Get aim direction from player (use public variable, not method)
	var aim_dir = player.aim_direction

	# Focused Fire: a charged hold narrows the cone (90 -> 15 deg) and scales
	# damage inversely (1x at 90, up to 6x at 15).
	var ratio: float = clampf(pending_burst_charge, 0.0, 1.0)
	pending_burst_charge = 0.0
	var arc: float = lerpf(BURST_BASE_ARC, BURST_MIN_ARC, ratio)

	var beam = SnowWhiteBurstBeamScript.new()
	beam.owner_node = player
	beam.damage = int(player.calc_damage() * BURST_DMG_MULT)
	beam.damage_multiplier = BURST_BASE_ARC / arc
	beam.beam_range = 1200.0
	beam.beam_angle_degrees = arc
	beam.burn_level = burst_burn_level
	beam.gauge_level = burst_gauge_level
	beam.gauge_per_kill = BurstConfig.get_rate(data.weapon_kind) if data else 0.0
	beam.pierce_level = pierce_through_level
	beam.stun_level = burst_stun_level
	beam.player_level = player.level if "level" in player else 1
	beam.configure(aim_dir)
	player.get_parent().add_child(beam)
	beam.global_position = player.global_position

	# A CENTURY OF PREP TIME: deploy turrets across the whole map.
	if century_prep_unlocked:
		var barrage = SnowWhiteCenturyBarrageScript.new()
		barrage.owner_node = player
		player.get_parent().add_child(barrage)

	# The shot fired; drop the ghost-arc preview.
	_clear_burst_charge_visual()

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

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		# --- ATTACK tree ---
		"weak_point":
			weak_point_level = mini(weak_point_level + 1, 3)
		"explosive_rounds":
			explosive_level = mini(explosive_level + 1, 3)
		"afterburn":
			_has_afterburn = true
		"burning":
			burning_level = mini(burning_level + 1, 3)
		"inferno":
			inferno_level = mini(inferno_level + 1, 3)
		"charging":
			charging_unlocked = true
		"unyielding":
			unyielding_unlocked = true
		# --- SKILL / BURST tree ---
		"special":
			special_unlocked = true
			turret_charges = turret_max_charges # Refresh charges
			turret_timer = 0.0
			turret_recharging = false
		"special_count":
			special_count_level = mini(special_count_level + 1, 3)
			turret_max_charges = 2 + special_count_level
			turret_charges = turret_max_charges # Refresh charges
			turret_timer = 0.0
			turret_recharging = false
		"special_capacity":
			special_capacity_level = mini(special_capacity_level + 1, 3)
			turret_charges = turret_max_charges # Refresh charges
			turret_timer = 0.0
			turret_recharging = false
		"defensive_line":
			defensive_line_unlocked = true
		"incendiary_ammo":
			incendiary_level = mini(incendiary_level + 1, 3)
		"armor_piercing":
			armor_piercing_level = mini(armor_piercing_level + 1, 3)
		"permanent_emplacement":
			permanent_emplacement = true
		"detonation":
			detonation_unlocked = true
		"burst_burn":
			burst_burn_level = mini(burst_burn_level + 1, 3)
		"burst_gauge":
			burst_gauge_level = mini(burst_gauge_level + 1, 3)
		"focused_fire":
			focused_fire_unlocked = true
		"pierce_through":
			pierce_through_level = mini(pierce_through_level + 1, 3)
		"burst_stun":
			burst_stun_level = mini(burst_stun_level + 1, 3)
		"century_prep":
			century_prep_unlocked = true
		"goddess_no_yield":
			goddess_no_yield_unlocked = true


## Kill-triggered attack talents (Explosive Rounds, Unyielding). Called by
## PlayerCore.on_enemy_killed. Only direct bullet kills ("sniper") qualify - the
## fire trail, Burning DoT and the explosion itself use other source strings, so
## they can't chain explosions or proc Unyielding.
func on_enemy_killed(enemy: Node, killer_source: String) -> void:
	if killer_source != "sniper":
		return

	# Explosive Rounds: chance for the killed enemy to detonate.
	if explosive_level > 0 and is_instance_valid(enemy) and enemy is Node2D:
		if randf() < EXPLOSIVE_CHANCES[explosive_level - 1]:
			_spawn_explosive_round((enemy as Node2D).global_position)

	# Unyielding: 20% chance to heal 1 HP per bullet kill.
	if unyielding_unlocked and randf() < 0.20:
		if player and player.has_method("heal"):
			player.heal(1)


## Spawn a rocket-sized explosion dealing damage equal to the default attack.
## Damage routes through take_damage, so a Weak Point mark on nearby enemies
## amplifies it automatically.
func _spawn_explosive_round(pos: Vector2) -> void:
	var parent = player.get_parent()
	if parent == null:
		return

	var explosion = ProjectileCache.create_explosion()
	if explosion.has_method("initialize"):
		explosion.initialize(player.calc_damage(), EXPLOSION_RADIUS)
	explosion.owner_node = player
	explosion.killer_source_override = "snow_white_explosion"
	if explosion.has_node("Sprite2D"):
		explosion.get_node("Sprite2D").visible = false
	parent.add_child(explosion)
	explosion.global_position = pos

	var visual = ProjectileCache.create_explosion_effect()
	if visual:
		if "radius" in visual:
			visual.radius = EXPLOSION_RADIUS
		parent.add_child(visual)
		visual.global_position = pos


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

