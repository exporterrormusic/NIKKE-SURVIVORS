class_name AchievementRow
extends Button
## Single achievement entry (light admin register): medal diamond (gold ✓ =
## cleared, cyan % = in progress, gray ◆ = untouched), title + description,
## progress gauge for multi-step goals, CLEARED chip. Slightly translucent so
## the category ghost art breathes through. Status accent bar on the left.

const UI := preload("res://scripts/ui/UITheme.gd")

const MEDAL_ZONE := 78.0
const DIAMOND_HALF := 28.0

var title := ""
var description := ""
var unlocked := false
var progress := 0
var target := 1


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.92)
	normal.border_color = UI.ADMIN_HAIRLINE
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(0)
	var hover := normal.duplicate()
	hover.border_color = UI.ACCENT_CYAN
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", normal)
	add_theme_stylebox_override("focus", UI.create_button_style_focus())

	var has_gauge := not unlocked and target > 1
	custom_minimum_size = Vector2(0, 117 if has_gauge else 96)

	var mid := VBoxContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	mid.offset_left = MEDAL_ZONE + 9
	mid.offset_right = -150 if unlocked else -21
	mid.offset_top = 12
	mid.offset_bottom = -12
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 3)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mid)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_override("font", UI.FONT_BOLD)
	title_label.add_theme_font_size_override("font_size", 23)
	title_label.add_theme_color_override("font_color",
		Color(0.173, 0.478, 0.306, 1.0) if unlocked else UI.ADMIN_TEXT)
	title_label.clip_text = true
	mid.add_child(title_label)

	var desc_label := Label.new()
	desc_label.text = description
	desc_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(desc_label)

	if has_gauge:
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 18)
		prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_child(prow)

		var bar := ProgressBar.new()
		bar.max_value = target
		bar.value = progress
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UI.create_gauge_bg_style())
		bar.add_theme_stylebox_override("fill", UI.create_gauge_fill_style(UI.ACCENT_CYAN, false))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prow.add_child(bar)

		var pnum := Label.new()
		pnum.text = "%s / %s" % [_format_number(progress), _format_number(target)]
		pnum.add_theme_font_override("font", UI.FONT_BOLD)
		pnum.add_theme_font_size_override("font_size", 17)
		pnum.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)
		prow.add_child(pnum)


func _draw() -> void:
	# Status accent bar
	var accent := Color("#c4cad1")
	if unlocked:
		accent = UI.COLOR_SUCCESS.darkened(0.15)
	elif progress > 0:
		accent = UI.ACCENT_CYAN
	draw_rect(Rect2(1, 1, 7, size.y - 2), accent)

	# Medal diamond
	var center := Vector2(MEDAL_ZONE * 0.5 + 9, size.y * 0.5)
	var pts := PackedVector2Array([
		center + Vector2(0, -DIAMOND_HALF), center + Vector2(DIAMOND_HALF, 0),
		center + Vector2(0, DIAMOND_HALF), center + Vector2(-DIAMOND_HALF, 0),
	])
	var outline_color := Color("#c4cad1")
	var fill_color := Color(0.949, 0.953, 0.961, 1.0)
	var glyph_color := UI.ADMIN_TEXT_DIM
	var glyph := "◆"
	var glyph_size := 20
	if unlocked:
		fill_color = Color(0.992, 0.769, 0.392, 1.0)
		outline_color = Color(0.788, 0.498, 0.114, 1.0)
		glyph_color = Color(0.478, 0.302, 0.02, 1.0)
		glyph = "✓"
		glyph_size = 24
	elif target > 1 and progress > 0:
		outline_color = UI.ACCENT_CYAN_DEEP
		glyph_color = UI.ACCENT_CYAN_DEEP
		glyph = "%d%%" % roundi(float(progress) / float(target) * 100.0)
		glyph_size = 15
	draw_colored_polygon(pts, fill_color)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, outline_color, 2.5, true)
	var font: Font = UI.FONT_BOLD
	var glyph_width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph_size).x
	draw_string(font, center + Vector2(-glyph_width * 0.5, glyph_size * 0.36), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, glyph_color)

	# CLEARED chip (right side)
	if unlocked:
		var chip_size := Vector2(111, 32)
		var chip_pos := Vector2(size.x - chip_size.x - 21, (size.y - chip_size.y) * 0.5)
		draw_colored_polygon(PackedVector2Array([
			chip_pos, chip_pos + Vector2(chip_size.x, 0),
			chip_pos + Vector2(chip_size.x, chip_size.y - 9),
			chip_pos + Vector2(chip_size.x - 9, chip_size.y),
			chip_pos + Vector2(0, chip_size.y),
		]), UI.COLOR_SUCCESS.darkened(0.15))
		draw_string(font, chip_pos + Vector2(14, 22), "CLEARED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


static func _format_number(value: int) -> String:
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return result
