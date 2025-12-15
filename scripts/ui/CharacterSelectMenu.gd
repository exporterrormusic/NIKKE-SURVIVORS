extends Control
## Character and Stage Selection Menu.
## Layout: Grid (top-left) + Details (bottom-left) + Squad slots (right full height).
## When squad is complete, animates up to reveal stage selector.

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

signal play_requested(squad: Array[int], stage_id: String)
signal back_requested

const SquadSlotsScript = preload("res://scripts/ui/components/SquadSlots.gd")
const CharacterInfoPanelScript = preload("res://scripts/ui/components/CharacterInfoPanel.gd")
const StageSelectorScript = preload("res://scripts/ui/components/StageSelector.gd")
const VenetianBlindsScript = preload("res://scripts/ui/components/VenetianBlindsBackground.gd")
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

const CARD_SIZE := Vector2(140, 220)
const GRID_COLUMNS := 5
const SQUAD_SLOT_SIZE := Vector2(180, 220)

enum Phase { SQUAD, STAGE }
var _phase: Phase = Phase.SQUAD

var _registry: RefCounted
var _cards: Dictionary = {}  # char_id -> card node

var _burst_audio: AudioStreamPlayer  # For character selection burst SFX

var _bg: Control
var _squad_container: Control
var _stage_container: Control
var _grid: Control  # VBoxContainer holding row HBoxContainers
var _squad_slots: Control
var _info_panel: Panel
var _stage_selector: Control
var _transition_tween: Tween

func _ready() -> void:
	_load_registry()
	_build_ui()
	_populate_grid()
	_setup_burst_audio()
	
	# Start menu music if not already playing (handles direct scene load from game)
	_ensure_menu_music()

func _setup_burst_audio() -> void:
	_burst_audio = AudioStreamPlayer.new()
	_burst_audio.bus = "SFX"  # Use SFX bus for burst preview sounds
	add_child(_burst_audio)

func _ensure_menu_music() -> void:
	# When coming from the game (Level scene), MenuManager's music is stopped
	# We need to restart it when entering the character select menu
	if MenuManager:
		MenuManager.start_menu_music()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_escape()
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()

func _handle_escape() -> void:
	if _phase == Phase.STAGE:
		# Go back to squad selection
		_transition_to_squad()
	else:
		# Go back to main menu
		_go_back()

func _go_back() -> void:
	UISounds.play_back()
	
	# Reset stage selector if interacting with it (clears music/modes)
	# Reset stage selector if interacting with it (clears music/modes)
	if _stage_selector and _stage_selector.has_method("clear_goddess_flags"):
		# _stage_selector.clear_goddess_flags() # DISABLED: Prevents aggressive flag clearing
		pass
	elif _stage_selector and _stage_selector.has_method("reset_state"):
		# _stage_selector.reset_state()
		pass
	
	# If we are being managed by MenuManager (sub-menu), just ask to go back
	# This avoids reloading the MainMenu scene which breaks state/music
	if back_requested.get_connections().size() > 0:
		back_requested.emit()
	elif MenuManager:
		# Fallback only if we have no connections (e.g. Pause Menu context)
		MenuManager.return_to_main_menu()
	else:
		back_requested.emit()

func _load_registry() -> void:
	_registry = CharacterRegistry.get_instance()

func _build_ui() -> void:
	# Background
	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.set_script(VenetianBlindsScript)
	add_child(_bg)
	
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = UI.OVERLAY_DARK
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	
	# Squad selection container
	_squad_container = Control.new()
	_squad_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_squad_container)
	_build_squad_phase()
	
	# Stage selection container (hidden below)
	_stage_container = Control.new()
	_stage_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_container.position.y = get_viewport_rect().size.y
	_stage_container.modulate.a = 0.0
	add_child(_stage_container)
	_build_stage_phase()

func _build_squad_phase() -> void:
	# Main content area (full height minus bottom buttons)
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 24
	content.offset_bottom = -70
	content.offset_left = 24
	content.offset_right = -24
	_squad_container.add_child(content)
	
	# RIGHT: Squad slots panel (full height, right side)
	var squad_panel := Panel.new()
	squad_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	squad_panel.anchor_left = 0.78
	squad_panel.offset_left = 0
	squad_panel.offset_right = 0
	_apply_panel_style(squad_panel)
	content.add_child(squad_panel)
	
	_squad_slots = SquadSlotsScript.new()
	_squad_slots.set_anchors_preset(Control.PRESET_FULL_RECT)
	_squad_slots.offset_left = 20
	_squad_slots.offset_right = -20
	_squad_slots.offset_top = 16
	_squad_slots.offset_bottom = -16
	_squad_slots.squad_complete.connect(_on_squad_complete)
	_squad_slots.slot_cleared.connect(_on_slot_cleared)
	squad_panel.add_child(_squad_slots)
	
	# LEFT SIDE: Grid (top) + Details (bottom)
	var left_side := Control.new()
	left_side.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_side.anchor_right = 0.77
	left_side.offset_right = -16
	content.add_child(left_side)
	
	# TOP-LEFT: Character grid (about 65% height)
	var grid_panel := Panel.new()
	grid_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	grid_panel.anchor_bottom = 0.65
	_apply_panel_style(grid_panel)
	left_side.add_child(grid_panel)
	
	var grid_margin := MarginContainer.new()
	grid_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid_margin.add_theme_constant_override("margin_left", 20)
	grid_margin.add_theme_constant_override("margin_right", 20)
	grid_margin.add_theme_constant_override("margin_top", 16)
	grid_margin.add_theme_constant_override("margin_bottom", 16)
	grid_panel.add_child(grid_margin)
	
	# Use a VBoxContainer to hold rows that expand vertically
	var grid_vbox := VBoxContainer.new()
	grid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_vbox.add_theme_constant_override("separation", 16)
	grid_margin.add_child(grid_vbox)
	
	# Row 1
	var row1 := HBoxContainer.new()
	row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row1.add_theme_constant_override("separation", 16)
	grid_vbox.add_child(row1)
	
	# Row 2
	var row2 := HBoxContainer.new()
	row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row2.add_theme_constant_override("separation", 16)
	grid_vbox.add_child(row2)
	
	# Store rows for later population
	_grid = grid_vbox
	_grid.set_meta("row1", row1)
	_grid.set_meta("row2", row2)
	
	# BOTTOM-LEFT: Details panel (about 35% height)
	_info_panel = CharacterInfoPanelScript.new()
	_info_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_info_panel.anchor_top = 0.67
	_info_panel.offset_top = 8
	left_side.add_child(_info_panel)
	
	# Back button at bottom
	var btn_row := HBoxContainer.new()
	btn_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	btn_row.offset_top = -55
	btn_row.offset_bottom = -10
	btn_row.offset_left = 24
	btn_row.offset_right = -24
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_squad_container.add_child(btn_row)
	
	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(140, 45)
	_apply_button_style(back_btn)
	back_btn.pressed.connect(_go_back)
	btn_row.add_child(back_btn)
	
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 20
	btn_row.add_child(spacer)
	
	var random_btn := Button.new()
	random_btn.text = "RANDOM"
	random_btn.custom_minimum_size = Vector2(140, 45)
	_apply_random_button_style(random_btn)
	random_btn.pressed.connect(_on_random_pressed)
	btn_row.add_child(random_btn)
	
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.x = 20
	btn_row.add_child(spacer2)
	
	var next_btn := Button.new()
	next_btn.text = "NEXT"
	next_btn.custom_minimum_size = Vector2(140, 45)
	_apply_next_button_style(next_btn)
	next_btn.pressed.connect(_on_next_pressed)
	btn_row.add_child(next_btn)

func _build_stage_phase() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	_stage_container.add_child(margin)
	
	var panel := Panel.new()
	_apply_panel_style(panel)
	margin.add_child(panel)
	
	_stage_selector = StageSelectorScript.new()
	_stage_selector.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_selector.offset_left = 24
	_stage_selector.offset_right = -24
	_stage_selector.offset_top = 24
	_stage_selector.offset_bottom = -24
	_stage_selector.stage_confirmed.connect(_on_stage_confirmed)
	_stage_selector.back_requested.connect(_on_stage_back)
	panel.add_child(_stage_selector)

func _populate_grid() -> void:
	if not _registry:
		return
	
	var row1: HBoxContainer = _grid.get_meta("row1")
	var row2: HBoxContainer = _grid.get_meta("row2")
	
	var char_ids = _registry.get_all_character_ids()
	for i in range(char_ids.size()):
		var char_id = char_ids[i]
		var data = _registry.get_character(char_id)
		var card := _create_card(char_id, data)
		
		# First 5 go to row1, rest go to row2
		if i < GRID_COLUMNS:
			row1.add_child(card)
		else:
			row2.add_child(card)
		
		_cards[char_id] = card

func _create_card(char_id: String, data: Resource) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_SIZE.x, 0)  # Min width only, height expands
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("char_id", char_id)
	card.set_meta("char_data", data)
	card.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	
	# Check if character is unlocked
	var is_unlocked: bool = ShopMenuScript.is_character_unlocked(char_id)
	card.set_meta("is_unlocked", is_unlocked)
	
	_apply_card_style(card, false)
	
	var portrait := TextureRect.new()
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if data:
		portrait.texture = data.get_portrait()
	# Dim portrait if locked
	portrait.modulate = UI.CHAR_PORTRAIT_UNLOCKED if is_unlocked else UI.CHAR_LOCKED
	card.add_child(portrait)
	
	# Lock overlay for locked characters
	if not is_unlocked:
		var lock_overlay := ColorRect.new()
		lock_overlay.color = UI.BG_OVERLAY
		lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lock_overlay)
		
		# CenterContainer to properly center the VBox
		var lock_center := CenterContainer.new()
		lock_center.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lock_center)
		
		# VBox to center lock icon and text vertically
		var lock_vbox := VBoxContainer.new()
		lock_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		lock_vbox.add_theme_constant_override("separation", 6)
		lock_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_center.add_child(lock_vbox)
		
		var lock_icon := Label.new()
		lock_icon.text = "🔒"
		lock_icon.add_theme_font_size_override("font_size", 72)
		lock_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_vbox.add_child(lock_icon)
		
		var locked_text := Label.new()
		locked_text.text = "LOCKED"
		locked_text.add_theme_font_size_override("font_size", 24)
		locked_text.add_theme_color_override("font_color", UI.COLOR_DANGER)
		locked_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		locked_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_vbox.add_child(locked_text)
	
	var name_bg := ColorRect.new()
	name_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_bg.anchor_top = 0.86
	name_bg.color = UI.NAME_BAR_BG
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_bg)
	
	var name_lbl := Label.new()
	name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_lbl.offset_left = 4
	name_lbl.offset_right = -4
	name_lbl.offset_top = 2
	name_lbl.offset_bottom = -2
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", UI.TEXT_PRIMARY if is_unlocked else UI.TEXT_MUTED)
	name_lbl.text = data.display_name if data else char_id
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bg.add_child(name_lbl)
	
	# White border overlay on TOP of everything
	var border_overlay := Panel.new()
	border_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	border_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = UI.TRANSPARENT
	border_style.border_color = UI.ACCENT_PRIMARY if is_unlocked else UI.COLOR_LOCKED
	border_style.set_border_width_all(3 if is_unlocked else 2)
	border_style.set_corner_radius_all(12)
	border_overlay.add_theme_stylebox_override("panel", border_style)
	card.add_child(border_overlay)
	card.set_meta("border_overlay", border_overlay)
	
	card.gui_input.connect(_on_card_input.bind(char_id))
	card.mouse_entered.connect(_on_card_hover.bind(char_id))
	card.mouse_exited.connect(_on_card_unhover.bind(char_id))
	
	return card

func _apply_panel_style(panel: Panel) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_color = UI.ACCENT_PRIMARY
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)

func _apply_card_style(card: Panel, in_squad: bool, is_hovered: bool = false) -> void:
	# Base panel style (no border, just background)
	var style := StyleBoxFlat.new()
	style.bg_color = UI.CHAR_NORMAL
	style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", style)
	
	# Update border overlay if it exists
	var border_overlay = card.get_meta("border_overlay") if card.has_meta("border_overlay") else null
	if border_overlay:
		var border_style := StyleBoxFlat.new()
		border_style.bg_color = UI.TRANSPARENT
		border_style.set_corner_radius_all(12)
		
		if in_squad:
			border_style.border_color = UI.COLOR_SUCCESS
			border_style.set_border_width_all(4)
		elif is_hovered:
			border_style.border_color = UI.ACCENT_HOVER
			border_style.set_border_width_all(4)
		else:
			border_style.border_color = UI.ACCENT_PRIMARY
			border_style.set_border_width_all(3)
		
		border_overlay.add_theme_stylebox_override("panel", border_style)

func _apply_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UI.ENTRY_BG
	normal.border_color = UI.BORDER_DEFAULT
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UI.BG_LIGHT
	hover.border_color = UI.ACCENT_PRIMARY
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UI.TEXT_PRIMARY)

func _apply_random_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UI.BTN_BACK_BG
	normal.border_color = UI.COLOR_DANGER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UI.BTN_BACK_HOVER_BG
	hover.border_color = UI.COLOR_DANGER
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UI.TEXT_PRIMARY)

func _on_random_pressed() -> void:
	UISounds.play_select()
	# Disconnect squad_complete signal to prevent auto-transition
	if _squad_slots.squad_complete.is_connected(_on_squad_complete):
		_squad_slots.squad_complete.disconnect(_on_squad_complete)
	
	# Clear current squad
	_squad_slots.clear()
	_update_card_states()
	
	# Get all character IDs and filter to only unlocked ones
	var all_ids: Array = _registry.get_all_character_ids().duplicate()
	var unlocked_ids: Array = []
	for char_id in all_ids:
		if ShopMenuScript.is_character_unlocked(char_id):
			unlocked_ids.append(char_id)
	unlocked_ids.shuffle()
	
	# Pick first 3 unlocked characters
	for i in range(mini(3, unlocked_ids.size())):
		_squad_slots.add_character(unlocked_ids[i])
	
	_update_card_states()
	
	# Reconnect the signal
	_squad_slots.squad_complete.connect(_on_squad_complete)
	
	# Manually check if complete, since we suppressed the signal during adding
	if _squad_slots.is_complete():
		_on_squad_complete()

func _apply_next_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UI.BTN_SUCCESS_BG
	normal.border_color = UI.BTN_SUCCESS_BORDER
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UI.BTN_SUCCESS_HOVER_BG
	hover.border_color = UI.BTN_SUCCESS_HOVER_BORDER
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UI.BTN_SUCCESS_TEXT)

func _on_next_pressed() -> void:
	# Only proceed if we have a full squad (3 characters)
	if not _squad_slots.is_complete():
		return
	UISounds.play_confirm()
	_transition_to_stage()

func _on_card_input(event: InputEvent, char_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check if character is unlocked
		var card = _cards.get(char_id)
		var is_unlocked: bool = true
		if card:
			is_unlocked = card.get_meta("is_unlocked", true)
		
		if not is_unlocked:
			# Shake the card to indicate locked
			if card:
				var orig_pos: float = card.position.x
				var tween := create_tween()
				tween.tween_property(card, "position:x", orig_pos + 5, 0.05)
				tween.tween_property(card, "position:x", orig_pos - 5, 0.05)
				tween.tween_property(card, "position:x", orig_pos + 3, 0.05)
				tween.tween_property(card, "position:x", orig_pos, 0.05)
			return
		
		if _squad_slots.has_character(char_id):
			# Click on already-selected character removes them
			_remove_from_squad(char_id)
		else:
			_add_to_squad(char_id)

func _on_card_hover(char_id: String) -> void:
	if _registry:
		var data = _registry.get_character(char_id)
		_info_panel.set_character(data)
	
	var card = _cards.get(char_id)
	if card:
		var in_squad: bool = _squad_slots.has_character(char_id)
		_apply_card_style(card, in_squad, true)
		var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card, "scale", Vector2(1.02, 1.02), 0.1)

func _on_card_unhover(char_id: String) -> void:
	var card = _cards.get(char_id)
	if card:
		var in_squad: bool = _squad_slots.has_character(char_id)
		_apply_card_style(card, in_squad, false)
		var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card, "scale", Vector2.ONE, 0.1)

func _add_to_squad(char_id: String) -> void:
	if _squad_slots.has_character(char_id):
		return  # Already in squad
	
	if _squad_slots.add_character(char_id):
		_play_burst_sfx(char_id)
		_update_card_states()

func _play_burst_sfx(char_id: String) -> void:
	# Stop any currently playing burst sound to prevent overlap
	if _burst_audio.playing:
		_burst_audio.stop()
	
	# Use CharacterRegistry for sound loading (supports Commander random selection)
	var registry = CharacterRegistry.get_instance()
	var stream: AudioStream = registry.get_burst_sound(char_id)
	
	if stream:
		_burst_audio.stream = stream
		_burst_audio.play()

func _on_slot_cleared(_index: int) -> void:
	_update_card_states()

func _update_card_states() -> void:
	for char_id in _cards:
		var card = _cards[char_id]
		var in_squad: bool = _squad_slots.has_character(char_id)
		_apply_card_style(card, in_squad, false)
		card.modulate = UI.CHAR_IN_SQUAD if in_squad else Color.WHITE

func _remove_from_squad(char_id: String) -> void:
	_squad_slots.remove_character_by_id(char_id)
	_update_card_states()

func _on_squad_complete() -> void:
	UISounds.play_confirm()
	_transition_to_stage()

func _transition_to_stage() -> void:
	if _phase == Phase.STAGE:
		return
	_phase = Phase.STAGE
	
	if _transition_tween:
		_transition_tween.kill()
	
	var vh := get_viewport_rect().size.y
	_transition_tween = create_tween().set_parallel(true)
	_transition_tween.tween_property(_squad_container, "position:y", -vh, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_squad_container, "modulate:a", 0.0, 0.4)
	_transition_tween.tween_property(_stage_container, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_stage_container, "modulate:a", 1.0, 0.4).set_delay(0.1)

func _on_stage_back() -> void:
	UISounds.play_back()
	_transition_to_squad()

func _transition_to_squad() -> void:
	if _phase == Phase.SQUAD:
		return
	_phase = Phase.SQUAD
	
	# Reset stage selector state (music, easter eggs)
	# Reset stage selector state (music, easter eggs)
	if _stage_selector and _stage_selector.has_method("clear_goddess_flags"):
		# _stage_selector.clear_goddess_flags() # DISABLED: Prevents aggressive flag clearing
		pass
	elif _stage_selector and _stage_selector.has_method("reset_state"):
		# _stage_selector.reset_state()
		pass
	
	if _transition_tween:
		_transition_tween.kill()
	
	var vh := get_viewport_rect().size.y
	_transition_tween = create_tween().set_parallel(true)
	_transition_tween.tween_property(_stage_container, "position:y", vh, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_stage_container, "modulate:a", 0.0, 0.4)
	_transition_tween.tween_property(_squad_container, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_squad_container, "modulate:a", 1.0, 0.4).set_delay(0.1)

func _on_stage_confirmed(stage_id: String) -> void:
	var squad_ids: Array[String] = _squad_slots.get_squad()
	
	# Convert character IDs to indices for the Level/GameState
	var squad_indices: Array[int] = []
	var all_ids = _registry.get_all_character_ids()
	for char_id in squad_ids:
		var idx: int = all_ids.find(char_id)
		if idx >= 0:
			squad_indices.append(idx)
	
	# Emit signal for MenuManager if connected
	play_requested.emit(squad_indices, stage_id)
	
	# If no listeners (loaded directly from game), handle game start ourselves
	if play_requested.get_connections().is_empty():
		_start_game(squad_indices, stage_id)

func _start_game(squad: Array[int], stage_id: String) -> void:
	# Save selection to GameState
	if GameState:
		GameState.set_selected_characters(squad)
		if squad.size() > 0:
			GameState.set_player_character(squad[0])
		GameState.current_stage_id = stage_id
	
	# Stop menu music
	if MenuManager:
		MenuManager.stop_menu_music()
	
	# Change to Level scene
	get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")
