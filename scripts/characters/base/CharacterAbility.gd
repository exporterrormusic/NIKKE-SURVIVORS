extends Node
class_name CharacterAbility
## Base class for character abilities in the composition system.
##
## Abilities are separate nodes attached to a CharacterController.
## This allows modular, reusable abilities that can be mixed and matched.
##
## Subclasses should override:
## - _perform_ability() - Execute the ability logic
## - can_activate() - Check if ability can be used (optional)
##
## Example:
##   extends CharacterAbility
##   
##   func _perform_ability():
##       # Spawn projectile, trigger effect, etc.
##       character.spawn_projectile(...)

## Emitted when ability is successfully activated
signal ability_activated

## Emitted when cooldown starts
signal cooldown_started(duration: float)

## Emitted when ability is ready to use again
signal ability_ready

## Reference to the parent character controller
var character = null  # Untyped to avoid cast issues

## Current cooldown timer (counts down to 0)
var cooldown_timer: float = 0.0

## Display name of the ability
@export var ability_name: String = ""

## Base cooldown duration in seconds
@export var base_cooldown: float = 5.0

## Whether this ability uses ammo instead of cooldown
@export var uses_ammo: bool = false

## If using ammo, the max ammo count
@export var max_ammo: int = 30

## Current ammo (if uses_ammo is true)
var current_ammo: int = 0


func _ready() -> void:
	# Get parent without strict type checking
	character = get_parent()
	if character == null:
		push_error("[CharacterAbility] Must have a parent node")
	
	if uses_ammo:
		current_ammo = max_ammo


func _process(delta: float) -> void:
	# Update cooldown
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			cooldown_timer = 0.0
			ability_ready.emit()


## Attempt to activate the ability
func activate() -> bool:
	if not can_activate():
		return false
	
	_perform_ability()
	_start_cooldown()
	ability_activated.emit()
	return true


## Check if ability can be activated
func can_activate() -> bool:
	# On cooldown
	if cooldown_timer > 0.0:
		return false
	
	# Out of ammo
	if uses_ammo and current_ammo <= 0:
		return false
	
	return true


## Override this in subclass to implement ability logic
func _perform_ability() -> void:
	push_warning("[CharacterAbility] _perform_ability() not implemented for " + ability_name)


## Start the cooldown timer
func _start_cooldown() -> void:
	if uses_ammo:
		current_ammo -= 1
		if current_ammo <= 0:
			# Reload cooldown
			cooldown_timer = base_cooldown
			cooldown_started.emit(base_cooldown)
	else:
		cooldown_timer = base_cooldown
		cooldown_started.emit(base_cooldown)


## Reload ammo (for ammo-based abilities)
func reload() -> void:
	if uses_ammo:
		current_ammo = max_ammo
		cooldown_timer = 0.0
		ability_ready.emit()


##  Get cooldown progress (0.0 = ready, 1.0 = just used)
func get_cooldown_progress() -> float:
	if base_cooldown <= 0.0:
		return 0.0
	return cooldown_timer / base_cooldown


## Get ammo progress (0.0 = empty, 1.0 = full)
func get_ammo_progress() -> float:
	if not uses_ammo or max_ammo <= 0:
		return 1.0
	return float(current_ammo) / float(max_ammo)
