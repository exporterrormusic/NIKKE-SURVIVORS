extends CanvasLayer
class_name WaveUI

## Displays combined wave progress bar with timer and wave info
## Syncs with WaveDirector's 30-second wave intervals

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
var _current_wave := 1
var _bar_flash_timer := 0.0

# Wave timing - matches WaveDirector SPAWN_BRACKETS
const WAVE_DURATION := 30.0  # Each wave is 30 seconds
const TOTAL_WAVES := 11

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


func _ready() -> void:
	_setup_ui()


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
	
	# Wave label removed - wave number is shown in warnings instead
	# The progress bar just shows timer on the left
	
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
	
	# Fill based on progress within current wave
	var fill_width := rect.size.x * _current_progress
	var fill_rect := Rect2(Vector2.ZERO, Vector2(fill_width, rect.size.y))
	
	# Flash when wave changes
	var fill_color := BAR_FILL_COLOR
	if _bar_flash_timer > 0:
		var flash_t := _bar_flash_timer / 0.5
		fill_color = BAR_FILL_COLOR.lerp(BAR_FLASH_COLOR, flash_t)
	
	bar.draw_rect(fill_rect, fill_color)
	
	# Border
	bar.draw_rect(rect, BAR_BORDER_COLOR, false, 2.0)
	
	# Segment markers for visual interest (11 segments for 11 waves)
	var segment_count := TOTAL_WAVES
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
	
	# Calculate progress within current wave (0.0 to 1.0)
	# Each wave is WAVE_DURATION seconds
	var wave_start_time := float(_current_wave - 1) * WAVE_DURATION
	var time_in_wave := elapsed - wave_start_time
	_target_progress = clampf(time_in_wave / WAVE_DURATION, 0.0, 1.0)


func update_wave(wave_number: int) -> void:
	# Called when wave changes
	if wave_number != _current_wave:
		_bar_flash_timer = 0.5  # Flash when wave changes
		_current_progress = 0.0
		_target_progress = 0.0
	
	_current_wave = wave_number
	
	if _wave_label:
		_wave_label.text = "WAVE %d" % wave_number


func show_event(event_type: String, event_data: Dictionary, elapsed_time: float = 0.0) -> void:
	if not _event_label:
		return
	
	# Skip warning bar for wave 1 events (game already starts at wave 1)
	if elapsed_time < 25.0:
		# Only show boss warnings during wave 1, skip normal wave warnings
		if event_type not in ["boss", "super_boss"]:
			return
	
	var text := ""
	var show_warning_bar := false
	
	match event_type:
		"wave":
			# Show wave number (only for wave 2+)
			var wave_num: int = event_data.get("wave", _current_wave)
			text = "WAVE %d" % wave_num
			show_warning_bar = true
		"horde":
			# Horde is just a wave with more enemies (only for wave 2+)
			var wave_num: int = event_data.get("wave", _current_wave)
			text = "WAVE %d" % wave_num
			show_warning_bar = true
		"elite":
			# Elite spawn - still show wave number (only for wave 2+)
			var wave_num: int = event_data.get("wave", _current_wave)
			text = "WAVE %d" % wave_num
			show_warning_bar = true
		"boss":
			var boss_name: String = event_data.get("name", "BOSS")
			text = "WARNING: %s INCOMING" % boss_name
			show_warning_bar = true
		"super_boss":
			var boss_name: String = event_data.get("name", "FINAL BOSS")
			text = "WARNING: %s INCOMING" % boss_name
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


func set_custom_timer_text(text: String) -> void:
	if _timer_label:
		_timer_label.text = text