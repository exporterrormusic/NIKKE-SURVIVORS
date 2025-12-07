extends Control
class_name StageSelector
## Holocure-style stage selector with fixed stages, preview, and animated start button.

const UISounds := preload("res://scripts/ui/UISoundManager.gd")

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
var _hp_scale_label: Label
var _atk_scale_label: Label
var _core_scale_label: Label
var _elite_core_label: Label

func _ready() -> void:
	_build_ui()
	_select_first_unlocked()
	_start_pulse_animation()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		UISounds.play_back()
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
	header_style.bg_color = UITheme.PANEL_HEADER_BG
	header_style.border_color = UITheme.PANEL_HEADER_BORDER
	header_style.set_border_width_all(3)
	header_style.set_corner_radius_all(12)
	header_style.shadow_color = UITheme.SHADOW_HEADER
	header_style.shadow_size = 6
	header_panel.add_theme_stylebox_override("panel", header_style)
	left.add_child(header_panel)
	
	var stages_title := Label.new()
	stages_title.text = "⚔  MODIFIERS  ⚔"
	stages_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	stages_title.add_theme_font_size_override("font_size", 42)
	stages_title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	stages_title.add_theme_color_override("font_shadow_color", UITheme.SHADOW_PURPLE)
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
	preview_style.bg_color = UITheme.PANEL_PREVIEW_BG
	preview_style.border_color = UITheme.PANEL_PREVIEW_BORDER
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
	banner_style.bg_color = UITheme.BANNER_BG
	banner_style.border_color = UITheme.BANNER_BORDER
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
	_map_left_btn.custom_minimum_size = Vector2(70, 50)
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
	_stage_name_lbl.add_theme_font_size_override("font_size", 48)
	_stage_name_lbl.add_theme_color_override("font_color", UITheme.BANNER_TEXT)
	_stage_name_lbl.add_theme_color_override("font_shadow_color", UITheme.SHADOW_COLOR)
	_stage_name_lbl.add_theme_constant_override("shadow_offset_x", 3)
	_stage_name_lbl.add_theme_constant_override("shadow_offset_y", 3)
	_stage_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_center.add_child(_stage_name_lbl)
	
	_modifier_lbl = Label.new()
	_modifier_lbl.add_theme_font_size_override("font_size", 26)
	_modifier_lbl.add_theme_color_override("font_color", UITheme.BANNER_SUBTITLE)
	_modifier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_center.add_child(_modifier_lbl)
	
	# Right arrow button
	_map_right_btn = Button.new()
	_map_right_btn.text = "▶"
	_map_right_btn.custom_minimum_size = Vector2(70, 50)
	_map_right_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_arrow_button_style(_map_right_btn)
	_map_right_btn.pressed.connect(_on_map_next)
	banner_hbox.add_child(_map_right_btn)
	
	# Difficulty panel - compact horizontal layout
	# Wrap difficulty + buttons in HBox with scaling info on right
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	right.add_child(bottom_row)
	
	# Left side: difficulty + buttons stacked
	var left_stack := VBoxContainer.new()
	left_stack.add_theme_constant_override("separation", 8)
	left_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(left_stack)
	
	var diff_panel := Panel.new()
	diff_panel.custom_minimum_size.y = 55
	var diff_style := StyleBoxFlat.new()
	diff_style.bg_color = UITheme.PANEL_DIFF_BG
	diff_style.border_color = UITheme.PANEL_DIFF_BORDER
	diff_style.set_border_width_all(2)
	diff_style.set_corner_radius_all(8)
	diff_panel.add_theme_stylebox_override("panel", diff_style)
	left_stack.add_child(diff_panel)
	
	# Horizontal layout: Labels | Slider | Value
	var diff_hbox := HBoxContainer.new()
	diff_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	diff_hbox.offset_left = 12
	diff_hbox.offset_right = -12
	diff_hbox.offset_top = 6
	diff_hbox.offset_bottom = -6
	diff_hbox.add_theme_constant_override("separation", 10)
	diff_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_panel.add_child(diff_hbox)
	
	# Left side: Title and description stacked vertically
	var diff_labels := VBoxContainer.new()
	diff_labels.add_theme_constant_override("separation", 0)
	diff_labels.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_labels.custom_minimum_size.x = 80
	diff_hbox.add_child(diff_labels)
	
	var diff_title := Label.new()
	diff_title.text = "DIFFICULTY"
	diff_title.add_theme_font_size_override("font_size", 12)
	diff_title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	diff_labels.add_child(diff_title)
	
	# Center: Slider
	_difficulty_slider = HSlider.new()
	_difficulty_slider.min_value = 1
	_difficulty_slider.max_value = 100
	_difficulty_slider.value = GameState.difficulty_multiplier
	_difficulty_slider.step = 1
	_difficulty_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_difficulty_slider.custom_minimum_size = Vector2(120, 28)
	_apply_slider_style(_difficulty_slider)
	_difficulty_slider.value_changed.connect(_on_difficulty_changed)
	diff_hbox.add_child(_difficulty_slider)
	
	# Right side: Value display
	_difficulty_label = Label.new()
	_difficulty_label.text = "x%d" % GameState.difficulty_multiplier
	_difficulty_label.add_theme_font_size_override("font_size", 20)
	_difficulty_label.add_theme_color_override("font_color", _get_difficulty_color(GameState.difficulty_multiplier))
	_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_label.custom_minimum_size.x = 50
	diff_hbox.add_child(_difficulty_label)
	
	# Buttons row: Back (left) | Start (right)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left_stack.add_child(btn_row)
	
	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(120, 45)
	_apply_back_button_style(back_btn)
	back_btn.pressed.connect(func(): UISounds.play_back(); back_requested.emit())
	btn_row.add_child(back_btn)
	
	_start_btn = Button.new()
	_start_btn.text = "MISSION START"
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn.custom_minimum_size = Vector2(160, 45)
	_start_btn.add_theme_font_size_override("font_size", 18)
	_apply_start_button_style()
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.pivot_offset = _start_btn.custom_minimum_size / 2.0
	btn_row.add_child(_start_btn)
	
	# Right side: Scaling info panel
	var scale_panel := Panel.new()
	scale_panel.custom_minimum_size = Vector2(150, 0)
	var scale_style := StyleBoxFlat.new()
	scale_style.bg_color = UITheme.PANEL_SCALE_BG
	scale_style.border_color = UITheme.PANEL_SCALE_BORDER
	scale_style.set_border_width_all(2)
	scale_style.set_corner_radius_all(8)
	scale_panel.add_theme_stylebox_override("panel", scale_style)
	bottom_row.add_child(scale_panel)
	
	var scale_vbox := VBoxContainer.new()
	scale_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	scale_vbox.offset_left = 8
	scale_vbox.offset_right = -8
	scale_vbox.offset_top = 6
	scale_vbox.offset_bottom = -6
	scale_vbox.add_theme_constant_override("separation", 2)
	scale_panel.add_child(scale_vbox)
	
	var scale_title := Label.new()
	scale_title.text = "SCALING"
	scale_title.add_theme_font_size_override("font_size", 14)
	scale_title.add_theme_color_override("font_color", UITheme.TEXT_SECONDARY)
	scale_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_vbox.add_child(scale_title)
	
	# Spacer between title and stats
	var title_spacer := Control.new()
	title_spacer.custom_minimum_size = Vector2(0, 2)
	scale_vbox.add_child(title_spacer)
	
	_hp_scale_label = Label.new()
	_hp_scale_label.add_theme_font_size_override("font_size", 16)
	_hp_scale_label.add_theme_color_override("font_color", UITheme.STAT_HP)
	_hp_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_vbox.add_child(_hp_scale_label)
	
	_atk_scale_label = Label.new()
	_atk_scale_label.add_theme_font_size_override("font_size", 16)
	_atk_scale_label.add_theme_color_override("font_color", UITheme.STAT_ATK)
	_atk_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_vbox.add_child(_atk_scale_label)
	
	_core_scale_label = Label.new()
	_core_scale_label.add_theme_font_size_override("font_size", 16)
	_core_scale_label.add_theme_color_override("font_color", UITheme.STAT_SPD)
	_core_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_vbox.add_child(_core_scale_label)
	
	_elite_core_label = Label.new()
	_elite_core_label.add_theme_font_size_override("font_size", 13)
	_elite_core_label.add_theme_color_override("font_color", UITheme.STAT_CRIT)
	_elite_core_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_vbox.add_child(_elite_core_label)
	
	_update_scaling_labels(GameState.difficulty_multiplier)

func _on_difficulty_changed(value: float) -> void:
	GameState.difficulty_multiplier = int(value)
	_difficulty_label.text = "x%d" % int(value)
	_difficulty_label.add_theme_color_override("font_color", _get_difficulty_color(int(value)))
	_update_scaling_labels(int(value))

func _update_scaling_labels(difficulty: int) -> void:
	# HP scales at 1x per difficulty level (x1, x2, x3...)
	var hp_mult: float = float(difficulty)
	# ATK scales at 0.25x per difficulty level (x1, x1.25, x1.5...)
	var atk_mult: float = 1.0 + 0.25 * (difficulty - 1)
	# Core drops scale at 1x per difficulty level (x1, x2, x3...)
	var core_mult: float = float(difficulty)
	
	_hp_scale_label.text = "HP: x%.0f" % hp_mult
	if atk_mult == int(atk_mult):
		_atk_scale_label.text = "ATK: x%.0f" % atk_mult
	else:
		_atk_scale_label.text = "ATK: x%.2f" % atk_mult
	_core_scale_label.text = "Cores: x%.0f" % core_mult
	
	# Elite core label no longer used - info moved to Goddess Fall button
	_elite_core_label.visible = false

func _on_goddess_fall_toggled(pressed: bool) -> void:
	if pressed:
		UISounds.play_select()
	else:
		UISounds.play_back()
	GameState.goddess_fall_mode = pressed
	_update_scaling_labels(GameState.difficulty_multiplier)

func _get_difficulty_color(value: int) -> Color:
	if value <= 1:
		return UITheme.DIFF_NORMAL
	elif value <= 10:
		return UITheme.DIFF_EASY
	elif value <= 25:
		return UITheme.DIFF_MEDIUM
	elif value <= 50:
		return UITheme.DIFF_HARD
	else:
		return UITheme.DIFF_EXTREME

# Modifier button definitions with icons and colors
const MODIFIER_STYLES := {
	"stage_1": {"icon": "⚔", "color": UITheme.MOD_STANDARD, "title": "STANDARD"},
	"stage_2": {"icon": "👑", "color": UITheme.MOD_ELITE, "title": "ELITE HUNT"},
	"stage_3": {"icon": "∞", "color": UITheme.MOD_ENDLESS, "title": "ENDLESS"},
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
	icon_lbl.add_theme_font_size_override("font_size", 52)
	icon_lbl.add_theme_color_override("font_color", style_info.color if is_unlocked else UITheme.COLOR_LOCKED)
	icon_lbl.custom_minimum_size.x = 70
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
	title.add_theme_font_override("font", UITheme.FONT_BOLD)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", style_info.color if is_unlocked else UITheme.COLOR_LOCKED)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(title)
	
	# Description
	var desc := Label.new()
	desc.text = stage.get("description", "") if is_unlocked else "Clear previous stage to unlock"
	desc.add_theme_font_size_override("font_size", 26)
	desc.add_theme_color_override("font_color", UITheme.TEXT_MUTED if is_unlocked else UITheme.TEXT_DISABLED)
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
	line.color = UITheme.DIVIDER_SUBTLE
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
	var accent_color := UITheme.MOD_GODDESS
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
	icon_lbl.add_theme_font_size_override("font_size", 52)
	icon_lbl.add_theme_color_override("font_color", accent_color)
	icon_lbl.custom_minimum_size.x = 70
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_lbl)
	
	# Text content
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 6)
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(text_vbox)
	
	var title := Label.new()
	title.text = "GODDESS FALL"
	title.add_theme_font_override("font", UITheme.FONT_BOLD)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", accent_color)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(title)
	
	var desc := Label.new()
	desc.text = "Enemies 30% faster. Elites drop cores (20%). Tanks fire missiles. Bosses enrage!"
	desc.add_theme_font_size_override("font_size", 26)
	desc.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(desc)
	
	return btn


func _apply_goddess_fall_style(btn: Button, _accent_color: Color) -> void:
	# Red danger background with glow effect like the divider
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.BTN_DANGER_BG
	normal.border_color = UITheme.BTN_DANGER_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.shadow_color = UITheme.BTN_DANGER_GLOW
	normal.shadow_size = 6
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UITheme.BTN_DANGER_HOVER_BG
	hover.border_color = UITheme.BTN_DANGER_HOVER_BORDER
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(10)
	hover.shadow_color = UITheme.BTN_DANGER_GLOW
	hover.shadow_size = 10
	btn.add_theme_stylebox_override("hover", hover)
	
	# Pressed/toggled-on state - intense glowing effect
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = UITheme.BTN_DANGER_PRESSED_BG
	pressed.border_color = UITheme.BTN_DANGER_PRESSED_BORDER
	pressed.set_border_width_all(4)
	pressed.set_corner_radius_all(10)
	pressed.shadow_color = UITheme.BTN_DANGER_PRESSED_GLOW
	pressed.shadow_size = 20
	btn.add_theme_stylebox_override("pressed", pressed)
	
	# Disabled state
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = UITheme.BTN_DISABLED_BG
	disabled.border_color = UITheme.BTN_DISABLED_BORDER
	disabled.set_border_width_all(2)
	disabled.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("disabled", disabled)


func _apply_modifier_card_style(btn: Button, accent_color: Color, is_unlocked: bool) -> void:
	var base_bg := UITheme.BTN_NORMAL_BG if is_unlocked else UITheme.BTN_DISABLED_BG
	var base_border := accent_color * 0.5 if is_unlocked else UITheme.BTN_DISABLED_BORDER
	
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
	disabled.bg_color = UITheme.BTN_DISABLED_BG
	disabled.border_color = UITheme.BTN_DISABLED_BORDER
	disabled.set_border_width_all(2)
	disabled.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("disabled", disabled)


func _on_modifier_toggled(is_pressed: bool, stage_id: String) -> void:
	# Prevent infinite recursion from programmatic button_pressed changes
	if _updating_selection:
		return
	
	_updating_selection = true
	
	if is_pressed:
		UISounds.play_select()
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
	normal.bg_color = UITheme.MAP_BTN_BG
	normal.border_color = UITheme.MAP_BTN_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UITheme.MAP_BTN_HOVER_BG
	hover.border_color = UITheme.MAP_BTN_HOVER_BORDER
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = UITheme.MAP_BTN_PRESSED_BG
	pressed.border_color = UITheme.MAP_BTN_PRESSED_BORDER
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	btn.add_theme_font_size_override("font_size", 32)
	btn.add_theme_color_override("font_color", UITheme.MAP_BTN_TEXT)


func _apply_slider_style(slider: HSlider) -> void:
	# Make a much taller, easier to click slider
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = UITheme.SLIDER_GRABBER
	grabber.set_corner_radius_all(8)
	grabber.content_margin_left = 12
	grabber.content_margin_right = 12
	grabber.content_margin_top = 16
	grabber.content_margin_bottom = 16
	slider.add_theme_stylebox_override("grabber_area", grabber)
	
	var grabber_highlight := StyleBoxFlat.new()
	grabber_highlight.bg_color = UITheme.SLIDER_GRABBER_HIGHLIGHT
	grabber_highlight.set_corner_radius_all(8)
	grabber_highlight.content_margin_left = 12
	grabber_highlight.content_margin_right = 12
	grabber_highlight.content_margin_top = 16
	grabber_highlight.content_margin_bottom = 16
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber_highlight)
	
	# Slider track (background)
	var slider_style := StyleBoxFlat.new()
	slider_style.bg_color = UITheme.SLIDER_BG
	slider_style.set_corner_radius_all(6)
	slider_style.content_margin_top = 12
	slider_style.content_margin_bottom = 12
	slider.add_theme_stylebox_override("slider", slider_style)
	
	# Make the grabber icon bigger
	slider.add_theme_constant_override("grabber_offset", 8)


func _apply_start_button_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.START_BTN_BG
	normal.border_color = UITheme.START_BTN_BORDER
	normal.set_border_width_all(4)
	normal.set_corner_radius_all(12)
	normal.shadow_color = UITheme.START_BTN_SHADOW
	normal.shadow_size = 8
	_start_btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UITheme.START_BTN_HOVER_BG
	hover.border_color = UITheme.START_BTN_HOVER_BORDER
	hover.set_border_width_all(4)
	hover.set_corner_radius_all(12)
	hover.shadow_size = 12
	_start_btn.add_theme_stylebox_override("hover", hover)
	
	_start_btn.add_theme_color_override("font_color", Color.WHITE)

func _apply_back_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.BACK_BTN_BG
	normal.border_color = UITheme.BACK_BTN_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_color_override("font_color", UITheme.BACK_BTN_TEXT)

func _apply_goddess_button_style(btn: Button) -> void:
	# Create impressive Goddess Fall toggle button with glowing effect
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.GODDESS_BTN_BG
	normal.border_color = UITheme.GODDESS_BTN_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UITheme.GODDESS_BTN_HOVER_BG
	hover.border_color = UITheme.GODDESS_BTN_HOVER_BORDER
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	# Pressed/toggled-on state - bright red glow
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = UITheme.GODDESS_BTN_PRESSED_BG
	pressed.border_color = UITheme.GODDESS_BTN_PRESSED_BORDER
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(8)
	pressed.shadow_color = UITheme.GODDESS_BTN_SHADOW
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
	icon_lbl.add_theme_color_override("font_color", UITheme.GODDESS_ICON)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(icon_lbl)
	
	var title := Label.new()
	title.text = "GODDESS"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UITheme.GODDESS_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = "FALL"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", UITheme.GODDESS_SUBTITLE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)

func _start_pulse_animation() -> void:
	if _start_tween:
		_start_tween.kill()
	_start_tween = create_tween().set_loops()
	_start_tween.tween_property(_start_btn, "scale", Vector2(1.008, 1.008), 0.8).set_trans(Tween.TRANS_SINE)
	_start_tween.tween_property(_start_btn, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_SINE)

func _on_start_pressed() -> void:
	UISounds.play_confirm()
	# GameState.selected_biome and selected_time are already set by _update_preview
	stage_confirmed.emit(_selected_stage_id)
