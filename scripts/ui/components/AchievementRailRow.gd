class_name AchievementRailRow
extends Button
## Category rail row for the achievements menu: portrait chip (or crown glyph
## for GENERAL), name, n/m count, and a thin green completion underbar.
## Locked operators render dimmed. Yellow accent when selected.

const UI := preload("res://scripts/ui/UITheme.gd")

@export var category_name := "GENERAL"
@export var portrait: Texture2D = null   # null = GENERAL crown tile
@export var is_locked := false

var _count_label: Label = null
var _underbar_fill: ColorRect = null
var _selected := false


func _ready() -> void:
	text = ""
	custom_minimum_size = Vector2(0, 87)
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
	row.offset_left = 18
	row.offset_right = -18
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(63, 63)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.clip_contents = true
	tile.add_theme_stylebox_override("panel", UI.create_chamfer_card(
		Color(0.133, 0.153, 0.184, 1.0), Color(0, 0, 0, 0), 0,
		ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT, 12.0))
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tile)

	if portrait:
		var tex := TextureRect.new()
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.texture = portrait
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_locked:
			tex.modulate = Color(0.35, 0.35, 0.38, 1.0)
		tile.add_child(tex)
	else:
		var crown := Label.new()
		crown.text = "♕"
		crown.set_anchors_preset(Control.PRESET_FULL_RECT)
		crown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crown.add_theme_font_size_override("font_size", 30)
		crown.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(crown)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 7)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)

	var name_label := Label.new()
	name_label.text = category_name.to_upper()
	name_label.add_theme_font_override("font", UI.FONT_BOLD)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color",
		UI.ADMIN_TEXT_DIM if is_locked else UI.ADMIN_TEXT)
	name_label.clip_text = true
	mid.add_child(name_label)

	var underbar := Panel.new()
	underbar.custom_minimum_size = Vector2(0, 6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.235, 0.275, 0.322, 0.15)
	track.set_corner_radius_all(0)
	underbar.add_theme_stylebox_override("panel", track)
	underbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(underbar)

	_underbar_fill = ColorRect.new()
	_underbar_fill.color = UI.COLOR_SUCCESS.darkened(0.15)
	_underbar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_underbar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underbar.add_child(_underbar_fill)

	_count_label = Label.new()
	_count_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_count_label.add_theme_font_size_override("font_size", 26)
	_count_label.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_count_label)


func set_counts(unlocked: int, total: int) -> void:
	if _count_label:
		_count_label.text = "%d/%d" % [unlocked, total]
		_count_label.add_theme_color_override("font_color",
			UI.COLOR_SUCCESS.darkened(0.2) if (total > 0 and unlocked == total) else UI.ADMIN_TEXT_DIM)
	if _underbar_fill:
		var parent_width: float = _underbar_fill.get_parent().size.x
		var ratio := float(unlocked) / float(maxi(total, 1))
		_underbar_fill.anchor_right = ratio
		_underbar_fill.offset_right = 0


func set_selected(selected: bool) -> void:
	_selected = selected
	queue_redraw()


func _draw() -> void:
	if not _selected:
		return
	draw_rect(Rect2(0, 0, 6, size.y), UI.ACCENT_SECONDARY)
	draw_rect(Rect2(Vector2.ZERO, size), UI.ACCENT_SECONDARY, false, 3.0)
