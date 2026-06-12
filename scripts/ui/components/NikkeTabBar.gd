class_name NikkeTabBar
extends HBoxContainer
## Skewed NIKKE-style tab rail: dark selected tab with yellow underline,
## light idle tabs. Set `tab_titles` and listen to `tab_changed`.
## With a single tab it renders as a static section header chip.

signal tab_changed(index: int)

const UI := preload("res://scripts/ui/UITheme.gd")
const SKEW := Vector2(-0.105, 0.0)

@export var tab_titles: PackedStringArray = []:
	set(value):
		tab_titles = value
		if is_inside_tree():
			_rebuild()

var selected_index := 0
var _buttons: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_rebuild()


func _rebuild() -> void:
	for btn in _buttons:
		btn.queue_free()
	_buttons.clear()

	for i in tab_titles.size():
		var btn := Button.new()
		btn.text = tab_titles[i]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 51)
		btn.add_theme_font_override("font", UI.FONT_BOLD)
		btn.add_theme_font_size_override("font_size", 19)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_tab(btn)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		add_child(btn)
		_buttons.append(btn)
	_apply_selection()


func _style_tab(btn: Button) -> void:
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0.867, 0.882, 0.902, 1.0)
	idle.set_corner_radius_all(0)
	idle.skew = SKEW
	idle.content_margin_left = 39
	idle.content_margin_right = 39

	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = UI.ADMIN_TEXT
	selected_style.set_corner_radius_all(0)
	selected_style.skew = SKEW
	selected_style.content_margin_left = 39
	selected_style.content_margin_right = 39
	selected_style.border_color = UI.ACCENT_SECONDARY
	selected_style.border_width_bottom = 4

	var hover := idle.duplicate()
	hover.bg_color = Color(0.92, 0.93, 0.945, 1.0)

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


func _on_tab_pressed(index: int) -> void:
	selected_index = index
	_apply_selection()
	tab_changed.emit(index)


func select(index: int) -> void:
	selected_index = clampi(index, 0, _buttons.size() - 1)
	_apply_selection()


func _apply_selection() -> void:
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == selected_index)
