extends CanvasLayer
class_name WaveUI

## Wave banner (dark field register, approved mockup docs/mockups/hud_v2.html):
## skewed dark chip at top-center with oblique WAVE text, cyan letter-spaced
## timer, and a slim progress strip along the chip bottom.
## Syncs with WaveDirector's 30-second wave intervals.

const UI := preload("res://scripts/ui/UITheme.gd")
const BracketStyleBoxScript := preload("res://scripts/ui/components/BracketStyleBox.gd")

# UI elements
var _progress_container: Control = null
var _progress_bar: Control = null # Custom drawn progress
var _timer_label: Label = null
var _wave_label: Label = null
var _event_label: Label = null
var _boss_warning: Control = null

# State
var _event_fade_timer := 0.0
var _boss_warning_timer := 0.0
var _current_progress := 0.0
var _target_progress := 0.0
var _current_wave := 0
var _bar_flash_timer := 0.0

# Wave timing - matches WaveDirector SPAWN_BRACKETS
const WAVE_DURATION := 30.0 # Each wave is 30 seconds
const TOTAL_WAVES := 11

const EVENT_DISPLAY_TIME := 3.0
const BOSS_WARNING_PULSE_SPEED := 6.0
const BOSS_WARNING_DURATION := 2.4
const CHIP_WIDTH := 330.0
const CHIP_HEIGHT := 76.0

# Colors
const BAR_BG_COLOR := Color(1, 1, 1, 0.12)
const BAR_FILL_COLOR := Color(0.208, 0.773, 0.949, 0.8)
const BAR_FLASH_COLOR := Color(1.0, 0.9, 0.5, 1.0)


# Local override to ensure UI stays correct even if GameManager flags are flaky
var _goddess_mode_override: bool = false

func set_goddess_mode(enabled: bool) -> void:
	_goddess_mode_override = enabled
	if enabled:
		# Force redraw/update immediately
		if _wave_label:
			_wave_label.text = "DEFEAT THE QUEEN"
			_wave_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		if _timer_label:
			_timer_label.text = "2:55"
			_timer_label.add_theme_color_override("font_color", Color.WHITE)
		if _progress_bar:
			_progress_bar.queue_redraw()


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# Bracket-frame chip at top center (wave text + timer + progress strip) -
	# same corner-bracket vocabulary as the rest of the HUD
	var chip := Panel.new()
	chip.name = "ProgressContainer"
	chip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	chip.position = Vector2(-CHIP_WIDTH / 2, 27)
	chip.size = Vector2(CHIP_WIDTH, CHIP_HEIGHT)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_style = BracketStyleBoxScript.new()
	chip_style.bg_color = Color(0.039, 0.051, 0.071, 0.7)
	chip.add_theme_stylebox_override("panel", chip_style)
	add_child(chip)
	_progress_container = chip

	# Wave text (oblique, upper area of the chip)
	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wave_label.offset_top = 7
	_wave_label.offset_bottom = -32
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_wave_label.add_theme_font_size_override("font_size", 31)
	_wave_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	_wave_label.text = "WAVE 1"
	_progress_container.add_child(_wave_label)

	# Timer (cyan, letter-spaced, below the wave text)
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_timer_label.offset_top = 40
	_timer_label.offset_bottom = -10
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.style_subtitle_label(_timer_label, 16, UI.ACCENT_CYAN)
	_timer_label.text = "0:00"
	_progress_container.add_child(_timer_label)

	# Slim progress strip along the chip bottom
	_progress_bar = Control.new()
	_progress_bar.name = "ProgressBar"
	_progress_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_progress_bar.offset_left = 12
	_progress_bar.offset_right = -12
	_progress_bar.offset_top = -8
	_progress_bar.offset_bottom = -4
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_container.add_child(_progress_bar)
	_progress_bar.draw.connect(_draw_progress_bar)

	# Boss warning - thin red bar across middle of screen
	var warning_container := Control.new()
	warning_container.name = "WarningContainer"
	warning_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	warning_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(warning_container)
	
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
	
	_boss_warning = preload("res://scripts/world/WarningBar.gd").new()
	_boss_warning.name = "BossWarning"
	_boss_warning.visible = false
	warning_container.add_child(_boss_warning)


func _draw_progress_bar() -> void:
	var bar := _progress_bar
	var rect := Rect2(Vector2.ZERO, bar.size)

	# Check mode for colors
	var is_goddess: bool = _goddess_mode_override
	if GameManager and (GameManager.she_descends_mode or GameManager.goddess_fall_mode):
		is_goddess = true

	bar.draw_rect(rect, BAR_BG_COLOR)

	# Fill based on progress within current wave
	var fill_color := BAR_FILL_COLOR
	if is_goddess:
		fill_color = Color(0.91, 0.224, 0.18, 0.9) # Red strip for Goddess mode

	# Flash when wave changes
	if _bar_flash_timer > 0:
		var flash_t := _bar_flash_timer / 0.5
		fill_color = fill_color.lerp(BAR_FLASH_COLOR, flash_t)

	bar.draw_rect(Rect2(Vector2.ZERO, Vector2(rect.size.x * _current_progress, rect.size.y)), fill_color)


func _process(delta: float) -> void:
	# Force override for She Descends mode
	var is_goddess: bool = _goddess_mode_override
	if GameManager and (GameManager.she_descends_mode or GameManager.goddess_fall_mode):
		is_goddess = true
		
	if is_goddess:
		if _wave_label and _wave_label.text != "DEFEAT THE QUEEN":
			_wave_label.text = "DEFEAT THE QUEEN"
			
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
	# Special Countdown for Goddess Fall / She Descends (2:55 = 175s)
	var is_goddess: bool = _goddess_mode_override
	if GameManager and (GameManager.she_descends_mode or GameManager.goddess_fall_mode):
		is_goddess = true

	if is_goddess:
		# Use elapsed to calculate count DOWN from 175s
		var total_duration := 175.0
		var time_left := clampf(total_duration - elapsed, 0.0, total_duration)
		
		@warning_ignore("integer_division")
		var mins := int(time_left) / 60
		var secs := int(time_left) % 60
		
		if _timer_label:
			_timer_label.text = "%d:%02d" % [mins, secs]
			_timer_label.add_theme_color_override("font_color", Color.WHITE)
			
		# Bar empties as time runs out (visual countdown)
		_target_progress = time_left / total_duration
		_current_progress = _target_progress
		if _progress_bar:
			_progress_bar.queue_redraw()
		return
	
	# Wave 12 boss fight: remaining = -1 means endless, show blank timer with full red bar
	if remaining < 0:
		if _timer_label:
			_timer_label.text = "" # Blank timer during boss fight
		# Full red bar (will be colored via is_boss_wave flag)
		_target_progress = 1.0
		return
	
	# Standard Mode: Count UP using elapsed
	@warning_ignore("integer_division")
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	
	if _timer_label:
		_timer_label.text = "%d:%02d" % [mins, secs]
		_timer_label.remove_theme_color_override("font_color")
	
	# Calculate progress within current wave (0.0 to 1.0)
	var time_in_wave := fmod(elapsed, WAVE_DURATION)
	_target_progress = clampf(time_in_wave / WAVE_DURATION, 0.0, 1.0)
	
	# Special case: If exactly at end of wave (e.g. 30.0), fmod gives 0.0
	# We might want it to stay full until wave change triggers reset.
	# But generally it's fine as visual.


func update_wave(wave_number: int) -> void:
	# Called when wave changes
	if wave_number != _current_wave:
		_bar_flash_timer = 0.5 # Flash when wave changes
		_current_progress = 0.0
		_target_progress = 0.0
	
	_current_wave = wave_number
	
	if _wave_label:
		var is_goddess: bool = _goddess_mode_override
		if GameManager and (GameManager.she_descends_mode or GameManager.goddess_fall_mode):
			is_goddess = true
			
		if is_goddess or wave_number == 12:
			# Goddess Fall mode or Wave 12 N01 boss fight
			_wave_label.text = "DEFEAT THE QUEEN"
			_wave_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2)) # Red text
		else:
			_wave_label.text = "WAVE %d" % wave_number
			_wave_label.remove_theme_color_override("font_color")


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
	
	# Helper buffer for text
	var is_she_descends: bool = (GameManager and (GameManager.get("she_descends_mode") or GameManager.get("goddess_fall_mode")))
	var custom_text: String = "ENDGAME"
	
	match event_type:
		"wave":
			# Surpress wave notification in She Descends mode
			if is_she_descends:
				return
			
			# Show wave number (only for wave 2+)
			var wave_num: int = event_data.get("wave", _current_wave)
			text = "WAVE %d" % wave_num
			show_warning_bar = true
		"horde":
			# Horde is just a wave with more enemies (only for wave 2+)
			var wave_num: int = event_data.get("wave", _current_wave)
			text = custom_text if is_she_descends else "WAVE %d" % wave_num
			show_warning_bar = true
		"elite":
			# Elite spawn - still show wave number (only for wave 2+)
			var wave_num: int = event_data.get("wave", _current_wave)
			text = custom_text if is_she_descends else "WAVE %d" % wave_num
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



func set_custom_timer_text(text: String) -> void:
	if _timer_label:
		_timer_label.text = text