extends Node
class_name EffectBase
## Base class for visual effects (hit sparks, explosions, floating numbers, etc.)
##
## Provides common functionality:
## - Lifetime management
## - Auto-despawn when animation complete
## - Pool-friendly reset() method
## - EventBus integration
##
## Subclasses should override:
## - _play_effect() - Start the effect animation
## - _effect_ready() - Custom initialization (optional)
##
## Example:
##   extends EffectBase
##   
##   func _play_effect():
##       $AnimationPlayer.play("explosion")
##       await $AnimationPlayer.animation_finished
##       _finish()

## Emitted when effect completes
signal effect_finished

## Lifetime timer
var _lifetime: float = 0.0

## Max lifetime before auto-despawn (0 = wait for manual finish)
@export var max_lifetime: float = 2.0

## Whether effect has finished
var _finished: bool = false

## Pool ID (for object pooling systems)
var pool_id: String = ""


func _ready() -> void:
	_effect_ready()
	_play_effect()


func _process(delta: float) -> void:
	if _finished:
		return
	
	_lifetime += delta
	
	if max_lifetime > 0.0 and _lifetime >= max_lifetime:
		_finish()


## Override for custom initialization
func _effect_ready() -> void:
	pass


## Override to play the effect animation
func _play_effect() -> void:
	push_warning("[EffectBase] _play_effect() not implemented")
	call_deferred("_finish")


## Call this when effect animation is complete
func _finish() -> void:
	if _finished:
		return
	
	_finished = true
	effect_finished.emit()
	
	# Return to pool or queue_free
	if pool_id != "":
		_return_to_pool()
	else:
		queue_free()


## Reset for object pooling
func reset() -> void:
	_lifetime = 0.0
	_finished = false
	pool_id = ""


## Return to pool (override if using custom pooling)
func _return_to_pool() -> void:
	# Default: just queue_free
	# Subclasses can override to return to specific pools
	queue_free()


## Spawn helper - creates effect at position
static func spawn_at(effect_scene: PackedScene, parent: Node, pos: Vector2) -> EffectBase:
	var effect = effect_scene.instantiate() as EffectBase
	if effect:
		parent.add_child(effect)
		if effect is Node2D:
			effect.global_position = pos
	return effect
