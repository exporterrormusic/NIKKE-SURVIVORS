# Extracted from scripts/characters/MarianController.gd (was runtime-compiled embedded source).
extends Node2D

var player: Node2D = null
var radius: float = 150.0
var indicator_color: Color = Color(0.3, 0.5, 1.0, 0.3)
var _visible: bool = false
var _activation_flash: float = 0.0

func show_indicator() -> void:
	_visible = true
	queue_redraw()

func hide_indicator() -> void:
	_visible = false
	queue_redraw()

func set_radius(r: float) -> void:
	radius = r
	queue_redraw()

func trigger_activation() -> void:
	_activation_flash = 1.0

func _process(delta: float) -> void:
	if player and is_instance_valid(player):
		global_position = player.get_global_mouse_position()
	
	if _activation_flash > 0:
		_activation_flash -= delta * 3.0
		queue_redraw()
	elif _visible:
		queue_redraw()

func _draw() -> void:
	if not _visible and _activation_flash <= 0:
		return
	
	var alpha := indicator_color.a
	if _activation_flash > 0:
		alpha = _activation_flash
	
	var color := Color(indicator_color.r, indicator_color.g, indicator_color.b, alpha)
	
	# Outer glow ring
	draw_arc(Vector2.ZERO, radius * 1.05, 0, TAU, 48, Color(color.r, color.g, color.b, alpha * 0.4), 8.0)
	
	# Main circle - thick and bright
	draw_arc(Vector2.ZERO, radius, 0, TAU, 48, color, 4.0)
	
	# Inner ring
	draw_arc(Vector2.ZERO, radius * 0.9, 0, TAU, 48, Color(color.r, color.g, color.b, alpha * 0.6), 2.0)
	
	# Filled center - more opaque
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, alpha * 0.35))
	
	# Crosshair lines
	var line_color := Color(color.r, color.g, color.b, alpha * 0.7)
	draw_line(Vector2(-radius * 0.3, 0), Vector2(radius * 0.3, 0), line_color, 2.0)
	draw_line(Vector2(0, -radius * 0.3), Vector2(0, radius * 0.3), line_color, 2.0)
