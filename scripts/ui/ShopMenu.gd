extends Control
class_name ShopMenu
## Main Menu Shop - Permanent general stat upgrades purchased with Pristine
## Rapture Cores. Character unlocks live in the character select screen;
## character signature upgrades are in-run talents (TalentData row 2).

# Removed SaveManagerScript preload - now using global SaveManager autoload
const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

signal back_requested

const GENERAL_FILTER := "GENERAL"

# Character data - loaded from CharacterRegistry (single source of truth)
var _registry: CharacterRegistry = null

# Shop data persistence
var _unlocked_characters: Array[String] = []
var _upgrade_levels: Dictionary = {} # "upgrade_id" -> level
var _cores_spent: Dictionary = {} # "general" -> total cores spent

# UI references
var _upgrade_grid: GridContainer = null
var _upgrade_scroll: ScrollContainer = null
var _right_panel: Panel = null
var _currency_label: Label = null
var _currency_icon: Control = null

# Extracted components
var _upgrade_grid_component: ShopUpgradeGrid = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_registry = CharacterRegistry.get_instance()

	_upgrade_grid_component = ShopUpgradeGrid.new()
	_upgrade_grid_component.purchase_requested.connect(_on_upgrade_requested)
	_upgrade_grid_component.reset_requested.connect(_on_category_reset)
	add_child(_upgrade_grid_component)

	_load_shop_data()
	_build_ui()
	_rebuild_content()


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
	top_bar.add_child(currency_row)

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
	
	# === CONTENT: general upgrades only (character unlocks moved to character select) ===
	_right_panel = Panel.new()
	_right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content_style := StyleBoxFlat.new()
	content_style.bg_color = UI.SHOP_PANEL_UNLOCKED_BG
	content_style.set_border_width_all(2)
	content_style.border_color = UI.ENTRY_SEPARATOR
	content_style.set_corner_radius_all(8)
	_right_panel.add_theme_stylebox_override("panel", content_style)
	content_margin.add_child(_right_panel)

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
	
	# Setup upgrade grid component
	_upgrade_grid_component.setup(_upgrade_grid, _upgrade_scroll, _right_panel, _create_core_icon)


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


func _rebuild_content() -> void:
	if _upgrade_grid_component:
		_upgrade_grid_component.rebuild(_upgrade_levels, _cores_spent)


func _on_upgrade_requested(upgrade_id: String, cost: int) -> void:
	_do_purchase(upgrade_id, cost)


func _on_upgrade_purchased(upgrade_id: String, cost: int) -> void:
	if GameManager.spend_pristine_cores(cost):
		UISounds.play_confirm()
		_upgrade_levels[upgrade_id] = _upgrade_levels.get(upgrade_id, 0) + 1

		# All purchasable upgrades are general now (character upgrades are talents)
		_cores_spent[GENERAL_FILTER] = _cores_spent.get(GENERAL_FILTER, 0) + cost

		_save_shop_data()
		_update_currency_display()

		# Rebuild to show updated levels
		_rebuild_content()
		print("[ShopMenu] Purchased upgrade: %s (now level %d)" % [upgrade_id, _upgrade_levels[upgrade_id]])


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
	_rebuild_content()

	print("[ShopMenu] All shop data reset!")


func _on_category_reset(_category: String) -> void:
	# Only general upgrades are purchasable here now
	var refund_amount: int = _cores_spent.get(GENERAL_FILTER, 0)

	if refund_amount <= 0:
		print("[ShopMenu] Nothing to refund")
		return

	# Refund the cores
	GameManager.add_pristine_cores(refund_amount)

	# Reset general upgrade levels
	var keys_to_remove: Array[String] = []
	for upgrade_id in _upgrade_levels.keys():
		if upgrade_id.begins_with("general_"):
			keys_to_remove.append(upgrade_id)
	for key in keys_to_remove:
		_upgrade_levels.erase(key)

	_cores_spent.erase(GENERAL_FILTER)

	# Save
	_save_shop_data()

	# Update UI
	_update_currency_display()
	_rebuild_content()

	print("[ShopMenu] Refunded %d cores for general upgrades" % refund_amount)


func _update_currency_display() -> void:
	if _currency_label:
		_currency_label.text = str(GameManager.get_pristine_cores())


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


## Persist a character unlock (called from the character select storefront).
## Preserves the rest of the shop save section.
static func unlock_character(char_id: String) -> bool:
	var data := SaveManager.load_section("shop")
	var chars: Dictionary = data.get("characters", {})
	var unlocked: Array = chars.get("unlocked", [])
	if char_id not in unlocked:
		unlocked.append(char_id)
	chars["unlocked"] = unlocked
	data["characters"] = chars
	return SaveManager.save_section("shop", data) == OK


## Check if a character-specific signature upgrade is active.
## Phase 3 rework: these are now run-only talents, so this reads the current
## run's talent tree instead of persistent shop purchases. The name is kept
## because ~30 call sites (projectiles, controllers) use it as the lookup API.
static func has_character_upgrade(char_id: String, upgrade_id: String) -> bool:
	var tree := TalentTree.instance
	if tree == null:
		return false

	var registry := CharacterRegistry.get_instance()
	if registry == null:
		return false

	var char_index: int = registry.get_character_index(char_id)
	if char_index < 0:
		return false

	return tree.get_talent_level(char_index, upgrade_id) > 0

## Kept for compatibility; talent state needs no cache invalidation
static func invalidate_upgrade_cache() -> void:
	pass


func _do_purchase(upgrade_id: String, cost: int) -> void:
	_on_upgrade_purchased(upgrade_id, cost)


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


