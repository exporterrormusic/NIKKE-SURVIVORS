extends Control
class_name StageSelector
## Holocure-style stage selector with fixed stages, preview, and animated start button.

signal stage_confirmed(stage_id: String)
signal back_requested

var _selected_stage_id: String = "stage_1"
var _stage_cards: Array[Control] = []
var _selected_map_index: int = 0
var _updating_selection: bool = false  # Prevent recursive toggled signals

# Map definitions - biome/time combinations with display names
const MAPS := [
	{"id": "sakura_day", "name": "Ark Outskirts", "subtitle": "Day", "biome": "sakura_grove", "time": "day", "preview": "res://assets/backgrounds/forest.jpg"},
	{"id": "sakura_night", "name": "Ark Outskirts", "subtitle": "Night", "biome": "sakura_grove", "time": "night", "preview": "res://assets/backgrounds/rapturefield2.jpg"},
	{"id": "snow_day", "name": "The Frozen North", "subtitle": "Day", "biome": "snowfield", "time": "day", "preview": "res://assets/backgrounds/snow-day.jpg"},
	{"id": "snow_night", "name": "The Frozen North", "subtitle": "Night", "biome": "snowfield", "time": "night", "preview": "res://assets/backgrounds/snow-night.jpg"},
]

var _preview_rect: TextureRect
var _stage_name_lbl: Label
var _modifier_lbl: Label
var _map_left_btn: Button
var _map_right_btn: Button
var _start_btn: Button
var _start_tween: Tween
var _difficulty_slider: HSlider
var _difficulty_label: Label
var _goddess_fall_btn: Button

func _ready() -> void:
	_build_ui()
	_select_first_unlocked()
	_start_pulse_animation()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

func _select_first_unlocked() -> void:
	# Select the first unlocked stage
	for stage in StageRegistry.STAGES:
		if GameState.is_stage_unlocked(stage.id):
			_selected_stage_id = stage.id
			break
	_update_selection()

func _build_ui() -> void:
	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.add_theme_constant_override("separation", 20)
	add_child(main)
	
	# LEFT SIDE: Modifiers section (expanded to fill space)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	main.add_child(left)
	
	# Stylish section header - LARGE
	var header_panel := Panel.new()
	header_panel.custom_minimum_size = Vector2(0, 100)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.06, 0.05, 0.1, 0.95)
	header_style.border_color = Color(0.5, 0.4, 0.7, 0.9)
	header_style.set_border_width_all(3)
	header_style.set_corner_radius_all(12)
	header_style.shadow_color = Color(0.4, 0.2, 0.6, 0.3)
	header_style.shadow_size = 6
	header_panel.add_theme_stylebox_override("panel", header_style)
	left.add_child(header_panel)
	
	var stages_title := Label.new()
	stages_title.text = "⚔  MODIFIERS  ⚔"
	stages_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	stages_title.add_theme_font_size_override("font_size", 42)
	stages_title.add_theme_color_override("font_color", Color(0.95, 0.9, 1.0))
	stages_title.add_theme_color_override("font_shadow_color", Color(0.4, 0.2, 0.6, 0.8))
	stages_title.add_theme_constant_override("shadow_offset_x", 3)
	stages_title.add_theme_constant_override("shadow_offset_y", 3)
	stages_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stages_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_panel.add_child(stages_title)
	
	# Modifier buttons - large vertical cards
	var modifier_container := VBoxContainer.new()
	modifier_container.add_theme_constant_override("separation", 10)
	modifier_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(modifier_container)
	
	for stage in StageRegistry.STAGES:
		var card := _create_modifier_button(stage)
		modifier_container.add_child(card)
		_stage_cards.append(card)
	
	# Red sci-fi divider before Goddess Fall
	var divider := _create_danger_divider()
	modifier_container.add_child(divider)
	
	# Goddess Fall as the last modifier card
	var goddess_card := _create_goddess_fall_card()
	modifier_container.add_child(goddess_card)
	
	# RIGHT SIDE: Preview + Difficulty + Buttons
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.2
	main.add_child(right)
	
	# Preview panel container - holds preview + overlay banner
	var preview_container := Control.new()
	preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(preview_container)
	
	# Preview panel
	var preview_panel := Panel.new()
	preview_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	preview_style.border_color = Color(0.4, 0.45, 0.55, 0.8)
	preview_style.set_border_width_all(3)
	preview_style.set_corner_radius_all(10)
	preview_panel.add_theme_stylebox_override("panel", preview_style)
	preview_container.add_child(preview_panel)
	
	_preview_rect = TextureRect.new()
	_preview_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_rect.offset_left = 4
	_preview_rect.offset_right = -4
	_preview_rect.offset_top = 4
	_preview_rect.offset_bottom = -4
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview_panel.add_child(_preview_rect)
	
	# Banner overlay on bottom 20% of preview
	var banner := Panel.new()
	banner.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	banner.anchor_top = 0.8
	banner.offset_left = 4
	banner.offset_right = -4
	banner.offset_top = 0
	banner.offset_bottom = -4
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	banner_style.border_color = Color(0.8, 0.6, 0.2, 0.9)
	banner_style.border_width_top = 2
	banner_style.border_width_bottom = 0
	banner_style.border_width_left = 0
	banner_style.border_width_right = 0
	banner_style.set_corner_radius_all(0)
	banner_style.corner_radius_bottom_left = 8
	banner_style.corner_radius_bottom_right = 8
	banner.add_theme_stylebox_override("panel", banner_style)
	preview_panel.add_child(banner)
	
	# Banner content - horizontal layout with arrows
	var banner_hbox := HBoxContainer.new()
	banner_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_hbox.offset_left = 8
	banner_hbox.offset_right = -8
	banner_hbox.offset_top = 4
	banner_hbox.offset_bottom = -4
	banner_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(banner_hbox)
	
	# Left arrow button
	_map_left_btn = Button.new()
	_map_left_btn.text = "◀"
	_map_left_btn.custom_minimum_size = Vector2(50, 0)
	_map_left_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_arrow_button_style(_map_left_btn)
	_map_left_btn.pressed.connect(_on_map_prev)
	banner_hbox.add_child(_map_left_btn)
	
	# Center text container
	var banner_center := VBoxContainer.new()
	banner_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_center.add_theme_constant_override("separation", 0)
	banner_center.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_hbox.add_child(banner_center)
	
	_stage_name_lbl = Label.new()
	_stage_name_lbl.add_theme_font_size_override("font_size", 36)
	_stage_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_stage_name_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_stage_name_lbl.add_theme_constant_override("shadow_offset_x", 3)
	_stage_name_lbl.add_theme_constant_override("shadow_offset_y", 3)
	_stage_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_center.add_child(_stage_name_lbl)
	
	_modifier_lbl = Label.new()
	_modifier_lbl.add_theme_font_size_override("font_size", 18)
	_modifier_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_modifier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_center.add_child(_modifier_lbl)
	
	# Right arrow button
	_map_right_btn = Button.new()
	_map_right_btn.text = "▶"
	_map_right_btn.custom_minimum_size = Vector2(50, 0)
	_map_right_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_arrow_button_style(_map_right_btn)
	_map_right_btn.pressed.connect(_on_map_next)
	banner_hbox.add_child(_map_right_btn)
	
	# Difficulty panel - compact horizontal layout
	var diff_panel := Panel.new()
	diff_panel.custom_minimum_size.y = 70
	var diff_style := StyleBoxFlat.new()
	diff_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	diff_style.border_color = Color(0.4, 0.45, 0.55, 0.8)
	diff_style.set_border_width_all(2)
	diff_style.set_corner_radius_all(8)
	diff_panel.add_theme_stylebox_override("panel", diff_style)
	right.add_child(diff_panel)
	
	# Horizontal layout: Labels | Slider | Value
	var diff_hbox := HBoxContainer.new()
	diff_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	diff_hbox.offset_left = 12
	diff_hbox.offset_right = -12
	diff_hbox.offset_top = 8
	diff_hbox.offset_bottom = -8
	diff_hbox.add_theme_constant_override("separation", 12)
	diff_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_panel.add_child(diff_hbox)
	
	# Left side: Title and description stacked vertically
	var diff_labels := VBoxContainer.new()
	diff_labels.add_theme_constant_override("separation", 0)
	diff_labels.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_labels.custom_minimum_size.x = 100
	diff_hbox.add_child(diff_labels)
	
	var diff_title := Label.new()
	diff_title.text = "DIFFICULTY"
	diff_title.add_theme_font_size_override("font_size", 14)
	diff_title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	diff_labels.add_child(diff_title)
	
	var diff_desc := Label.new()
	diff_desc.text = "HP & Core Drops"
	diff_desc.add_theme_font_size_override("font_size", 9)
	diff_desc.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	diff_labels.add_child(diff_desc)
	
	# Center: Big, easy-to-click slider
	_difficulty_slider = HSlider.new()
	_difficulty_slider.min_value = 1
	_difficulty_slider.max_value = 100
	_difficulty_slider.value = GameState.difficulty_multiplier
	_difficulty_slider.step = 1
	_difficulty_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_difficulty_slider.custom_minimum_size = Vector2(150, 32)
	_apply_slider_style(_difficulty_slider)
	_difficulty_slider.value_changed.connect(_on_difficulty_changed)
	diff_hbox.add_child(_difficulty_slider)
	
	# Right side: Large value display
	_difficulty_label = Label.new()
	_difficulty_label.text = "x%d" % GameState.difficulty_multiplier
	_difficulty_label.add_theme_font_size_override("font_size", 24)
	_difficulty_label.add_theme_color_override("font_color", _get_difficulty_color(GameState.difficulty_multiplier))
	_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_label.custom_minimum_size.x = 60
	diff_hbox.add_child(_difficulty_label)
	
	# Buttons row: Back (left) | Start (right)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(btn_row)
	
	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(140, 55)
	_apply_back_button_style(back_btn)
	back_btn.pressed.connect(func(): back_requested.emit())
	btn_row.add_child(back_btn)
	
	_start_btn = Button.new()
	_start_btn.text = "MISSION START"
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn.custom_minimum_size = Vector2(200, 55)
	_start_btn.add_theme_font_size_override("font_size", 20)
	_apply_start_button_style()
	_start_btn.pressed.connect(_on_start_pressed)
	# Set pivot to center for proper scaling animation
	_start_btn.pivot_offset = _start_btn.custom_minimum_size / 2.0
	btn_row.add_child(_start_btn)

func _on_difficulty_changed(value: float) -> void:
	GameState.difficulty_multiplier = int(value)
	_difficulty_label.text = "x%d" % int(value)
	_difficulty_label.add_theme_color_override("font_color", _get_difficulty_color(int(value)))

func _on_goddess_fall_toggled(pressed: bool) -> void:
	GameState.goddess_fall_mode = pressed

func _get_difficulty_color(value: int) -> Color:
	if value <= 1:
		return Color(0.7, 0.75, 0.85)  # Grey/white for normal
	elif value <= 10:
		return Color(0.4, 0.9, 0.5)  # Green for easy boost
	elif value <= 25:
		return Color(1.0, 0.85, 0.3)  # Yellow for medium
	elif value <= 50:
		return Color(1.0, 0.5, 0.2)  # Orange for hard
	else:
		return Color(1.0, 0.2, 0.2)  # Red for extreme

# Modifier button definitions with icons and colors
const MODIFIER_STYLES := {
	"stage_1": {"icon": "⚔", "color": Color(0.3, 0.7, 0.4), "title": "STANDARD"},
	"stage_2": {"icon": "👑", "color": Color(0.9, 0.6, 0.2), "title": "ELITE HUNT"},
	"stage_3": {"icon": "∞", "color": Color(0.6, 0.4, 0.9), "title": "ENDLESS"},
}

func _create_modifier_button(stage: Dictionary) -> Button:
	var is_unlocked: bool = GameState.is_stage_unlocked(stage.id)
	var style_info: Dictionary = MODIFIER_STYLES.get(stage.id, {"icon": "?", "color": Color.WHITE, "title": "???"})
	
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = (_selected_stage_id == stage.id)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 100)
	btn.set_meta("stage_id", stage.id)
	
	# Apply styles based on unlock state
	_apply_modifier_card_style(btn, style_info.color, is_unlocked)
	
	if is_unlocked:
		btn.toggled.connect(_on_modifier_toggled.bind(stage.id))
	else:
		btn.disabled = true
	
	# Button content - horizontal layout with icon, title, description
	btn.text = ""
	
	var content := HBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20
	content.offset_right = -20
	content.offset_top = 16
	content.offset_bottom = -16
	content.add_theme_constant_override("separation", 20)
	content.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(content)
	
	# Icon on the left
	var icon_lbl := Label.new()
	icon_lbl.text = style_info.icon if is_unlocked else "🔒"
	icon_lbl.add_theme_font_size_override("font_size", 42)
	icon_lbl.add_theme_color_override("font_color", style_info.color if is_unlocked else Color(0.4, 0.4, 0.45))
	icon_lbl.custom_minimum_size.x = 60
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_lbl)
	
	# Text content on the right
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 6)
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(text_vbox)
	
	# Title
	var title := Label.new()
	title.text = style_info.title if is_unlocked else "???"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", style_info.color if is_unlocked else Color(0.4, 0.4, 0.45))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(title)
	
	# Description
	var desc := Label.new()
	desc.text = stage.get("description", "") if is_unlocked else "Clear previous stage to unlock"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75) if is_unlocked else Color(0.35, 0.35, 0.4))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(desc)
	
	return btn


func _create_danger_divider() -> Control:
	# Simple subtle divider line
	var container := Control.new()
	container.custom_minimum_size = Vector2(0, 16)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Thin subtle grey line
	var line := ColorRect.new()
	line.set_anchors_preset(Control.PRESET_CENTER)
	line.anchor_left = 0.1
	line.anchor_right = 0.9
	line.offset_top = -1
	line.offset_bottom = 1
	line.color = Color(0.4, 0.4, 0.45, 0.5)
	container.add_child(line)
	
	return container


func _create_goddess_fall_card() -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = GameState.goddess_fall_mode
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 100)
	btn.set_meta("stage_id", "goddess_fall")
	btn.clip_contents = true
	_goddess_fall_btn = btn
	
	# Red/danger color scheme with glowing red background
	var accent_color := Color(1.0, 0.3, 0.3)
	_apply_goddess_fall_style(btn, accent_color)
	btn.toggled.connect(_on_goddess_fall_toggled)
	
	# Diagonal warning stripes overlay (behind content)
	var stripes := Control.new()
	stripes.set_anchors_preset(Control.PRESET_FULL_RECT)
	stripes.set_script(preload("res://scripts/ui/components/DiagonalStripes.gd"))
	stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(stripes)
	
	# Hologram scanline overlay
	var scanlines := Control.new()
	scanlines.set_anchors_preset(Control.PRESET_FULL_RECT)
	scanlines.set_script(preload("res://scripts/ui/components/HologramScanlines.gd"))
	scanlines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(scanlines)
	
	# Button content
	btn.text = ""
	
	var content := HBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20
	content.offset_right = -20
	content.offset_top = 16
	content.offset_bottom = -16
	content.add_theme_constant_override("separation", 20)
	content.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(content)
	
	# Icon
	var icon_lbl := Label.new()
	icon_lbl.text = "☠"
	icon_lbl.add_theme_font_size_override("font_size", 42)
	icon_lbl.add_theme_color_override("font_color", accent_color)
	icon_lbl.custom_minimum_size.x = 60
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_lbl)
	
	# Text content
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 4)
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(text_vbox)
	
	var title := Label.new()
	title.text = "GODDESS FALL"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", accent_color)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(title)
	
	var desc := Label.new()
	desc.text = "Tanks fire missiles, elites get lasers, bosses enrage after 60s!"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.8, 0.6, 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(desc)
	
	return btn


func _apply_goddess_fall_style(btn: Button, _accent_color: Color) -> void:
	# Red danger background with glow effect like the divider
	var danger_bg := Color(0.15, 0.04, 0.04, 0.98)
	var glow_color := Color(1.0, 0.1, 0.1, 0.5)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = danger_bg
	normal.border_color = Color(1.0, 0.2, 0.2, 0.7)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.shadow_color = glow_color
	normal.shadow_size = 6
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.2, 0.06, 0.06, 0.98)
	hover.border_color = Color(1.0, 0.3, 0.3, 0.9)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(10)
	hover.shadow_color = Color(1.0, 0.15, 0.15, 0.6)
	hover.shadow_size = 10
	btn.add_theme_stylebox_override("hover", hover)
	
	# Pressed/toggled-on state - intense glowing effect
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.3, 0.08, 0.08, 1.0)
	pressed.border_color = Color(1.0, 0.4, 0.4, 1.0)
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(10)
	pressed.shadow_color = Color(1.0, 0.2, 0.2, 0.7)
	pressed.shadow_size = 12
	btn.add_theme_stylebox_override("pressed", pressed)
	
	# Disabled state
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.08, 0.04, 0.04, 0.9)
	disabled.border_color = Color(0.3, 0.15, 0.15, 0.6)
	disabled.set_border_width_all(2)
	disabled.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("disabled", disabled)


func _apply_modifier_card_style(btn: Button, accent_color: Color, is_unlocked: bool) -> void:
	var base_bg := Color(0.06, 0.06, 0.09, 0.95) if is_unlocked else Color(0.04, 0.04, 0.06, 0.9)
	var base_border := accent_color * 0.5 if is_unlocked else Color(0.2, 0.2, 0.25, 0.6)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_bg
	normal.border_color = base_border
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(base_bg.r + 0.05, base_bg.g + 0.05, base_bg.b + 0.08, 1.0)
	hover.border_color = accent_color * 0.8
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("hover", hover)
	
	# Pressed/toggled-on state - glowing effect
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(accent_color.r * 0.3, accent_color.g * 0.3, accent_color.b * 0.3, 1.0)
	pressed.border_color = accent_color
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(10)
	pressed.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.5)
	pressed.shadow_size = 6
	btn.add_theme_stylebox_override("pressed", pressed)
	
	# Disabled state
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.04, 0.04, 0.06, 0.9)
	disabled.border_color = Color(0.15, 0.15, 0.2, 0.6)
	disabled.set_border_width_all(2)
	disabled.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("disabled", disabled)


func _on_modifier_toggled(is_pressed: bool, stage_id: String) -> void:
	# Prevent infinite recursion from programmatic button_pressed changes
	if _updating_selection:
		return
	
	_updating_selection = true
	
	if is_pressed:
		_selected_stage_id = stage_id
		# Deselect other buttons
		for card in _stage_cards:
			if card is Button and card.get_meta("stage_id") != stage_id:
				card.button_pressed = false
	else:
		# Don't allow deselecting the current one - reselect it
		for card in _stage_cards:
			if card is Button and card.get_meta("stage_id") == stage_id:
				card.button_pressed = true
	
	_updating_selection = false


func _get_modifier_text(stage: Dictionary) -> String:
	# Return the stage description directly for display in the modifier cards
	return stage.get("description", "Standard mission.")

func _update_selection() -> void:
	# Update modifier button visuals
	for card in _stage_cards:
		if card is Button:
			var card_stage_id: String = card.get_meta("stage_id")
			card.button_pressed = (card_stage_id == _selected_stage_id)
	
	_update_preview()

func _update_preview() -> void:
	# Update map display based on selected map index
	var current_map: Dictionary = MAPS[_selected_map_index]
	
	_stage_name_lbl.text = current_map.name
	_modifier_lbl.text = current_map.subtitle
	
	# Update GameState immediately so the correct map is used
	GameState.selected_biome = current_map.biome
	GameState.selected_time = current_map.time
	
	# Load map preview
	var preview_path: String = current_map.preview
	if preview_path != "" and ResourceLoader.exists(preview_path):
		_preview_rect.texture = load(preview_path)
	else:
		_preview_rect.texture = null


func _on_map_prev() -> void:
	_selected_map_index = (_selected_map_index - 1 + MAPS.size()) % MAPS.size()
	_update_preview()


func _on_map_next() -> void:
	_selected_map_index = (_selected_map_index + 1) % MAPS.size()
	_update_preview()


func _apply_arrow_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	normal.border_color = Color(0.8, 0.6, 0.2, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.15, 0.12, 0.08, 0.8)
	hover.border_color = Color(1.0, 0.8, 0.3, 1.0)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.2, 0.15, 0.1, 0.9)
	pressed.border_color = Color(1.0, 0.9, 0.5, 1.0)
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))


func _apply_slider_style(slider: HSlider) -> void:
	# Make a much taller, easier to click slider
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.4, 0.6, 0.9, 1.0)
	grabber.set_corner_radius_all(8)
	grabber.content_margin_left = 12
	grabber.content_margin_right = 12
	grabber.content_margin_top = 16
	grabber.content_margin_bottom = 16
	slider.add_theme_stylebox_override("grabber_area", grabber)
	
	var grabber_highlight := StyleBoxFlat.new()
	grabber_highlight.bg_color = Color(0.5, 0.7, 1.0, 1.0)
	grabber_highlight.set_corner_radius_all(8)
	grabber_highlight.content_margin_left = 12
	grabber_highlight.content_margin_right = 12
	grabber_highlight.content_margin_top = 16
	grabber_highlight.content_margin_bottom = 16
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber_highlight)
	
	# Slider track (background)
	var slider_style := StyleBoxFlat.new()
	slider_style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	slider_style.set_corner_radius_all(6)
	slider_style.content_margin_top = 12
	slider_style.content_margin_bottom = 12
	slider.add_theme_stylebox_override("slider", slider_style)
	
	# Make the grabber icon bigger
	slider.add_theme_constant_override("grabber_offset", 8)


func _apply_start_button_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.7, 0.4, 1.0)
	normal.border_color = Color(0.4, 1.0, 0.6)
	normal.set_border_width_all(4)
	normal.set_corner_radius_all(12)
	normal.shadow_color = Color(0.2, 0.8, 0.4, 0.4)
	normal.shadow_size = 8
	_start_btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.8, 0.5, 1.0)
	hover.border_color = Color(0.5, 1.0, 0.7)
	hover.set_border_width_all(4)
	hover.set_corner_radius_all(12)
	hover.shadow_size = 12
	_start_btn.add_theme_stylebox_override("hover", hover)
	
	_start_btn.add_theme_color_override("font_color", Color.WHITE)

func _apply_back_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.12, 0.16, 0.95)
	normal.border_color = Color(0.4, 0.4, 0.5, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

func _apply_goddess_button_style(btn: Button) -> void:
	# Create impressive Goddess Fall toggle button with glowing effect
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.08, 0.12, 0.95)
	normal.border_color = Color(0.5, 0.25, 0.35, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.2, 0.1, 0.15, 1.0)
	hover.border_color = Color(0.7, 0.35, 0.45, 0.9)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	# Pressed/toggled-on state - bright red glow
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.35, 0.08, 0.12, 1.0)
	pressed.border_color = Color(1.0, 0.3, 0.4, 1.0)
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(8)
	pressed.shadow_color = Color(1.0, 0.2, 0.3, 0.5)
	pressed.shadow_size = 8
	btn.add_theme_stylebox_override("pressed", pressed)
	
	# Build the button content with icon + text
	btn.text = ""  # Clear text, we'll use a custom layout
	
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 6
	content.offset_right = -6
	content.offset_top = 6
	content.offset_bottom = -6
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	btn.add_child(content)
	
	# Skull/danger icon using unicode
	var icon_lbl := Label.new()
	icon_lbl.text = "☠"
	icon_lbl.add_theme_font_size_override("font_size", 24)
	icon_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(icon_lbl)
	
	var title := Label.new()
	title.text = "GODDESS"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = "FALL"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)

func _start_pulse_animation() -> void:
	if _start_tween:
		_start_tween.kill()
	_start_tween = create_tween().set_loops()
	_start_tween.tween_property(_start_btn, "scale", Vector2(1.008, 1.008), 0.8).set_trans(Tween.TRANS_SINE)
	_start_tween.tween_property(_start_btn, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_SINE)

func _on_start_pressed() -> void:
	# GameState.selected_biome and selected_time are already set by _update_preview
	stage_confirmed.emit(_selected_stage_id)
