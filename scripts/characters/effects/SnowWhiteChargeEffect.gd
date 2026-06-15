extends Node2D
class_name SnowWhiteChargeEffect
## Energy orb that gathers at Snow White's muzzle while the "Charging" talent is
## held. Size and brightness scale with charge_ratio (0..1). Driven by
## SnowWhiteController.update_charge_visual().

var charge_ratio: float = 0.0
var _t: float = 0.0
var _cached_env: Node = null

const BASE_RADIUS := 5.0
const MAX_RADIUS := 30.0

func _ready() -> void:
	z_index = 65
	_cached_env = get_tree().get_first_node_in_group("environment_controller")

func set_ratio(r: float) -> void:
	charge_ratio = clampf(r, 0.0, 1.0)
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if charge_ratio > 0.0:
		queue_redraw()

func _draw() -> void:
	if charge_ratio <= 0.0:
		return

	# Compensate for the environment's day/night modulate so the orb stays bright.
	var inv := Color.WHITE
	if _cached_env and "current_modulate" in _cached_env:
		var m: Color = _cached_env.current_modulate
		inv = Color(1.0 / max(m.r, 0.001), 1.0 / max(m.g, 0.001), 1.0 / max(m.b, 0.001), 1.0)

	var flicker := 0.8 + 0.2 * sin(_t * 26.0)
	var radius := lerpf(BASE_RADIUS, MAX_RADIUS, charge_ratio) * flicker

	# Layered glow: outer blue -> mid cyan -> white core.
	draw_circle(Vector2.ZERO, radius * 1.7, Color(0.2, 0.5, 1.0, 0.30 * charge_ratio) * inv)
	draw_circle(Vector2.ZERO, radius * 1.1, Color(0.4, 0.8, 1.0, 0.55 * charge_ratio) * inv)
	draw_circle(Vector2.ZERO, radius * 0.55, Color(0.9, 1.0, 1.0, minf(1.0, 0.5 + charge_ratio)) * inv)

	# Bright ring flash once fully charged.
	if charge_ratio >= 0.999:
		draw_arc(Vector2.ZERO, radius * 2.0, 0.0, TAU, 28, Color(1, 1, 1, 0.9) * inv, 2.5, true)
