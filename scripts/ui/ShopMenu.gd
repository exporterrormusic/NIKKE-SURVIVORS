extends Control
class_name ShopMenu
## Main Menu Shop - Permanent upgrades purchased with Pristine Rapture Cores.
## Layout: Left sidebar with character portraits + GENERAL, right side with upgrade grid.
## Characters can be unlocked here. Default unlocked: Snow White, Rapunzel, Scarlet.

# Removed SaveManagerScript preload - now using global SaveManager autoload
const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

signal back_requested

const GENERAL_FILTER := "GENERAL"

# Session state not reset on menu close
static var _session_warning_shown: bool = false

# Character data - loaded from CharacterRegistry (single source of truth)
var _registry: CharacterRegistry = null

# Character unlock costs
const CHARACTER_UNLOCK_COST := 3 # Pristine Rapture Cores to unlock a character


# Shop data persistence
var _unlocked_characters: Array[String] = []
var _upgrade_levels: Dictionary = {} # "upgrade_id" -> level
var _cores_spent: Dictionary = {} # "character_id" or "general" -> total cores spent

var _selected_filter: String = GENERAL_FILTER
var _character_entries: Array[Dictionary] = []

# UI references
var _character_list: VBoxContainer = null
var _upgrade_grid: GridContainer = null
var _upgrade_scroll: ScrollContainer = null
var _right_panel: Panel = null
var _currency_label: Label = null
var _currency_icon: Control = null
var _unlock_panel: Control = null
var _button_group: ButtonGroup = null
var _warning_popup: ConfirmationDialog = null
var _pending_purchase_callback: Callable = Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_registry = CharacterRegistry.get_instance()
	_button_group = ButtonGroup.new()
	
	_load_shop_data()
	_build_ui()
	_create_warning_popup()
	_select_filter(GENERAL_FILTER)


func _get_talent_tree() -> Control:
	var canvas := get_parent().get_node_or_null("CanvasLayer")
	if canvas == null:
		canvas = get_tree().root
	return canvas.get_node_or_null("TalentTree")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		UISounds.play_back()
		emit_signal("back_requested")
	
	# All debug keys moved to F5 Debug Menu in Level.gd


func _load_shop_data() -> void:
	var data: Dictionary = SaveManager.load_config(SaveManager.SHOP_PATH)
	
	# Start with default unlocked characters
	_unlocked_characters.clear()
	for char_id in CharacterRegistry.DEFAULT_UNLOCKED:
		_unlocked_characters.append(char_id)
	
	if not data.is_empty():
		# Load unlocked characters
		var saved_unlocked = data.get("characters", {}).get("unlocked", [])
		for char_id in saved_unlocked:
			if char_id not in _unlocked_characters:
				_unlocked_characters.append(char_id)
		
		# Load upgrade levels
		var saved_upgrades = data.get("upgrades", {})
		if saved_upgrades is Dictionary:
			for key in saved_upgrades:
				_upgrade_levels[key] = saved_upgrades[key]
		
		# Load cores spent
		var saved_cores = data.get("cores_spent", {})
		if saved_cores is Dictionary:
			for key in saved_cores:
				_cores_spent[key] = saved_cores[key]
		
		# Load talent tree data
		var talent_tree = _get_talent_tree()
		if talent_tree and talent_tree.has_method("set_unlocked_talents"):
			var saved_talents = data.get("talents", {}).get("unlocked", {})
			talent_tree.set_unlocked_talents(saved_talents)
	
	_build_ui()
	print("[ShopMenu] Loaded shop data: %d characters unlocked, %d upgrades" % [_unlocked_characters.size(), _upgrade_levels.size()])


func _save_shop_data() -> void:
	# Save unlocked characters (excluding defaults to save space, though we could save all)
	var extra_unlocked: Array = []
	for char_id in _unlocked_characters:
		if char_id not in CharacterRegistry.DEFAULT_UNLOCKED:
			extra_unlocked.append(char_id)
	
	var data := {
		"characters": {
			"unlocked": extra_unlocked
		},
		"upgrades": _upgrade_levels,
		"cores_spent": _cores_spent
	}
	
	# Save talent data
	var talent_tree = _get_talent_tree()
	if talent_tree and talent_tree.has_method("get_unlocked_talents"):
		data["talents"] = {
			"unlocked": talent_tree.get_unlocked_talents()
		}
	
	var err := SaveManager.save_config(data, SaveManager.SHOP_PATH)
	if err == OK:
		print("[ShopMenu] Shop data saved")
		# Invalidate upgrade cache so hot paths get fresh data
		invalidate_upgrade_cache()
	else:
		push_error("[ShopMenu] Failed to save shop data: %d" % err)


func _build_ui() -> void:
	# Clear existing children
	for child in get_children():
		child.queue_free()
	
	# Background with venetian blinds effect
	var bg := Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists("res://scripts/ui/components/VenetianBlindsBackground.gd"):
		bg.set_script(load("res://scripts/ui/components/VenetianBlindsBackground.gd"))
	add_child(bg)
	
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = UI.OVERLAY_LIGHT
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	
	# Top bar with title and currency
	var top_bar := Panel.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = 24
	top_bar.offset_bottom = 160
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_stylebox_override("panel", _make_letterbox_style())
	add_child(top_bar)
	
	# Title label - absolutely centered in the header
	var title_label := Label.new()
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.text = "SHOP"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if UI.FONT_TITLE:
		title_label.add_theme_font_override("font", UI.FONT_TITLE)
	title_label.add_theme_font_size_override("font_size", 80)
	title_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	title_label.add_theme_color_override("font_outline_color", UI.SHOP_TITLE_OUTLINE)
	title_label.add_theme_constant_override("outline_size", 3)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(title_label) # Restored
	
	# BACK Button - Modular SciFiBackButton component
	var back_btn := SciFiBackButton.new()
	back_btn.position = Vector2(48, 30) # Absolute center for 136px header
	back_btn.custom_minimum_size = Vector2(200, 75)
	
	back_btn.pressed.connect(func():
		UISounds.play_back()
		back_requested.emit()
	)
	top_bar.add_child(back_btn)
	
	# Currency container - positions elements to the right via spacer
	var currency_row := HBoxContainer.new()
	currency_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	currency_row.offset_left = 48
	currency_row.offset_right = -48
	currency_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(currency_row) # Restored
	# The one at 232 was my new insertion?
	# Step 1046: I inserted `var currency_row := HBoxContainer.new()` at line 232 (in my replacement text).
	# But I also *kept* `var currency_row := HBoxContainer.new()` at line 249 (in the "original" part that followed?).
	# Wait, the tool output showed:
	# +	var currency_row := HBoxContainer.new()
	# ...
	# +	# Currency container - positioned at right side
	# +	var currency_row := HBoxContainer.new()
	# It duplicated it in the *replacement content*. 
	# Logic: I will delete the SECOND declaration.
	
	# Actually, looking at the file view:
	# Line 232: var currency_row := HBoxContainer.new()
	# Line 249: var currency_row := HBoxContainer.new()
	# I should check which one is configured correctly.
	# 232 is `PRESET_CENTER_RIGHT` (my new code).
	# 249 is `PRESET_FULL_RECT` (original code).
	# I wanted the RIGHT positioning.
	# But `PRESET_FULL_RECT` with offset might be how it was working.
	# User said "PRISTINE RAPTURE CORE counter is on the right side".
	# Original code used `PRESET_FULL_RECT` with margins.
	# My new code `PRESET_CENTER_RIGHT` might be safer.
	# I will keep the *first* one (232) and remove the second (249).
	# Also remove lines 234-245 (commented out junk).
	
	# Actually, simply removing 249-254 is safest.
	# But wait, lines 256+ use `currency_row`.
	# If I keep 232, `currency_row` exists.
	# So I remove lines 248-254.

	
	# Spacer to push currency to right
	var currency_spacer := Control.new()
	currency_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	currency_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	currency_row.add_child(currency_spacer)
	
	# Sci-fi danger container for Pristine Rapture Core currency (modular component)
	var core_container := PristineCoreContainer.new()
	core_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	currency_row.add_child(core_container)
	
	# Store references for updating
	_currency_icon = core_container.get_core_icon()
	_currency_label = core_container.get_count_label()
	
	_update_currency_display()
	
	# Main content panel
	var content_panel := Panel.new()
	content_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_panel.offset_left = 48
	content_panel.offset_top = 176
	content_panel.offset_right = -48
	content_panel.offset_bottom = -48
	content_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(content_panel)
	
	# Content margin
	var content_margin := MarginContainer.new()
	content_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_margin.add_theme_constant_override("margin_left", 16)
	content_margin.add_theme_constant_override("margin_right", 16)
	content_margin.add_theme_constant_override("margin_top", 16)
	content_margin.add_theme_constant_override("margin_bottom", 16)
	content_panel.add_child(content_margin)
	
	# Main HBox: Left sidebar + Right content
	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 16)
	content_margin.add_child(main_hbox)
	
	# === LEFT SIDEBAR (20%) ===
	var left_panel := Panel.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.25
	left_panel.add_theme_stylebox_override("panel", _make_sidebar_style())
	main_hbox.add_child(left_panel)
	
	var left_margin := MarginContainer.new()
	left_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_margin.add_theme_constant_override("margin_left", 8)
	left_margin.add_theme_constant_override("margin_right", 8)
	left_margin.add_theme_constant_override("margin_top", 8)
	left_margin.add_theme_constant_override("margin_bottom", 8)
	left_panel.add_child(left_margin)
	
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_margin.add_child(left_scroll)
	
	_character_list = VBoxContainer.new()
	_character_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_list.add_theme_constant_override("separation", 10)
	var char_list_margin := MarginContainer.new()
	char_list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_list_margin.add_theme_constant_override("margin_right", 14)
	left_scroll.add_child(char_list_margin)
	char_list_margin.add_child(_character_list)
	
	# === RIGHT CONTENT (80%) ===
	_right_panel = Panel.new()
	_right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_panel.size_flags_stretch_ratio = 1.0
	_right_panel.add_theme_stylebox_override("panel", _make_content_style())
	main_hbox.add_child(_right_panel)
	
	var right_vbox := VBoxContainer.new()
	right_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_vbox.offset_left = 16
	right_vbox.offset_right = -16
	right_vbox.offset_top = 16
	right_vbox.offset_bottom = -16
	right_vbox.add_theme_constant_override("separation", 12)
	_right_panel.add_child(right_vbox)
	
	# Upgrade scroll
	_upgrade_scroll = ScrollContainer.new()
	_upgrade_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrade_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_vbox.add_child(_upgrade_scroll)
	
	# Upgrade grid container
	var grid_margin := MarginContainer.new()
	grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_scroll.add_child(grid_margin)
	
	_upgrade_grid = GridContainer.new()
	_upgrade_grid.columns = 5 # 5 per row instead of 3
	_upgrade_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_grid.add_theme_constant_override("h_separation", 12)
	_upgrade_grid.add_theme_constant_override("v_separation", 12)
	grid_margin.add_child(_upgrade_grid)
	
	# Unlock panel (shown when locked character selected)
	_unlock_panel = _create_unlock_panel()
	_unlock_panel.visible = false
	right_vbox.add_child(_unlock_panel)
	
	# Build character list
	_build_character_list()
	_update_sidebar_counts()


func _create_core_icon(icon_size: int) -> Control:
	# Create a shiny red sphere with glowing interior
	var container := Control.new()
	container.custom_minimum_size = Vector2(icon_size, icon_size)
	
	# Use inner class from PristineCoreContainer component
	var core := PristineCoreContainer.PristineCoreIcon.new()
	core.custom_minimum_size = Vector2(icon_size, icon_size)
	core.size = Vector2(icon_size, icon_size)
	container.add_child(core)
	
	return container


func _build_character_list() -> void:
	if not _character_list:
		return
	
	for child in _character_list.get_children():
		child.queue_free()
	_character_entries.clear()
	
	# Add "General" category first
	var general_entry := _create_character_entry(GENERAL_FILTER, "General", null, true)
	_character_entries.append(general_entry)
	
	# Add all characters from registry
	var char_ids := _registry.get_all_character_ids()
	var char_names := _registry.get_all_character_names()
	var portrait_paths := _registry.get_all_portrait_paths()
	
	for i in range(char_ids.size()):
		var char_name: String = char_names[i] if i < char_names.size() else ""
		var char_id: String = char_ids[i]
		var is_unlocked: bool = char_id in _unlocked_characters
		var portrait: Texture2D = null
		if i < portrait_paths.size() and ResourceLoader.exists(portrait_paths[i]):
			portrait = load(portrait_paths[i])
		var entry := _create_character_entry(char_id, char_name, portrait, is_unlocked)
		_character_entries.append(entry)


func _create_character_entry(code: String, _display_name: String, portrait: Texture2D, is_unlocked: bool) -> Dictionary:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _button_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 165)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_character_button_styles(button, is_unlocked)
	
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(hbox)
	
	# Portrait section - centered in its area, larger to fill space
	var portrait_container := CenterContainer.new()
	portrait_container.custom_minimum_size = Vector2(165, 165)
	portrait_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(portrait_container)
	
	var portrait_panel := Panel.new()
	portrait_panel.custom_minimum_size = Vector2(150, 150)
	portrait_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_panel.clip_contents = true
	portrait_panel.add_theme_stylebox_override("panel", _make_portrait_style(is_unlocked))
	portrait_container.add_child(portrait_panel)
	
	if portrait != null:
		var tex_rect := TextureRect.new()
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.offset_left = 3
		tex_rect.offset_top = 3
		tex_rect.offset_right = -3
		tex_rect.offset_bottom = -3
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.texture = portrait
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Darken if locked
		if not is_unlocked:
			tex_rect.modulate = UI.SHOP_PORTRAIT_LOCKED
		portrait_panel.add_child(tex_rect)
		
		# Lock overlay for locked characters - ON TOP of portrait
		if not is_unlocked and code != GENERAL_FILTER:
			var lock_overlay := VBoxContainer.new()
			lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			lock_overlay.alignment = BoxContainer.ALIGNMENT_CENTER
			lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			portrait_panel.add_child(lock_overlay)
			
			var lock_icon := Label.new()
			lock_icon.text = "🔒"
			lock_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lock_icon.add_theme_font_size_override("font_size", 48)
			lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock_overlay.add_child(lock_icon)
			
			var locked_text := Label.new()
			locked_text.text = "LOCKED"
			locked_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if UI.FONT_BOLD:
				locked_text.add_theme_font_override("font", UI.FONT_BOLD)
			locked_text.add_theme_font_size_override("font_size", 14)
			locked_text.add_theme_color_override("font_color", UI.COLOR_CORE)
			locked_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock_overlay.add_child(locked_text)
	else:
		# Exciting animated icon for General (upgrades)
		var icon_container := Control.new()
		icon_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_panel.add_child(icon_container)
		
		# Glowing background burst effect
		var glow := _GeneralUpgradeIcon.new()
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(glow)
	
	# Subtle divider line - centered vertically (matching Achievements)
	var divider_container := CenterContainer.new()
	divider_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	divider_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(divider_container)
	
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(2, 100)
	divider.color = UI.DIVIDER_LIGHT
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider_container.add_child(divider)
	
	# Cores spent label container - expand to fill remaining space and center
	var count_container := CenterContainer.new()
	count_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(count_container)
	
	var count_label := Label.new()
	count_label.text = "0"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if UI.FONT_BOLD:
		count_label.add_theme_font_override("font", UI.FONT_BOLD)
	count_label.add_theme_font_size_override("font_size", 56)
	count_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_container.add_child(count_label)
	
	button.pressed.connect(_on_character_pressed.bind(code))
	_character_list.add_child(button)
	
	return {
		"code": code,
		"button": button,
		"count_label": count_label,
		"is_unlocked": is_unlocked
	}


func _apply_character_button_styles(button: Button, is_unlocked: bool) -> void:
	var base_color := UI.CHAR_NORMAL if is_unlocked else UI.CHAR_LOCKED
	button.add_theme_stylebox_override("normal", _make_char_button_style(base_color))
	button.add_theme_stylebox_override("hover", _make_char_button_style(UI.CHAR_HOVER))
	button.add_theme_stylebox_override("pressed", _make_char_button_style(UI.CHAR_SELECTED))
	button.add_theme_stylebox_override("focus", _make_char_button_style(UI.CHAR_HOVER))


func _make_char_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(2)
	style.border_color = UI.ENTRY_SEPARATOR
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style


func _on_character_pressed(code: String) -> void:
	UISounds.play_select()
	_select_filter(code)


func _select_filter(filter_code: String) -> void:
	_selected_filter = filter_code
	
	# Update button states
	for entry in _character_entries:
		var button: Button = entry.get("button")
		if button:
			button.button_pressed = (entry.get("code") == filter_code)
	
	_rebuild_content()


func _rebuild_content() -> void:
	# Clear grid
	for child in _upgrade_grid.get_children():
		child.queue_free()
	
	# Clear any existing reset buttons from the right panel
	if _right_panel:
		for child in _right_panel.get_children():
			if child.has_meta("is_reset_container"):
				child.queue_free()
	
	if _selected_filter == GENERAL_FILTER:
		# Show general upgrades
		_upgrade_scroll.visible = true
		_unlock_panel.visible = false
		_build_general_upgrades()
	else:
		# Check if character is unlocked
		var is_unlocked := _selected_filter in _unlocked_characters
		if is_unlocked:
			_upgrade_scroll.visible = true
			_unlock_panel.visible = false
			_build_character_upgrades(_selected_filter)
		else:
			_upgrade_scroll.visible = false
			_unlock_panel.visible = true
			_update_unlock_panel(_selected_filter)


func _build_general_upgrades() -> void:
	for upgrade in ShopData.GENERAL_UPGRADES:
		var card := _create_upgrade_card(upgrade, "general")
		_upgrade_grid.add_child(card)
	
	# Add reset button in bottom right
	_add_reset_button_to_content(GENERAL_FILTER)


func _build_character_upgrades(char_id: String) -> void:
	# Get character-specific upgrades
	if char_id in ShopData.CHARACTER_UPGRADES:
		var upgrades: Array = ShopData.CHARACTER_UPGRADES[char_id]
		for upgrade in upgrades:
			var card := _create_upgrade_card(upgrade, char_id)
			_upgrade_grid.add_child(card)
	else:
		# Fallback for characters without upgrades yet
		var placeholder := Label.new()
		placeholder.text = "No upgrades available"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if UI.FONT_MEDIUM:
			placeholder.add_theme_font_override("font", UI.FONT_MEDIUM)
		placeholder.add_theme_font_size_override("font_size", 24)
		placeholder.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
		_upgrade_grid.add_child(placeholder)
	
	# Add reset button in bottom right
	_add_reset_button_to_content(char_id)


func _create_upgrade_card(upgrade: Dictionary, category: String) -> Control:
	var upgrade_id: String = category + "_" + upgrade["id"]
	var current_level: int = _upgrade_levels.get(upgrade_id, 0)
	var max_level: int = upgrade["max_level"]
	var is_maxed: bool = current_level >= max_level
	var cost: int = _calculate_upgrade_cost(upgrade["base_cost"], current_level)
	var can_afford: bool = GameManager.get_pristine_cores() >= cost
	
	# Use interactive card class for hover effects
	var card := _UpgradeCard.new()
	card.custom_minimum_size = Vector2(200, 560) # Minimum height
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL # Expand to fill container
	card.setup(is_maxed)
	card.set_can_purchase(can_afford and not is_maxed)
	
	# Connect card click to purchase
	if not is_maxed:
		card.card_clicked.connect(_request_purchase_with_warning.bind(upgrade_id, cost, card))
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 20
	vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)
	
	# Icon centered at top
	var icon_center := CenterContainer.new()
	icon_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_center)
	
	var icon := Label.new()
	icon.text = upgrade["icon"]
	icon.add_theme_font_size_override("font_size", 80) # Slightly smaller icon
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(icon)
	
	# Name centered
	var name_label := Label.new()
	name_label.text = upgrade["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_BOLD:
		name_label.add_theme_font_override("font", UI.FONT_BOLD)
	name_label.add_theme_font_size_override("font_size", 40) # Slightly smaller
	name_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD # WORD not WORD_SMART to avoid breaking at hyphens
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_label)
	
	# Level indicator centered
	var level_label := Label.new()
	level_label.text = "Lv. %d / %d" % [current_level, max_level]
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_MEDIUM:
		level_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	level_label.add_theme_font_size_override("font_size", 28)
	level_label.add_theme_color_override("font_color", UI.COLOR_UNLOCKED if is_maxed else UI.TEXT_SECONDARY)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(level_label)
	
	# Description in a container that expands but clips overflow
	var desc_container := Control.new()
	desc_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_container.clip_contents = true
	desc_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_container)
	
	var desc_label := Label.new()
	desc_label.text = upgrade["desc"]
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if UI.FONT_MEDIUM:
		desc_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	
	# Auto-scale text to fit
	var desc_len = upgrade["desc"].length()
	var font_size = 24
	if desc_len > 100:
		font_size = 18
	elif desc_len > 80:
		font_size = 20
	desc_label.add_theme_font_size_override("font_size", font_size)
	
	desc_label.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD # WORD not WORD_SMART to avoid breaking at hyphens
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	desc_container.add_child(desc_label)
	
	# Buy button or maxed label - centered, always at bottom
	var btn_center := CenterContainer.new()
	btn_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(btn_center)
	
	if is_maxed:
		var maxed_label := Label.new()
		maxed_label.text = "MAXED"
		maxed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if UI.FONT_BOLD:
			maxed_label.add_theme_font_override("font", UI.FONT_BOLD)
		maxed_label.add_theme_font_size_override("font_size", 32)
		maxed_label.add_theme_color_override("font_color", UI.COLOR_UNLOCKED)
		maxed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_center.add_child(maxed_label)
	else:
		var buy_btn := _create_core_cost_button(cost, upgrade_id, card)
		btn_center.add_child(buy_btn)
	
	return card


func _create_buy_button(cost: int, upgrade_id: String) -> Button:
	# Legacy function - redirect to new core cost button
	return _create_core_cost_button(cost, upgrade_id, null)


func _create_core_cost_button(cost: int, upgrade_id: String, parent_card: _UpgradeCard = null) -> Button:
	var can_afford: bool = GameManager.get_pristine_cores() >= cost
	
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 72) # Much bigger button
	btn.focus_mode = Control.FOCUS_NONE
	
	# Style: sci-fi container look matching the header
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()
	
	if can_afford:
		normal.bg_color = UI.SHOP_UNLOCK_AFFORD_BG
		normal.border_color = UI.SHOP_UNLOCK_AFFORD_BORDER
		hover.bg_color = UI.SHOP_UNLOCK_AFFORD_HOVER_BG
		hover.border_color = UI.SHOP_UNLOCK_AFFORD_HOVER_BORDER
		pressed.bg_color = UI.SHOP_UNLOCK_AFFORD_PRESSED_BG
		pressed.border_color = UI.SHOP_UNLOCK_AFFORD_PRESSED_BORDER
	else:
		normal.bg_color = UI.SHOP_UNLOCK_CANT_BG
		normal.border_color = UI.SHOP_UNLOCK_CANT_BORDER
		hover.bg_color = UI.SHOP_UNLOCK_CANT_HOVER_BG
		hover.border_color = UI.SHOP_UNLOCK_CANT_HOVER_BORDER
		pressed.bg_color = UI.SHOP_UNLOCK_CANT_BG
		pressed.border_color = UI.SHOP_UNLOCK_CANT_BORDER
	
	disabled.bg_color = UI.SHOP_UNLOCK_DISABLED_BG
	disabled.border_color = UI.SHOP_UNLOCK_DISABLED_BORDER
	
	for style in [normal, hover, pressed, disabled]:
		style.set_border_width_all(3)
		style.set_corner_radius_all(6)
		style.corner_detail = 2
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	
	# Button content: icon | divider | cost
	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(content)
	
	# Core icon section - much bigger
	var icon_section := CenterContainer.new()
	icon_section.custom_minimum_size = Vector2(60, 0)
	icon_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_section)
	
	var core_icon := _create_core_icon(44) # Much bigger icon
	core_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_section.add_child(core_icon)
	
	# Divider line
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(2, 48) # Taller divider
	divider.color = UI.SHOP_DIVIDER_AFFORD if can_afford else UI.SHOP_DIVIDER_CANT
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)
	
	# Cost section
	var cost_section := CenterContainer.new()
	cost_section.custom_minimum_size = Vector2(60, 0)
	cost_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cost_section)
	
	var cost_label := Label.new()
	cost_label.text = str(cost)
	if UI.FONT_BOLD:
		cost_label.add_theme_font_override("font", UI.FONT_BOLD)
	cost_label.add_theme_font_size_override("font_size", 36) # Much bigger text
	cost_label.add_theme_color_override("font_color", UI.COLOR_CORE if can_afford else UI.COLOR_LOCKED)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_section.add_child(cost_label)
	
	btn.disabled = not can_afford
	
	# Connect with parent card for visual feedback
	if parent_card:
		btn.pressed.connect(_request_purchase_with_warning.bind(upgrade_id, cost, parent_card))
	else:
		btn.pressed.connect(_request_purchase_with_warning.bind(upgrade_id, cost, null))
	
	# Flash red on click if can't afford
	if not can_afford and parent_card:
		btn.button_down.connect(parent_card.flash_cant_afford)
	
	return btn


func _create_unlock_panel() -> Control:
	# The entire panel is a button
	var panel_btn := Button.new()
	panel_btn.name = "UnlockButton"
	panel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_btn.focus_mode = Control.FOCUS_NONE
	
	# Style the button to look like a panel
	var normal := StyleBoxFlat.new()
	normal.bg_color = UI.SHOP_UNLOCK_PANEL_BG
	normal.set_border_width_all(3)
	normal.border_color = UI.SHOP_UNLOCK_PANEL_BORDER
	normal.set_corner_radius_all(12)
	panel_btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UI.SHOP_UNLOCK_PANEL_HOVER_BG
	hover.set_border_width_all(4)
	hover.border_color = UI.SHOP_UNLOCK_PANEL_HOVER_BORDER
	hover.set_corner_radius_all(12)
	panel_btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = UI.SHOP_UNLOCK_PANEL_PRESSED_BG
	pressed.set_border_width_all(4)
	pressed.border_color = UI.SHOP_UNLOCK_PANEL_PRESSED_BORDER
	pressed.set_corner_radius_all(12)
	panel_btn.add_theme_stylebox_override("pressed", pressed)
	
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = UI.SHOP_UNLOCK_PANEL_DISABLED_BG
	disabled.set_border_width_all(2)
	disabled.border_color = UI.SHOP_UNLOCK_PANEL_DISABLED_BORDER
	disabled.set_corner_radius_all(12)
	panel_btn.add_theme_stylebox_override("disabled", disabled)
	
	# Content container
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20
	content.offset_right = -20
	content.offset_top = 20
	content.offset_bottom = -20
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 24)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_btn.add_child(content)
	
	var lock_icon := Label.new()
	lock_icon.name = "LockIcon"
	lock_icon.text = "🔒"
	lock_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_icon.add_theme_font_size_override("font_size", 120)
	lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(lock_icon)
	
	var unlock_label := Label.new()
	unlock_label.name = "UnlockLabel"
	unlock_label.text = "CHARACTER LOCKED"
	unlock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_TITLE:
		unlock_label.add_theme_font_override("font", UI.FONT_TITLE)
	unlock_label.add_theme_font_size_override("font_size", 42)
	unlock_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	unlock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(unlock_label)
	
	# Cost display row
	var cost_row := HBoxContainer.new()
	cost_row.name = "CostRow"
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 16)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cost_row)
	
	# Click to unlock hint
	var hint := Label.new()
	hint.name = "ClickHint"
	hint.text = "Click to Unlock"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_MEDIUM:
		hint.add_theme_font_override("font", UI.FONT_MEDIUM)
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", UI.SHOP_HINT_DIM)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(hint)
	
	return panel_btn


func _update_unlock_panel(char_id: String) -> void:
	var char_name := _registry.get_character_name(char_id)
	
	# The unlock panel is now a Button itself
	var panel_btn := _unlock_panel as Button
	if not panel_btn:
		return
	
	# Find the content container (first VBoxContainer child)
	var content: VBoxContainer = null
	for child in panel_btn.get_children():
		if child is VBoxContainer:
			content = child
			break
	if not content:
		return
	
	var unlock_label := content.get_node_or_null("UnlockLabel") as Label
	if unlock_label:
		unlock_label.text = char_name.to_upper() + " LOCKED"
	
	var cost := CHARACTER_UNLOCK_COST
	var can_afford: bool = GameManager.get_pristine_cores() >= cost
	
	# Update cost row
	var cost_row := content.get_node_or_null("CostRow") as HBoxContainer
	if cost_row:
		for child in cost_row.get_children():
			child.queue_free()
		
		var core_icon := _create_core_icon(40)
		core_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_row.add_child(core_icon)
		
		var cost_label := Label.new()
		cost_label.text = "%d" % cost
		if UI.FONT_TITLE:
			cost_label.add_theme_font_override("font", UI.FONT_TITLE)
		cost_label.add_theme_font_size_override("font_size", 48)
		cost_label.add_theme_color_override("font_color", UI.COLOR_CORE)
		cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_row.add_child(cost_label)
	
	# Update hint text based on affordability
	var hint := content.get_node_or_null("ClickHint") as Label
	if hint:
		if can_afford:
			hint.text = "Click to Unlock"
			hint.add_theme_color_override("font_color", UI.SHOP_HINT_BRIGHT)
		else:
			hint.text = "Not Enough Cores"
			hint.add_theme_color_override("font_color", UI.SHOP_HINT_MUTED)
	
	# Enable/disable button
	panel_btn.disabled = not can_afford
	
	# Disconnect old signals and connect new
	for connection in panel_btn.pressed.get_connections():
		panel_btn.pressed.disconnect(connection["callable"])
	
	panel_btn.pressed.connect(_on_character_unlock.bind(char_id, cost))


func _on_upgrade_purchased(upgrade_id: String, cost: int) -> void:
	_on_upgrade_purchased_with_card(upgrade_id, cost, null)


func _on_upgrade_purchased_with_card(upgrade_id: String, cost: int, card: _UpgradeCard) -> void:
	if GameManager.spend_pristine_cores(cost):
		UISounds.play_confirm()
		_upgrade_levels[upgrade_id] = _upgrade_levels.get(upgrade_id, 0) + 1
		
		# Track cores spent - character upgrades go to char_id, others go to GENERAL_FILTER
		var category: String = GENERAL_FILTER
		for char_id in ShopData.CHARACTER_UPGRADES.keys():
			if upgrade_id.begins_with(char_id + "_"):
				category = char_id
				break
		_cores_spent[category] = _cores_spent.get(category, 0) + cost
		
		# Flash card to show successful purchase
		if card and is_instance_valid(card):
			card.flash_purchased()
		
		_save_shop_data()
		_update_currency_display()
		_update_sidebar_counts()
		
		# Delay rebuild slightly to show the flash effect
		await get_tree().create_timer(0.15).timeout
		_rebuild_content()
		print("[ShopMenu] Purchased upgrade: %s (now level %d)" % [upgrade_id, _upgrade_levels[upgrade_id]])


func _on_character_unlock(char_id: String, cost: int) -> void:
	if GameManager.spend_pristine_cores(cost):
		_unlocked_characters.append(char_id)
		
		# Track cores spent for unlocking
		_cores_spent[char_id] = _cores_spent.get(char_id, 0) + cost
		
		# Track achievement for unlocking character in shop
		if has_node("/root/AchievementManager"):
			get_node("/root/AchievementManager").on_character_unlocked_in_shop(char_id)
		
		_save_shop_data()
		_update_currency_display()
		
		# Rebuild character list to update appearance
		_build_character_list()
		_update_sidebar_counts()
		
		# Re-select the character to show upgrades
		_select_filter(char_id)
		
		print("[ShopMenu] Unlocked character: %s" % char_id)


func _on_reset_pressed() -> void:
	UISounds.play_select()
	_reset_all_shop_data()


func _reset_all_shop_data() -> void:
	# Reset pristine cores to 0
	var current_cores := GameManager.get_pristine_cores()
	if current_cores > 0:
		GameManager.spend_pristine_cores(current_cores)
	
	# Reset unlocked characters to defaults only
	_unlocked_characters.clear()
	for char_id in CharacterRegistry.DEFAULT_UNLOCKED:
		_unlocked_characters.append(char_id)
	
	# Reset all upgrade levels
	_upgrade_levels.clear()
	
	# Reset cores spent tracking
	_cores_spent.clear()
	
	# Save the reset data
	_save_shop_data()
	
	# Update UI
	_update_currency_display()
	_build_character_list()
	_update_sidebar_counts()
	_select_filter(GENERAL_FILTER)
	
	print("[ShopMenu] All shop data reset!")


func _add_reset_button_to_content(category: String) -> void:
	# Create a container that positions the reset button at bottom right of the right panel
	var reset_container := Control.new()
	reset_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	reset_container.offset_left = -90
	reset_container.offset_top = -90
	reset_container.offset_right = -20
	reset_container.offset_bottom = -20
	reset_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset_container.set_meta("is_reset_container", true)
	
	# Add to the right panel directly so it stays in the content area
	if _right_panel:
		_right_panel.add_child(reset_container)
	
	var reset_btn := Button.new()
	reset_btn.text = "↺"
	reset_btn.custom_minimum_size = Vector2(70, 70)
	reset_btn.size = Vector2(70, 70)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.tooltip_text = "Reset " + ("General" if category == "general" else category.capitalize()) + " upgrades and refund cores"
	reset_btn.add_theme_font_size_override("font_size", 36)
	reset_btn.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	
	# Style the reset button as a big square
	var reset_normal := StyleBoxFlat.new()
	reset_normal.bg_color = UI.RESET_BTN_BG
	reset_normal.set_border_width_all(3)
	reset_normal.border_color = UI.RESET_BTN_BORDER
	reset_normal.set_corner_radius_all(10)
	reset_btn.add_theme_stylebox_override("normal", reset_normal)
	
	var reset_hover := StyleBoxFlat.new()
	reset_hover.bg_color = UI.RESET_BTN_HOVER_BG
	reset_hover.set_border_width_all(3)
	reset_hover.border_color = UI.RESET_BTN_HOVER_BORDER
	reset_hover.set_corner_radius_all(10)
	reset_btn.add_theme_stylebox_override("hover", reset_hover)
	
	var reset_pressed := StyleBoxFlat.new()
	reset_pressed.bg_color = UI.RESET_BTN_PRESSED_BG
	reset_pressed.set_border_width_all(3)
	reset_pressed.border_color = UI.RESET_BTN_PRESSED_BORDER
	reset_pressed.set_corner_radius_all(10)
	reset_btn.add_theme_stylebox_override("pressed", reset_pressed)
	
	reset_btn.pressed.connect(_on_category_reset.bind(category))
	reset_container.add_child(reset_btn)


func _on_category_reset(category: String) -> void:
	# Calculate how many cores were spent on this category
	var refund_amount: int = _cores_spent.get(category, 0)
	
	if refund_amount <= 0:
		print("[ShopMenu] Nothing to refund for category: %s" % category)
		return
	
	# Refund the cores
	GameManager.add_pristine_cores(refund_amount)
	
	# Reset upgrade levels for this category
	var keys_to_remove: Array[String] = []
	# Handle special prefix for General category ("GENERAL" spent key vs "general_" upgrade prefix)
	var prefix = category + "_"
	if category == GENERAL_FILTER:
		prefix = "general_"
		
	for upgrade_id in _upgrade_levels.keys():
		if upgrade_id.begins_with(prefix):
			keys_to_remove.append(upgrade_id)
	for key in keys_to_remove:
		_upgrade_levels.erase(key)
	
	# If this is a character category (not "general"), re-lock the character if it was purchased
	# Default unlocked characters cannot be re-locked
	if category != "general" and category not in CharacterRegistry.DEFAULT_UNLOCKED:
		if category in _unlocked_characters:
			_unlocked_characters.erase(category)
			print("[ShopMenu] Re-locked character: %s" % category)
	
	# Reset cores spent for this category
	_cores_spent.erase(category)
	
	# Save
	_save_shop_data()
	
	# Update UI
	_update_currency_display()
	_build_character_list() # Rebuild to show re-locked status
	_update_sidebar_counts()
	_rebuild_content()
	
	print("[ShopMenu] Refunded %d cores for category: %s" % [refund_amount, category])


func _update_currency_display() -> void:
	if _currency_label:
		_currency_label.text = str(GameManager.get_pristine_cores())


func _update_sidebar_counts() -> void:
	for entry in _character_entries:
		var code: String = entry.get("code", "")
		var count_label: Label = entry.get("count_label")
		if count_label:
			var spent: int = _cores_spent.get(code, 0)
			count_label.text = str(spent)


# === STYLE HELPERS ===

func _make_letterbox_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = UI.SHOP_PANEL_BORDER
	style.shadow_color = UI.SHOP_PANEL_SHADOW
	style.shadow_size = 3
	style.shadow_offset = Vector2(2, 2)
	return style


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.set_border_width_all(4)
	style.border_color = UI.ENTRY_BORDER
	style.set_corner_radius_all(12)
	style.shadow_color = UI.SHOP_PANEL_SHADOW_SELECTED
	style.shadow_size = 6
	style.shadow_offset = Vector2(3, 3)
	return style


func _make_sidebar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.SHOP_PANEL_LOCKED_BG
	style.set_border_width_all(2)
	style.border_color = UI.ENTRY_SEPARATOR
	style.set_corner_radius_all(8)
	return style


func _make_content_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.SHOP_PANEL_UNLOCKED_BG
	style.set_border_width_all(2)
	style.border_color = UI.ENTRY_SEPARATOR
	style.set_corner_radius_all(8)
	return style


func _make_portrait_style(is_unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.SHOP_PANEL_ACTIVE_BG
	style.set_border_width_all(3)
	if is_unlocked:
		style.border_color = UI.SHOP_PANEL_ACTIVE_BORDER_SELECTED
	else:
		style.border_color = UI.SHOP_PANEL_ACTIVE_BORDER
	style.set_corner_radius_all(8)
	return style


func _make_upgrade_card_style(is_maxed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.ENTRY_BG
	style.set_border_width_all(2)
	if is_maxed:
		style.border_color = UI.COLOR_UNLOCKED
	else:
		style.border_color = UI.ENTRY_BORDER.darkened(0.3)
	style.set_corner_radius_all(10)
	return style


# === UTILITY FUNCTIONS ===

## Calculate upgrade cost - linear for first 10 levels, then doubles each level after
static func _calculate_upgrade_cost(base_cost: int, current_level: int) -> int:
	if current_level < 10:
		# First 10 levels: base_cost + current_level (1, 2, 3, ... 10)
		return base_cost + current_level
	else:
		# After level 10: starts at base cost of 11, then doubles each level
		# Level 10 costs 11, level 11 costs 22, level 12 costs 44, etc.
		var levels_past_10 := current_level - 10
		var doubling_cost := 11 * int(pow(2, levels_past_10))
		return doubling_cost

## Get total bonus for an upgrade type (for use by game systems)
static func get_upgrade_bonus(upgrade_type: String) -> float:
	var data := SaveManager.load_config(SaveManager.SHOP_PATH)
	if data.is_empty():
		return 0.0
	
	var level: int = data.get("upgrades", {}).get("general_" + upgrade_type, 0)
	
	match upgrade_type:
		"atk":
			return level * 0.25 # +25% per level
		"hp":
			return float(level) # +1 HP per level
		"speed":
			return level * 0.05 # +5% per level
		"crit":
			return level * 0.02 # +2% per level
		"pickup":
			return level * 0.10 # +10% per level
		"xp":
			return level * 0.05 # +5% per level
	
	return 0.0


## Check if a character is unlocked
static func is_character_unlocked(char_id: String) -> bool:
	if char_id in CharacterRegistry.DEFAULT_UNLOCKED:
		return true
	
	var data := SaveManager.load_config(SaveManager.SHOP_PATH)
	if data.is_empty():
		return false
	
	var unlocked = data.get("characters", {}).get("unlocked", [])
	return char_id in unlocked


## Check if a character-specific upgrade is purchased
## Uses cached values to avoid file I/O on every call (critical for hot paths like bullet collision)
static var _upgrade_cache: Dictionary = {}
static var _upgrade_cache_loaded: bool = false

static func has_character_upgrade(char_id: String, upgrade_id: String) -> bool:
	var full_id := char_id + "_" + upgrade_id
	
	# Return cached value if available
	if _upgrade_cache.has(full_id):
		return _upgrade_cache[full_id]
	
	# Load cache if not loaded yet
	if not _upgrade_cache_loaded:
		_load_upgrade_cache()
	
	# Return cached value (may have been loaded above)
	if _upgrade_cache.has(full_id):
		return _upgrade_cache[full_id]
	
	# Upgrade not found = not purchased
	return false

static func _load_upgrade_cache() -> void:
	_upgrade_cache_loaded = true
	_upgrade_cache.clear()
	
	var data := SaveManager.load_config(SaveManager.SHOP_PATH)
	if data.is_empty():
		return
	
	# Cache all upgrade values
	var upgrades_data: Dictionary = data.get("upgrades", {})
	for key in upgrades_data:
		var value = upgrades_data[key]
		if value is int or value is float:
			_upgrade_cache[key] = int(value) > 0
		else:
			# Log warning but don't crash, assume not purchased (false)
			# push_warning("[ShopMenu] Invalid upgrade value for key '%s': %s" % [key, str(value)])
			_upgrade_cache[key] = false

## Invalidate the upgrade cache (call when upgrades are purchased)
static func invalidate_upgrade_cache() -> void:
	_upgrade_cache_loaded = false
	_upgrade_cache.clear()


# === UPGRADE CARD (Inner class) - Interactive card with hover/flash effects ===

class _UpgradeCard extends Control:
	signal card_clicked
	
	const UI := preload("res://scripts/ui/UITheme.gd")
	
	var _is_maxed: bool = false
	var _is_hovered: bool = false
	var _flash_color: Color = Color.TRANSPARENT
	var _flash_time: float = 0.0
	var _flash_duration: float = 0.3
	var _can_purchase: bool = false
	
	func setup(is_maxed: bool) -> void:
		_is_maxed = is_maxed
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
	
	func set_can_purchase(can_purchase: bool) -> void:
		_can_purchase = can_purchase
	
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				if _is_maxed:
					return # Can't click maxed cards
				if not _can_purchase:
					flash_cant_afford()
					return
				emit_signal("card_clicked")
	
	func _process(delta: float) -> void:
		if _flash_time > 0.0:
			_flash_time -= delta
			queue_redraw()
	
	func _on_mouse_entered() -> void:
		_is_hovered = true
		queue_redraw()
	
	func _on_mouse_exited() -> void:
		_is_hovered = false
		queue_redraw()
	
	func flash_purchased() -> void:
		_flash_color = UI.SHOP_CARD_PURCHASED_BG
		_flash_time = _flash_duration
		queue_redraw()
	
	func flash_cant_afford() -> void:
		_flash_color = UI.SHOP_CARD_CANT_AFFORD_BG
		_flash_time = _flash_duration * 0.5 # Shorter red flash
		queue_redraw()
	
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		
		# Calculate current background color
		var bg_color: Color = UI.SHOP_CARD_BG
		if _flash_time > 0.0:
			var flash_t: float = _flash_time / _flash_duration
			bg_color = UI.SHOP_CARD_BG.lerp(_flash_color, flash_t)
		elif _is_hovered:
			bg_color = UI.SHOP_CARD_HOVER_BG
		
		# Border color
		var border_color: Color
		if _is_maxed:
			border_color = UI.SHOP_CARD_MAXED_BORDER
		elif _is_hovered:
			border_color = UI.SHOP_CARD_HOVER_BORDER
		else:
			border_color = UI.SHOP_CARD_BORDER
		
		# Draw rounded rectangle background
		var corner_radius := 10.0
		
		# Background
		_draw_rounded_rect(rect, bg_color, corner_radius)
		
		# Border
		_draw_rounded_rect_outline(rect, border_color, corner_radius, 2.0)
		
		# Subtle hover glow
		if _is_hovered and _flash_time <= 0.0:
			for i in range(3, 0, -1):
				var glow_alpha: float = 0.05 * (1.0 - float(i) / 3.0)
				var glow_rect := Rect2(rect.position - Vector2(i, i) * 2, rect.size + Vector2(i, i) * 4)
				_draw_rounded_rect(glow_rect, Color(UI.ORB_CARD_GLOW.r, UI.ORB_CARD_GLOW.g, UI.ORB_CARD_GLOW.b, glow_alpha), corner_radius + i * 2)
	
	func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
		# Simple rounded rect using polygon
		var points := PackedVector2Array()
		var segments := 8
		
		# Top-left corner
		for i in range(segments + 1):
			var angle := PI + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(radius, radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		# Top-right corner
		for i in range(segments + 1):
			var angle := -PI / 2.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(rect.size.x - radius, radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		# Bottom-right corner
		for i in range(segments + 1):
			var angle := 0.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		# Bottom-left corner
		for i in range(segments + 1):
			var angle := PI / 2.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(radius, rect.size.y - radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		draw_colored_polygon(points, color)
	
	func _draw_rounded_rect_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
		var points := PackedVector2Array()
		var segments := 8
		
		# Top-left corner
		for i in range(segments + 1):
			var angle := PI + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(radius, radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		# Top-right corner
		for i in range(segments + 1):
			var angle := -PI / 2.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(rect.size.x - radius, radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		# Bottom-right corner
		for i in range(segments + 1):
			var angle := 0.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		# Bottom-left corner
		for i in range(segments + 1):
			var angle := PI / 2.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(radius, rect.size.y - radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		# Close the loop
		points.append(points[0])
		
		draw_polyline(points, color, width, true)


# === GENERAL UPGRADE ICON (Inner class) - Animated star burst ===

class _GeneralUpgradeIcon extends Control:
	const UI := preload("res://scripts/ui/UITheme.gd")
	var _time: float = 0.0
	
	func _ready() -> void:
		set_process(true)
	
	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()
	
	func _draw() -> void:
		var center: Vector2 = size / 2.0
		var base_radius: float = minf(size.x, size.y) / 2.0 - 8.0
		
		# Rotating outer glow rays
		var num_rays: int = 8
		for i in range(num_rays):
			var angle: float = (float(i) / float(num_rays)) * TAU + _time * 0.5
			var ray_length: float = base_radius * 0.9 + sin(_time * 3.0 + float(i)) * 8.0
			var ray_width: float = 6.0 + sin(_time * 2.0 + float(i) * 0.5) * 2.0
			var start_pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * base_radius * 0.3
			var end_pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * ray_length
			
			# Gradient ray with glow
			for g in range(3, 0, -1):
				var glow_alpha: float = 0.15 * float(g) / 3.0
				var glow_width: float = ray_width + float(g) * 4.0
				draw_line(start_pos, end_pos, Color(UI.ORB_RAY_GLOW.r, UI.ORB_RAY_GLOW.g, UI.ORB_RAY_GLOW.b, glow_alpha), glow_width)
			draw_line(start_pos, end_pos, UI.ORB_RAY_CORE, ray_width)
		
		# Pulsing outer ring
		var ring_pulse: float = 1.0 + sin(_time * 4.0) * 0.08
		var ring_radius: float = base_radius * 0.85 * ring_pulse
		for i in range(4, 0, -1):
			var alpha: float = 0.2 * float(i) / 4.0
			var r: float = ring_radius + float(i) * 3.0
			draw_arc(center, r, 0, TAU, 64, Color(UI.ORB_RING_DIM.r, UI.ORB_RING_DIM.g, UI.ORB_RING_DIM.b, alpha), 2.0)
		draw_arc(center, ring_radius, 0, TAU, 64, UI.ORB_RING_BRIGHT, 3.0)
		
		# Central glowing orb
		var orb_pulse: float = 1.0 + sin(_time * 5.0) * 0.1
		var orb_radius: float = base_radius * 0.45 * orb_pulse
		
		# Orb outer glow
		for i in range(10, 0, -1):
			var glow_alpha: float = 0.12 * (1.0 - float(i) / 10.0)
			var glow_radius: float = orb_radius + float(i) * 4.0
			draw_circle(center, glow_radius, Color(UI.ORB_GLOW.r, UI.ORB_GLOW.g, UI.ORB_GLOW.b, glow_alpha))
		
		# Orb gradient fill
		var segments: int = 24
		for i in range(segments, 0, -1):
			var t: float = float(i) / float(segments)
			var r: float = orb_radius * t
			var brightness: float = 0.6 + 0.4 * (1.0 - t)
			draw_circle(center, r, Color(1.0 * brightness, 0.85 * brightness, 0.3 * brightness + 0.3 * (1.0 - t)))
		
		# Hot white center
		var core_pulse: float = 1.0 + sin(_time * 6.0) * 0.15
		draw_circle(center, orb_radius * 0.35 * core_pulse, UI.ORB_CENTER_WHITE)
		draw_circle(center, orb_radius * 0.2 * core_pulse, UI.ORB_CENTER_CORE)
		
		# Floating sparkles
		var num_sparkles: int = 6
		for i in range(num_sparkles):
			var sparkle_angle: float = (float(i) / float(num_sparkles)) * TAU + _time * 1.5
			var sparkle_dist: float = base_radius * 0.6 + sin(_time * 2.5 + float(i) * 1.2) * base_radius * 0.15
			var sparkle_pos: Vector2 = center + Vector2(cos(sparkle_angle), sin(sparkle_angle)) * sparkle_dist
			var sparkle_size: float = 4.0 + sin(_time * 4.0 + float(i)) * 2.0
			var sparkle_alpha: float = 0.6 + sin(_time * 5.0 + float(i) * 0.7) * 0.3
			draw_circle(sparkle_pos, sparkle_size, Color(UI.ORB_SPARKLE.r, UI.ORB_SPARKLE.g, UI.ORB_SPARKLE.b, sparkle_alpha))


func _create_warning_popup() -> void:
	_warning_popup = ConfirmationDialog.new()
	_warning_popup.title = "Support Unit Info"
	_warning_popup.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_warning_popup.dialog_text = "Support units require skill tree unlock during matches to activate shop upgrades."
	_warning_popup.ok_button_text = "Got it"
	_warning_popup.min_size = Vector2(400, 150)
	_warning_popup.max_size = Vector2(500, 200)
	
	# Style the label
	var label := _warning_popup.get_label()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	if UI.FONT_MEDIUM:
		label.add_theme_font_override("font", UI.FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	
	_warning_popup.confirmed.connect(_on_warning_confirmed)
	add_child(_warning_popup)

func _request_purchase_with_warning(upgrade_id: String, cost: int, card: _UpgradeCard = null) -> void:
	# Store the callback for the purchase
	if card:
		_pending_purchase_callback = _on_upgrade_purchased_with_card.bind(upgrade_id, cost, card)
	else:
		_pending_purchase_callback = _on_upgrade_purchased.bind(upgrade_id, cost)
	
	# Check if this is a general upgrade (no warning needed)
	if upgrade_id.begins_with("general"):
		if _pending_purchase_callback.is_valid():
			_pending_purchase_callback.call()
		return
		
	# Check if warning already shown this session
	if _session_warning_shown:
		if _pending_purchase_callback.is_valid():
			_pending_purchase_callback.call()
		return
	
	# Show warning
	_warning_popup.popup_centered()
	_session_warning_shown = true

func _on_warning_confirmed() -> void:
	# Execute the pending purchase
	if _pending_purchase_callback.is_valid():
		_pending_purchase_callback.call()
