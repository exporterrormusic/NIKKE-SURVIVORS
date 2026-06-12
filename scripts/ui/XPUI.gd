extends Control

## XP line (dark field register, approved mockup docs/mockups/hud_v2.html):
## yellow-bordered LV chip + slim flat cyan bar. Sits under the player cluster.

const UI := preload("res://scripts/ui/UITheme.gd")

# Sizing (mockup ×1.5)
const BAR_HEIGHT := 10.0
const BADGE_WIDTH := 78.0
const BADGE_PADDING := 12.0

var _current_level: int = 1
var _display_value: float = 0.0
var _target_value: float = 0.0
var _max_value: float = 100.0
var _fill_tween: Tween = null

func _ready():
	# Hide the ProgressBar child - we draw manually
	var progress_bar = get_node_or_null("ProgressBar")
	if progress_bar:
		progress_bar.visible = false

	queue_redraw()

func _draw():
	# LV chip: dark glass + 1px yellow border + yellow text
	var badge_rect := Rect2(0, 0, BADGE_WIDTH, size.y)
	draw_rect(badge_rect, Color(0.039, 0.051, 0.071, 0.6))
	draw_rect(badge_rect, UI.ACCENT_SECONDARY, false, 1.0)

	var font: Font = UI.FONT_BOLD
	var level_text := "LV %d" % _current_level
	var font_size := 15
	var text_size := font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2(
		(badge_rect.size.x - text_size.x) / 2,
		(badge_rect.size.y + text_size.y) / 2 - 3
	)
	draw_string(font, text_pos, level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UI.ACCENT_SECONDARY)

	# Slim flat bar, vertically centered against the chip
	var bar_left := BADGE_WIDTH + BADGE_PADDING
	var bar_y := (size.y - BAR_HEIGHT) * 0.5
	var bar_rect := Rect2(bar_left, bar_y, size.x - bar_left, BAR_HEIGHT)
	draw_rect(bar_rect, Color(0.039, 0.051, 0.071, 0.75))

	var fill_percent := _display_value / _max_value if _max_value > 0 else 0.0
	fill_percent = clampf(fill_percent, 0.0, 1.0)
	if fill_percent > 0.0:
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * fill_percent, BAR_HEIGHT)),
			UI.ACCENT_CYAN_DEEP)

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
	# Impressive golden flash and glow effect
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Bright golden flash - peak brightness
	tween.tween_property(self, "modulate", UI.FLASH_GOLD, 0.08)
	
	# Then sustain a warm glow
	tween.chain().tween_property(self, "modulate", UI.FLASH_GOLD_MID, 0.15)
	
	# Pulse brighter again
	tween.chain().tween_property(self, "modulate", UI.FLASH_GOLD_ALT, 0.1)
	
	# Fade back smoothly
	tween.chain().tween_property(self, "modulate", UI.FLASH_GOLD_DIM, 0.2)
	tween.chain().tween_property(self, "modulate", Color.WHITE, 0.3)
