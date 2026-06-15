extends "res://scripts/characters/CharacterController.gd"
class_name ScarletController
## Scarlet - Melee fighter with sword attacks and dash abilities

# Shop upgrade reference

const RosePetalScript = preload("res://scripts/characters/effects/RosePetal.gd")

# Scarlet-specific state
var special_ammo: int = 1
var special_max_ammo: int = 1
var special_reloading: bool = false
var special_reload_timer: float = 0.0
var special_reload_time: float = 5.0

var damage_accumulator: float = 0.0 # Tracks fractional self-damage

# Shop upgrade state
var _has_roses_core_upgrade: bool = false
var _has_low_hp_upgrade: bool = false

# Talent states
var special_cd_level: int = 0 # Quick Dash: reduces cooldown
var special_heal_level: int = 0

# Burst-tree talent state
var execute_level: int = 0            # Execution: 33/66/100% instakill chance on regulars
var drink_to_victory_level: int = 0   # Drink to Victory: heal 5/10/15% max HP per burst kill
var expose_weakness_level: int = 0    # Expose Weakness: 2x/4x/6x permanent damage_vulnerability
var fire_in_my_veins_level: int = 0   # Fire In My Veins: 33/66/100% chance per kill to refund gauge
var d1_crashout_unlocked: bool = false
var goddess_no_yield_unlocked: bool = false
var _burst_low_hp_mult: float = 1.0   # snapshot of the low-HP multiplier at burst trigger

# Attack-tree talent state
var dodge_level: int = 0                  # 0-3: dash invincibility + 0/0.5/1s after the dash
var eviscerate_level: int = 0             # 0-3: bleed 3x/5x/7x attack damage over 5s
var parry_unlocked: bool = false          # slash deflects enemy bullets instead of destroying them
var evasion_level: int = 0                # 0-3: invincible 0.5/1/1.5s after a parry deflect
var retaliation_level: int = 0            # 0-3: deflected bullets deal x5/x10/x15 damage
var i_am_cheating_unlocked: bool = false  # successive melee hits on the same enemy double in damage

const EVISCERATE_MULTS := [3.0, 5.0, 7.0]
const EVASION_DURATIONS := [0.5, 1.0, 1.5]
const DODGE_AFTER := [0.0, 0.5, 1.0]
const RETALIATION_MULTS := [5.0, 10.0, 15.0]

var _evasion_effect: Node = null # active ScarletEvasionEffect (scanline), if any

# Skill-tree talent state
var nothing_personal_unlocked: bool = false # 2nd skill press teleports to the wave + AOE
var aoe_damage_level: int = 0               # 0-3: teleport AOE damage x2/x4/x6 (on top of 3x base)
var surprise_level: int = 0                 # 0-3: AOE survivors stunned 1/2/3s
var musashi_unlocked: bool = false          # hold the skill to charge a bigger/stronger wave
var in_one_strike_unlocked: bool = false    # wave kills explode

const TELEPORT_AOE_BASE_MULT := 3.0         # base teleport AOE = 3x skill damage
const AOE_UPGRADE_MULTS := [1.0, 2.0, 4.0, 6.0] # No Hard Feelings, indexed by level (0=none)
const SURPRISE_STUNS := [0.0, 1.0, 2.0, 3.0]    # Surprise stun seconds, indexed by level
const TELEPORT_AOE_RADIUS := 200.0          # damage area; the purple blast visual is ~1.5x this
const IN_ONE_STRIKE_RADIUS := 360.0         # 2x the turret Detonation size (180)
const MUSASHI_MAX_MULT := 3.0               # full charge => 3x size & damage

var _active_wave: Node = null               # the live Dash Slash wave (for the teleport)
var pending_special_charge: float = 0.0     # 0..1 Musashi charge set by PlayerInputHandler
var _special_charge_effect: Node = null     # pale-purple charge orb, if charging

# Scripts for effects
const ScarletBurstEffectScript = preload("res://scripts/characters/effects/ScarletBurstEffect.gd")
const ScarletEvasionEffectScript = preload("res://scripts/characters/effects/ScarletEvasionEffect.gd")
const ScarletTeleportStrikeScript = preload("res://scripts/characters/effects/ScarletTeleportStrike.gd")
const ScarletWaveChargeEffectScript = preload("res://scripts/characters/effects/ScarletWaveChargeEffect.gd")

func _on_initialize() -> void:
	# Scarlet has unlimited basic attacks (melee)
	max_ammo = -1
	ammo = -1
	special_ammo = special_max_ammo
	
	# Check if "Rose's Core" talent is owned (rose-petal attack augment)
	_has_roses_core_upgrade = has_upgrade("scarlet", "roses_core")
	# Check if "Scraping the Bottle" upgrade is purchased
	_has_low_hp_upgrade = has_upgrade("scarlet", "low_hp_damage")

	# Pre-compile the Evasion phase shader so the first Dodge/parry never hitches.
	call_deferred("_warm_evasion_shader")


func _warm_evasion_shader() -> void:
	if is_instance_valid(player):
		ScarletEvasionEffectScript.warm(player)

func _on_process(delta: float) -> void:
	# Update special reload
	if special_reloading:
		special_reload_timer -= delta
		if special_reload_timer <= 0:
			special_reloading = false
			special_ammo = special_max_ammo

func _can_attack() -> bool:
	return true # Scarlet can always attack (melee)

func _perform_attack(direction: Vector2) -> void:
	# Fire sword slash (melee attack attached to player)
	var slash = ProjectileCache.create_slash()
	slash.rotation = direction.angle()
	# Use character's base damage with level scaling
	# Use character's base damage with level scaling
	var damage: int = int(float(player.calc_damage()) * get_low_hp_damage_multiplier())
	slash.base_damage = damage
	# Hand over Scarlet's attack-tree talent payloads (Parry/Retaliation/Eviscerate/I am cheating).
	slash.parry_enabled = parry_unlocked
	slash.deflect_damage_mult = RETALIATION_MULTS[retaliation_level - 1] if retaliation_level > 0 else 1.0
	slash.eviscerate_total = float(damage) * EVISCERATE_MULTS[eviscerate_level - 1] if eviscerate_level > 0 else 0.0
	slash.i_am_cheating_enabled = i_am_cheating_unlocked
	slash.scarlet_controller = self
	player.add_child(slash) # Attach to player, not parent
	slash.position = Vector2.ZERO # Centered on player
	
	# Rose's Core upgrade: shoot 5 rose petals from slash tip
	if _has_roses_core_upgrade:
		_spawn_rose_petals(direction, damage)
	
	# Play sword sound
	_play_sound("sword")
	
	# Apply self-damage (3% of max HP per attack)
	_apply_self_damage()

func _spawn_rose_petals(direction: Vector2, damage: int) -> void:
	const PETAL_COUNT := 5
	const SPREAD_ANGLE := PI / 6 # 30 degrees: tight enough that the aimed target is reliably covered
	const PETAL_SPEED := 1200.0 # Faster to fly further
	const SLASH_TIP_OFFSET := 60.0 # Spawn near Scarlet so close targets are also hit (not 280px past them)
	
	var base_angle: float = direction.angle()
	var start_angle: float = base_angle - SPREAD_ANGLE / 2
	var angle_step: float = SPREAD_ANGLE / (PETAL_COUNT - 1) if PETAL_COUNT > 1 else 0.0
	
	var spawn_pos: Vector2 = player.global_position + direction * SLASH_TIP_OFFSET
	
	for i in range(PETAL_COUNT):
		var angle: float = start_angle + angle_step * i
		var petal_dir: Vector2 = Vector2.from_angle(angle)
		
		var petal = RosePetalScript.new()
		player.get_parent().add_child(petal)
		petal.global_position = spawn_pos
		petal.velocity = petal_dir * PETAL_SPEED
		petal.rotation = angle
		petal.owner_node = player
		petal.base_damage = maxi(1, int(damage * 0.5)) # Rose petals do half slash damage

func _can_use_special() -> bool:
	return special_ammo > 0 and not special_reloading

## Override use_special to bypass base class special_ready check
## Scarlet uses her own ammo/reload system instead
func use_special(direction: Vector2) -> bool:
	if not special_unlocked:
		return false
	if not _can_use_special():
		return false
	
	_perform_special(direction)
	return true

func _perform_special(direction: Vector2) -> void:
	# Consume special ammo
	special_ammo -= 1
	_start_special_reload()

	# Spawn forward piercing wave (special does 0.8x base damage)
	var w = ProjectileCache.create_scarlet_wave()
	w.rotation = direction.angle()
	w.owner_node = player
	w.pierce_all = true
	w.damage = _skill_base_damage()
	w.base_damage = w.damage

	# Musashi: a charged hold grows the wave (up to 3x size) and damage (up to 3x).
	var charge: float = clampf(pending_special_charge, 0.0, 1.0)
	pending_special_charge = 0.0
	if musashi_unlocked and charge > 0.0:
		var mult: float = 1.0 + (MUSASHI_MAX_MULT - 1.0) * charge
		w.damage = int(w.damage * mult)
		w.base_damage = w.damage
		w.scale *= mult
	_clear_special_charge_visual()

	if special_heal_level > 0:
		w.heal_mode = true
		var heal_percents := [0.0, 0.05, 0.10, 0.15]
		w.heal_percent = heal_percents[special_heal_level]

	# In One Strike: enemies killed by the wave explode for the skill's damage.
	if in_one_strike_unlocked:
		w.in_one_strike = true
		w.in_one_strike_radius = IN_ONE_STRIKE_RADIUS
		w.in_one_strike_damage = w.base_damage
		w.in_one_strike_owner = player

	player.get_parent().add_child(w)
	w.global_position = player.global_position + direction * 36
	w.velocity = direction.normalized() * 1200

	# Track the live wave for the "Nothing Personal, Kid" teleport.
	_active_wave = w

	_play_sound("sword")
	_apply_self_damage()


## Nominal Dash Slash damage (0.8x attack, low-HP scaled). Used for the wave and
## as the 1x base for the teleport AOE; deliberately independent of Musashi charge.
func _skill_base_damage() -> int:
	return int(float(player.calc_damage(0.8)) * get_low_hp_damage_multiplier())

func _start_special_reload() -> void:
	special_reloading = true
	special_reload_timer = special_reload_time

func _on_burst_start() -> void:
	# Scarlet burst costs 50% of current HP
	var hp_cost = int(player.hp * 0.5)
	player.hp = max(player.hp - hp_cost, 1)
	player._update_health_display(-hp_cost, true)
	
	# Manually enable invincibility during the burst sequence
	# The burst effect will take time to complete (0.2s per enemy)
	player.invincible = true

	# Scraping the Bottle: snapshot the low-HP multiplier NOW (after the 50% cost)
	# so Drink to Victory healing during the burst can't reduce the burst's damage.
	_burst_low_hp_mult = get_low_hp_damage_multiplier()

	# Create burst effect
	var effect = ScarletBurstEffectScript.new()
	effect.owner_node = player
	effect.execute_level = execute_level
	effect.expose_weakness_level = expose_weakness_level
	effect.drink_to_victory_level = drink_to_victory_level
	effect.fire_in_my_veins_level = fire_in_my_veins_level
	effect.gauge_per_kill = BurstConfig.get_rate(data.weapon_kind) if data else 0.0
	effect.low_hp_mult = _burst_low_hp_mult
	effect.d1_crashout = d1_crashout_unlocked
	player.get_parent().add_child(effect)
	effect.global_position = player.global_position
	effect.burst_complete.connect(_on_burst_complete)
	
	_play_sound("sword")

func _on_burst_complete(teleport_position: Vector2) -> void:
	# Disable manual invincibility
	player.invincible = false
	
	# Grant 1 second of post-burst safety
	if player.has_method("add_invincibility"):
		player.add_invincibility(1.0)
	
	if teleport_position != Vector2.ZERO:
		player.global_position = teleport_position
	burst_active = false
	burst_ended.emit()

func _apply_self_damage() -> void:
	# 3% of max HP per attack (accumulate fractions)
	var damage_raw: float = player.max_hp * 0.03
	damage_accumulator += damage_raw
	
	if damage_accumulator >= 1.0:
		var int_damage: int = int(damage_accumulator)
		damage_accumulator -= int_damage
		
		# Never reduce HP below 1
		var old_hp: int = player.hp
		player.hp = max(player.hp - int_damage, 1)
		var actual_damage: int = old_hp - player.hp
		
		if actual_damage > 0:
			player._update_health_display(-actual_damage, true)

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			special_ammo = special_max_ammo # Refill ammo
			special_reloading = false # Refresh cooldown
			special_reload_timer = 0.0
		"special_cd":
			special_cd_level = mini(special_cd_level + 1, 3)
			# Reduce cooldown by 1s per level (base 5s, min 2s)
			special_reload_time = maxf(5.0 - special_cd_level, 2.0)
			special_reloading = false # Refresh cooldown
			special_reload_timer = 0.0
			special_ammo = special_max_ammo # Refill ammo
		"special_heal":
			special_heal_level = mini(special_heal_level + 1, 3)
			special_reloading = false # Refresh cooldown
			special_reload_timer = 0.0
			special_ammo = special_max_ammo # Refill ammo
		# --- BURST tree ---
		"burst_execute":
			execute_level = mini(execute_level + 1, 3)
		"drink_to_victory":
			drink_to_victory_level = mini(drink_to_victory_level + 1, 3)
		"expose_weakness":
			expose_weakness_level = mini(expose_weakness_level + 1, 3)
		"fire_in_my_veins":
			fire_in_my_veins_level = mini(fire_in_my_veins_level + 1, 3)
		"d1_crashout":
			d1_crashout_unlocked = true
		"goddess_no_yield":
			goddess_no_yield_unlocked = true
		# --- ATTACK tree ---
		"dodge":
			dodge_level = mini(dodge_level + 1, 3)
		"eviscerate":
			eviscerate_level = mini(eviscerate_level + 1, 3)
		"parry":
			parry_unlocked = true
		"evasion":
			evasion_level = mini(evasion_level + 1, 3)
		"retaliation":
			retaliation_level = mini(retaliation_level + 1, 3)
		"roses_core":
			_has_roses_core_upgrade = true
		"i_am_cheating":
			i_am_cheating_unlocked = true
		# --- SKILL tree ---
		"nothing_personal":
			nothing_personal_unlocked = true
		"no_hard_feelings":
			aoe_damage_level = mini(aoe_damage_level + 1, 3)
		"surprise":
			surprise_level = mini(surprise_level + 1, 3)
		"musashi":
			musashi_unlocked = true
		"in_one_strike":
			in_one_strike_unlocked = true


# ============= SKILL-TREE TALENT HOOKS (Nothing Personal / Musashi) =============

## True while the Dash Slash wave is live AND the teleport talent is owned.
func has_active_wave() -> bool:
	return nothing_personal_unlocked and is_instance_valid(_active_wave) and _active_wave.is_inside_tree()


## Nothing Personal, Kid: vanish, reappear at the wave, and strike for an AOE.
## The wave is consumed; the teleport itself is free (cooldown already running).
func do_teleport() -> void:
	if not is_instance_valid(_active_wave):
		_active_wave = null
		return
	var pos: Vector2 = _active_wave.global_position
	_active_wave.queue_free()
	_active_wave = null

	if is_instance_valid(player):
		player.global_position = pos

	# AOE = base 3x skill damage, multiplied by No Hard Feelings (x2/x4/x6).
	var aoe_damage: int = int(_skill_base_damage() * TELEPORT_AOE_BASE_MULT * AOE_UPGRADE_MULTS[aoe_damage_level])
	var strike = ScarletTeleportStrikeScript.new()
	strike.damage = aoe_damage
	strike.radius = TELEPORT_AOE_RADIUS
	strike.stun_duration = SURPRISE_STUNS[surprise_level] # Surprise
	strike.owner_node = player
	player.get_parent().add_child(strike)
	strike.global_position = pos

	_play_sound("sword")


## Musashi: holding the skill button charges a bigger wave (PlayerInputHandler).
func is_special_charge_enabled() -> bool:
	return musashi_unlocked


## Charging only starts when the skill is actually ready (off cooldown).
func is_special_ready() -> bool:
	return _can_use_special()


func set_pending_special_charge(ratio: float) -> void:
	pending_special_charge = clampf(ratio, 0.0, 1.0)


## Show/update the pale-purple charge orb (ratio 0..1). ratio <= 0 removes it.
func update_special_charge_visual(ratio: float) -> void:
	if ratio <= 0.0:
		_clear_special_charge_visual()
		return
	if _special_charge_effect == null or not is_instance_valid(_special_charge_effect):
		_special_charge_effect = ScarletWaveChargeEffectScript.new()
		player.add_child(_special_charge_effect)
	_special_charge_effect.position = player.aim_direction * 60.0
	_special_charge_effect.set_ratio(ratio)


func _clear_special_charge_visual() -> void:
	if _special_charge_effect and is_instance_valid(_special_charge_effect):
		_special_charge_effect.queue_free()
	_special_charge_effect = null


# ============= ATTACK-TREE TALENT HOOKS =============

## Dodge: dashing grants invincibility (during the dash, plus 0/0.5/1s after).
## Called by PlayerCore when a dash begins. Since the dash has a fixed duration,
## granting (dash_duration + after) up front covers the whole window.
func on_dash_started() -> void:
	if dodge_level <= 0:
		return
	var after: float = DODGE_AFTER[dodge_level - 1]
	var dash_dur := 0.3
	if player and player.get("_movement"):
		dash_dur = player._movement.dash_duration
	_grant_evasion_invuln(dash_dur + after)

## Evasion: deflecting a bullet with Parry grants invincibility. Called by Slash
## on a successful deflect.
func on_parry_deflect() -> void:
	if evasion_level <= 0:
		return
	_grant_evasion_invuln(EVASION_DURATIONS[evasion_level - 1])

## Grant `duration` seconds of invincibility and show the slanted red scanline.
func _grant_evasion_invuln(duration: float) -> void:
	if duration <= 0.0 or not is_instance_valid(player):
		return
	# Full invincibility so she also ignores enemy CONTACT damage while dodging
	# (the normal i-frame lets contact/collision damage through by design).
	if player.has_method("add_full_invincibility"):
		player.add_full_invincibility(duration)
	elif player.has_method("add_invincibility"):
		player.add_invincibility(duration)
	_apply_evasion_scanline(duration)

func _apply_evasion_scanline(duration: float) -> void:
	var sprite: CanvasItem = player.get_node_or_null("Sprite2D")
	if sprite == null:
		sprite = player.get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	if _evasion_effect == null or not is_instance_valid(_evasion_effect):
		_evasion_effect = ScarletEvasionEffectScript.new()
		player.add_child(_evasion_effect)
		_evasion_effect.setup(sprite)
	_evasion_effect.refresh(duration)


## Get special cooldown progress
func get_special_cooldown_progress() -> float:
	if special_reloading:
		return 1.0 - (special_reload_timer / special_reload_time)
	return 1.0

func get_low_hp_damage_multiplier() -> float:
	## Returns damage multiplier based on missing HP if upgrade is unlocked
	## 1.0 (no bonus) at 100% HP -> 2.0 (+100% bonus) at <= 15% HP
	if not _has_low_hp_upgrade:
		return 1.0
	
	if player.max_hp <= 0:
		return 1.0
		
	var hp_pct: float = float(player.hp) / float(player.max_hp)
	
	# If HP > 100% (somehow), no bonus
	if hp_pct >= 1.0:
		return 1.0
	
	# If HP <= 15%, max bonus (+500% = x6.0)
	if hp_pct <= 0.15:
		return 6.0

	# Linear scaling between 15% and 100% HP. bonus_fraction goes 0 -> 1 as HP
	# drops 100% -> 15%; the bonus itself scales up to +500%.
	var bonus: float = (1.0 - hp_pct) / 0.85
	return 1.0 + bonus * 5.0


## A GODDESS WHO CANNOT YIELD: fraction of the burst gauge consumed on use.
## Mirrors Snow White exactly (read by PlayerCore._attempt_burst_activation).
func get_burst_consume_fraction() -> float:
	if not goddess_no_yield_unlocked:
		return 1.0
	var r := randf()
	if r < 0.25:
		return 0.0 # consume nothing - gauge stays full
	elif r < 0.5:
		return 0.5 # consume half
	return 1.0     # consume all
