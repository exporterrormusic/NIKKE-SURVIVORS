extends Node
class_name PlayerMovement
## Player movement and dash system module.
##
## Handles movement input, velocity, dashing, and stamina.
## Extracted from PlayerCore for better separation of concerns.

signal dash_started
signal dash_ended
signal stamina_changed(current: float, maximum: float)

@export var speed: float = 400.0
@export var dash_speed: float = 800.0
@export var dash_duration: float = 0.3
@export var acceleration: float = 6000.0
@export var friction: float = 5000.0
@export var dash_stamina_cost: float = 20.0
@export var running_speed_multiplier: float = 1.5
@export var running_stamina_drain: float = 20.0
@export var stamina_regen: float = 30.0

var stamina: float = 100.0
var max_stamina: float = 100.0

# Movement state
var dashing: bool = false
var running: bool = false
var wants_running: bool = false
var dash_direction: Vector2 = Vector2.ZERO
var dash_timer: float = 0.0

# For the character body
var _character_body: CharacterBody2D = null


func _ready() -> void:
	_character_body = get_parent() as CharacterBody2D


func _process(delta: float) -> void:
	_update_dash(delta)
	_update_stamina(delta)


## Update dash timer
func _update_dash(delta: float) -> void:
	if dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			end_dash()


## Update stamina regen/drain
func _update_stamina(delta: float) -> void:
	if running and stamina > 0.0:
		stamina -= running_stamina_drain * delta
		if stamina < 0.0:
			stamina = 0.0
			running = false
			wants_running = false
	else:
		stamina += stamina_regen * delta
		if stamina > max_stamina:
			stamina = max_stamina
	
	stamina_changed.emit(stamina, max_stamina)


## Handle movement input and physics
func handle_movement(delta: float, input_direction: Vector2) -> void:
	if not _character_body:
		return
	
	if dashing:
		# Dash movement
		_character_body.velocity = dash_direction * dash_speed
	else:
		# Normal movement
		var effective_speed = speed
		if running:
			effective_speed *= running_speed_multiplier
		
		if input_direction.length() > 0.0:
			# Accelerate
			_character_body.velocity = _character_body.velocity.move_toward(
				input_direction.normalized() * effective_speed,
				acceleration * delta
			)
		else:
			# Apply friction
			_character_body.velocity = _character_body.velocity.move_toward(
				Vector2.ZERO,
				friction * delta
			)
	
	_character_body.move_and_slide()


## Attempt to start a dash
func try_dash(direction: Vector2) -> bool:
	if dashing:
		return false
	
	if stamina < dash_stamina_cost:
		return false
	
	if direction.length() < 0.1:
		return false
	
	start_dash(direction)
	return true


## Start dashing
func start_dash(direction: Vector2) -> void:
	dashing = true
	dash_direction = direction.normalized()
	dash_timer = dash_duration
	stamina -= dash_stamina_cost
	stamina_changed.emit(stamina, max_stamina)
	dash_started.emit()


## End dash
func end_dash() -> void:
	dashing = false
	dash_timer = 0.0
	dash_ended.emit()


## Toggle running
func set_running(is_running: bool) -> void:
	wants_running = is_running
	if is_running and stamina > 0.0:
		running = true
	else:
		running = false


## Get current velocity
func get_velocity() -> Vector2:
	return _character_body.velocity if _character_body else Vector2.ZERO


## Set velocity (for external forces like knockback)
func set_velocity(new_velocity: Vector2) -> void:
	if _character_body:
		_character_body.velocity = new_velocity
