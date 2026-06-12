class_name HazardToggle
extends Button
## Hazard-striped danger toggle (GODDESS FALL): skull icon, red title, small
## description, drawn toggle switch on the right. Reusable for any "arm a
## dangerous protocol" setting.

const UI := preload("res://scripts/ui/UITheme.gd")

@export var title_text := "GODDESS FALL"
@export var desc_text := "Hardcore protocol. She descends."

const STRIPE_WIDTH := 12.0
const SWITCH_SIZE := Vector2(63, 30)
const SWITCH_MARGIN := 24.0

var _title: Label = null


func _ready() -> void:
	toggle_mode = true
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.078, 0.094, 0.122, 0.78)
	normal.border_color = Color(UI.COLOR_DANGER.r, UI.COLOR_DANGER.g, UI.COLOR_DANGER.b, 0.55)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(0)
	var hover := normal.duplicate()
	hover.border_color = Color(UI.COLOR_DANGER.r, UI.COLOR_DANGER.g, UI.COLOR_DANGER.b, 0.85)
	var on_style := StyleBoxFlat.new()
	on_style.bg_color = Color(0.47, 0.04, 0.02, 0.45)
	on_style.border_color = UI.COLOR_DANGER
	on_style.set_border_width_all(1)
	on_style.set_corner_radius_all(0)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", on_style)
	add_theme_stylebox_override("hover_pressed", on_style)
	add_theme_stylebox_override("focus", UI.create_button_style_focus())

	var content := HBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = STRIPE_WIDTH + 18
	content.offset_right = -(SWITCH_SIZE.x + SWITCH_MARGIN + 12)
	content.offset_top = 12
	content.offset_bottom = -12
	content.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.add_theme_constant_override("separation", 14)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	var skull := Label.new()
	skull.text = "☠"
	skull.add_theme_font_size_override("font_size", 33)
	skull.add_theme_color_override("font_color", UI.COLOR_DANGER)
	skull.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skull.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(skull)

	var text_col := VBoxContainer.new()
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.add_theme_constant_override("separation", 1)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(text_col)

	_title = Label.new()
	_title.text = title_text
	_title.add_theme_font_override("font", UI.FONT_BOLD)
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38, 1.0))
	text_col.add_child(_title)

	var desc := Label.new()
	desc.text = desc_text
	desc.add_theme_font_override("font", UI.FONT_MEDIUM)
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	text_col.add_child(desc)

	toggled.connect(_on_toggled)
	resized.connect(queue_redraw)


func _on_toggled(pressed_state: bool) -> void:
	if _title:
		_title.add_theme_color_override("font_color",
			Color.WHITE if pressed_state else Color(1.0, 0.42, 0.38, 1.0))
	queue_redraw()


func _draw() -> void:
	# Hazard stripe bar down the left edge
	var stripe_rect := Rect2(1, 1, STRIPE_WIDTH, size.y - 2)
	draw_rect(stripe_rect, Color(0.08, 0.094, 0.122, 1.0))
	var stripe_step := 21.0
	var dark := Color(0.08, 0.094, 0.122, 1.0)
	var y := -stripe_step
	while y < size.y + stripe_step:
		var quad := PackedVector2Array([
			Vector2(1, y), Vector2(1 + STRIPE_WIDTH, y - STRIPE_WIDTH),
			Vector2(1 + STRIPE_WIDTH, y - STRIPE_WIDTH + stripe_step * 0.5),
			Vector2(1, y + stripe_step * 0.5),
		])
		draw_colored_polygon(quad, UI.COLOR_DANGER)
		y += stripe_step
	draw_rect(Rect2(1, 0, STRIPE_WIDTH, 1), dark)  # keep the border line crisp

	# Toggle switch on the right
	var sw_pos := Vector2(size.x - SWITCH_SIZE.x - SWITCH_MARGIN, (size.y - SWITCH_SIZE.y) * 0.5)
	var frame_color := Color(UI.COLOR_DANGER.r, UI.COLOR_DANGER.g, UI.COLOR_DANGER.b, 0.6)
	draw_rect(Rect2(sw_pos, SWITCH_SIZE), frame_color, false, 1.0)
	var knob_size := Vector2(SWITCH_SIZE.y - 9, SWITCH_SIZE.y - 9)
	var knob_x := sw_pos.x + (SWITCH_SIZE.x - knob_size.x - 4.5) if button_pressed else sw_pos.x + 4.5
	var knob_color := UI.COLOR_DANGER if button_pressed else Color(0.35, 0.39, 0.44, 1.0)
	draw_rect(Rect2(Vector2(knob_x, sw_pos.y + 4.5), knob_size), knob_color)
