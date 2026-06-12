extends Control
class_name ScoreUI
## Score counter (dark field register, approved mockup docs/mockups/hud_v2.html):
## frameless letter-spaced SCORE caption over oblique white numerals,
## right-aligned in the bottom-right corner above the core counter.

const UI := preload("res://scripts/ui/UITheme.gd")

# Animation
const SCORE_PULSE_SCALE := 1.15
const SCORE_PULSE_DURATION := 0.15

var _score_label: Label
var _title_label: Label
var _current_score: int = 0
var _display_score: int = 0
var _score_tween: Tween = null
var _pulse_tween: Tween = null
var _fps_label: Label = null

func _ready() -> void:
	_build_ui()
	_update_display()
	
	# Start polling GameManager for score updates
	set_process(true)

func _process(_delta: float) -> void:
	if GameManager:
		var new_score: int = GameManager.current_score
		if new_score != _current_score:
			_set_score(new_score)
	
	# Always update display for FPS counter
	if DebugSettings.show_fps:
		_update_display()

func _build_ui() -> void:
	# Frameless block - anchored bottom right, above the core counter
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -420
	offset_right = -30
	offset_top = -216
	offset_bottom = -126

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# Caption
	_title_label = Label.new()
	_title_label.text = "SCORE"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.style_subtitle_label(_title_label, 14, Color(1, 1, 1, 0.65))
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_title_label.add_theme_constant_override("shadow_offset_x", 1)
	_title_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(_title_label)

	# Score numerals
	_score_label = Label.new()
	_score_label.text = "0"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_score_label.add_theme_font_size_override("font_size", 54)
	_score_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	_score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_score_label.add_theme_constant_override("shadow_offset_x", 2)
	_score_label.add_theme_constant_override("shadow_offset_y", 3)
	_score_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_score_label)

	# FPS Label (just above the score block)
	_fps_label = Label.new()
	_fps_label.text = "FPS: 60"
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_size_override("font_size", 10)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fps_label.position = Vector2(-70, -230)
	add_child(_fps_label)
	_fps_label.visible = false

func _set_score(new_score: int) -> void:
	var old_score := _current_score
	_current_score = new_score
	
	# Animate the score counting up
	if _score_tween and _score_tween.is_running():
		_score_tween.kill()
	
	_score_tween = create_tween()
	_score_tween.set_ease(Tween.EASE_OUT)
	_score_tween.set_trans(Tween.TRANS_CUBIC)
	_score_tween.tween_method(_update_display_score, _display_score, _current_score, 0.3)
	
	# Pulse effect on score increase
	if new_score > old_score:
		_pulse_score()

func _update_display_score(value: int) -> void:
	_display_score = value
	_update_display()

func _update_display() -> void:
	if _score_label:
		_score_label.text = _format_number(_display_score)
	
	# Update FPS label visibility and text
	if _fps_label:
		if DebugSettings.show_fps:
			_fps_label.visible = true
			_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
			
			# Color code FPS
			var fps = Engine.get_frames_per_second()
			if fps >= 55:
				_fps_label.modulate = Color(0.5, 1.0, 0.5, 0.7) # Green
			elif fps >= 30:
				_fps_label.modulate = Color(1.0, 1.0, 0.5, 0.7) # Yellow
			else:
				_fps_label.modulate = Color(1.0, 0.4, 0.4, 0.7) # Red
		else:
			_fps_label.visible = false

func _format_number(value: int) -> String:
	var str_value := str(value)
	var result := ""
	var count := 0
	for i in range(str_value.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_value[i] + result
		count += 1
	return result

func _pulse_score() -> void:
	if _pulse_tween and _pulse_tween.is_running():
		_pulse_tween.kill()
	
	_score_label.pivot_offset = _score_label.size / 2
	
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_score_label, "scale", Vector2.ONE * SCORE_PULSE_SCALE, SCORE_PULSE_DURATION * 0.4).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_score_label, "scale", Vector2.ONE, SCORE_PULSE_DURATION * 0.6).set_ease(Tween.EASE_IN_OUT)
	
	# Brief color flash
	var flash_tween := create_tween()
	flash_tween.tween_property(_score_label, "modulate", Color(1.5, 1.3, 1.0, 1.0), SCORE_PULSE_DURATION * 0.3)
	flash_tween.tween_property(_score_label, "modulate", Color.WHITE, SCORE_PULSE_DURATION * 0.5)

## Manually set the score (for testing or direct control)
func set_score(value: int) -> void:
	_set_score(value)

## Get the current score
func get_score() -> int:
	return _current_score
