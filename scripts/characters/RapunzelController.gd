extends "res://scripts/characters/CharacterController.gd"
class_name RapunzelController
## Rapunzel - Rocket launcher with healing abilities

# Healing cross special state
var cross_timer: float = 0.0
var cross_cooldown: float = 5.0

# Talent states
var special_power_level: int = 0 # Healing power bonus
var special_size_level: int = 0 # Healing radius/duration bonus
var burst_stun_level: int = 0          # "Blinding Radiance" - burst stun bonus (non-bosses)
var burst_turrets_unlocked: bool = false # "6,000? Really?" talent - spawns 20 turrets

# Burst-tree talent states
var lingering_light_level: int = 0       # "Lingering Light" - post-burst heal-over-time
var incendiary_rockets_level: int = 0    # "Incendiary Rockets" - turret rockets leave It Burns ground
var extra_stuffed_level: int = 0         # "Extra Stuffed" - turrets carry +2/4/6 ammo
var anti_queen_unlocked: bool = false    # "Anti-Queen Bombardment" - hold-to-aim the barrage
var goddess_no_yield_unlocked: bool = false # "A Goddess Who Cannot Yield"

const BLINDING_BONUS := [0.0, 2.0, 4.0, 6.0]      # burst stun bonus per rank (non-bosses)
const LINGERING_DURATIONS := [0.0, 6.0, 8.0, 10.0] # heal-over-time seconds per rank
const LINGERING_HEAL_PCT := 0.10                   # % max HP healed per second
const EXTRA_STUFFED_AMMO := [0, 2, 4, 6]           # bonus turret ammo per rank
# ~1s hold to arm, given PlayerInputHandler's BURST_CHARGE_MAX of 2.5s (1.0 / 2.5).
const ANTI_QUEEN_ARM_RATIO := 0.4

var _pending_burst_charge: float = 0.0   # hold ratio captured on burst release (Anti-Queen)
var _lingering_remaining: float = 0.0    # Lingering Light HoT time left
var _lingering_tick_accum: float = 0.0
var _designator: Node = null             # Anti-Queen laser designator visual
const RapunzelDesignatorScript = preload("res://scripts/characters/effects/RapunzelDesignator.gd")

# Skill-tree talent states (Divine Blessing upgrades)
var more_more_level: int = 0           # "More, more!" - blessing burn damage x2/x4/x6
var oooh_ahhhh_level: int = 0          # "Oooh, Ahhhh" - blessing first-hit stun
var personal_toy_unlocked: bool = false # "Personal Toy" - blessing aura follows the player
var all_the_toys_unlocked: bool = false # "All the Toys" - aura stays active while one is deployed

const MORE_MORE_MULTS := [1.0, 2.0, 4.0, 6.0] # burn damage multiplier (index by level)
const OOOH_STUNS := [0.0, 0.5, 1.0, 1.5]      # stun seconds (index by level)

var _personal_aura: Node = null  # the persistent follow-the-player blessing aura
var _deployed_cross: Node = null # the currently active deployable Divine Blessing

# Attack-tree talent states
var concussive_level: int = 0          # "Concussive Blast" - rocket/explosion stun
var anti_armor_level: int = 0          # "Anti-Armor Munitions" - permanent damage mark
var burning_desire_unlocked: bool = false # "Burning Desire" - rocket leaves burning zone
var spread_level: int = 0              # "Spread the Love" - burning zone size
var it_burns_level: int = 0            # "It Burns" - burning zone applies a DoT
var endless_desire_unlocked: bool = false # "Endless Desire" - permanent stacking DoTs

const CONCUSSIVE_STUNS := [0.5, 1.0, 1.5]   # stun seconds per rank
const ANTI_ARMOR_MULTS := [2.0, 4.0, 6.0]   # permanent damage-taken multiplier per rank
const SPREAD_MULTS := [1.0, 1.5, 2.0, 2.5]  # burning zone size multiplier (index by level)
const IT_BURNS_MULTS := [0.0, 2.0, 4.0, 6.0] # burn DoT multiplier (index by level)

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

	_update_personal_aura()
	_update_lingering_light(delta)

## Lingering Light: heal 10% max HP each second for the talent's duration after a burst.
func _update_lingering_light(delta: float) -> void:
	if _lingering_remaining <= 0.0:
		return
	_lingering_remaining -= delta
	_lingering_tick_accum += delta
	if _lingering_tick_accum >= 1.0:
		_lingering_tick_accum -= 1.0
		if is_instance_valid(player) and player.has_method("heal"):
			player.heal(maxi(1, int(player.max_hp * LINGERING_HEAL_PCT)))

## Personal Toy: keep a blessing aura on the player. It's active only when no
## deployable Divine Blessing is alive - unless All the Toys lifts that limit.
func _update_personal_aura() -> void:
	if not personal_toy_unlocked:
		return
	if not is_instance_valid(_personal_aura):
		_personal_aura = ProjectileCache.create_healing_cross()
		_personal_aura.follow_target = player
		_personal_aura.persistent = true
		player.get_parent().add_child(_personal_aura)
		_personal_aura.global_position = player.global_position
		_configure_blessing(_personal_aura)
	var deployed_active: bool = is_instance_valid(_deployed_cross)
	_personal_aura.active = all_the_toys_unlocked or not deployed_active

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
	# Use character's base damage with level scaling
	var base_dmg: int = player.calc_damage()
	missile.damage = base_dmg
	missile.explosion_damage = base_dmg

	# Concussive Blast: explosion stuns enemies hit.
	if concussive_level > 0:
		missile.explosion_stun_duration = CONCUSSIVE_STUNS[mini(concussive_level, CONCUSSIVE_STUNS.size()) - 1]
	# Anti-Armor Munitions: explosion permanently marks enemies for amplified damage.
	if anti_armor_level > 0:
		missile.armor_pierce_mult = ANTI_ARMOR_MULTS[mini(anti_armor_level, ANTI_ARMOR_MULTS.size()) - 1]

	# Burning Desire: rocket leaves a burning zone (off by default).
	if burning_desire_unlocked:
		missile.ground_fire_enabled = true
		missile.ground_fire_duration = 3.0
		missile.ground_fire_damage = maxi(int(base_dmg / 3.0), 1) # Ground fire does 1/3 of missile damage
		# Spread the Love: scale the zone size.
		missile.ground_fire_radius = 120.0 * SPREAD_MULTS[mini(spread_level, SPREAD_MULTS.size() - 1)]
		# It Burns / Endless Desire payloads.
		missile.ground_fire_it_burns_mult = IT_BURNS_MULTS[mini(it_burns_level, IT_BURNS_MULTS.size() - 1)]
		missile.ground_fire_attack_damage = base_dmg
		missile.ground_fire_endless = endless_desire_unlocked

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
	# Spawn deployable Divine Blessing
	var cross = ProjectileCache.create_healing_cross()
	cross.lifespan = 9.0 # Fixed duration, not affected by size talent
	_configure_blessing(cross)

	player.get_parent().add_child(cross)
	cross.global_position = player.global_position + direction * 60
	_deployed_cross = cross

	# Start cooldown
	cross_timer = cross_cooldown

## Apply the current Divine Blessing talent values to a blessing node (deployable
## cross or the Personal Toy follow aura).
func _configure_blessing(cross) -> void:
	# Power: 3% base + 7/14.5/22% per level
	var power_bonuses := [0.0, 0.07, 0.145, 0.22]
	cross.heal_percent = 0.03 + power_bonuses[mini(special_power_level, 3)]
	# Size: radius multiplier (+50/100/150%)
	var size_multipliers := [1.0, 1.5, 2.0, 2.5]
	cross.heal_radius = 180.0 * size_multipliers[mini(special_size_level, 3)]
	# A Burning Sensation (+ More, more! / Oooh, Ahhhh)
	if ShopMenuScript.has_character_upgrade("rapunzel", "burning_sensation"):
		cross.burn_enabled = true
		cross.burn_damage_mult = MORE_MORE_MULTS[mini(more_more_level, 3)]
		cross.stun_duration = OOOH_STUNS[mini(oooh_ahhhh_level, 3)]

## Re-apply config to the live Personal Toy aura after a talent purchase.
func _refresh_aura() -> void:
	if is_instance_valid(_personal_aura):
		_configure_blessing(_personal_aura)

func _on_burst_start() -> void:
	var effect = RapunzelBurstEffectScript.new()
	effect.owner_node = player

	# Blinding Radiance: base 4s stun on non-bosses, +2/4/6s per rank. Bosses immune.
	effect.stun_duration = 4.0 + BLINDING_BONUS[mini(burst_stun_level, 3)]
	effect.stun_bosses = false

	# "6,000? Really?" talent: spawn 20 turrets across the map
	effect.spawn_turrets = burst_turrets_unlocked
	effect.turret_owner_level = player.level if "level" in player else 1
	# Turret upgrades: Incendiary Rockets (It Burns ground) + Extra Stuffed ammo
	effect.turret_incendiary_level = incendiary_rockets_level
	effect.turret_extra_ammo = EXTRA_STUFFED_AMMO[mini(extra_stuffed_level, 3)]

	# Anti-Queen Bombardment: a ~1s hold paints a target for every turret rocket.
	if anti_queen_unlocked and _pending_burst_charge >= ANTI_QUEEN_ARM_RATIO:
		effect.use_fixed_target = true
		effect.fixed_target_position = player.get_global_mouse_position()
	_pending_burst_charge = 0.0
	_clear_designator()

	player.get_parent().add_child(effect)
	effect.global_position = player.global_position

	# Lingering Light: begin the post-burst heal-over-time.
	if lingering_light_level > 0:
		_lingering_remaining = LINGERING_DURATIONS[mini(lingering_light_level, 3)]
		_lingering_tick_accum = 0.0

	# Burst is instant for Rapunzel (effect handles duration)
	burst_active = false
	burst_ended.emit()

## Anti-Queen Bombardment uses the shared hold-to-charge burst flow (like Snow
## White's Focused Fire): held burst key accumulates, releases to fire.
func is_burst_charge_enabled() -> bool:
	return anti_queen_unlocked and burst_turrets_unlocked

func set_pending_burst_charge(ratio: float) -> void:
	_pending_burst_charge = clampf(ratio, 0.0, 1.0)

## Drives the laser designator while the burst key is held (called each frame by
## PlayerInputHandler). ratio <= 0 removes it.
func update_burst_charge_visual(ratio: float) -> void:
	if ratio <= 0.0:
		_clear_designator()
		return
	if not is_instance_valid(_designator):
		_designator = RapunzelDesignatorScript.new()
		player.get_parent().add_child(_designator)
	_designator.global_position = player.get_global_mouse_position()
	if _designator.has_method("set_armed"):
		_designator.set_armed(ratio >= ANTI_QUEEN_ARM_RATIO)

func _clear_designator() -> void:
	if is_instance_valid(_designator):
		_designator.queue_free()
	_designator = null

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

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			cross_timer = 0.0 # Refresh cooldown
		"special_power":
			special_power_level = mini(special_power_level + 1, 3)
			cross_timer = 0.0 # Refresh cooldown
			_refresh_aura()
		"special_size":
			special_size_level = mini(special_size_level + 1, 3)
			cross_timer = 0.0 # Refresh cooldown
			_refresh_aura()
		"burning_sensation":
			_refresh_aura()
		"more_more":
			more_more_level = mini(more_more_level + 1, 3)
			_refresh_aura()
		"oooh_ahhhh":
			oooh_ahhhh_level = mini(oooh_ahhhh_level + 1, 3)
			_refresh_aura()
		"personal_toy":
			personal_toy_unlocked = true
		"all_the_toys":
			all_the_toys_unlocked = true
		"burst_stun":
			burst_stun_level = mini(burst_stun_level + 1, 3)
		"burst_turrets":
			burst_turrets_unlocked = true
		"lingering_light":
			lingering_light_level = mini(lingering_light_level + 1, 3)
		"incendiary_rockets":
			incendiary_rockets_level = mini(incendiary_rockets_level + 1, 3)
		"extra_stuffed":
			extra_stuffed_level = mini(extra_stuffed_level + 1, 3)
		"anti_queen":
			anti_queen_unlocked = true
		"goddess_no_yield":
			goddess_no_yield_unlocked = true
		"concussive_blast":
			concussive_level = mini(concussive_level + 1, 3)
		"anti_armor":
			anti_armor_level = mini(anti_armor_level + 1, 3)
		"burning_desire":
			burning_desire_unlocked = true
		"spread_love":
			spread_level = mini(spread_level + 1, 3)
		"it_burns":
			it_burns_level = mini(it_burns_level + 1, 3)
		"endless_desire":
			endless_desire_unlocked = true

## Get special cooldown progress
func get_special_cooldown_progress() -> float:
	if cross_timer <= 0:
		return 1.0
	return 1.0 - (cross_timer / cross_cooldown)
