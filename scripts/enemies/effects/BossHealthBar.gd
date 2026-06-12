extends CanvasLayer
class_name BossHealthBar

## Boss health bar (dark field register, approved mockup
## docs/mockups/hud_v2.html): bottom-center - skewed red name chip above a
## segmented bar with red corner brackets, percentage outside on the right.

const UI := preload("res://scripts/ui/UITheme.gd")

var _container: Control = null
var _bar_background: ColorRect = null
var _bar_fill: Control = null
var _name_chip: PanelContainer = null
var _name_label: Label = null
var _pct_label: Label = null
var _timer_label: Label = null # Enrage timer display
var _boss: Node2D = null
var _target_fill: float = 1.0
var _current_fill: float = 1.0
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_timer: float = 0.0
var _is_goddess_fall: bool = false
var _flash_time: float = 0.0 # For timer flashing effect

const BAR_WIDTH := 760.0
const BAR_HEIGHT := 24.0
const PCT_WIDTH := 86.0
const NAME_ROW_HEIGHT := 36.0
const BAR_Y := 60.0
const BOTTOM_MARGIN := 200.0
const SEGMENT_COUNT := 10
const SEGMENT_GAP := 2.0
const BRACKET_SIZE := 21.0
const BRACKET_WIDTH := 3.0

const BG_COLOR := Color(0.039, 0.051, 0.071, 0.7)
const FILL_COLOR := Color(0.7, 0.2, 0.9, 1.0) # Purple for regular boss
const SUPER_BOSS_COLOR := Color(0.9, 0.2, 0.2, 1.0) # Red for N01/super boss
const FILL_LOW_COLOR := Color(0.9, 0.2, 0.3, 1.0)
const BRACKET_COLOR := Color(0.91, 0.224, 0.18, 0.9)
const SEGMENT_LINE_COLOR := Color(0.05, 0.05, 0.08, 0.8)

const SHIELD_HEIGHT := 16.0

var _is_super_boss := false # Track if current boss is super boss (red bar)
var _shield_bar: Control = null
var _shield_fill: float = 0.0


func _ready() -> void:
	layer = 50 # Above game elements
	visible = false
	_setup_ui()

func _setup_ui() -> void:
	# Main container - bottom center (approved mockup position)
	_container = Control.new()
	_container.name = "BossBarContainer"
	_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_container.position = Vector2(-(BAR_WIDTH + PCT_WIDTH) / 2, -BOTTOM_MARGIN)
	_container.size = Vector2(BAR_WIDTH + PCT_WIDTH, 120)
	add_child(_container)

	# Skewed red name chip (top row, left-aligned)
	_name_chip = PanelContainer.new()
	_name_chip.name = "NameChip"
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.47, 0.03, 0.016, 0.85)
	chip_style.border_color = UI.COLOR_DANGER
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(0)
	chip_style.skew = Vector2(-0.105, 0)
	chip_style.content_margin_left = 21
	chip_style.content_margin_right = 21
	chip_style.content_margin_top = 4
	chip_style.content_margin_bottom = 4
	_name_chip.add_theme_stylebox_override("panel", chip_style)
	_name_chip.position = Vector2(8, 0)
	_container.add_child(_name_chip)

	_name_label = Label.new()
	_name_label.name = "BossName"
	_name_label.text = "☠  BOSS"
	_name_label.add_theme_font_override("font", UI.FONT_BOLD)
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.706, 0.682, 1.0))
	_name_chip.add_child(_name_label)

	# Bar background
	_bar_background = ColorRect.new()
	_bar_background.name = "Background"
	_bar_background.color = BG_COLOR
	_bar_background.position = Vector2(0, BAR_Y)
	_bar_background.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_container.add_child(_bar_background)

	# Fill
	_bar_fill = Control.new()
	_bar_fill.name = "Fill"
	_bar_fill.position = Vector2(0, BAR_Y)
	_bar_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_fill.draw.connect(_draw_bar)
	_container.add_child(_bar_fill)

	# Percentage (outside the bar, right)
	_pct_label = Label.new()
	_pct_label.name = "Percent"
	_pct_label.text = "100%"
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_pct_label.add_theme_font_size_override("font_size", 27)
	_pct_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.52, 1.0))
	_pct_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_pct_label.add_theme_constant_override("shadow_offset_x", 1)
	_pct_label.add_theme_constant_override("shadow_offset_y", 2)
	_pct_label.position = Vector2(BAR_WIDTH + 6, BAR_Y - 6)
	_pct_label.size = Vector2(PCT_WIDTH - 12, BAR_HEIGHT + 12)
	_container.add_child(_pct_label)

	# Shield Bar (stacked between name chip and main bar)
	_shield_bar = Control.new()
	_shield_bar.name = "ShieldBar"
	_shield_bar.position = Vector2(0, BAR_Y - SHIELD_HEIGHT - 4)
	_shield_bar.size = Vector2(BAR_WIDTH, SHIELD_HEIGHT)
	_shield_bar.draw.connect(_draw_shield_bar)
	_shield_bar.visible = false
	_container.add_child(_shield_bar)

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
	_timer_label.position = Vector2(0, BAR_Y + BAR_HEIGHT + 6)
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
	
	# Color based on health and boss type
	var base_color := SUPER_BOSS_COLOR if _is_super_boss else FILL_COLOR
	var fill_color := base_color
	if _current_fill < 0.3:
		fill_color = FILL_LOW_COLOR
	elif _current_fill < 0.5:
		var t := (_current_fill - 0.3) / 0.2
		fill_color = FILL_LOW_COLOR.lerp(base_color, t)
	
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

	# Red corner brackets (top-left + bottom-right), outside the fill
	var s := BRACKET_SIZE
	var w := BRACKET_WIDTH
	bar.draw_rect(Rect2(-2, -2, s, w), BRACKET_COLOR)
	bar.draw_rect(Rect2(-2, -2, w, s), BRACKET_COLOR)
	bar.draw_rect(Rect2(rect.size.x + 2 - s, rect.size.y + 2 - w, s, w), BRACKET_COLOR)
	bar.draw_rect(Rect2(rect.size.x + 2 - w, rect.size.y + 2 - s, w, s), BRACKET_COLOR)

func show_boss(boss: Node2D, boss_name: String = "BOSS", is_super: bool = false) -> void:
	_boss = boss
	_is_super_boss = is_super # Red bar for super boss (N01)
	_name_label.text = "☠  %s" % boss_name.to_upper()

	# Connect to boss tree_exiting to reliably hide when boss dies/freed
	if is_instance_valid(boss) and not boss.tree_exiting.is_connected(_on_boss_exiting):
		boss.tree_exiting.connect(_on_boss_exiting)

	# Font scaling for very long names (chip auto-sizes horizontally)
	var name_len = boss_name.length()
	var font_size = 16
	if name_len > 35:
		font_size = 13
	elif name_len > 25:
		font_size = 14
	_name_label.add_theme_font_size_override("font_size", font_size)

	_current_fill = 1.0
	_target_fill = 1.0
	visible = true

	# Check if Goddess Fall mode - show enrage timer
	var game_manager = get_node_or_null("/root/GameManager")
	_is_goddess_fall = game_manager and game_manager.goddess_fall_mode
	_timer_label.visible = _is_goddess_fall

	# Entrance animation - slide up from below
	_container.modulate.a = 0.0
	_container.position.y = -BOTTOM_MARGIN + 40.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_container, "modulate:a", 1.0, 0.3)
	tween.tween_property(_container, "position:y", -BOTTOM_MARGIN, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _on_boss_exiting() -> void:
	# Called when boss is about to be freed - hide the bar immediately
	call_deferred("hide_boss")

func hide_boss() -> void:
	if _boss == null and not visible:
		return # Already hidden
	_boss = null # Clear reference immediately to prevent duplicate calls
	var tween := create_tween()
	tween.tween_property(_container, "modulate:a", 0.0, 0.3)
	tween.finished.connect(func(): visible = false)

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
	if _boss:
		if not is_instance_valid(_boss):
			# Boss object was freed - hide immediately
			call_deferred("hide_boss")
			return
		
		if "hp" in _boss and "max_hp" in _boss:
			update_health(_boss.hp, _boss.max_hp)
			if _boss.hp <= 0:
				call_deferred("hide_boss")
				return
		
		# Update enrage timer display in Goddess Fall mode
		if _is_goddess_fall and _timer_label.visible:
			_update_enrage_timer_display()
	
	# Smooth fill transition
	_current_fill = lerpf(_current_fill, _target_fill, delta * 8.0)

	# Percentage readout (outside the bar)
	if _pct_label:
		_pct_label.text = "%d%%" % maxi(0, roundi(_current_fill * 100.0))

	# Handle shake
	var bar_base := Vector2(0, BAR_Y)
	if _shake_timer > 0:
		_shake_timer -= delta
		_bar_fill.position = bar_base + _shake_offset * (_shake_timer / 0.15)
	else:
		_bar_fill.position = bar_base

	if _bar_fill:
		_bar_fill.queue_redraw()

	# Update Shield Logic
	if _boss and _shield_bar:
		var s_data = Vector2.ZERO
		if _boss.has_method("get_active_shield_stats"):
			s_data = _boss.get_active_shield_stats()
		
		# If protected, show bar
		if s_data.y > 0 and s_data.x > 0:
			_shield_fill = clampf(s_data.x / s_data.y, 0.0, 1.0)
			_shield_bar.visible = true
			_shield_bar.queue_redraw()
		else:
			_shield_bar.visible = false

func _draw_shield_bar() -> void:
	if not _shield_bar: return
	
	var rect := Rect2(Vector2.ZERO, _shield_bar.size)
	
	# Background (Darker)
	_shield_bar.draw_rect(rect, Color(0.1, 0.05, 0.2, 0.9))
	
	# Fill (Purple/Cyan based on theme? Using Purple for Bosses)
	var fill_w = rect.size.x * _shield_fill
	if fill_w > 0:
		_shield_bar.draw_rect(Rect2(0, 0, fill_w, rect.size.y), Color(0.6, 0.3, 1.0, 1.0))
		
	# Border
	_shield_bar.draw_rect(rect, Color(1, 1, 1, 0.3), false, 1.0)
	
	# Gloss
	if _shield_fill > 0:
		_shield_bar.draw_rect(Rect2(0, 0, fill_w, 4), Color(1, 1, 1, 0.2))
	
	# Shield HP Text (centered)
	if _boss and _shield_fill > 0:
		var s_data = Vector2.ZERO
		if _boss.has_method("get_active_shield_stats"):
			s_data = _boss.get_active_shield_stats()
		if s_data.y > 0:
			var shield_text := "%d / %d" % [int(s_data.x), int(s_data.y)]
			var font = ThemeDB.fallback_font
			var font_size := 12
			var text_size = font.get_string_size(shield_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos := Vector2((rect.size.x - text_size.x) / 2, rect.size.y / 2 + text_size.y / 4)
			# Shadow
			_shield_bar.draw_string(font, text_pos + Vector2(1, 1), shield_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
			# Text
			_shield_bar.draw_string(font, text_pos, shield_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 1.0))


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
		_timer_label.add_theme_font_size_override("font_size", 26) # Larger
	elif time_remaining <= 10.0:
		# Flashing red - speed increases as time decreases
		# Flash frequency: starts at 1Hz at 10s, increases to 5Hz at 3s
		var urgency := 1.0 - (time_remaining - 3.0) / 7.0 # 0 at 10s, 1 at 3s
		var flash_speed := 2.0 + urgency * 8.0 # 2Hz to 10Hz
		var flash := sin(_flash_time * flash_speed * PI) * 0.5 + 0.5
		
		# Lerp between yellow and red based on flash
		var color := Color(1.0, 0.9 - flash * 0.8, 0.3 - flash * 0.3, 1.0)
		_timer_label.add_theme_color_override("font_color", color)
		_timer_label.add_theme_font_size_override("font_size", 22 + int(flash * 4))
	else:
		# Normal yellow color
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
		_timer_label.add_theme_font_size_override("font_size", 22)
