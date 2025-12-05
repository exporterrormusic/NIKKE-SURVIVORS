class_name CharacterController
extends RefCounted
## Base class for character-specific combat logic.
## Each character extends this and implements their unique attack, special, and burst.

# Reference to the player node
var player: Node2D = null

# Character data resource
var data: Resource = null  # CharacterData

# State tracking
var ammo: int = -1
var max_ammo: int = -1
var is_reloading: bool = false
var reload_timer: float = 0.0

var special_unlocked: bool = false  # Must be unlocked via talent
var special_timer: float = 0.0
var special_ready: bool = true

var burst_active: bool = false
var burst_timer: float = 0.0

var attack_timer: float = 0.0

# Signals that the player should connect to
signal ammo_changed(current: int, maximum: int)
signal reload_started(duration: float)
signal reload_finished()
signal special_cooldown_changed(progress: float)
signal burst_activated()
signal burst_ended()

## Initialize the controller with player reference and character data
func initialize(p_player: Node2D, p_data: Resource) -> void:  # CharacterData
	player = p_player
	data = p_data
	
	# Initialize ammo
	max_ammo = data.ammo_capacity
	ammo = max_ammo
	
	# Reset timers
	attack_timer = 0.0
	special_timer = 0.0
	reload_timer = 0.0
	burst_timer = 0.0
	
	# Character-specific initialization
	_on_initialize()

## Called when controller is initialized - override for custom setup
func _on_initialize() -> void:
	pass

## Called when controller is being destroyed - override to clean up resources
func cleanup() -> void:
	_on_cleanup()

## Override for custom cleanup
func _on_cleanup() -> void:
	pass

## Process frame update - call from Player._physics_process
func process(delta: float) -> void:
	# Update attack cooldown
	if attack_timer > 0:
		attack_timer -= delta
	
	# Update special cooldown
	if special_timer > 0:
		special_timer -= delta
		special_cooldown_changed.emit(1.0 - (special_timer / data.special_cooldown))
		if special_timer <= 0:
			special_timer = 0
			special_ready = true
			special_cooldown_changed.emit(1.0)
	
	# Update reload
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0:
			_finish_reload()
	
	# Update burst
	if burst_active:
		burst_timer -= delta
		if burst_timer <= 0:
			_end_burst()
	
	# Character-specific processing
	_on_process(delta)

## Called every frame - override for custom processing
func _on_process(_delta: float) -> void:
	pass

## Attempt to attack - returns true if attack was performed
func attack(direction: Vector2) -> bool:
	if attack_timer > 0:
		return false
	
	if not _can_attack():
		return false
	
	# Consume ammo if applicable
	if max_ammo > 0 and not burst_active:
		ammo -= 1
		ammo_changed.emit(ammo, max_ammo)
		
		if ammo <= 0:
			start_reload()
	
	attack_timer = data.attack_cooldown
	
	# Perform the attack
	_perform_attack(direction)
	return true

## Check if can attack - override to add conditions
func _can_attack() -> bool:
	if is_reloading:
		return false
	if max_ammo > 0 and ammo <= 0:
		return false
	return true

## Perform the actual attack - MUST override
func _perform_attack(_direction: Vector2) -> void:
	push_error("CharacterController._perform_attack not implemented!")

## Attempt to use special attack - returns true if used
func use_special(direction: Vector2) -> bool:
	if not special_unlocked:
		return false
	if not special_ready:
		return false
	
	if not _can_use_special():
		return false
	
	special_ready = false
	special_timer = data.special_cooldown
	special_cooldown_changed.emit(0.0)
	
	_perform_special(direction)
	return true

## Check if can use special - override to add conditions
func _can_use_special() -> bool:
	return true

## Perform the special attack - MUST override
func _perform_special(_direction: Vector2) -> void:
	push_error("CharacterController._perform_special not implemented!")

## Start reloading
func start_reload() -> void:
	if is_reloading or max_ammo <= 0:
		return
	if ammo >= max_ammo:
		return
	
	is_reloading = true
	reload_timer = data.reload_time
	reload_started.emit(data.reload_time)
	
	# Play reload sound
	if player and player.audio_director:
		var weapon_type := _get_weapon_type_name()
		player.audio_director.play_weapon_reload_sound(weapon_type)

## Manual reload triggered by player (R key)
func manual_reload() -> void:
	if is_reloading or max_ammo <= 0:
		return
	if ammo >= max_ammo:
		return
	
	start_reload()

## Get weapon type name for audio
func _get_weapon_type_name() -> String:
	# Override in subclasses for specific weapon types
	return "sniper"  # Default

## Finish reloading
func _finish_reload() -> void:
	is_reloading = false
	ammo = max_ammo
	reload_finished.emit()
	ammo_changed.emit(ammo, max_ammo)

## Activate burst ability
func activate_burst() -> bool:
	if burst_active:
		return false
	
	burst_active = true
	burst_timer = data.burst_duration
	
	_on_burst_start()
	burst_activated.emit()
	return true

## End burst ability
func _end_burst() -> void:
	burst_active = false
	burst_timer = 0.0
	
	_on_burst_end()
	burst_ended.emit()

## Called when burst starts - override for custom behavior
func _on_burst_start() -> void:
	pass

## Called when burst ends - override for custom behavior
func _on_burst_end() -> void:
	pass

## Get the damage multiplier (including burst bonus)
func get_damage_multiplier() -> float:
	if burst_active:
		return data.burst_damage_multiplier
	return 1.0

## Check if the character is invincible (e.g., during burst)
func is_invincible() -> bool:
	return false  # Override in subclasses

## Get reload progress (0.0 to 1.0)
func get_reload_progress() -> float:
	if not is_reloading:
		return 1.0
	return 1.0 - (reload_timer / data.reload_time)

## Get special cooldown progress (0.0 to 1.0)
func get_special_progress() -> float:
	if special_ready:
		return 1.0
	return 1.0 - (special_timer / data.special_cooldown)
