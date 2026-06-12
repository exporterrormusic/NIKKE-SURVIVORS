class_name CharacterSelectCard
extends Button
## Character select grid card (NIKKE squad-file style, light register):
## white chamfered frame, portrait, name bar, weapon tag. Locked characters
## show a desaturated portrait + core cost. Selection = yellow corner
## brackets + outline. A "random" variant renders the translucent "?" slot.

const UI := preload("res://scripts/ui/UITheme.gd")

signal card_selected(char_id: String)  # char_id == "" for the RANDOM slot

const PORTRAIT_HEIGHT := 201.0

var char_id := ""
var display_name := ""
var weapon_tag := ""
var portrait_texture: Texture2D = null
var is_unlocked := true
var unlock_cost := 0
var is_random := false

var _brackets: Control = null
var _is_selected := false


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)

	_apply_frame_style()
	if is_random:
		_build_random_content()
	else:
		_build_character_content()
	_build_brackets()

	pressed.connect(func(): card_selected.emit(char_id))
	mouse_entered.connect(func(): UI.apply_hover_effect(self))
	mouse_exited.connect(func(): UI.remove_hover_effect(self))
	button_down.connect(func(): UI.apply_press_effect(self))


func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _brackets:
		_brackets.visible = selected


func _apply_frame_style() -> void:
	var frame: StyleBox
	if is_random:
		frame = UI.create_chamfer_card(
			Color(0.176, 0.659, 0.91, 0.8), Color(0.47, 0.82, 0.97, 0.8), 1, 2, 15.0)
	else:
		frame = UI.create_chamfer_card(Color.WHITE, Color(0, 0, 0, 0), 0, 2, 15.0)
	add_theme_stylebox_override("normal", frame)
	add_theme_stylebox_override("hover", frame)
	add_theme_stylebox_override("pressed", frame)
	add_theme_stylebox_override("hover_pressed", frame)
	add_theme_stylebox_override("disabled", frame)
	add_theme_stylebox_override("focus", UI.create_button_style_focus())


func _build_character_content() -> void:
	var portrait := TextureRect.new()
	portrait.texture = portrait_texture
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.set_anchors_preset(Control.PRESET_TOP_WIDE)
	portrait.offset_bottom = PORTRAIT_HEIGHT
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_unlocked:
		portrait.modulate = Color(0.4, 0.4, 0.44, 1.0)
	add_child(portrait)

	var name_lbl := Label.new()
	name_lbl.text = display_name.to_upper()
	name_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_lbl.offset_top = -57  # card height 258 - portrait 201
	name_lbl.offset_left = 4
	name_lbl.offset_right = -16  # keep clear of the chamfer cut
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_override("font", UI.FONT_BOLD)
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", UI.ADMIN_TEXT if is_unlocked else UI.ADMIN_TEXT_DIM)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_lbl)

	var tag := Label.new()
	tag.text = weapon_tag
	tag.position = Vector2(6, 6)
	tag.add_theme_font_override("font", UI.FONT_BOLD)
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color.WHITE)
	var tag_bg := StyleBoxFlat.new()
	tag_bg.bg_color = Color(0, 0, 0, 0.7)
	tag_bg.set_corner_radius_all(0)
	tag_bg.set_content_margin_all(0)
	tag_bg.content_margin_left = 7
	tag_bg.content_margin_right = 7
	tag_bg.content_margin_top = 2
	tag_bg.content_margin_bottom = 2
	var tag_panel := PanelContainer.new()
	tag_panel.add_theme_stylebox_override("panel", tag_bg)
	tag_panel.position = Vector2(6, 6)
	tag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.position = Vector2.ZERO
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_panel.add_child(tag)
	add_child(tag_panel)

	if not is_unlocked:
		_build_lock_overlay()


func _build_lock_overlay() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = PORTRAIT_HEIGHT * 0.36
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var cost := Label.new()
	cost.text = "◆ %d" % unlock_cost
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_override("font", UI.FONT_BOLD)
	cost.add_theme_font_size_override("font_size", 26)
	cost.add_theme_color_override("font_color", Color.WHITE)
	cost.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	cost.add_theme_constant_override("outline_size", 4)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cost)

	var unlock := Label.new()
	unlock.text = "UNLOCK"
	unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.style_subtitle_label(unlock, 12, UI.ACCENT_SECONDARY)
	unlock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	unlock.add_theme_constant_override("outline_size", 4)
	unlock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(unlock)


func _build_random_content() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var q := Label.new()
	q.text = "?"
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_font_override("font", UI.FONT_TITLE)
	q.add_theme_font_size_override("font_size", 56)
	q.add_theme_color_override("font_color", Color.WHITE)
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(q)

	var lbl := Label.new()
	lbl.text = "RANDOM"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.style_subtitle_label(lbl, 15, Color(0.92, 0.97, 1.0, 1.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)


func _build_brackets() -> void:
	_brackets = Control.new()
	_brackets.set_anchors_preset(Control.PRESET_FULL_RECT)
	_brackets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brackets.visible = false
	_brackets.draw.connect(_draw_brackets.bind(_brackets))
	add_child(_brackets)


func _draw_brackets(target: Control) -> void:
	var col := UI.ACCENT_SECONDARY
	var w := target.size.x
	var h := target.size.y
	var arm := 21.0
	var t := 4.0
	# Outline ring 3px outside the card
	target.draw_rect(Rect2(-3, -3, w + 6, h + 6), col, false, 3.0)
	# Top-left bracket
	target.draw_rect(Rect2(-10, -10, arm, t), col)
	target.draw_rect(Rect2(-10, -10, t, arm), col)
	# Bottom-right bracket
	target.draw_rect(Rect2(w + 10 - arm, h + 6, arm, t), col)
	target.draw_rect(Rect2(w + 6, h + 10 - arm, t, arm), col)
