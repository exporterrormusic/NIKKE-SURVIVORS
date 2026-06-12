class_name PauseCommandButton
extends Button
## Command slab for the pause/results overlays (dark field register): chamfered
## dark glass with an oblique title, optional right-aligned key hint.
## Styles: "default" (dark glass), "primary" (solid cyan CTA), "danger" (red).

const UI := preload("res://scripts/ui/UITheme.gd")

@export var command_style: String = "default"
@export var title_text: String = "":
	set(value):
		title_text = value
		if _title:
			_title.text = value
@export var key_hint: String = ""

var _title: Label = null


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var title_color := UI.TEXT_PRIMARY
	match command_style:
		"primary":
			custom_minimum_size.y = maxf(custom_minimum_size.y, 96)
			add_theme_stylebox_override("normal", UI.create_chamfer_card(
				UI.ACCENT_CYAN, UI.ACCENT_CYAN_DEEP, 0, ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
			add_theme_stylebox_override("hover", UI.create_chamfer_card(
				UI.ACCENT_CYAN_BRIGHT, UI.ACCENT_CYAN_DEEP, 0, ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
			add_theme_stylebox_override("pressed", UI.create_chamfer_card(
				UI.ACCENT_CYAN_DEEP, UI.ACCENT_CYAN_DEEP, 0, ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
			title_color = Color.WHITE
		"danger":
			custom_minimum_size.y = maxf(custom_minimum_size.y, 87)
			add_theme_stylebox_override("normal", UI.create_chamfer_card(
				Color(0.3, 0.035, 0.02, 0.6), Color(0.91, 0.224, 0.18, 0.55), 1,
				ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
			add_theme_stylebox_override("hover", UI.create_chamfer_card(
				Color(0.38, 0.05, 0.03, 0.7), UI.COLOR_DANGER, 1,
				ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
			add_theme_stylebox_override("pressed", UI.create_chamfer_card(
				Color(0.46, 0.06, 0.04, 0.8), UI.COLOR_DANGER, 1,
				ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
			title_color = Color(1.0, 0.55, 0.52, 1.0)
		_:
			custom_minimum_size.y = maxf(custom_minimum_size.y, 87)
			add_theme_stylebox_override("normal", UI.create_chamfer_card(
				Color(0.078, 0.094, 0.122, 0.86), Color(1, 1, 1, 0.18), 1,
				ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
			add_theme_stylebox_override("hover", UI.create_chamfer_card(
				Color(0.11, 0.13, 0.165, 0.9), UI.ACCENT_CYAN, 1,
				ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
			add_theme_stylebox_override("pressed", UI.create_chamfer_card(
				Color(0.122, 0.561, 0.878, 0.28), UI.ACCENT_CYAN, 1,
				ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 20.0))
	add_theme_stylebox_override("hover_pressed",
		get_theme_stylebox("pressed"))
	add_theme_stylebox_override("focus", UI.create_button_style_focus())

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 33
	row.offset_right = -33
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_title = Label.new()
	_title.text = title_text
	_title.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_title.add_theme_font_size_override("font_size", 36 if command_style == "primary" else 33)
	_title.add_theme_color_override("font_color", title_color)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)

	if key_hint != "":
		var hint := Label.new()
		hint.text = key_hint
		UI.style_subtitle_label(hint, 16, Color(1, 1, 1, 0.4) if command_style == "primary" else Color(1, 1, 1, 0.35))
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.size_flags_vertical = Control.SIZE_FILL
		row.add_child(hint)
