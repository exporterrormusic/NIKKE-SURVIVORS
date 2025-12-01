extends Node2D

# Draws HP text centered on the enemy HP bar

var _current_hp: int = 1
var _max_hp: int = 1
var _enemy: Node = null

func setup(enemy: Node) -> void:
	_enemy = enemy
	if enemy:
		_current_hp = enemy.hp
		_max_hp = enemy.max_hp
	queue_redraw()

func update_values(current: int, maximum: int) -> void:
	_current_hp = current
	_max_hp = maximum
	queue_redraw()

func _draw() -> void:
	var text := "%d/%d" % [_current_hp, _max_hp]
	var font := ThemeDB.fallback_font
	var font_size := 12  # Larger font for readability
	
	# Get text size for centering
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	
	# Center horizontally, and vertically using half the ascent
	var draw_pos := Vector2(
		-text_size.x * 0.5,
		font_size * 0.4  # Better vertical centering based on font size
	)
	
	# Draw black outline for readability (thicker outline)
	var shadow_color := Color(0, 0, 0, 1.0)
	var offsets := [
		Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
	]
	for offset in offsets:
		draw_string(font, draw_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color)
	
	# Draw white text
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
