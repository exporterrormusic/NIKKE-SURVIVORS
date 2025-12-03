extends Control

## HoloCure-style XP Bar UI
## Clean red fill, white border, level badge, smooth fill animations
## Uses custom drawing to ensure border is always on top of fill

# Colors - HoloCure style flat colors
const BAR_FILL_COLOR := Color(0.9, 0.15, 0.15, 1.0)  # Bright red
const BAR_BG_COLOR := Color(0.12, 0.12, 0.15, 0.95)  # Dark background
const BAR_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.9)  # White border
const BADGE_BG_COLOR := Color(0.12, 0.12, 0.15, 0.95)
const BADGE_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

# Sizing
const BAR_HEIGHT := 30.0
const BORDER_WIDTH := 4.0
const BADGE_WIDTH := 60.0
const BADGE_PADDING := 8.0
const CORNER_RADIUS := 4

var _current_level: int = 1
var _display_value: float = 0.0
var _target_value: float = 0.0
var _max_value: float = 100.0
var _fill_tween: Tween = null

func _ready():
	# Hide the ProgressBar child - we'll draw manually
	var progress_bar = get_node_or_null("ProgressBar")
	if progress_bar:
		progress_bar.visible = false
	
	queue_redraw()

func _draw():
	var bar_left := BADGE_WIDTH + BADGE_PADDING
	var bar_width := size.x - bar_left
	var bar_rect := Rect2(bar_left, 0, bar_width, size.y)
	
	# 1. Draw bar background
	_draw_rounded_rect(bar_rect, BAR_BG_COLOR, CORNER_RADIUS)
	
	# 2. Draw fill (inset by border width)
	var fill_inset := BORDER_WIDTH
	var fill_rect := Rect2(
		bar_rect.position.x + fill_inset,
		bar_rect.position.y + fill_inset,
		bar_rect.size.x - fill_inset * 2,
		bar_rect.size.y - fill_inset * 2
	)
	
	var fill_percent := _display_value / _max_value if _max_value > 0 else 0.0
	fill_percent = clampf(fill_percent, 0.0, 1.0)
	
	if fill_percent > 0.0:
		var filled_width := fill_rect.size.x * fill_percent
		var filled_rect := Rect2(fill_rect.position, Vector2(filled_width, fill_rect.size.y))
		_draw_rounded_rect(filled_rect, BAR_FILL_COLOR, maxi(1, CORNER_RADIUS - 2))
	
	# 3. Draw border ON TOP of everything
	_draw_rounded_border(bar_rect, BAR_BORDER_COLOR, CORNER_RADIUS, BORDER_WIDTH)
	
	# 4. Draw level badge
	var badge_rect := Rect2(0, 0, BADGE_WIDTH, size.y)
	_draw_rounded_rect(badge_rect, BADGE_BG_COLOR, CORNER_RADIUS)
	_draw_rounded_border(badge_rect, BADGE_BORDER_COLOR, CORNER_RADIUS, BORDER_WIDTH)
	
	# 5. Draw level text
	var font := get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	
	var level_text := "LV %d" % _current_level
	var font_size := 14
	var text_size := font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2(
		(badge_rect.size.x - text_size.x) / 2,
		(badge_rect.size.y + text_size.y) / 2 - 2
	)
	draw_string(font, text_pos, level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)

func _draw_rounded_rect(rect: Rect2, color: Color, radius: int) -> void:
	# Simple rounded rectangle using polygon
	var points := _get_rounded_rect_points(rect, radius)
	draw_colored_polygon(points, color)

func _draw_rounded_border(rect: Rect2, color: Color, radius: int, width: float) -> void:
	# Draw border as lines
	var points := _get_rounded_rect_points(rect, radius)
	points.append(points[0])  # Close the loop
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, width, true)

func _get_rounded_rect_points(rect: Rect2, radius: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := float(mini(radius, int(min(rect.size.x, rect.size.y) / 2)))
	var segments_per_corner := 4
	
	# Top-left corner
	for i in range(segments_per_corner + 1):
		var angle := PI + (PI / 2.0) * float(i) / float(segments_per_corner)
		points.append(Vector2(rect.position.x + r + cos(angle) * r, rect.position.y + r + sin(angle) * r))
	
	# Top-right corner
	for i in range(segments_per_corner + 1):
		var angle := PI * 1.5 + (PI / 2.0) * float(i) / float(segments_per_corner)
		points.append(Vector2(rect.position.x + rect.size.x - r + cos(angle) * r, rect.position.y + r + sin(angle) * r))
	
	# Bottom-right corner
	for i in range(segments_per_corner + 1):
		var angle := 0.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
		points.append(Vector2(rect.position.x + rect.size.x - r + cos(angle) * r, rect.position.y + rect.size.y - r + sin(angle) * r))
	
	# Bottom-left corner
	for i in range(segments_per_corner + 1):
		var angle := PI / 2.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
		points.append(Vector2(rect.position.x + r + cos(angle) * r, rect.position.y + rect.size.y - r + sin(angle) * r))
	
	return points

func set_level(level: int):
	_current_level = level
	queue_redraw()

func set_xp(current: float, max_value: float, animate: bool = true):
	_max_value = max_value
	_target_value = current
	
	if animate and abs(_target_value - _display_value) > 0.1:
		# Animate the fill
		if _fill_tween and _fill_tween.is_running():
			_fill_tween.kill()
		
		_fill_tween = create_tween()
		_fill_tween.set_ease(Tween.EASE_OUT)
		_fill_tween.set_trans(Tween.TRANS_CUBIC)
		_fill_tween.tween_method(_update_display_value, _display_value, _target_value, 0.3)
	else:
		_display_value = _target_value
		queue_redraw()

func _update_display_value(value: float):
	_display_value = value
	queue_redraw()

func flash_level_up():
	# Quick flash effect
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.5, 1.5, 0.8, 1.0), 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)
