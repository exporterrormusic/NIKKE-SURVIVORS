extends Node2D
class_name StunEffect

## Generic "dazed" indicator shown over a stunned enemy: a few cartoon stars
## orbiting above its head. Added as a child of the enemy by ModularEnemy.apply_stun
## and self-removes once the enemy is no longer stunned (or a safety timeout hits).

const STAR_COUNT := 3
const ORBIT_RX := 20.0   # horizontal orbit radius
const ORBIT_RY := 7.0    # vertical orbit radius (gives a "ring around the head" look)
# Local Y of the enemy "head", matching the HP bar's anchor (EnemyHUD uses -47 * scale).
# A few px above the bar so the stars crown the enemy.
const HEAD_OFFSET := -54.0
const SPIN_SPEED := 4.5

var _time: float = 0.0
var _target: Node = null
var _max_lifetime: float = 0.0 # safety fallback; <=0 means "until unstunned"

func _ready() -> void:
	_target = get_parent()
	z_as_relative = false
	z_index = 120
	# Unshaded so it stays bright at night.
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	set_process(true)
	_update_transform()

## Optional safety timeout (stun duration + margin) in case the unstun signal is missed.
func setup(duration: float) -> void:
	_max_lifetime = duration + 0.5

## Keep the indicator at the same relative spot above the head, and the same on-screen
## size, regardless of how large the enemy is scaled. The local offset rides the enemy's
## node scale (so it tracks the head height) while we counter-scale to hold star size.
func _update_transform() -> void:
	var s := 1.0
	if _target is Node2D:
		s = maxf((_target as Node2D).scale.y, 0.01)
	position = Vector2(0, HEAD_OFFSET)
	scale = Vector2.ONE / s

func _process(delta: float) -> void:
	_time += delta
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	if _target.has_method("is_stunned") and not _target.is_stunned():
		queue_free()
		return
	if _max_lifetime > 0.0 and _time >= _max_lifetime:
		queue_free()
		return
	_update_transform()
	queue_redraw()

func _draw() -> void:
	# Stars orbit on an ellipse; the ones at the "front" (bottom of the ellipse)
	# draw larger/brighter to fake depth.
	for i in range(STAR_COUNT):
		var phase: float = _time * SPIN_SPEED + float(i) * TAU / float(STAR_COUNT)
		var pos := Vector2(cos(phase) * ORBIT_RX, sin(phase) * ORBIT_RY)
		var depth: float = (sin(phase) + 1.0) * 0.5 # 0 = back, 1 = front
		var size: float = lerpf(3.0, 6.0, depth)
		var alpha: float = lerpf(0.45, 1.0, depth)
		_draw_star(pos, size, Color(1.0, 0.9, 0.35, alpha))

func _draw_star(c: Vector2, r: float, col: Color) -> void:
	# 4-point sparkle.
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 2.0, true)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 2.0, true)
	var d := r * 0.6
	draw_line(c - Vector2(d, d), c + Vector2(d, d), col, 1.5, true)
	draw_line(c - Vector2(d, -d), c + Vector2(d, -d), col, 1.5, true)
