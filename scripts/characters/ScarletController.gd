extends "res://scripts/characters/CharacterController.gd"
class_name ScarletController
## Scarlet - Melee fighter with sword attacks and dash abilities

# Shop upgrade reference
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")
const RosePetalScript = preload("res://scripts/characters/effects/RosePetal.gd")

# Scarlet-specific state
var special_ammo: int = 1
var special_max_ammo: int = 1
var special_reloading: bool = false
var special_reload_timer: float = 0.0
var special_reload_time: float = 4.0

var damage_accumulator: float = 0.0  # Tracks fractional self-damage

# Shop upgrade state
var _has_roses_core_upgrade: bool = false

# Talent states
var special_cd_level: int = 0  # Quick Dash: reduces cooldown
var special_heal_level: int = 0
var burst_execute_unlocked: bool = false
var burst_vuln_unlocked: bool = false

# Scripts for effects
const ScarletBurstEffectScript = preload("res://scripts/characters/effects/ScarletBurstEffect.gd")

func _on_initialize() -> void:
	# Scarlet has unlimited basic attacks (melee)
	max_ammo = -1
	ammo = -1
	special_ammo = special_max_ammo
	
	# Check if "Rose's Core" upgrade is purchased
	_has_roses_core_upgrade = ShopMenuScript.has_character_upgrade("scarlet", "basic_attack")

func _on_process(delta: float) -> void:
	# Update special reload
	if special_reloading:
		special_reload_timer -= delta
		if special_reload_timer <= 0:
			special_reloading = false
			special_ammo = special_max_ammo

func _can_attack() -> bool:
	return true  # Scarlet can always attack (melee)

func _perform_attack(direction: Vector2) -> void:
	# Fire sword slash (melee attack attached to player)
	var slash = ProjectileCache.create_slash()
	slash.rotation = direction.angle()
	# Use character's base damage with level scaling
	var damage: int = player.calc_damage()
	slash.base_damage = damage
	player.add_child(slash)  # Attach to player, not parent
	slash.position = Vector2.ZERO  # Centered on player
	
	# Rose's Core upgrade: shoot 5 rose petals from slash tip
	if _has_roses_core_upgrade:
		_spawn_rose_petals(direction, damage)
	
	# Play sword sound
	_play_sound("sword")
	
	# Apply self-damage (3% of max HP per attack)
	_apply_self_damage()

func _spawn_rose_petals(direction: Vector2, damage: int) -> void:
	const PETAL_COUNT := 5
	const SPREAD_ANGLE := PI / 3  # 60 degrees spread total for wider coverage
	const PETAL_SPEED := 1200.0  # Faster to fly further
	const SLASH_TIP_OFFSET := 280.0  # Match slash radius
	
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
		petal.base_damage = maxi(1, int(damage * 0.5))  # Rose petals do half slash damage

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
	
	# Spawn forward piercing wave
	var w = ProjectileCache.create_scarlet_wave()
	w.rotation = direction.angle()
	w.owner_node = player
	w.pierce_all = true
	# Use character's base damage with level scaling (special does 0.8x base damage)
	w.damage = player.calc_damage(0.8)
	w.base_damage = w.damage
	if special_heal_level > 0:
		w.heal_mode = true
		var heal_percents := [0.0, 0.05, 0.15, 0.25]
		w.heal_percent = heal_percents[special_heal_level]
	player.get_parent().add_child(w)
	w.global_position = player.global_position + direction * 36
	w.velocity = direction.normalized() * 2400
	
	_play_sound("sword")
	_apply_self_damage()

func _start_special_reload() -> void:
	special_reloading = true
	special_reload_timer = special_reload_time

func _on_burst_start() -> void:
	# Scarlet burst costs 50% of current HP
	var hp_cost = int(player.hp * 0.5)
	player.hp = max(player.hp - hp_cost, 1)
	player._update_health_display(-hp_cost, true)
	
	# Create burst effect
	var effect = ScarletBurstEffectScript.new()
	effect.owner_node = player
	effect.execute_talent = burst_execute_unlocked
	effect.vuln_talent = burst_vuln_unlocked
	player.get_parent().add_child(effect)
	effect.global_position = player.global_position
	effect.burst_complete.connect(_on_burst_complete)
	
	_play_sound("sword")

func _on_burst_complete(teleport_position: Vector2) -> void:
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

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

## Get weapon type name for audio
func _get_weapon_type_name() -> String:
	return "sword"

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			special_ammo = special_max_ammo  # Refill ammo
			special_reloading = false  # Refresh cooldown
			special_reload_timer = 0.0
		"special_cd":
			special_cd_level = mini(special_cd_level + 1, 3)
			# Reduce cooldown by 1s per level (base 4s, min 1s)
			special_reload_time = maxf(4.0 - special_cd_level, 1.0)
			special_reloading = false  # Refresh cooldown
			special_reload_timer = 0.0
			special_ammo = special_max_ammo  # Refill ammo
		"special_heal":
			special_heal_level = mini(special_heal_level + 1, 3)
			special_reloading = false  # Refresh cooldown
			special_reload_timer = 0.0
			special_ammo = special_max_ammo  # Refill ammo
		"burst_execute":
			burst_execute_unlocked = true
		"burst_vuln":
			burst_vuln_unlocked = true

## Get special cooldown progress
func get_special_cooldown_progress() -> float:
	if special_reloading:
		return 1.0 - (special_reload_timer / special_reload_time)
	return 1.0
