extends CanvasLayer
class_name WaveUI

## Displays combined wave progress bar with timer and event info

# UI elements
var _progress_container: Control = null
var _progress_bar: Control = null  # Custom drawn progress
var _timer_label: Label = null
var _wave_label: Label = null
var _event_label: Label = null
var _boss_warning: Control = null

# State
var _event_fade_timer := 0.0
var _boss_warning_timer := 0.0
var _current_progress := 0.0
var _target_progress := 0.0
var _next_event_time := 0.0
var _last_event_time := 0.0
var _current_event_name := ""
var _bar_flash_timer := 0.0

const EVENT_DISPLAY_TIME := 3.0
const BOSS_WARNING_PULSE_SPEED := 6.0
const BOSS_WARNING_DURATION := 1.2
const BAR_WIDTH := 400.0
const BAR_HEIGHT := 28.0

# Colors
const BAR_BG_COLOR := Color(0.1, 0.1, 0.15, 0.9)
const BAR_FILL_COLOR := Color(0.3, 0.7, 1.0, 1.0)
const BAR_FLASH_COLOR := Color(1.0, 0.9, 0.5, 1.0)
const BAR_BORDER_COLOR := Color(0.4, 0.45, 0.5, 1.0)

# Event schedule for progress calculation
const EVENTS := [
	{"time": 25.0, "name": "HORDE"},
	{"time": 40.0, "name": "ELITE"},
	{"time": 55.0, "name": "HORDE"},
	{"time": 70.0, "name": "ELITE"},
	{"time": 85.0, "name": "HORDE"},
	{"time": 100.0, "name": "ELITE"},
	{"time": 115.0, "name": "HORDE"},
	{"time": 130.0, "name": "ELITE"},
	{"time": 145.0, "name": "HORDE"},
	{"time": 160.0, "name": "ELITE"},
	{"time": 175.0, "name": "HORDE"},
	{"time": 190.0, "name": "ELITE"},
	{"time": 205.0, "name": "HORDE"},
	{"time": 220.0, "name": "ELITE"},
	{"time": 235.0, "name": "HORDE"},
	{"time": 270.0, "name": "BOSS"},
	{"time": 300.0, "name": "VICTORY"},
]

func _ready() -> void:
	_setup_ui()
	_update_next_event(0.0)

func _setup_ui() -> void:
	# Main container at top center
	_progress_container = Control.new()
	_progress_container.name = "ProgressContainer"
	_progress_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_progress_container.position = Vector2(-BAR_WIDTH / 2, 70)
	_progress_container.size = Vector2(BAR_WIDTH, BAR_HEIGHT + 4)
	_progress_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_container)
	
	# Custom progress bar (drawn manually for better visuals)
	_progress_bar = Control.new()
	_progress_bar.name = "ProgressBar"
	_progress_bar.position = Vector2.ZERO
	_progress_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_container.add_child(_progress_bar)
	_progress_bar.draw.connect(_draw_progress_bar)
	
	# Timer label (left side)
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 18)
	_timer_label.add_theme_color_override("font_color", Color.WHITE)
	_timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_timer_label.add_theme_constant_override("shadow_offset_x", 1)
	_timer_label.add_theme_constant_override("shadow_offset_y", 1)
	_timer_label.text = "0:00"
	_timer_label.position = Vector2(10, 0)
	_timer_label.size = Vector2(60, BAR_HEIGHT)
	_progress_container.add_child(_timer_label)
	
	# Wave/event label (right side)
	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 16)
	_wave_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_wave_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_wave_label.add_theme_constant_override("shadow_offset_x", 1)
	_wave_label.add_theme_constant_override("shadow_offset_y", 1)
	_wave_label.text = "NEXT: HORDE"
	_wave_label.position = Vector2(BAR_WIDTH - 130, 0)
	_wave_label.size = Vector2(120, BAR_HEIGHT)
	_progress_container.add_child(_wave_label)
	
	# Event notification (center screen, larger)
	_event_label = Label.new()
	_event_label.name = "EventLabel"
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_event_label.add_theme_font_size_override("font_size", 48)
	_event_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_event_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_event_label.add_theme_constant_override("shadow_offset_x", 3)
	_event_label.add_theme_constant_override("shadow_offset_y", 3)
	_event_label.text = ""
	_event_label.visible = false
	_event_label.set_anchors_preset(Control.PRESET_CENTER)
	_event_label.position = Vector2(-200, -150)
	_event_label.size = Vector2(400, 60)
	add_child(_event_label)
	
	# Boss warning - thin red bar across middle of screen
	# Create a full-screen container first
	var warning_container := Control.new()
	warning_container.name = "WarningContainer"
	warning_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	warning_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(warning_container)
	
	_boss_warning = preload("res://scripts/world/WarningBar.gd").new()
	_boss_warning.name = "BossWarning"
	_boss_warning.visible = false
	warning_container.add_child(_boss_warning)

func _draw_progress_bar() -> void:
	var bar := _progress_bar
	var rect := Rect2(Vector2.ZERO, bar.size)
	
	# Background
	bar.draw_rect(rect, BAR_BG_COLOR)
	
	# Fill based on progress to next event
	var fill_width := rect.size.x * _current_progress
	var fill_rect := Rect2(Vector2.ZERO, Vector2(fill_width, rect.size.y))
	
	# Flash when event triggers
	var fill_color := BAR_FILL_COLOR
	if _bar_flash_timer > 0:
		var flash_t := _bar_flash_timer / 0.5
		fill_color = BAR_FILL_COLOR.lerp(BAR_FLASH_COLOR, flash_t)
	
	bar.draw_rect(fill_rect, fill_color)
	
	# Border
	bar.draw_rect(rect, BAR_BORDER_COLOR, false, 2.0)
	
	# Segment markers for visual interest
	var segment_count := 10
	for i in range(1, segment_count):
		var x := rect.size.x * float(i) / float(segment_count)
		var top := Vector2(x, 0)
		var bottom := Vector2(x, 4)
		bar.draw_line(top, bottom, BAR_BORDER_COLOR, 1.0)
		bar.draw_line(Vector2(x, rect.size.y - 4), Vector2(x, rect.size.y), BAR_BORDER_COLOR, 1.0)

func _process(delta: float) -> void:
	# Smooth progress bar
	_current_progress = lerp(_current_progress, _target_progress, delta * 8.0)
	if _progress_bar:
		_progress_bar.queue_redraw()
	
	# Flash decay
	if _bar_flash_timer > 0:
		_bar_flash_timer -= delta
	
	# Fade out event label
	if _event_label and _event_label.visible:
		_event_fade_timer -= delta
		if _event_fade_timer <= 0:
			_event_label.visible = false
		elif _event_fade_timer < 0.5:
			_event_label.modulate.a = _event_fade_timer * 2.0
	
	# Pulse boss warning
	if _boss_warning and _boss_warning.visible:
		_boss_warning_timer -= delta
		if _boss_warning_timer <= 0:
			_boss_warning.visible = false

func _update_next_event(elapsed: float) -> void:
	# Find the next upcoming event
	for i in range(EVENTS.size()):
		if EVENTS[i]["time"] > elapsed:
			_next_event_time = EVENTS[i]["time"]
			_current_event_name = EVENTS[i]["name"]
			# Find previous event time
			if i > 0:
				_last_event_time = EVENTS[i - 1]["time"]
			else:
				_last_event_time = 0.0
			break
	
	# Update wave label
	if _wave_label:
		_wave_label.text = "NEXT: %s" % _current_event_name

func update_time(elapsed: float, remaining: float) -> void:
	if _timer_label:
		@warning_ignore("integer_division")
		var mins := int(elapsed) / 60
		var secs := int(elapsed) % 60
		# In endless mode (remaining == -1), just show elapsed time
		if remaining < 0:
			_timer_label.text = "%d:%02d ∞" % [mins, secs]
		else:
			_timer_label.text = "%d:%02d" % [mins, secs]
	
	# Calculate progress to next event
	if _next_event_time > _last_event_time:
		var segment_duration := _next_event_time - _last_event_time
		var segment_progress := elapsed - _last_event_time
		_target_progress = clampf(segment_progress / segment_duration, 0.0, 1.0)
	
	# Check if we crossed into a new segment
	if elapsed >= _next_event_time:
		_update_next_event(elapsed)
		_bar_flash_timer = 0.5  # Flash when event triggers
		_target_progress = 0.0
		_current_progress = 0.0

func show_event(event_type: String, _event_data: Dictionary, elapsed_time: float = 0.0) -> void:
	if not _event_label:
		return
	
	# Skip warning bar for the very first wave (at time 0)
	if elapsed_time < 1.0:
		return
	
	var text := ""
	var show_warning_bar := false
	
	match event_type:
		"horde":
			text = "HORDE WAVE"
			show_warning_bar = true
		"elite":
			text = "ELITE ENEMY"
			show_warning_bar = true
		"boss":
			text = "FINAL BOSS"
			show_warning_bar = true
	
	# Show the red warning bar for important events
	if show_warning_bar and _boss_warning:
		_boss_warning.visible = true
		_boss_warning_timer = BOSS_WARNING_DURATION
		if _boss_warning.has_method("start_pulse"):
			_boss_warning.set_warning_text(text)
			_boss_warning.start_pulse(BOSS_WARNING_DURATION)
	
	# Hide the old text label - we're using the warning bar now
	_event_label.visible = false

func show_boss_warning(_time_until: float) -> void:
	if not _boss_warning:
		return
	
	_boss_warning.visible = true
	_boss_warning_timer = BOSS_WARNING_DURATION
	if _boss_warning.has_method("start_pulse"):
		_boss_warning.start_pulse(BOSS_WARNING_DURATION)

func hide_all() -> void:
	if _event_label:
		_event_label.visible = false
	if _boss_warning:
		_boss_warning.visible = false

func update_wave(_wave_number: int) -> void:
	pass  # Wave display is handled by Level.gd via WaveDisplay label in scene