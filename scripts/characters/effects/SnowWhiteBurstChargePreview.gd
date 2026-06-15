extends Node2D
class_name SnowWhiteBurstChargePreview
## Ghost preview of Snow White's "Focused Fire" burst cone. Shows where the burst
## will fire and how wide; the arc narrows as the player holds the burst key and
## the whole cone flashes once fully charged to cue the release.

var forward: Vector2 = Vector2.RIGHT
var arc_degrees: float = 90.0
var beam_range: float = 1200.0
var fully_charged: bool = false

var _t: float = 0.0
var _cached_env: Node = null
const ARC_STEPS := 32

func _ready() -> void:
	z_index = 415 # just under the real burst beam (420)
	z_as_relative = false
	_cached_env = get_tree().get_first_node_in_group("environment_controller")

func set_charge(forward_dir: Vector2, arc_deg: float, full: bool) -> void:
	if forward_dir.length() > 0.0:
		forward = forward_dir.normalized()
	arc_degrees = arc_deg
	fully_charged = full
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	# Compensate for day/night modulate so the ghost stays visible.
	var inv := Color.WHITE
	if _cached_env and "current_modulate" in _cached_env:
		var m: Color = _cached_env.current_modulate
		inv = Color(1.0 / max(m.r, 0.001), 1.0 / max(m.g, 0.001), 1.0 / max(m.b, 0.001), 1.0)

	var base_angle := forward.angle()
	var total := deg_to_rad(arc_degrees)

	# Cone polygon (fan from origin).
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(ARC_STEPS + 1):
		var t := float(i) / float(ARC_STEPS)
		var ang := base_angle - total * 0.5 + total * t
		points.append(Vector2.RIGHT.rotated(ang) * beam_range)

	# Fill: soft pulse while charging, strong flash when full.
	var fill_alpha: float
	var edge_alpha: float
	if fully_charged:
		var flash := 0.5 + 0.5 * sin(_t * 18.0)
		fill_alpha = 0.16 + 0.20 * flash
		edge_alpha = 0.55 + 0.45 * flash
	else:
		fill_alpha = 0.10 + 0.04 * sin(_t * 6.0)
		edge_alpha = 0.5

	draw_colored_polygon(points, Color(0.55, 0.8, 1.0, fill_alpha) * inv)

	# Edge + center-aim lines for a clear "where it points" read.
	var edge := Color(0.85, 0.95, 1.0, edge_alpha) * inv
	var left := Vector2.RIGHT.rotated(base_angle - total * 0.5) * beam_range
	var right := Vector2.RIGHT.rotated(base_angle + total * 0.5) * beam_range
	draw_line(Vector2.ZERO, left, edge, 4.0, true)
	draw_line(Vector2.ZERO, right, edge, 4.0, true)
	draw_line(Vector2.ZERO, forward * beam_range, Color(edge.r, edge.g, edge.b, edge.a * 0.35), 2.0, true)
