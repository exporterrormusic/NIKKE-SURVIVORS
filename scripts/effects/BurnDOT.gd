extends Node
class_name BurnDOT
## Damage Over Time component that can be attached to enemies
## Handles refreshing and stacking of burn effects

var damage_percent: float = 0.03  # 3% HP per second for regular enemies
var boss_damage_percent: float = 0.01  # 1% HP per second for bosses
var duration: float = 10.0
var _timer: float = 0.0
var _tick_interval: float = 0.5
var _tick_timer: float = 0.0
var _target: Node2D = null
var _is_boss: bool = false
var _source_id: String = ""  # Identifier for the source (e.g., "snow_white_burn")

func _ready() -> void:
	_timer = duration

func setup(target: Node2D, source_id: String, duration_override: float = -1.0) -> void:
	_target = target
	_source_id = source_id
	_is_boss = target.is_in_group("bosses") or target.is_in_group("elite")
	if duration_override > 0:
		duration = duration_override
	_timer = duration

func refresh() -> void:
	## Refresh the burn duration to full
	_timer = duration

func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return
	
	_timer -= delta
	if _timer <= 0:
		queue_free()
		return
	
	_tick_timer += delta
	if _tick_timer >= _tick_interval:
		_tick_timer = 0.0
		_apply_damage()

func _apply_damage() -> void:
	if not is_instance_valid(_target) or not _target.has_method("take_damage"):
		return
	
	# Get target's max HP if available
	var max_hp: int = 100
	if "max_hp" in _target:
		max_hp = _target.max_hp
	elif _target.has_method("get_max_hp"):
		max_hp = _target.get_max_hp()
	
	# Calculate damage based on whether target is boss
	var percent := boss_damage_percent if _is_boss else damage_percent
	var damage := int(max_hp * percent * _tick_interval)
	damage = maxi(damage, 1)  # At least 1 damage per tick
	
	# Apply damage without crit (burn is consistent damage)
	_target.take_damage(damage, false, Vector2.ZERO, false, "burn_dot")
