class_name NikkeSegmentToggle
extends HBoxContainer
## Two-cell segmented ON/OFF switch (light admin register): selected cell is
## charcoal with white text, idle cell is white with dim text. One click,
## state always visible. Emits toggled_changed(bool).

signal toggled_changed(value: bool)

const UI := preload("res://scripts/ui/UITheme.gd")

@export var on_text := "ON"
@export var off_text := "OFF"
@export var value := true:
	set(new_value):
		value = new_value
		_apply()

var _on_btn: Button = null
var _off_btn: Button = null


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_on_btn = _make_cell(on_text, true)
	_off_btn = _make_cell(off_text, false)
	_apply()


func _make_cell(label: String, cell_value: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0, 60)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", UI.FONT_BOLD)
	btn.add_theme_font_size_override("font_size", 19)

	var idle := StyleBoxFlat.new()
	idle.bg_color = Color.WHITE
	idle.border_color = Color(0.784, 0.804, 0.827, 1.0)
	idle.set_border_width_all(1)
	idle.set_corner_radius_all(0)
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = UI.ADMIN_TEXT
	selected_style.set_corner_radius_all(0)
	var hover := idle.duplicate()
	hover.border_color = UI.ACCENT_CYAN_DEEP

	btn.add_theme_stylebox_override("normal", idle)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", selected_style)
	btn.add_theme_stylebox_override("hover_pressed", selected_style)
	btn.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	btn.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", UI.ADMIN_TEXT)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", UI.ADMIN_TEXT_DIM)

	btn.pressed.connect(func():
		if value != cell_value:
			value = cell_value
			toggled_changed.emit(value)
		else:
			_apply()  # re-press of the active cell: keep it pressed
	)
	add_child(btn)
	return btn


func _apply() -> void:
	if _on_btn:
		_on_btn.set_pressed_no_signal(value)
	if _off_btn:
		_off_btn.set_pressed_no_signal(not value)
