extends Node2D
class_name RapunzelDesignator

## Anti-Queen Bombardment targeting reticle, StarCraft-ghost-nuke style: a spinning
## bracketed ring + crosshair painted at the cursor while the burst key is held.
## Amber while arming, red and pulsing once the ~1s arm threshold is reached.

const RADIUS := 46.0
const SPIN_SPEED := 1.6

var _armed: bool = false
var _time: float = 0.0

func _ready() -> void:
	z_as_relative = false
	z_index = 400
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	set_process(true)

func set_armed(armed: bool) -> void:
	_armed = armed

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * (10.0 if _armed else 4.0))
	var col: Color
	if _armed:
		col = Color(1.0, 0.2, 0.15, 0.65 + 0.35 * pulse) # locked: red
	else:
		col = Color(1.0, 0.78, 0.25, 0.55 + 0.2 * pulse) # arming: amber

	var r := RADIUS * (1.0 if _armed else lerpf(1.25, 1.0, pulse))

	# Spinning bracket ring: four 40-degree arcs with gaps.
	var spin := _time * SPIN_SPEED
	for i in range(4):
		var a0: float = spin + float(i) * (TAU / 4.0)
		draw_arc(Vector2.ZERO, r, a0, a0 + deg_to_rad(40.0), 12, col, 3.0, true)

	# Inner ring.
	draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 32, Color(col.r, col.g, col.b, col.a * 0.5), 2.0, true)

	# Crosshair lines with a center gap.
	var gap := 8.0
	var reach := r * 0.95
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(d * gap, d * reach, col, 2.0, true)

	# Center dot.
	draw_circle(Vector2.ZERO, 3.0, Color(col.r, col.g, col.b, col.a))

	# Armed: add a downward "incoming" chevron to read as a strike marker.
	if _armed:
		var tip := Vector2(0, -r - 10.0 - 4.0 * pulse)
		var w := 9.0
		draw_colored_polygon(PackedVector2Array([
			tip,
			tip + Vector2(-w, -w),
			tip + Vector2(w, -w),
		]), Color(1.0, 0.25, 0.2, 0.9))
