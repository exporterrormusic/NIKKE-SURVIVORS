extends Control
class_name ScoreUI
## Score counter UI displayed in top-right corner during gameplay.
## Matches the HoloCure-style HUD aesthetic.

# Styling - matches PlayerHudCluster
const FRAME_BACKGROUND := Color(0.08, 0.08, 0.12, 0.95)
const FRAME_BORDER_COLOR := Color(0.95, 0.95, 1.0, 1.0)
const FRAME_BORDER_WIDTH := 4
const FRAME_CORNER_RADIUS := 8
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const LABEL_COLOR := Color(0.7, 0.75, 0.85, 1.0)
const SCORE_COLOR := Color(1.0, 0.85, 0.25, 1.0)  # Gold/yellow like burst

# Animation
const SCORE_PULSE_SCALE := 1.15
const SCORE_PULSE_DURATION := 0.15

var _panel: Panel
var _score_label: Label
var _title_label: Label
var _current_score: int = 0
var _display_score: int = 0
var _score_tween: Tween = null
var _pulse_tween: Tween = null

func _ready() -> void:
	_build_ui()
	_update_display()
	
	# Start polling GameState for score updates
	set_process(true)

func _process(_delta: float) -> void:
	if GameState:
		var new_score: int = GameState.current_score
		if new_score != _current_score:
			_set_score(new_score)

func _build_ui() -> void:
	# Main container - anchor to top right, below XP bar
	custom_minimum_size = Vector2(180, 70)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -200
	offset_right = -20
	offset_top = 50
	offset_bottom = 120
	
	# Panel background
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _create_panel_style())
	add_child(_panel)
	
	# VBox for content
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_right = -12
	vbox.offset_top = 6
	vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 0)
	_panel.add_child(vbox)
	
	# Title label
	_title_label = Label.new()
	_title_label.text = "SCORE"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.add_theme_color_override("font_color", LABEL_COLOR)
	vbox.add_child(_title_label)
	
	# Score label
	_score_label = Label.new()
	_score_label.text = "0"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 28)
	_score_label.add_theme_color_override("font_color", SCORE_COLOR)
	_score_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_score_label)

func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME_BACKGROUND
	style.border_color = FRAME_BORDER_COLOR
	style.set_border_width_all(FRAME_BORDER_WIDTH)
	style.set_corner_radius_all(FRAME_CORNER_RADIUS)
	return style

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
