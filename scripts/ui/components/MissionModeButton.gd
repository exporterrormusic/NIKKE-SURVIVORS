class_name MissionModeButton
extends Button
## Mission mode card (STANDARD / ENDLESS) for the mission select: dark glass
## chamfered slab, oblique title + small description, cyan accent when
## selected. Toggle button - put instances in a ButtonGroup for radio behavior.

const UI := preload("res://scripts/ui/UITheme.gd")

@export var title_text := "STANDARD":
	set(value):
		title_text = value
		if _title:
			_title.text = value
@export_multiline var desc_text := "":
	set(value):
		desc_text = value
		if _desc:
			_desc.text = value

var _title: Label = null
var _desc: Label = null


func _ready() -> void:
	toggle_mode = true
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := UI.create_chamfer_card(
		Color(0.078, 0.094, 0.122, 0.78), Color(1, 1, 1, 0.18), 1, ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 18.0)
	var hover := UI.create_chamfer_card(
		Color(0.11, 0.13, 0.165, 0.85), Color(1, 1, 1, 0.32), 1, ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 18.0)
	var selected_style := UI.create_chamfer_card(
		Color(0.122, 0.561, 0.878, 0.28), UI.ACCENT_CYAN, 1, ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 18.0)
	selected_style.set("accent_color", UI.ACCENT_CYAN)
	selected_style.set("accent_width", 4.0)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", selected_style)
	add_theme_stylebox_override("hover_pressed", selected_style)
	add_theme_stylebox_override("focus", UI.create_button_style_focus())

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 27
	content.offset_right = -24
	content.offset_top = 16
	content.offset_bottom = -16
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	_title = Label.new()
	_title.text = title_text
	_title.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	content.add_child(_title)

	_desc = Label.new()
	_desc.text = desc_text
	_desc.add_theme_font_override("font", UI.FONT_MEDIUM)
	_desc.add_theme_font_size_override("font_size", 16)
	_desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_desc)

	toggled.connect(_on_toggled)
	_on_toggled(button_pressed)


func _on_toggled(pressed_state: bool) -> void:
	if _title:
		_title.add_theme_color_override("font_color",
			UI.ACCENT_CYAN if pressed_state else UI.TEXT_PRIMARY)
