# Extracted from scripts/ui/HuntUI.gd (was runtime-compiled embedded source).
extends Control

var hunt_ui: Node = null
var _time := 0.0

func _process(delta: float) -> void:
	_time += delta

func _draw() -> void:
	if not hunt_ui:
		return
	
	var center := size / 2.0
	var box_size: float = min(size.x, size.y) - 8
	
	# Draw box background
	var box_rect := Rect2(center - Vector2(box_size/2, box_size/2), Vector2(box_size, box_size))
	var box_color := Color(0.1, 0.15, 0.2, 0.8)
	draw_rect(box_rect, box_color)
	
	# Draw box border
	var border_color: Color = Color(0.2, 0.8, 1.0, 0.8)
	if hunt_ui and hunt_ui._is_n01_phase:
		border_color = Color(1.0, 0.3, 0.3, 0.8)
	draw_rect(box_rect, border_color, false, 2.0)
	
	# Calculate direction to target
	var player = hunt_ui._player if hunt_ui else null
	var target_pos = hunt_ui._target_position if hunt_ui else Vector2.ZERO
	
	if player and is_instance_valid(player) and target_pos != Vector2.ZERO:
		var direction: Vector2 = (target_pos - player.global_position).normalized()
		var arrow_color: Color = border_color
		arrow_color.a = 0.7 + sin(_time * 4.0) * 0.3
		
		# Draw arrow pointing in direction
		var arrow_size: float = box_size * 0.35
		var tip: Vector2 = center + direction * arrow_size
		var base_pt: Vector2 = center - direction * arrow_size * 0.3
		var perp: Vector2 = Vector2(-direction.y, direction.x)
		
		var points := PackedVector2Array([
			tip,
			base_pt + perp * arrow_size * 0.5,
			base_pt - perp * arrow_size * 0.5
		])
		draw_colored_polygon(points, arrow_color)
