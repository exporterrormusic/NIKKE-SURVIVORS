extends Node
class_name PlayerHealth
## Player health management module.
##
## Handles HP, damage, shields, invincibility, and healing.
## Extracted from PlayerCore for better separation of concerns.

signal health_changed(current: int, maximum: int)
signal damage_taken(amount: int, is_crit: bool, direction: Vector2)
signal damage_blocked_by_shield(amount: int)
signal shield_changed(current: int, maximum: int)
signal sin_wish_triggered()
signal cecil_revive_triggered()
signal marian_beam_absorbed()
signal death

var hp: int = 10
var max_hp: int = 10
var invincible: bool = false

# Shield system (Kilo/Cecil Eden upgrade)
var shield_current: int = 0
var shield_max: int = 0

# Upgrade flags
var has_rapunzel_healer: bool = false
var has_cecil_lives: bool = false
var cecil_lives_remaining: int = 0
var has_sin_wish: bool = false
var sin_wish_used: bool = false
var has_marian_beam_absorb: bool = false

# Current character context (for character-specific blocks)
var current_character_id: String = ""

# Invincibility timers
var _invincibility_timer: float = 0.0
var _cecil_revive_invincible_timer: float = 0.0
var _invincibility_duration: float = 0.3 # Brief iframes only


func _process(delta: float) -> void:
	# Update invincibility timers
	var was_invincible = invincible
	
	if _invincibility_timer > 0.0:
		_invincibility_timer -= delta
	
	if _cecil_revive_invincible_timer > 0.0:
		_cecil_revive_invincible_timer -= delta
	
	if _invincibility_timer <= 0.0 and _cecil_revive_invincible_timer <= 0.0:
		invincible = false
	else:
		invincible = true


## Initialize health values
func initialize(starting_hp: int, starting_max_hp: int) -> void:
	hp = starting_hp
	max_hp = starting_max_hp
	health_changed.emit(hp, max_hp)


## Take damage (Enhanced with character logic)
func take_damage(amount: int, is_crit: bool = false, direction: Vector2 = Vector2.ZERO, is_true_damage: bool = false, source: String = "enemy") -> bool:
	if invincible and not is_true_damage:
		return false
		
	# Dev Cheat: Invincibility
	if CheatManager.is_cheat_active("invincible"):
		return false
	
	# Marian "She'll Eat Anything" - absorb boss beam attacks
	if source == "boss_beam" and has_marian_beam_absorb and current_character_id == "marian":
		marian_beam_absorbed.emit()
		return false
	
	var actual_damage = amount
	
	# Shield absorbs damage first
	if shield_current > 0:
		var shield_absorbed = min(shield_current, actual_damage)
		shield_current -= shield_absorbed
		actual_damage -= shield_absorbed
		damage_blocked_by_shield.emit(shield_absorbed)
		shield_changed.emit(shield_current, shield_max)
	
	# Apply remaining damage to HP
	if actual_damage > 0:
		hp -= actual_damage
		damage_taken.emit(actual_damage, is_crit, direction)
		health_changed.emit(hp, max_hp)
		
		# Trigger brief invincibility
		_trigger_invincibility(_invincibility_duration)
	
	# Check for death
	if hp <= 0:
		return _handle_death()
	
	return true


## Explicitly expose access to max_hp for external systems
func get_max_hp() -> int:
	return max_hp


## Heal HP
func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)


## Trigger invincibility
func _trigger_invincibility(duration: float) -> void:
	invincible = true
	_invincibility_timer = maxf(_invincibility_timer, duration)

## Public API to add invincibility
func add_invincibility(duration: float) -> void:
	_trigger_invincibility(duration)


## Handle death (returns false if revived, true if actually dead)
func _handle_death() -> bool:
	# Sin "I WISH They Were Gone" upgrade
	if has_sin_wish and not sin_wish_used:
		sin_wish_used = true
		hp = 1
		health_changed.emit(hp, max_hp)
		sin_wish_triggered.emit()
		return false

	# Cecil "Three Wishes..." upgrade
	if has_cecil_lives and cecil_lives_remaining > 0:
		cecil_lives_remaining -= 1
		hp = max_hp
		shield_current = shield_max
		_cecil_revive_invincible_timer = 5.0
		invincible = true
		health_changed.emit(hp, max_hp)
		shield_changed.emit(shield_current, shield_max)
		cecil_revive_triggered.emit()
		return false
	
	# Actually dead
	death.emit()
	return true


## Add shield
func add_shield(amount: int) -> void:
	if shield_max <= 0:
		return
	shield_current = mini(shield_current + amount, shield_max)
	shield_changed.emit(shield_current, shield_max)


## Configure shield system
func configure_shield(max_shield: int) -> void:
	shield_max = max_shield
	# Don't reset current shield if it's already higher? 
	# Actually, usually called during setup or upgrade.
	shield_current = mini(shield_current, shield_max)
	shield_changed.emit(shield_current, shield_max)


## Configure Cecil lives
func configure_cecil_lives(count: int, max_val: int = -1) -> void:
	has_cecil_lives = true
	cecil_lives_remaining = count


## Enable Sin's Wish
func enable_sin_wish() -> void:
	has_sin_wish = true
	sin_wish_used = false


## Enable Marian Beam Absorb
func enable_marian_beam_absorb() -> void:
	has_marian_beam_absorb = true


## Enable Rapunzel healing
func enable_rapunzel_healing() -> void:
	has_rapunzel_healer = true


## Heal on kill (Rapunzel upgrade)
func on_enemy_killed() -> void:
	if has_rapunzel_healer:
		var heal_amount = int(max_hp * 0.02) # 2% max HP
		heal(heal_amount)
