extends Node
class_name PlayerHealth
## Player health management module.
##
## Handles HP, damage, shields, invincibility, and healing.
## Extracted from PlayerCore for better separation of concerns.

signal health_changed(current: int, maximum: int)
signal damage_taken(amount: int)
signal death
signal shield_changed(current: int, maximum: int)

var hp: int = 10
var max_hp: int = 10
var invincible: bool = false

# Shield system (Kilo upgrade)
var shield_current: int = 0
var shield_max: int = 0
var shield_visual: Node2D = null

# Rapunzel healing upgrade
var has_rapunzel_healer: bool = false

# Cecil extra lives
var has_cecil_lives: bool = false
var cecil_lives_remaining: int = 0
var cecil_revive_invincible_timer: float = 0.0

# Invincibility timers
var _invincibility_timer: float = 0.0
var _invincibility_duration: float = 1.5


func _process(delta: float) -> void:
	# Update invincibility timers
	if _invincibility_timer > 0.0:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			invincible = false
	
	# Cecil revive invincibility
	if cecil_revive_invincible_timer > 0.0:
		cecil_revive_invincible_timer -= delta
		if cecil_revive_invincible_timer <= 0.0:
			invincible = false


## Initialize health values
func initialize(starting_hp: int, starting_max_hp: int) -> void:
	hp = starting_hp
	max_hp = starting_max_hp
	health_changed.emit(hp, max_hp)


## Take damage
func take_damage(amount: int, source: String = "enemy") -> bool:
	if invincible:
		return false
	
	var actual_damage = amount
	
	# Shield absorbs damage first
	if shield_current > 0:
		var shield_absorbed = min(shield_current, actual_damage)
		shield_current -= shield_absorbed
		actual_damage -= shield_absorbed
		shield_changed.emit(shield_current, shield_max)
	
	# Apply remaining damage to HP
	if actual_damage > 0:
		hp -= actual_damage
		damage_taken.emit(actual_damage)
		health_changed.emit(hp, max_hp)
		
		# Trigger brief invincibility
		_trigger_invincibility(_invincibility_duration)
	
	# Check for death
	if hp <= 0:
		return _handle_death()
	
	return true


## Heal HP
func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)


## Trigger invincibility
func _trigger_invincibility(duration: float) -> void:
	invincible = true
	_invincibility_timer = duration


## Handle death (returns false if revived, true if actually dead)
func _handle_death() -> bool:
	# Check for Cecil extra lives
	if has_cecil_lives and cecil_lives_remaining > 0:
		cecil_lives_remaining -= 1
		hp = max_hp
		shield_current = shield_max
		cecil_revive_invincible_timer = 5.0
		invincible = true
		health_changed.emit(hp, max_hp)
		shield_changed.emit(shield_current, shield_max)
		print("[PlayerHealth] Revived with Cecil's extra life! Lives remaining: ", cecil_lives_remaining)
		return false
	
	# Actually dead
	death.emit()
	return true


## Add shield (Kilo upgrade)
func add_shield(amount: int) -> void:
	if shield_max <= 0:
		return
	shield_current = mini(shield_current + amount, shield_max)
	shield_changed.emit(shield_current, shield_max)


## Configure shield system
func configure_shield(max_shield: int) -> void:
	shield_max = max_shield
	shield_current = 0
	shield_changed.emit(shield_current, shield_max)


## Configure Cecil lives
func configure_cecil_lives(count: int) -> void:
	has_cecil_lives = true
	cecil_lives_remaining = count


## Enable Rapunzel healing
func enable_rapunzel_healing() -> void:
	has_rapunzel_healer = true


## Heal on kill (Rapunzel upgrade)
func on_enemy_killed() -> void:
	if has_rapunzel_healer:
		var heal_amount = int(max_hp * 0.02)  # 2% max HP
		heal(heal_amount)
