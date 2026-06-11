extends Control
## Character and Stage Selection Menu.
## Layout: Grid (top) + Details (bottom). Picking a character reveals the
## stage selector.

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

signal play_requested(character_index: int, stage_id: String)
signal back_requested

const CharacterInfoPanelScript = preload("res://scripts/ui/components/CharacterInfoPanel.gd")
const StageSelectorScript = preload("res://scripts/ui/components/StageSelector.gd")
const VenetianBlindsScript = preload("res://scripts/ui/components/VenetianBlindsBackground.gd")
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

const CARD_SIZE := Vector2(140, 220)
const GRID_COLUMNS := 5

enum Phase {CHARACTER, STAGE}
var _phase: Phase = Phase.CHARACTER

var _selected_char_id: String = ""

# Unlock storefront state
var _core_counter: PristineCoreContainer = null
var _unlock_dialog: ConfirmationDialog = null
var _pending_unlock_id: String = ""

var _registry: RefCounted
var _cards: Dictionary = {} # char_id -> card node
var _card_tweens: Dictionary = {} # char_id -> Tween (for killing old tweens)

var _burst_audio: AudioStreamPlayer # For character selection burst SFX

var _bg: Control
var _char_container: Control
var _stage_container: Control
var _grid: Control # VBoxContainer holding row HBoxContainers
var _info_panel: Panel
var _stage_selector: Control
var _transition_tween: Tween

# PERFORMANCE: Pre-cached StyleBox objects to avoid per-hover allocation
var _style_normal: StyleBoxFlat
var _style_hovered: StyleBoxFlat
var _border_style_normal: StyleBoxFlat
var _border_style_hovered: StyleBoxFlat

func _ready() -> void:
	_init_style_cache() # PERFORMANCE: Pre-create StyleBox objects
	_load_registry()
	_build_ui()
	_populate_grid()
	_setup_burst_audio()
	
	# Start menu music if not already playing (handles direct scene load from game)
	_ensure_menu_music()
	
	# Auto-focus first character card for controller users
	call_deferred("_grab_initial_focus")

func _setup_burst_audio() -> void:
	_burst_audio = AudioStreamPlayer.new()
	_burst_audio.bus = "SFX" # Use SFX bus for burst preview sounds
	add_child(_burst_audio)

func _ensure_menu_music() -> void:
	# When coming from the game (Level scene), MenuManager's music is stopped
	# We need to restart it when entering the character select menu
	if MenuManager:
		MenuManager.start_menu_music()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
		
	if event.is_action_pressed("ui_cancel"):
		_handle_escape()
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		# Only handle character card selection in CHARACTER phase
		if _phase != Phase.CHARACTER:
			return
		# Controller A button on focused card
		var focused := get_viewport().gui_get_focus_owner()
		if focused and focused.has_meta("char_id"):
			var char_id: String = focused.get_meta("char_id")
			var is_unlocked: bool = focused.get_meta("is_unlocked", false)
			if is_unlocked:
				_select_character(char_id)
			else:
				_try_unlock(char_id)
			get_viewport().set_input_as_handled()

func _handle_escape() -> void:
	if _phase == Phase.STAGE:
		# Go back to character selection
		_transition_to_character()
	else:
		_go_back()


func _transition_to_stage() -> void:
	if _phase == Phase.STAGE:
		return
	
	_phase = Phase.STAGE
	_stage_container.visible = true # Enable input processing for stage selector
	
	# Release focus from character cards so controller input doesn't affect them
	var focused := get_viewport().gui_get_focus_owner()
	if focused and focused.has_meta("char_id"):
		focused.release_focus()
	
	if _transition_tween:
		_transition_tween.kill()
	
	var vh := get_viewport_rect().size.y
	_transition_tween = create_tween().set_parallel(true)
	_transition_tween.tween_property(_char_container, "position:y", -vh, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_char_container, "modulate:a", 0.0, 0.4)
	_transition_tween.tween_property(_stage_container, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_stage_container, "modulate:a", 1.0, 0.4).set_delay(0.1)
	
	# CRITICAL: Transfer focus to the Stage Selector so controller works immediately
	if _stage_selector and _stage_selector.has_method("_grab_initial_focus"):
		# Wait for transition to start so inputs aren't eaten
		_stage_selector.call_deferred("_grab_initial_focus")
	elif _stage_selector:
		# Fallback to finding a button
		var btn = _stage_selector.find_child("StartButton", true, false)
		if btn: btn.grab_focus()

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
	
	# Character selection container
	_char_container = Control.new()
	_char_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_char_container)
	_build_character_phase()
	
	# Stage selection container (hidden below)
	_stage_container = Control.new()
	_stage_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_container.position.y = get_viewport_rect().size.y
	_stage_container.modulate.a = 0.0
	_stage_container.visible = false # CRITICAL: Hide so it doesn't eat input relative to is_visible_in_tree()
	add_child(_stage_container)
	_build_stage_phase()

	# Pristine Core counter (top-right) - characters are unlocked here with cores
	_core_counter = PristineCoreContainer.new()
	_core_counter.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_core_counter.position = Vector2(get_viewport_rect().size.x - 224, 24)
	_char_container.add_child(_core_counter)
	call_deferred("_update_core_counter")

	# Unlock confirmation dialog
	_unlock_dialog = ConfirmationDialog.new()
	_unlock_dialog.title = "Unlock Character"
	_unlock_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_unlock_dialog.ok_button_text = "Unlock"
	_unlock_dialog.confirmed.connect(_on_unlock_confirmed)
	add_child(_unlock_dialog)

func _build_character_phase() -> void:
	# Main content area (full height minus bottom buttons)
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 24
	content.offset_bottom = -70
	content.offset_left = 24
	content.offset_right = -24
	_char_container.add_child(content)

	# Grid (top) + Details (bottom)
	var left_side := Control.new()
	left_side.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_char_container.add_child(btn_row)
	
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
	
	# Set up explicit focus neighbors for proper row-based navigation
	call_deferred("_setup_card_focus_neighbors")

func _create_card(char_id: String, data: Resource) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_SIZE.x, 0) # Min width only, height expands
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.focus_mode = Control.FOCUS_ALL # Enable controller focus
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

		# Unlock price (Pristine Cores)
		var cost_row := HBoxContainer.new()
		cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
		cost_row.add_theme_constant_override("separation", 6)
		cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_vbox.add_child(cost_row)

		var core_icon := PristineCoreContainer.PristineCoreIcon.new()
		core_icon.custom_minimum_size = Vector2(26, 26)
		core_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_row.add_child(core_icon)

		var cost_text := Label.new()
		cost_text.text = str(CharacterRegistry.get_unlock_cost(char_id))
		cost_text.add_theme_font_size_override("font_size", 26)
		cost_text.add_theme_color_override("font_color", UI.COLOR_CORE)
		cost_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_row.add_child(cost_text)

		var locked_text := Label.new()
		locked_text.text = "CLICK TO UNLOCK"
		locked_text.add_theme_font_size_override("font_size", 16)
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
	# Controller focus events (same as hover for visual consistency)
	card.focus_entered.connect(_on_card_hover.bind(char_id))
	card.focus_exited.connect(_on_card_unhover.bind(char_id))
	
	return card

func _apply_panel_style(panel: Panel) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_color = UI.ACCENT_PRIMARY
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)


func _init_style_cache() -> void:
	"""PERFORMANCE: Pre-create all StyleBox variations to avoid per-hover allocation."""
	# Base panel style (same for all states)
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = UI.CHAR_NORMAL
	_style_normal.set_corner_radius_all(12)
	
	# Border styles - normal
	_border_style_normal = StyleBoxFlat.new()
	_border_style_normal.bg_color = UI.TRANSPARENT
	_border_style_normal.set_corner_radius_all(12)
	_border_style_normal.border_color = UI.ACCENT_PRIMARY
	_border_style_normal.set_border_width_all(3)
	
	# Border styles - hovered
	_border_style_hovered = StyleBoxFlat.new()
	_border_style_hovered.bg_color = UI.TRANSPARENT
	_border_style_hovered.set_corner_radius_all(12)
	_border_style_hovered.border_color = UI.ACCENT_HOVER
	_border_style_hovered.set_border_width_all(4)


func _apply_card_style(card: Panel, is_hovered: bool = false) -> void:
	# PERFORMANCE: Use cached styles instead of creating new ones
	card.add_theme_stylebox_override("panel", _style_normal)

	# Update border overlay if it exists
	var border_overlay = card.get_meta("border_overlay") if card.has_meta("border_overlay") else null
	if border_overlay:
		var border_style: StyleBoxFlat = _border_style_hovered if is_hovered else _border_style_normal
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

	# Get all character IDs and filter to only unlocked ones
	var all_ids: Array = _registry.get_all_character_ids().duplicate()
	var unlocked_ids: Array = []
	for char_id in all_ids:
		if ShopMenuScript.is_character_unlocked(char_id):
			unlocked_ids.append(char_id)
	if unlocked_ids.is_empty():
		return
	unlocked_ids.shuffle()

	_select_character(unlocked_ids[0])

func _on_card_input(event: InputEvent, char_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check if character is unlocked
		var card = _cards.get(char_id)
		var is_unlocked: bool = true
		if card:
			is_unlocked = card.get_meta("is_unlocked", true)
		
		if not is_unlocked:
			_try_unlock(char_id)
			return

		_select_character(char_id)

func _on_card_hover(char_id: String) -> void:
	if _registry:
		var data = _registry.get_character(char_id)
		_info_panel.set_character(data)

	var card = _cards.get(char_id)
	if card:
		_apply_card_style(card, true)

		# PERFORMANCE: Kill old tween before starting new one
		if _card_tweens.has(char_id) and _card_tweens[char_id] and _card_tweens[char_id].is_valid():
			_card_tweens[char_id].kill()

		var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card, "scale", Vector2(1.02, 1.02), 0.1)
		_card_tweens[char_id] = tween

func _on_card_unhover(char_id: String) -> void:
	var card = _cards.get(char_id)
	if card:
		_apply_card_style(card, false)

		# PERFORMANCE: Kill old tween before starting new one
		if _card_tweens.has(char_id) and _card_tweens[char_id] and _card_tweens[char_id].is_valid():
			_card_tweens[char_id].kill()

		var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card, "scale", Vector2.ONE, 0.1)
		_card_tweens[char_id] = tween

func _select_character(char_id: String) -> void:
	_selected_char_id = char_id
	_play_burst_sfx(char_id)
	UISounds.play_confirm()
	_transition_to_stage()

# ─── Unlock storefront ──────────────────────────────────────────────────

func _try_unlock(char_id: String) -> void:
	var cost := CharacterRegistry.get_unlock_cost(char_id)

	if GameManager.get_pristine_cores() < cost:
		# Can't afford: shake the card
		UISounds.play_back()
		var card = _cards.get(char_id)
		if card:
			var orig_pos: float = card.position.x
			var tween := create_tween()
			tween.tween_property(card, "position:x", orig_pos + 5, 0.05)
			tween.tween_property(card, "position:x", orig_pos - 5, 0.05)
			tween.tween_property(card, "position:x", orig_pos + 3, 0.05)
			tween.tween_property(card, "position:x", orig_pos, 0.05)
		return

	# Confirm before spending
	_pending_unlock_id = char_id
	var data = _registry.get_character(char_id) if _registry else null
	var char_name: String = data.display_name if data else char_id
	_unlock_dialog.dialog_text = "Unlock %s for %d Pristine Cores?" % [char_name, cost]
	_unlock_dialog.popup_centered()

func _on_unlock_confirmed() -> void:
	if _pending_unlock_id.is_empty():
		return
	var char_id := _pending_unlock_id
	_pending_unlock_id = ""

	var cost := CharacterRegistry.get_unlock_cost(char_id)
	if not GameManager.spend_pristine_cores(cost):
		return

	ShopMenuScript.unlock_character(char_id)

	# Track achievement
	if has_node("/root/AchievementManager"):
		get_node("/root/AchievementManager").on_character_unlocked_in_shop(char_id)

	UISounds.play_confirm()
	_play_burst_sfx(char_id)
	_rebuild_grid()
	_update_core_counter()
	print("[CharacterSelectMenu] Unlocked character: %s (%d cores)" % [char_id, cost])

func _rebuild_grid() -> void:
	var row1: HBoxContainer = _grid.get_meta("row1") if _grid else null
	var row2: HBoxContainer = _grid.get_meta("row2") if _grid else null
	if not row1 or not row2:
		return
	for child in row1.get_children():
		child.queue_free()
	for child in row2.get_children():
		child.queue_free()
	_cards.clear()
	_card_tweens.clear()
	_populate_grid()
	call_deferred("_grab_initial_focus")

func _update_core_counter() -> void:
	if _core_counter and _core_counter.get_count_label():
		_core_counter.get_count_label().text = str(GameManager.get_pristine_cores())

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

func _on_stage_back() -> void:
	UISounds.play_back()
	_transition_to_character()

func _transition_to_character() -> void:
	if _phase == Phase.CHARACTER:
		return
	_phase = Phase.CHARACTER
	
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
	_transition_tween.tween_property(_char_container, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_char_container, "modulate:a", 1.0, 0.4).set_delay(0.1)
	_transition_tween.tween_callback(func(): _stage_container.visible = false) # Disable input processing after transition

	# Restore focus to first card when returning to character phase
	call_deferred("_grab_initial_focus")

func _on_stage_confirmed(stage_id: String) -> void:
	# Convert character ID to index for the Level/GameManager
	var all_ids = _registry.get_all_character_ids()
	var char_index: int = all_ids.find(_selected_char_id)
	if char_index < 0:
		push_warning("[CharacterSelectMenu] No character selected, defaulting to 0")
		char_index = 0

	# Emit signal for MenuManager if connected
	play_requested.emit(char_index, stage_id)

	# If no listeners (loaded directly from game), handle game start ourselves
	if play_requested.get_connections().is_empty():
		_start_game(char_index, stage_id)

func _start_game(char_index: int, stage_id: String) -> void:
	# Save selection to GameManager
	if GameManager:
		GameManager.set_player_character(char_index)
		GameManager.current_stage_id = stage_id
	
	# Stop menu music
	if MenuManager:
		MenuManager.stop_menu_music()
	
	# Change to Level scene
	get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")


## Auto-focus first character card for controller users
func _grab_initial_focus() -> void:
	# Find and focus the first unlocked character card
	for char_id in _cards.keys():
		var card: Control = _cards[char_id]
		if card and card.get_meta("is_unlocked", false):
			card.grab_focus()
			return
	# Fallback to first card if all locked
	if not _cards.is_empty():
		var first_card: Control = _cards.values()[0]
		if first_card:
			first_card.grab_focus()


## Set up explicit focus neighbors for row-based navigation
func _setup_card_focus_neighbors() -> void:
	var row1: HBoxContainer = _grid.get_meta("row1") if _grid else null
	var row2: HBoxContainer = _grid.get_meta("row2") if _grid else null
	if not row1 or not row2:
		return
	
	var row1_cards: Array[Control] = []
	var row2_cards: Array[Control] = []
	
	for child in row1.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			row1_cards.append(child)
	for child in row2.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			row2_cards.append(child)
	
	# Set up row 1 horizontal neighbors
	for i in range(row1_cards.size()):
		var card := row1_cards[i]
		# Left neighbor (wrap to end of row)
		var left_idx := i - 1 if i > 0 else row1_cards.size() - 1
		card.focus_neighbor_left = card.get_path_to(row1_cards[left_idx])
		# Right neighbor (wrap to start of row)
		var right_idx := i + 1 if i < row1_cards.size() - 1 else 0
		card.focus_neighbor_right = card.get_path_to(row1_cards[right_idx])
		# Down neighbor (same column in row 2, or last if row 2 is shorter)
		if row2_cards.size() > 0:
			var down_idx := mini(i, row2_cards.size() - 1)
			card.focus_neighbor_bottom = card.get_path_to(row2_cards[down_idx])
	
	# Set up row 2 horizontal neighbors
	for i in range(row2_cards.size()):
		var card := row2_cards[i]
		# Left neighbor (wrap to end of row)
		var left_idx := i - 1 if i > 0 else row2_cards.size() - 1
		card.focus_neighbor_left = card.get_path_to(row2_cards[left_idx])
		# Right neighbor (wrap to start of row)
		var right_idx := i + 1 if i < row2_cards.size() - 1 else 0
		card.focus_neighbor_right = card.get_path_to(row2_cards[right_idx])
		# Up neighbor (same column in row 1, or last if row 1 is shorter)
		if row1_cards.size() > 0:
			var up_idx := mini(i, row1_cards.size() - 1)
			card.focus_neighbor_top = card.get_path_to(row1_cards[up_idx])
