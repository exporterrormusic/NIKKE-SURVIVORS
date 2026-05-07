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

# Extracted components
var _char_list_component: ShopCharacterList = null
var _upgrade_grid_component: ShopUpgradeGrid = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_registry = CharacterRegistry.get_instance()
	_button_group = ButtonGroup.new()
	
	# Create extracted components
	_char_list_component = ShopCharacterList.new()
	_char_list_component.character_selected.connect(_on_character_selected)
	add_child(_char_list_component)
	
	_upgrade_grid_component = ShopUpgradeGrid.new()
	_upgrade_grid_component.purchase_requested.connect(_on_upgrade_requested)
	_upgrade_grid_component.reset_requested.connect(_on_category_reset)
	add_child(_upgrade_grid_component)
	
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
	var data: Dictionary = SaveManager.load_section("shop")
	
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
	
	var err := SaveManager.save_section("shop", data)
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
	var sidebar_style := StyleBoxFlat.new()
	sidebar_style.bg_color = UI.SHOP_PANEL_LOCKED_BG
	sidebar_style.set_border_width_all(2)
	sidebar_style.border_color = UI.ENTRY_SEPARATOR
	sidebar_style.set_corner_radius_all(8)
	left_panel.add_theme_stylebox_override("panel", sidebar_style)
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
	var content_style := StyleBoxFlat.new()
	content_style.bg_color = UI.SHOP_PANEL_UNLOCKED_BG
	content_style.set_border_width_all(2)
	content_style.border_color = UI.ENTRY_SEPARATOR
	content_style.set_corner_radius_all(8)
	_right_panel.add_theme_stylebox_override("panel", content_style)
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
	
	# Build character list via component
	_char_list_component.setup(_character_list, _button_group, _registry)
	_char_list_component.build(_unlocked_characters, _cores_spent)
	
	# Setup upgrade grid component
	_upgrade_grid_component.setup(_upgrade_grid, _upgrade_scroll, _right_panel, _unlock_panel, _create_core_icon)


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


func _on_character_selected(code: String) -> void:
	UISounds.play_select()
	_select_filter(code)


func _select_filter(filter_code: String) -> void:
	_selected_filter = filter_code
	
	# Update button states via component
	if _char_list_component:
		_char_list_component.update_selection(filter_code)
	
	_rebuild_content()


func _rebuild_content() -> void:
	if _upgrade_grid_component:
		_upgrade_grid_component.rebuild(_selected_filter, _unlocked_characters, _upgrade_levels, _cores_spent)


func _on_upgrade_requested(upgrade_id: String, cost: int) -> void:
	_request_purchase_with_warning(upgrade_id, cost)


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
	if _upgrade_grid_component:
		_upgrade_grid_component.update_unlock_panel(char_id, _registry, _cores_spent)


func _on_upgrade_purchased(upgrade_id: String, cost: int) -> void:
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
		
		_save_shop_data()
		_update_currency_display()
		_update_sidebar_counts()
		
		# Rebuild to show updated levels
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
		if _char_list_component:
			_char_list_component.build(_unlocked_characters, _cores_spent)
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
	if _char_list_component:
		_char_list_component.build(_unlocked_characters, _cores_spent)
	_update_sidebar_counts()
	_select_filter(GENERAL_FILTER)
	
	print("[ShopMenu] All shop data reset!")


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
	if _char_list_component:
		_char_list_component.build(_unlocked_characters, _cores_spent)
	_update_sidebar_counts()
	_rebuild_content()
	
	print("[ShopMenu] Refunded %d cores for category: %s" % [refund_amount, category])


func _update_currency_display() -> void:
	if _currency_label:
		_currency_label.text = str(GameManager.get_pristine_cores())


func _update_sidebar_counts() -> void:
	if _char_list_component:
		_char_list_component.update_counts(_cores_spent)


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


# === UTILITY FUNCTIONS ===

## Get total bonus for an upgrade type (for use by game systems)
static func get_upgrade_bonus(upgrade_type: String) -> float:
	var data := SaveManager.load_section("shop")
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
	
	var data := SaveManager.load_section("shop")
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
	
	var data := SaveManager.load_section("shop")
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


func _request_purchase_with_warning(upgrade_id: String, cost: int) -> void:
	# Check if this is a general upgrade (no warning needed)
	if upgrade_id.begins_with("general") or upgrade_id.ends_with("_unlock"):
		_do_purchase(upgrade_id, cost)
		return
		
	# Check if warning already shown this session
	if _session_warning_shown:
		_do_purchase(upgrade_id, cost)
		return
	
	# Store callback and show warning
	_pending_purchase_callback = _do_purchase.bind(upgrade_id, cost)
	_warning_popup.popup_centered()
	_session_warning_shown = true


func _do_purchase(upgrade_id: String, cost: int) -> void:
	if upgrade_id.ends_with("_unlock"):
		# Character unlock
		var char_id := upgrade_id.trim_suffix("_unlock")
		_on_character_unlock(char_id, cost)
	else:
		# Upgrade purchase
		_on_upgrade_purchased(upgrade_id, cost)


func _on_warning_confirmed() -> void:
	if _pending_purchase_callback.is_valid():
		_pending_purchase_callback.call()


# === UTILITY FUNCTIONS ===

## Calculate upgrade cost - linear for first 10 levels, then doubles each level after
static func _calculate_upgrade_cost(base_cost: int, current_level: int) -> int:
	if current_level < 10:
		return base_cost + current_level
	else:
		var levels_past_10 := current_level - 10
		var doubling_cost := 11 * int(pow(2, levels_past_10))
		return doubling_cost

## Get total bonus for an upgrade type (for use by game systems)


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
