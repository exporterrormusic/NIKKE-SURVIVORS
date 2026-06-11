# Shared burn damage-over-time effect (extracted from embedded sources in
# KiloPellet.gd and SnowWhiteBurstBeam.gd; identical except damage_source).
extends Node

var damage_per_second: int = 0
var duration: float = 3.0
var owner_node: Node = null
var damage_source: String = "burn"
var _timer: float = 0.0
var _tick_timer: float = 0.0
const TICK_INTERVAL := 0.5

func _process(delta: float) -> void:
	_timer += delta
	_tick_timer += delta

	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_apply_tick()

	if _timer >= duration:
		queue_free()

func _apply_tick() -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		queue_free()
		return

	var tick_damage := int(damage_per_second * TICK_INTERVAL)
	if tick_damage <= 0:
		return

	if parent.has_method("take_damage"):
		parent.take_damage(tick_damage, false, Vector2.ZERO, false, damage_source)
	elif "hp" in parent:
		parent.hp -= tick_damage
		if parent.hp <= 0 and parent.has_method("die"):
			parent.die()
