class_name ShopListRow
extends Button
## White admin list row for the supply-terminal shop: flat glyph tile,
## item name, right-aligned level text. Selected = yellow outline + accent
## bar (same selection language as the character cards).

const UI := preload("res://scripts/ui/UITheme.gd")

@export var glyph := "▲"
@export var glyph_tint := Color(1.0, 0.824, 0.247)
@export var item_name := "ATTACK"

var _level_label: Label = null
var _selected := false


func _ready() -> void:
	toggle_mode = false
	text = ""
	custom_minimum_size = Vector2(0, 90)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := UI.create_admin_card_style()
	var hover := UI.create_admin_card_style()
	hover.border_color = UI.ACCENT_CYAN
	hover.set_border_width_all(UI.BORDER_THIN)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", normal)
	add_theme_stylebox_override("focus", UI.create_button_style_focus())

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 21
	row.offset_right = -21
	row.add_theme_constant_override("separation", 21)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(63, 63)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override("panel", UI.create_chamfer_card(
		Color(0.133, 0.153, 0.184, 1.0), Color(0, 0, 0, 0), 0,
		ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 12.0))
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tile)

	var glyph_label := Label.new()
	glyph_label.text = glyph
	glyph_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_label.add_theme_font_size_override("font_size", 30)
	glyph_label.add_theme_color_override("font_color", glyph_tint)
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(glyph_label)

	var name_label := Label.new()
	name_label.text = item_name.to_upper()
	name_label.add_theme_font_override("font", UI.FONT_BOLD)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	_level_label = Label.new()
	_level_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_level_label.add_theme_font_size_override("font_size", 27)
	_level_label.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_level_label)


func set_level_text(value: String) -> void:
	if _level_label:
		_level_label.text = value


func set_selected(selected: bool) -> void:
	_selected = selected
	queue_redraw()


func _draw() -> void:
	if not _selected:
		return
	# Yellow accent bar + outline (selection language shared with char cards)
	draw_rect(Rect2(0, 0, 6, size.y), UI.ACCENT_SECONDARY)
	draw_rect(Rect2(Vector2.ZERO, size), UI.ACCENT_SECONDARY, false, 3.0)
