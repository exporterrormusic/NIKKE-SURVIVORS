extends Node
class_name HealthComponent

signal died(overkill: int)
signal health_changed(current: int, max: int)
signal damaged(amount, source)

@export var max_hp: int = 10
var current_hp: int : set = _set_current_hp

var _is_dead: bool = false
var _pending_overkill: int = 0

func _ready() -> void:
	current_hp = max_hp

func _set_current_hp(value: int) -> void:
	var old_hp = current_hp
	current_hp = clamp(value, 0, max_hp)
	if old_hp != current_hp:
		health_changed.emit(current_hp, max_hp)
	
	if current_hp == 0 and not _is_dead:
		die(_pending_overkill)
		_pending_overkill = 0

func set_max_hp(val: int) -> void:
	max_hp = val
	current_hp = min(current_hp, max_hp)

func damage(amount: int, source: String = "unknown") -> void:
	if _is_dead:
		return
		
	var potential_hp = current_hp - amount
	if potential_hp < 0:
		_pending_overkill = -potential_hp
	else:
		_pending_overkill = 0
		
	current_hp -= amount
	damaged.emit(amount, source)

func heal(amount: int) -> void:
	if _is_dead:
		return
		
	current_hp = min(current_hp + amount, max_hp)

func die(overkill: int = 0) -> void:
	if _is_dead:
		return
	_is_dead = true
	current_hp = 0
	died.emit(overkill)
