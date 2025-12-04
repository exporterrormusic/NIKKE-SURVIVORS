extends Control
class_name StageSelector
## Holocure-style stage selector with map preview, modifiers, and animated start button.

signal stage_confirmed(map_id: String, time_id: String)
signal back_requested

const MAPS := ["emerald_fields", "sakura_grove", "ashen_sands", "polar_front"]
const MAP_NAMES := {
	"emerald_fields": "Emerald Fields",
	"sakura_grove": "Sakura Grove", 
	"ashen_sands": "Ashen Sands",
	"polar_front": "Polar Front"
}
const TIMES := ["day", "night"]

var _selected_map: String = "emerald_fields"
var _selected_time: String = "day"

var _preview_rect: TextureRect
var _map_name_lbl: Label
var _modifier_lbl: Label
var _time_btns: Array[Button] = []
var _map_btns: Array[Button] = []
var _start_btn: Button
var _start_tween: Tween

func _ready() -> void:
	_build_ui()
	_update_preview()
	_start_pulse_animation()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.add_theme_constant_override("separation", 24)
	add_child(main)
	
	# Left: Map selection list
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size.x = 200
	main.add_child(left)
	
	var maps_title := Label.new()
	maps_title.text = "SELECT STAGE"
	maps_title.add_theme_font_size_override("font_size", 20)
	maps_title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	left.add_child(maps_title)
	
	for map_id in MAPS:
		var btn := _create_map_button(map_id)
		left.add_child(btn)
		_map_btns.append(btn)
	
	var sep := HSeparator.new()
	left.add_child(sep)
	
	var time_title := Label.new()
	time_title.text = "TIME OF DAY"
	time_title.add_theme_font_size_override("font_size", 16)
	time_title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	left.add_child(time_title)
	
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	left.add_child(time_row)
	
	for time_id in TIMES:
		var btn := _create_time_button(time_id)
		time_row.add_child(btn)
		_time_btns.append(btn)
	
	# Center: Preview
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 12)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(center)
	
	var preview_panel := Panel.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	preview_style.border_color = Color(0.4, 0.45, 0.55, 0.8)
	preview_style.set_border_width_all(3)
	preview_style.set_corner_radius_all(10)
	preview_panel.add_theme_stylebox_override("panel", preview_style)
	center.add_child(preview_panel)
	
	_preview_rect = TextureRect.new()
	_preview_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_rect.offset_left = 8
	_preview_rect.offset_right = -8
	_preview_rect.offset_top = 8
	_preview_rect.offset_bottom = -8
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_panel.add_child(_preview_rect)
	
	_map_name_lbl = Label.new()
	_map_name_lbl.add_theme_font_size_override("font_size", 28)
	_map_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	_map_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_map_name_lbl)
	
	_modifier_lbl = Label.new()
	_modifier_lbl.add_theme_font_size_override("font_size", 14)
	_modifier_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_modifier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_modifier_lbl)
	
	# Right: Start button
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.custom_minimum_size.x = 180
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(right)
	
	_start_btn = Button.new()
	_start_btn.text = "MISSION\nSTART"
	_start_btn.custom_minimum_size = Vector2(160, 100)
	_start_btn.add_theme_font_size_override("font_size", 24)
	_apply_start_button_style()
	_start_btn.pressed.connect(_on_start_pressed)
	right.add_child(_start_btn)
	
	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(160, 50)
	_apply_back_button_style(back_btn)
	back_btn.pressed.connect(func(): back_requested.emit())
	right.add_child(back_btn)

func _create_map_button(map_id: String) -> Button:
	var btn := Button.new()
	btn.text = MAP_NAMES.get(map_id, map_id)
	btn.custom_minimum_size = Vector2(180, 40)
	btn.toggle_mode = true
	btn.button_pressed = (map_id == _selected_map)
	btn.add_theme_font_size_override("font_size", 16)
	_apply_map_button_style(btn)
	btn.pressed.connect(_on_map_selected.bind(map_id))
	return btn

func _create_time_button(time_id: String) -> Button:
	var btn := Button.new()
	btn.text = time_id.capitalize()
	btn.custom_minimum_size = Vector2(80, 36)
	btn.toggle_mode = true
	btn.button_pressed = (time_id == _selected_time)
	btn.add_theme_font_size_override("font_size", 14)
	_apply_time_button_style(btn, time_id)
	btn.pressed.connect(_on_time_selected.bind(time_id))
	return btn

func _apply_map_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.1, 0.14, 0.95)
	normal.border_color = Color(0.35, 0.4, 0.5, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.15, 0.2, 0.28, 1.0)
	pressed.border_color = Color(0.95, 0.95, 0.98)
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))

func _apply_time_button_style(btn: Button, time_id: String) -> void:
	var color := Color(1.0, 0.85, 0.4) if time_id == "day" else Color(0.4, 0.5, 0.9)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.1, 0.14, 0.95)
	normal.border_color = color.darkened(0.3)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)
	
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.5)
	pressed.border_color = color
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	btn.add_theme_color_override("font_color", color.lightened(0.2))

func _apply_start_button_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.7, 0.4, 1.0)
	normal.border_color = Color(0.4, 1.0, 0.6)
	normal.set_border_width_all(4)
	normal.set_corner_radius_all(12)
	normal.shadow_color = Color(0.2, 0.8, 0.4, 0.4)
	normal.shadow_size = 8
	_start_btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.8, 0.5, 1.0)
	hover.border_color = Color(0.5, 1.0, 0.7)
	hover.set_border_width_all(4)
	hover.set_corner_radius_all(12)
	hover.shadow_size = 12
	_start_btn.add_theme_stylebox_override("hover", hover)
	
	_start_btn.add_theme_color_override("font_color", Color.WHITE)

func _apply_back_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.12, 0.16, 0.95)
	normal.border_color = Color(0.4, 0.4, 0.5, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

func _start_pulse_animation() -> void:
	if _start_tween:
		_start_tween.kill()
	_start_tween = create_tween().set_loops()
	_start_tween.tween_property(_start_btn, "scale", Vector2(1.03, 1.03), 0.6).set_trans(Tween.TRANS_SINE)
	_start_tween.tween_property(_start_btn, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

func _on_map_selected(map_id: String) -> void:
	_selected_map = map_id
	for i in _map_btns.size():
		_map_btns[i].button_pressed = (MAPS[i] == map_id)
	_update_preview()

func _on_time_selected(time_id: String) -> void:
	_selected_time = time_id
	for i in _time_btns.size():
		_time_btns[i].button_pressed = (TIMES[i] == time_id)
	_update_preview()

func _update_preview() -> void:
	_map_name_lbl.text = MAP_NAMES.get(_selected_map, _selected_map)
	
	var time_str := "Day" if _selected_time == "day" else "Night"
	_modifier_lbl.text = time_str + " • Standard Mode"
	
	# Try to load a preview image
	var preview_path := "res://assets/backgrounds/%s.jpg" % _selected_map
	if ResourceLoader.exists(preview_path):
		_preview_rect.texture = load(preview_path)
	else:
		_preview_rect.texture = null

func _on_start_pressed() -> void:
	stage_confirmed.emit(_selected_map, _selected_time)
