extends Node
class_name MovementComponent

@export var max_speed: float = 150.0
@export var acceleration: float = 800.0
@export var friction: float = 1000.0
@export var rotation_speed: float = 10.0

var _velocity: Vector2 = Vector2.ZERO
var _target_node: Node2D = null

# Dependencies
# Usually attached to CharacterBody2D, but could be Area2D
var _actor: Node2D

# Expose velocity for other components to read
var velocity: Vector2:
	get:
		if owner is CharacterBody2D:
			return owner.velocity
		return Vector2.ZERO

func setup(actor: Node2D) -> void:
	_actor = actor

func _ready() -> void:
	if get_parent() is Node2D:
		_actor = get_parent()

func set_target(target: Node2D) -> void:
	_target_node = target

var paused: bool = false

func set_paused(state: bool) -> void:
	paused = state
	if paused:
		_velocity = Vector2.ZERO
		if _actor is CharacterBody2D:
			_actor.velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	if not _actor or paused:
		return
		
	# Apply Global Enemy Time Scale (Bullet Time)
	var game_manager = get_node_or_null("/root/GameManager")
	var time_scale = game_manager.enemy_time_scale if game_manager else 1.0
	delta *= time_scale
	
	var direction := Vector2.ZERO
	
	# Determine direction based on target
	if _target_node and is_instance_valid(_target_node):
		var dist_sq = _actor.global_position.distance_squared_to(_target_node.global_position)
		if dist_sq > 100.0: # Stop dead zone
			direction = (_target_node.global_position - _actor.global_position).normalized()
	
	# Apply physics
	if direction != Vector2.ZERO:
		var current_max_speed = max_speed * time_scale
		_velocity = _velocity.move_toward(direction * current_max_speed, acceleration * delta)
		# Smooth rotation
		if _actor.has_method("look_at"):
			# Custom rotation smoothing if needed, or direct look_at for turrets
			# For sprites, usually we flip or rotate sprite, not the whole body
			pass
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, friction * delta)
	
	# Move the actor
	if _actor is CharacterBody2D:
		_actor.velocity = _velocity
		_actor.move_and_slide()
	else:
		_actor.global_position += _velocity * delta

func get_velocity() -> Vector2:
	if _actor is CharacterBody2D:
		return _actor.velocity
	return _velocity
