extends Node
class_name ScarletBleed
## Eviscerate's bleed: a flat-damage DoT attached to an enemy that also drops a
## fading trail of blood as the enemy moves. Attached as a child named
## "ScarletBleed"; re-applying refreshes duration and total via refresh().

const BloodDecalScript := preload("res://scripts/characters/effects/ScarletBloodDecal.gd")
const NODE_NAME := "ScarletBleed"
const SOURCE := "scarlet_bleed"

const TICK_INTERVAL := 0.5
const TRAIL_INTERVAL := 0.16
const TRAIL_MIN_MOVE := 10.0 # only drop a decal once the enemy has moved this far

var _target: Node2D = null
var total_damage: float = 0.0
var duration: float = 5.0

var _timer: float = 0.0
var _tick_accum: float = 0.0
var _trail_accum: float = 0.0
var _last_decal_pos: Vector2 = Vector2.ZERO


## Attach to `target` and start bleeding for `total` damage over `dur` seconds.
func setup(target: Node2D, total: float, dur: float) -> void:
	name = NODE_NAME
	_target = target
	total_damage = total
	duration = dur
	_timer = dur
	if is_instance_valid(target):
		_last_decal_pos = target.global_position


## Re-applied by a fresh slash: refresh duration to full and update the rate.
func refresh(total: float, dur: float) -> void:
	total_damage = total
	duration = dur
	_timer = dur


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return

	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return

	# Flat DoT: spread total_damage evenly over duration.
	_tick_accum += delta
	if _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_apply_tick()

	# Blood trail: drop decals along the enemy's path while it bleeds.
	_trail_accum += delta
	if _trail_accum >= TRAIL_INTERVAL:
		_trail_accum = 0.0
		var pos: Vector2 = _target.global_position
		if pos.distance_to(_last_decal_pos) >= TRAIL_MIN_MOVE:
			_last_decal_pos = pos
			var parent := _target.get_parent()
			if parent:
				BloodDecalScript.spawn(parent, pos)


func _apply_tick() -> void:
	if not is_instance_valid(_target) or not _target.has_method("take_damage"):
		return
	var dmg := int(round(total_damage * TICK_INTERVAL / maxf(duration, 0.001)))
	dmg = maxi(dmg, 1)
	_target.take_damage(dmg, false, Vector2.ZERO, false, SOURCE)
