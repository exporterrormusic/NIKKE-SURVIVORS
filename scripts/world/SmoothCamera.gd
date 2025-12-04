extends Camera2D
class_name SmoothCamera

## Smooth camera - tight follow with subtle lag only during dashes
## Almost locked to player during normal movement

# Follow settings
@export var follow_smoothing: float = 25.0  # Very fast follow (almost instant)
@export var dash_smoothing: float = 8.0  # Slower during dash for dramatic effect

# State
var _target_node: Node2D = null
var _is_dashing: bool = false
var _dash_timer: float = 0.0
const DASH_DURATION := 0.25  # How long the lag effect lasts

func _ready() -> void:
	if get_parent() is Node2D:
		_target_node = get_parent() as Node2D
	
	position_smoothing_enabled = false
	
	if _target_node:
		global_position = _target_node.global_position

func _process(delta: float) -> void:
	if not _target_node:
		return
	
	var target_pos := _target_node.global_position
	
	# Update dash state
	if _dash_timer > 0:
		_dash_timer -= delta
		if _dash_timer <= 0:
			_is_dashing = false
	
	# Choose smoothing based on dash state
	var smoothing := dash_smoothing if _is_dashing else follow_smoothing
	
	# Simple lerp follow
	var t := clampf(smoothing * delta, 0.0, 1.0)
	global_position = global_position.lerp(target_pos, t)

## Call this when player dashes
func notify_dash() -> void:
	_is_dashing = true
	_dash_timer = DASH_DURATION
