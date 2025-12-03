extends Control
## Squad assembly UI inspired by NIKKE and Holocure.
## Features a grid of character cards and 3 squad slots that start empty.
## Click a slot to select it, then click a character to assign.

signal play_requested(squad: Array, map_id: String, time_id: String)
signal back_requested

# Visual constants - NIKKE/Holocure inspired
const BG_COLOR := Color(0.06, 0.06, 0.10, 0.98)
const CARD_BG_COLOR := Color(0.11, 0.11, 0.17, 0.92)
const CARD_BORDER_COLOR := Color(0.39, 0.39, 0.47, 1.0)
const CARD_HOVER_BORDER := Color(0.56, 0.63, 0.92, 0.85)
const CARD_SELECTED_BORDER := Color(0.95, 0.95, 1.0, 1.0)
const SLOT_EMPTY_COLOR := Color(0.12, 0.12, 0.18, 0.7)
const SLOT_FILLED_COLOR := Color(0.11, 0.11, 0.17, 0.92)
const SLOT_SELECTED_BORDER := Color(0.56, 0.63, 0.92, 1.0)
const TEXT_COLOR := Color(0.95, 0.95, 1.0, 1.0)
const DIM_TEXT_COLOR := Color(0.6, 0.6, 0.7, 1.0)
const ACCENT_COLOR := Color(0.56, 0.63, 0.92, 1.0)
const GOLDEN_ACCENT := Color(1.0, 0.85, 0.25, 1.0)
const MAIN_SLOT_COLOR := Color(0.4, 1.0, 0.5, 1.0)
const SUPPORT_SLOT_COLOR := Color(0.6, 0.5, 1.0, 1.0)
const NAME_OVERLAY_COLOR := Color(0.0, 0.0, 0.0, 0.62)
const CORNER_RADIUS := 12
const CARD_CORNER_RADIUS := 10

# Sizes
const CARD_SIZE := Vector2(145, 185)
const SLOT_SIZE := Vector2(165, 210)

enum Phase { SQUAD, LEVEL }
var current_phase: Phase = Phase.SQUAD

# Squad slots - START BLANK (Holocure style)
var squad_slots: Array[String] = ["", "", ""]
var selected_slot_index: int = 0
var squad_slot_nodes: Array[Control] = []

# Character cards
var character_cards: Dictionary = {}  # char_id -> card node
var hovered_char_id: String = ""

# Level selection
var selected_map_id: String = ""
var selected_time_id: String = ""
var level_cards: Array[Control] = []

# UI references
var main_container: Control
var squad_phase_container: Control
var level_phase_container: Control
var detail_panel: Control
var character_grid: GridContainer
var transition_tween: Tween

func _ready() -> void:
	_setup_ui()
	_update_all_visuals()

func _setup_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Main container with margins
	main_container = MarginContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("margin_left", 30)
	main_container.add_theme_constant_override("margin_right", 30)
	main_container.add_theme_constant_override("margin_top", 15)
	main_container.add_theme_constant_override("margin_bottom", 15)
	add_child(main_container)
	
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 10)
	main_container.add_child(content)
	
	# Title bar
	var title_bar := _create_title_bar()
	content.add_child(title_bar)
	
	# Phase containers
	var phase_holder := Control.new()
	phase_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(phase_holder)
	
	squad_phase_container = _create_squad_phase()
	squad_phase_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	phase_holder.add_child(squad_phase_container)
	
	level_phase_container = _create_level_phase()
	level_phase_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_phase_container.modulate.a = 0.0
	level_phase_container.visible = false
	phase_holder.add_child(level_phase_container)
	
	# Bottom buttons
	var button_row := _create_button_row()
	content.add_child(button_row)

func _create_title_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "SELECT YOUR SQUAD"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title)
	
	return bar

func _create_squad_phase() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 12)
	
	# Squad slots section (top, centered)
	var slots_section := _create_slots_section()
	container.add_child(slots_section)
	
	# Separator line
	var sep := _create_separator()
	container.add_child(sep)
	
	# Main content: character grid + details
	var content_row := HBoxContainer.new()
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 20)
	container.add_child(content_row)
	
	# Character grid (left side)
	var grid_section := _create_character_grid_section()
	grid_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_section.size_flags_stretch_ratio = 0.58
	content_row.add_child(grid_section)
	
	# Detail panel (right side)
	detail_panel = _create_detail_panel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_stretch_ratio = 0.42
	content_row.add_child(detail_panel)
	
	return container

func _create_slots_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header_row.add_theme_constant_override("separation", 20)
	section.add_child(header_row)
	
	var label := Label.new()
	label.text = "YOUR SQUAD"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	header_row.add_child(label)
	
	var help_text := Label.new()
	help_text.text = "• Click slot → Click character to assign"
	help_text.add_theme_font_size_override("font_size", 12)
	help_text.add_theme_color_override("font_color", DIM_TEXT_COLOR)
	header_row.add_child(help_text)
	
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 20)
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	section.add_child(slots_row)
	
	for i in range(3):
		var slot := _create_squad_slot(i)
		slots_row.add_child(slot)
		squad_slot_nodes.append(slot)
	
	return section

func _create_squad_slot(index: int) -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT_EMPTY_COLOR
	style.border_color = CARD_BORDER_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(CARD_CORNER_RADIUS)
	slot.add_theme_stylebox_override("panel", style)
	
	# Content layout - MUST ignore mouse so slot gets events
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(vbox)
	
	# Slot badge (MAIN / SUPPORT)
	var badge_container := CenterContainer.new()
	badge_container.custom_minimum_size = Vector2(0, 28)
	badge_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(badge_container)
	
	var badge := Label.new()
	badge.name = "Badge"
	if index == 0:
		badge.text = "▶ MAIN"
		badge.add_theme_color_override("font_color", MAIN_SLOT_COLOR)
	else:
		badge.text = "SUPPORT %d" % index
		badge.add_theme_color_override("font_color", SUPPORT_SLOT_COLOR)
	badge.add_theme_font_size_override("font_size", 13)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_container.add_child(badge)
	
	# Portrait area
	var portrait_area := Control.new()
	portrait_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(portrait_area)
	
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_area.add_child(portrait)
	
	# Empty indicator (question mark)
	var empty_label := Label.new()
	empty_label.name = "EmptyLabel"
	empty_label.text = "?"
	empty_label.add_theme_font_size_override("font_size", 64)
	empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 0.5))
	empty_label.set_anchors_preset(Control.PRESET_CENTER)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_area.add_child(empty_label)
	
	# Name overlay at bottom
	var name_overlay := ColorRect.new()
	name_overlay.name = "NameOverlay"
	name_overlay.color = NAME_OVERLAY_COLOR
	name_overlay.custom_minimum_size = Vector2(0, 32)
	name_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_overlay)
	
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = "EMPTY"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", DIM_TEXT_COLOR)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_overlay.add_child(name_label)
	
	# Click handling
	slot.gui_input.connect(_on_slot_clicked.bind(index))
	
	return slot

func _create_separator() -> Control:
	var container := CenterContainer.new()
	container.custom_minimum_size = Vector2(0, 8)
	
	var line := ColorRect.new()
	line.color = Color(0.3, 0.35, 0.45, 0.4)
	line.custom_minimum_size = Vector2(800, 1)
	container.add_child(line)
	
	return container

func _create_character_grid_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	
	var label := Label.new()
	label.text = "AVAILABLE CHARACTERS"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	section.add_child(label)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(scroll)
	
	character_grid = GridContainer.new()
	character_grid.columns = 4
	character_grid.add_theme_constant_override("h_separation", 10)
	character_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(character_grid)
	
	_populate_character_grid()
	
	return section

func _populate_character_grid() -> void:
	# Clear existing
	for child in character_grid.get_children():
		child.queue_free()
	character_cards.clear()
	
	var registry := CharacterRegistry.get_instance()
	if not registry:
		return
	
	var char_ids := registry.get_all_character_ids()
	for char_id in char_ids:
		var card := _create_character_card(char_id)
		character_grid.add_child(card)
		character_cards[char_id] = card

func _create_character_card(char_id: String) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG_COLOR
	style.border_color = CARD_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(CARD_CORNER_RADIUS)
	card.add_theme_stylebox_override("panel", style)
	
	# Container for clipping - MUST ignore mouse so card gets events
	var clip_container := Control.new()
	clip_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_container.clip_contents = true
	clip_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(clip_container)
	
	# Portrait - ignore mouse
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.modulate = Color(1, 1, 1, 0.95)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var registry := CharacterRegistry.get_instance()
	var char_data := registry.get_character(char_id) if registry else null
	if char_data:
		var tex: Texture2D = char_data.get_portrait()
		if tex:
			portrait.texture = tex
	clip_container.add_child(portrait)
	
	# Name overlay at bottom - ignore mouse
	var name_overlay := ColorRect.new()
	name_overlay.color = NAME_OVERLAY_COLOR
	name_overlay.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_overlay.anchor_top = 0.78
	name_overlay.offset_top = 0
	name_overlay.offset_bottom = 0
	name_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_container.add_child(name_overlay)
	
	var name_label := Label.new()
	name_label.text = char_data.display_name if char_data else char_id
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_overlay.add_child(name_label)
	
	# Store metadata
	card.set_meta("char_id", char_id)
	
	# Event connections
	card.gui_input.connect(_on_card_clicked.bind(char_id, card))
	card.mouse_entered.connect(_on_card_hovered.bind(char_id, card))
	card.mouse_exited.connect(_on_card_unhovered.bind(char_id, card))
	
	return card

func _create_detail_panel() -> Control:
	var panel := Panel.new()
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.11, 0.98)
	style.border_color = ACCENT_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(CORNER_RADIUS)
	panel.add_theme_stylebox_override("panel", style)
	
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	# Portrait with frame
	var portrait_frame := Panel.new()
	portrait_frame.custom_minimum_size = Vector2(0, 200)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.05, 0.05, 0.08, 1.0)
	frame_style.border_color = Color(0.3, 0.35, 0.5, 0.8)
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(8)
	portrait_frame.add_theme_stylebox_override("panel", frame_style)
	vbox.add_child(portrait_frame)
	
	var portrait := TextureRect.new()
	portrait.name = "DetailPortrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 4
	portrait.offset_right = -4
	portrait.offset_top = 4
	portrait.offset_bottom = -4
	portrait_frame.add_child(portrait)
	
	# Character name
	var name_label := Label.new()
	name_label.name = "DetailName"
	name_label.text = "Select a Character"
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	# Description
	var desc_label := Label.new()
	desc_label.name = "DetailDesc"
	desc_label.text = ""
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", DIM_TEXT_COLOR)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(desc_label)
	
	# Stats section
	var stats_label := Label.new()
	stats_label.text = "━━ STATS ━━"
	stats_label.add_theme_font_size_override("font_size", 14)
	stats_label.add_theme_color_override("font_color", ACCENT_COLOR)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_label)
	
	var stats_container := VBoxContainer.new()
	stats_container.name = "StatsContainer"
	stats_container.add_theme_constant_override("separation", 8)
	vbox.add_child(stats_container)
	
	return panel

func _create_level_phase() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 30)
	
	var title := Label.new()
	title.text = "SELECT MISSION"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)
	
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(center)
	
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	center.add_child(grid)
	
	var maps := ["emerald_fields", "sakura_grove", "ashen_sands", "polar_front"]
	var map_names := {
		"emerald_fields": "Emerald Fields",
		"sakura_grove": "Sakura Grove",
		"ashen_sands": "Ashen Sands",
		"polar_front": "Polar Front"
	}
	var times := ["day", "night"]
	var time_labels := {"day": "Day", "night": "Night"}
	
	for map_id in maps:
		for time_id in times:
			var card := _create_level_card(map_id, map_names.get(map_id, map_id), time_id, time_labels.get(time_id, time_id))
			grid.add_child(card)
			level_cards.append(card)
	
	return container

func _create_level_card(map_id: String, map_name: String, time_id: String, time_label: String) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(180, 120)
	
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG_COLOR
	if time_id == "day":
		style.border_color = Color(1.0, 0.85, 0.4, 0.8)
	else:
		style.border_color = Color(0.4, 0.5, 0.9, 0.8)
	style.set_border_width_all(3)
	style.set_corner_radius_all(CORNER_RADIUS)
	card.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)
	
	var name_lbl := Label.new()
	name_lbl.text = map_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", TEXT_COLOR)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	
	var time_lbl := Label.new()
	time_lbl.text = time_label
	time_lbl.add_theme_font_size_override("font_size", 15)
	if time_id == "day":
		time_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 1.0))
	else:
		time_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0, 1.0))
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(time_lbl)
	
	card.set_meta("map_id", map_id)
	card.set_meta("time_id", time_id)
	card.gui_input.connect(_on_level_card_clicked.bind(map_id, time_id, card))
	
	return card

func _create_button_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	
	var back_btn := _create_styled_button("BACK")
	back_btn.pressed.connect(_on_back_pressed)
	row.add_child(back_btn)
	
	var confirm_btn := _create_styled_button("START MISSION")
	confirm_btn.name = "ConfirmButton"
	confirm_btn.pressed.connect(_on_confirm_pressed)
	row.add_child(confirm_btn)
	
	return row

func _create_styled_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(180, 50)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.12, 0.18, 1.0)
	normal.border_color = ACCENT_COLOR
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.18, 0.26, 1.0)
	hover.border_color = GOLDEN_ACCENT
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	pressed.border_color = GOLDEN_ACCENT
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	
	return btn

# ============== UPDATE METHODS ==============

func _update_all_visuals() -> void:
	_update_squad_slots()
	_update_character_cards()
	_update_detail_panel("")

func _update_squad_slots() -> void:
	var registry := CharacterRegistry.get_instance()
	
	for i in range(squad_slot_nodes.size()):
		var slot := squad_slot_nodes[i]
		var char_id := squad_slots[i]
		var is_selected := (i == selected_slot_index)
		var is_filled := (char_id != "")
		
		# Get child nodes
		var portrait: TextureRect = slot.find_child("Portrait", true, false)
		var name_label: Label = slot.find_child("NameLabel", true, false)
		var empty_label: Label = slot.find_child("EmptyLabel", true, false)
		
		# Update content
		if is_filled and registry:
			var char_data := registry.get_character(char_id)
			if char_data:
				if portrait:
					portrait.texture = char_data.get_portrait()
					portrait.visible = true
				if name_label:
					name_label.text = char_data.display_name
					name_label.add_theme_color_override("font_color", TEXT_COLOR)
				if empty_label:
					empty_label.visible = false
		else:
			if portrait:
				portrait.texture = null
				portrait.visible = false
			if name_label:
				name_label.text = "EMPTY"
				name_label.add_theme_color_override("font_color", DIM_TEXT_COLOR)
			if empty_label:
				empty_label.visible = true
		
		# Update slot style
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel").duplicate()
		style.bg_color = SLOT_FILLED_COLOR if is_filled else SLOT_EMPTY_COLOR
		if is_selected:
			style.border_color = GOLDEN_ACCENT
			style.set_border_width_all(4)
		else:
			style.border_color = CARD_BORDER_COLOR
			style.set_border_width_all(3)
		slot.add_theme_stylebox_override("panel", style)

func _update_character_cards() -> void:
	# Mark cards that are already in squad
	for char_id in character_cards:
		var card: Control = character_cards[char_id]
		var is_in_squad: bool = squad_slots.has(char_id)
		
		var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
		if is_in_squad:
			style.border_color = MAIN_SLOT_COLOR
			style.set_border_width_all(3)
			card.modulate = Color(0.7, 0.7, 0.7, 0.8)
		else:
			style.border_color = CARD_BORDER_COLOR
			style.set_border_width_all(2)
			card.modulate = Color.WHITE
		card.add_theme_stylebox_override("panel", style)

func _update_detail_panel(char_id: String) -> void:
	var portrait: TextureRect = detail_panel.find_child("DetailPortrait", true, false)
	var name_label: Label = detail_panel.find_child("DetailName", true, false)
	var desc_label: Label = detail_panel.find_child("DetailDesc", true, false)
	var stats_container: VBoxContainer = detail_panel.find_child("StatsContainer", true, false)
	
	# Clear stats
	if stats_container:
		for child in stats_container.get_children():
			child.queue_free()
	
	if char_id == "":
		if portrait:
			portrait.texture = null
		if name_label:
			name_label.text = "Hover over a character"
		if desc_label:
			desc_label.text = "Select a slot above, then click a character to assign"
		return
	
	var registry := CharacterRegistry.get_instance()
	var char_data := registry.get_character(char_id) if registry else null
	
	if not char_data:
		return
	
	if portrait:
		portrait.texture = char_data.get_portrait()
	if name_label:
		name_label.text = char_data.display_name
	if desc_label:
		desc_label.text = char_data.description if char_data.description else ""
	
	if stats_container:
		_add_stat_row(stats_container, "HP", str(char_data.base_hp), 20.0, Color(0.4, 0.9, 0.5, 1.0))
		_add_stat_row(stats_container, "Speed", str(int(char_data.move_speed)), 500.0, Color(0.5, 0.7, 1.0, 1.0))
		_add_stat_row(stats_container, "Attack", str(int(char_data.base_damage)), 50.0, Color(1.0, 0.5, 0.4, 1.0))

func _add_stat_row(container: VBoxContainer, stat_name: String, value: String, max_value: float = 500.0, bar_color: Color = ACCENT_COLOR) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	
	var label := Label.new()
	label.text = stat_name
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", DIM_TEXT_COLOR)
	label.custom_minimum_size = Vector2(55, 0)
	row.add_child(label)
	
	# Bar background
	var bar_bg := Panel.new()
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_bg.custom_minimum_size = Vector2(0, 16)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	bg_style.set_corner_radius_all(4)
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	row.add_child(bar_bg)
	
	# Bar fill
	var fill_ratio := clampf(float(value) / max_value, 0.0, 1.0)
	var bar_fill := ColorRect.new()
	bar_fill.color = bar_color
	bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar_fill.anchor_right = fill_ratio
	bar_fill.offset_left = 2
	bar_fill.offset_right = -2
	bar_fill.offset_top = 2
	bar_fill.offset_bottom = -2
	bar_bg.add_child(bar_fill)
	
	var val_label := Label.new()
	val_label.text = value
	val_label.add_theme_font_size_override("font_size", 13)
	val_label.add_theme_color_override("font_color", TEXT_COLOR)
	val_label.custom_minimum_size = Vector2(40, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_label)
	
	container.add_child(row)

# ============== EVENT HANDLERS ==============

func _on_slot_clicked(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Right-click to clear slot
		if event.button_index == MOUSE_BUTTON_RIGHT:
			squad_slots[slot_index] = ""
			_update_squad_slots()
			_update_character_cards()
			_update_detail_panel("")
		elif event.button_index == MOUSE_BUTTON_LEFT:
			selected_slot_index = slot_index
			_update_squad_slots()
			_update_character_cards()
			
			# Show currently assigned character in detail panel
			var char_id := squad_slots[slot_index]
			_update_detail_panel(char_id)

func _on_card_clicked(event: InputEvent, char_id: String, _card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Assign character to selected slot
		squad_slots[selected_slot_index] = char_id
		
		# Animate the slot
		_animate_slot_filled(selected_slot_index)
		
		# Auto-advance to next empty slot
		_advance_to_next_empty_slot()
		
		_update_squad_slots()
		_update_character_cards()
		_update_detail_panel(char_id)

func _on_card_hovered(char_id: String, card: Control) -> void:
	hovered_char_id = char_id
	_update_detail_panel(char_id)
	
	# Highlight card on hover
	if not squad_slots.has(char_id):
		var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
		style.border_color = CARD_HOVER_BORDER
		style.set_border_width_all(3)
		card.add_theme_stylebox_override("panel", style)

func _on_card_unhovered(char_id: String, card: Control) -> void:
	if hovered_char_id == char_id:
		hovered_char_id = ""
	
	# Reset card style
	if not squad_slots.has(char_id):
		var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
		style.border_color = CARD_BORDER_COLOR
		style.set_border_width_all(2)
		card.add_theme_stylebox_override("panel", style)

func _on_level_card_clicked(event: InputEvent, map_id: String, time_id: String, card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_map_id = map_id
		selected_time_id = time_id
		
		# Update all level card styles
		for lc in level_cards:
			var style: StyleBoxFlat = lc.get_theme_stylebox("panel").duplicate()
			if lc == card:
				style.border_color = GOLDEN_ACCENT
				style.set_border_width_all(5)
			else:
				var tid = lc.get_meta("time_id")
				if tid == "day":
					style.border_color = Color(1.0, 0.85, 0.4, 0.8)
				else:
					style.border_color = Color(0.4, 0.5, 0.9, 0.8)
				style.set_border_width_all(3)
			lc.add_theme_stylebox_override("panel", style)

func _on_back_pressed() -> void:
	if current_phase == Phase.LEVEL:
		_transition_to_squad_phase()
	else:
		back_requested.emit()

func _on_confirm_pressed() -> void:
	if current_phase == Phase.SQUAD:
		# Check if all slots are filled
		var all_filled := true
		for char_id in squad_slots:
			if char_id == "":
				all_filled = false
				break
		
		if all_filled:
			_transition_to_level_phase()
		else:
			# Flash empty slots
			for i in range(squad_slots.size()):
				if squad_slots[i] == "":
					_flash_slot_error(i)
	else:
		# Level phase - start game
		if selected_map_id != "" and selected_time_id != "":
			play_requested.emit(squad_slots, selected_map_id, selected_time_id)
		else:
			# Flash all level cards
			for card in level_cards:
				var tween := create_tween()
				tween.tween_property(card, "modulate", Color(1.0, 0.4, 0.4), 0.1)
				tween.tween_property(card, "modulate", Color.WHITE, 0.1)

# ============== HELPER METHODS ==============

func _advance_to_next_empty_slot() -> void:
	# Find next empty slot after current
	for i in range(squad_slots.size()):
		var idx := (selected_slot_index + 1 + i) % squad_slots.size()
		if squad_slots[idx] == "":
			selected_slot_index = idx
			return

func _animate_slot_filled(slot_index: int) -> void:
	if slot_index >= squad_slot_nodes.size():
		return
	var slot := squad_slot_nodes[slot_index]
	var tween := create_tween()
	tween.tween_property(slot, "scale", Vector2(1.08, 1.08), 0.1)
	tween.tween_property(slot, "scale", Vector2(1.0, 1.0), 0.1)

func _flash_slot_error(slot_index: int) -> void:
	if slot_index >= squad_slot_nodes.size():
		return
	var slot := squad_slot_nodes[slot_index]
	var tween := create_tween()
	tween.tween_property(slot, "modulate", Color(1.0, 0.3, 0.3), 0.1)
	tween.tween_property(slot, "modulate", Color.WHITE, 0.1)
	tween.tween_property(slot, "modulate", Color(1.0, 0.3, 0.3), 0.1)
	tween.tween_property(slot, "modulate", Color.WHITE, 0.1)

func _transition_to_level_phase() -> void:
	current_phase = Phase.LEVEL
	
	if transition_tween:
		transition_tween.kill()
	
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	
	# Fade out squad phase
	transition_tween.tween_property(squad_phase_container, "modulate:a", 0.0, 0.3)
	transition_tween.tween_property(squad_phase_container, "position:x", -50, 0.3)
	
	# Fade in level phase
	level_phase_container.visible = true
	level_phase_container.position.x = 50
	transition_tween.tween_property(level_phase_container, "modulate:a", 1.0, 0.3).set_delay(0.15)
	transition_tween.tween_property(level_phase_container, "position:x", 0, 0.3).set_delay(0.15)
	
	transition_tween.chain().tween_callback(func(): squad_phase_container.visible = false)
	
	# Update title
	var title: Label = main_container.find_child("TitleLabel", true, false)
	if title:
		title.text = "SELECT MISSION"

func _transition_to_squad_phase() -> void:
	current_phase = Phase.SQUAD
	
	if transition_tween:
		transition_tween.kill()
	
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	
	# Fade out level phase
	transition_tween.tween_property(level_phase_container, "modulate:a", 0.0, 0.3)
	transition_tween.tween_property(level_phase_container, "position:x", 50, 0.3)
	
	# Fade in squad phase
	squad_phase_container.visible = true
	squad_phase_container.position.x = -50
	transition_tween.tween_property(squad_phase_container, "modulate:a", 1.0, 0.3).set_delay(0.15)
	transition_tween.tween_property(squad_phase_container, "position:x", 0, 0.3).set_delay(0.15)
	
	transition_tween.chain().tween_callback(func(): level_phase_container.visible = false)
	
	# Update title
	var title: Label = main_container.find_child("TitleLabel", true, false)
	if title:
		title.text = "SELECT YOUR SQUAD"
