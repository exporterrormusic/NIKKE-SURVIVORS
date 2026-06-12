class_name CategoryRailButton
extends Button
## Vertical category-rail entry (light admin register): oblique title +
## tiny letter-spaced descriptor, yellow accent bar + outline when selected.
## Used by the settings menu rail; generic enough for future railed screens.

const UI := preload("res://scripts/ui/UITheme.gd")

@export var title_text := "AUDIO"
@export var desc_text := "VOLUME MIX"

var _selected := false


func _ready() -> void:
	toggle_mode = false
	text = ""
	custom_minimum_size = Vector2(0, 96)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := UI.create_admin_card_style()
	var hover := UI.create_admin_card_style()
	hover.border_color = UI.ACCENT_CYAN
	hover.set_border_width_all(UI.BORDER_THIN)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", normal)
	add_theme_stylebox_override("focus", UI.create_button_style_focus())

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 30
	col.offset_right = -20
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	title.add_theme_font_size_override("font_size", 33)
	title.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	col.add_child(title)

	var desc := Label.new()
	desc.text = desc_text
	UI.style_subtitle_label(desc, 14, UI.ADMIN_TEXT_DIM)
	col.add_child(desc)


func set_selected(selected: bool) -> void:
	_selected = selected
	queue_redraw()


func _draw() -> void:
	if not _selected:
		return
	draw_rect(Rect2(0, 0, 6, size.y), UI.ACCENT_SECONDARY)
	draw_rect(Rect2(Vector2.ZERO, size), UI.ACCENT_SECONDARY, false, 3.0)
