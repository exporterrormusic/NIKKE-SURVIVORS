extends Control

## HoloCure-style XP Bar UI
## Clean red fill, white border, level badge, smooth fill animations

# Colors - HoloCure style flat colors
const BAR_FILL_COLOR := Color(0.9, 0.15, 0.15, 1.0)  # Bright red
const BAR_BG_COLOR := Color(0.12, 0.12, 0.15, 0.95)  # Dark background
const BAR_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.9)  # White border
const BADGE_BG_COLOR := Color(0.12, 0.12, 0.15, 0.95)
const BADGE_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

# Sizing
const BAR_HEIGHT := 24.0
const BORDER_WIDTH := 4.0
const BADGE_WIDTH := 60.0
const BADGE_PADDING := 8.0
const CORNER_RADIUS := 4

var _progress_bar: ProgressBar = null
var _level_badge: Control = null
var _current_level: int = 1
var _display_value: float = 0.0
var _target_value: float = 0.0
var _fill_tween: Tween = null

func _ready():
	_progress_bar = get_node_or_null("ProgressBar")
	if _progress_bar:
		_style_progress_bar()
	
	# Create level badge
	_create_level_badge()

func _style_progress_bar():
	# Background style
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BAR_BG_COLOR
	bg_style.border_color = BAR_BORDER_COLOR
	bg_style.set_border_width_all(int(BORDER_WIDTH))
	bg_style.set_corner_radius_all(CORNER_RADIUS)
	
	# Fill style
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = BAR_FILL_COLOR
	fill_style.set_corner_radius_all(CORNER_RADIUS - 1)
	# Add slight expand margin so fill looks good inside border
	fill_style.expand_margin_left = -1
	fill_style.expand_margin_right = -1
	fill_style.expand_margin_top = -1
	fill_style.expand_margin_bottom = -1
	
	_progress_bar.add_theme_stylebox_override("background", bg_style)
	_progress_bar.add_theme_stylebox_override("fill", fill_style)
	
	# Adjust bar position to make room for badge
	_progress_bar.offset_left = BADGE_WIDTH + BADGE_PADDING
	_progress_bar.custom_minimum_size.y = BAR_HEIGHT

func _create_level_badge():
	_level_badge = Control.new()
	_level_badge.custom_minimum_size = Vector2(BADGE_WIDTH, BAR_HEIGHT)
	_level_badge.size = Vector2(BADGE_WIDTH, BAR_HEIGHT)
	_level_badge.position = Vector2(0, 0)
	add_child(_level_badge)
	
	# Connect draw signal
	_level_badge.draw.connect(_on_badge_draw)
	_level_badge.queue_redraw()

func _on_badge_draw():
	if not _level_badge:
		return
	
	var rect := Rect2(Vector2.ZERO, _level_badge.size)
	
	# Draw background
	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_BG_COLOR
	style.border_color = BADGE_BORDER_COLOR
	style.set_border_width_all(int(BORDER_WIDTH))
	style.set_corner_radius_all(CORNER_RADIUS)
	_level_badge.draw_style_box(style, rect)
	
	# Draw level text
	var font := _level_badge.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	
	var level_text := "LV %d" % _current_level
	var font_size := 14
	var text_size := font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2(
		(rect.size.x - text_size.x) / 2,
		(rect.size.y + text_size.y) / 2 - 2
	)
	_level_badge.draw_string(font, text_pos, level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)

func set_level(level: int):
	_current_level = level
	if _level_badge:
		_level_badge.queue_redraw()

func set_xp(current: float, max_value: float, animate: bool = true):
	if not _progress_bar:
		return
	
	_progress_bar.max_value = max_value
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
		_progress_bar.value = _display_value

func _update_display_value(value: float):
	_display_value = value
	if _progress_bar:
		_progress_bar.value = _display_value

func flash_level_up():
	# Quick flash effect on the badge when leveling up
	if not _level_badge:
		return
	
	var tween := create_tween()
	tween.tween_property(_level_badge, "modulate", Color(1.5, 1.5, 0.8, 1.0), 0.1)
	tween.tween_property(_level_badge, "modulate", Color.WHITE, 0.2)
