extends CanvasLayer
class_name BossHealthBar

## Large segmented health bar displayed at top of screen for boss enemies

var _container: Control = null
var _bar_background: ColorRect = null
var _bar_fill: Control = null
var _name_label: Label = null
var _timer_label: Label = null  # Enrage timer display
var _boss: Node2D = null
var _target_fill: float = 1.0
var _current_fill: float = 1.0
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_timer: float = 0.0
var _is_goddess_fall: bool = false
var _flash_time: float = 0.0  # For timer flashing effect

const BAR_WIDTH := 600.0
const BAR_HEIGHT := 24.0
const SEGMENT_COUNT := 10
const SEGMENT_GAP := 2.0

const BG_COLOR := Color(0.1, 0.05, 0.12, 0.9)
const FILL_COLOR := Color(0.7, 0.2, 0.9, 1.0)
const FILL_LOW_COLOR := Color(0.9, 0.2, 0.3, 1.0)
const BORDER_COLOR := Color(0.9, 0.85, 1.0, 0.9)
const SEGMENT_LINE_COLOR := Color(0.2, 0.1, 0.25, 0.8)

func _ready() -> void:
	layer = 50  # Above game elements
	visible = false
	_setup_ui()

func _setup_ui() -> void:
	# Main container
	_container = Control.new()
	_container.name = "BossBarContainer"
	_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_container.position = Vector2(-BAR_WIDTH / 2, 105)
	_container.size = Vector2(BAR_WIDTH, BAR_HEIGHT + 30)
	add_child(_container)
	
	# Bar background
	_bar_background = ColorRect.new()
	_bar_background.name = "Background"
	_bar_background.color = BG_COLOR
	_bar_background.position = Vector2(0, 0)
	_bar_background.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_container.add_child(_bar_background)
	
	# Fill
	_bar_fill = Control.new()
	_bar_fill.name = "Fill"
	_bar_fill.position = Vector2(0, 0)
	_bar_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_fill.draw.connect(_draw_bar)
	_container.add_child(_bar_fill)
	
	# Name Label
	_name_label = Label.new()
	_name_label.name = "BossName"
	_name_label.text = "BOSS"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Critical: Center alignment with clean font sizes
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 26) # Default safe size
	_name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.position = Vector2(0, 0)
	_name_label.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_name_label.clip_text = true
	_container.add_child(_name_label)
	
	# Enrage timer label
	_timer_label = Label.new()
	_timer_label.name = "EnrageTimer"
	_timer_label.text = ""
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_timer_label.add_theme_color_override("font_shadow_color", Color(0.3, 0.1, 0.0, 0.9))
	_timer_label.add_theme_constant_override("shadow_offset_x", 2)
	_timer_label.add_theme_constant_override("shadow_offset_y", 2)
	_timer_label.position = Vector2(0, BAR_HEIGHT + 4) # Adjust for height
	_timer_label.size = Vector2(BAR_WIDTH, 28)
	_timer_label.visible = false
	_container.add_child(_timer_label)

func _draw_bar() -> void:
    # ... (Keep existing draw logic, just ensure it uses rect.size.y which is now BAR_HEIGHT)
	if not _bar_fill:
		return
	
	var bar := _bar_fill
	var rect := Rect2(Vector2.ZERO, bar.size)
	var segment_width := (rect.size.x - SEGMENT_GAP * (SEGMENT_COUNT - 1)) / SEGMENT_COUNT
	
	# Draw filled segments
	var filled_segments := int(_current_fill * SEGMENT_COUNT)
	var partial_fill := fmod(_current_fill * SEGMENT_COUNT, 1.0)
	
	# Color based on health
	var fill_color := FILL_COLOR
	if _current_fill < 0.3:
		fill_color = FILL_LOW_COLOR
	elif _current_fill < 0.5:
		var t := (_current_fill - 0.3) / 0.2
		fill_color = FILL_LOW_COLOR.lerp(FILL_COLOR, t)
	
	for i in range(SEGMENT_COUNT):
		var x := i * (segment_width + SEGMENT_GAP)
		var segment_rect := Rect2(Vector2(x, 0), Vector2(segment_width, rect.size.y))
		
		if i < filled_segments:
			# Fully filled segment
			bar.draw_rect(segment_rect, fill_color)
		elif i == filled_segments and partial_fill > 0:
			# Partially filled segment
			var partial_width := segment_width * partial_fill
			var partial_rect := Rect2(Vector2(x, 0), Vector2(partial_width, rect.size.y))
			bar.draw_rect(partial_rect, fill_color)
		
		# Segment border
		bar.draw_rect(segment_rect, SEGMENT_LINE_COLOR, false, 1.0)
	
	# Outer border
	bar.draw_rect(Rect2(Vector2(-2, -2), rect.size + Vector2(4, 4)), BORDER_COLOR, false, 2.0)

func show_boss(boss: Node2D, boss_name: String = "BOSS") -> void:
	_boss = boss
	_name_label.text = boss_name
	
	# Intelligent Font Scaling for 24px Bar
	var name_len = boss_name.length()
	var font_size = 26 # Bigger again (User requested)
	
	if name_len > 35:
		font_size = 16
	elif name_len > 25:
		font_size = 18
	elif name_len > 15:
		font_size = 22
	
	_name_label.add_theme_font_size_override("font_size", font_size)
	
	_current_fill = 1.0
	_target_fill = 1.0
	visible = true

	
	# Check if Goddess Fall mode - show enrage timer
	_is_goddess_fall = GameState and GameState.goddess_fall_mode
	_timer_label.visible = _is_goddess_fall
	
	# Entrance animation - slide down from above
	_container.modulate.a = 0.0
	_container.position.y = 85
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_container, "modulate:a", 1.0, 0.3)
	tween.tween_property(_container, "position:y", 105.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func hide_boss() -> void:
	var tween := create_tween()
	tween.tween_property(_container, "modulate:a", 0.0, 0.3)
	tween.finished.connect(func(): visible = false)
	_boss = null

func update_health(current: int, maximum: int) -> void:
	if maximum <= 0:
		return
	_target_fill = clampf(float(current) / float(maximum), 0.0, 1.0)
	
	# Trigger shake on damage
	if _target_fill < _current_fill:
		_shake_timer = 0.15
		_shake_offset = Vector2(randf_range(-4, 4), randf_range(-2, 2))

func _process(delta: float) -> void:
	if not visible:
		return
	
	_flash_time += delta
	
	# Check if boss is still alive
	if _boss and is_instance_valid(_boss):
		if "hp" in _boss and "max_hp" in _boss:
			update_health(_boss.hp, _boss.max_hp)
			if _boss.hp <= 0:
				call_deferred("hide_boss")
		
		# Update enrage timer display in Goddess Fall mode
		if _is_goddess_fall and _timer_label.visible:
			_update_enrage_timer_display()
	elif _boss:
		# Boss died
		call_deferred("hide_boss")
	
	# Smooth fill transition
	_current_fill = lerpf(_current_fill, _target_fill, delta * 8.0)
	
	# Handle shake
	if _shake_timer > 0:
		_shake_timer -= delta
		_bar_fill.position = Vector2(0, 26) + _shake_offset * (_shake_timer / 0.15)
	else:
		_bar_fill.position = Vector2(0, 26)
	
	if _bar_fill:
		_bar_fill.queue_redraw()

func _update_enrage_timer_display() -> void:
	if not _boss or not is_instance_valid(_boss):
		return
	
	# Get remaining time from boss's enrage timer
	var enrage_timer: Timer = _boss.get_node_or_null("EnrageTimer")
	if not enrage_timer:
		_timer_label.visible = false
		return
	
	var time_remaining: float = enrage_timer.time_left
	var seconds := int(time_remaining)
	var tenths := int((time_remaining - seconds) * 10)
	
	# Format timer text
	_timer_label.text = "⚠ %d.%d ⚠" % [seconds, tenths]
	
	# Determine color and flashing based on time remaining
	if time_remaining <= 3.0:
		# Solid intense red for last 3 seconds
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1, 1.0))
		_timer_label.add_theme_font_size_override("font_size", 26)  # Larger
	elif time_remaining <= 10.0:
		# Flashing red - speed increases as time decreases
		# Flash frequency: starts at 1Hz at 10s, increases to 5Hz at 3s
		var urgency := 1.0 - (time_remaining - 3.0) / 7.0  # 0 at 10s, 1 at 3s
		var flash_speed := 2.0 + urgency * 8.0  # 2Hz to 10Hz
		var flash := sin(_flash_time * flash_speed * PI) * 0.5 + 0.5
		
		# Lerp between yellow and red based on flash
		var color := Color(1.0, 0.9 - flash * 0.8, 0.3 - flash * 0.3, 1.0)
		_timer_label.add_theme_color_override("font_color", color)
		_timer_label.add_theme_font_size_override("font_size", 22 + int(flash * 4))
	else:
		# Normal yellow color
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
		_timer_label.add_theme_font_size_override("font_size", 22)
