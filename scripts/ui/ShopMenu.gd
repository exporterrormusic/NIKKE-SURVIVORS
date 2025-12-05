extends Control
class_name ShopMenu
## Main Menu Shop - Permanent upgrades purchased with Pristine Rapture Cores.
## Layout: Left sidebar with character portraits + GENERAL, right side with upgrade grid.
## Characters can be unlocked here. Default unlocked: Snow White, Rapunzel, Scarlet.

const SaveManagerScript = preload("res://scripts/systems/SaveManager.gd")

signal back_requested

# Visual constants - matching AchievementsMenu style
const BACKGROUND_COLOR := Color(0.04, 0.055, 0.08, 0.95)
const PANEL_BG_COLOR := Color(0.04, 0.055, 0.08, 0.97)
const BORDER_COLOR := Color(0.95, 0.95, 0.98, 0.9)
const ENTRY_BG_COLOR := Color(0.1, 0.1, 0.14, 0.95)
const ENTRY_BORDER_COLOR := Color(0.95, 0.95, 0.98, 0.9)
const SEPARATOR_COLOR := Color(0.95, 0.95, 0.98, 0.3)

const HEADER_COLOR := Color(0.95, 0.95, 0.98, 1.0)
const LABEL_COLOR := Color(0.784, 0.792, 0.878, 1.0)
const UNLOCKED_COLOR := Color(0.392, 0.86, 0.549, 1.0)
const LOCKED_COLOR := Color(0.4, 0.4, 0.45, 1.0)
const CORE_COLOR := Color(1.0, 0.3, 0.3, 1.0)  # Red for Pristine Rapture Cores

const CHARACTER_NORMAL_COLOR := Color(0.08, 0.08, 0.12, 0.95)
const CHARACTER_HOVER_COLOR := Color(0.12, 0.12, 0.18, 0.98)
const CHARACTER_SELECTED_COLOR := Color(0.18, 0.18, 0.25, 1.0)
const CHARACTER_LOCKED_COLOR := Color(0.05, 0.05, 0.07, 0.95)

const GENERAL_FILTER := "GENERAL"

# Character data - loaded from CharacterRegistry (single source of truth)
var _registry: CharacterRegistry = null

# Character unlock costs
const CHARACTER_UNLOCK_COST := 3  # Pristine Rapture Cores to unlock a character

# General upgrades (apply to all characters)
const GENERAL_UPGRADES := [
	{"id": "atk", "name": "ATK", "desc": "+5% Attack Damage", "max_level": 99, "base_cost": 1, "icon": "⚔️"},
	{"id": "hp", "name": "HP", "desc": "+1 Max HP", "max_level": 99, "base_cost": 1, "icon": "❤️"},
	{"id": "speed", "name": "SPD", "desc": "+5% Movement Speed", "max_level": 99, "base_cost": 1, "icon": "👟"},
	{"id": "crit", "name": "CRIT", "desc": "+2% Critical Chance", "max_level": 99, "base_cost": 1, "icon": "💥"},
	{"id": "xp", "name": "XP", "desc": "+5% Experience Gain", "max_level": 99, "base_cost": 2, "icon": "⭐"},
]

# Shop data persistence
var _unlocked_characters: Array[String] = []
var _upgrade_levels: Dictionary = {}  # "upgrade_id" -> level
var _cores_spent: Dictionary = {}  # "character_id" or "general" -> total cores spent

var _selected_filter: String = GENERAL_FILTER
var _character_entries: Array[Dictionary] = []

# Preload fonts at compile time for better performance
const _futura_bold: Font = preload("res://resources/fonts/futura_condensed_extra_bold.tres")
const _pretendard_bold: Font = preload("res://resources/fonts/pretendard_bold.tres")
const _pretendard_medium: Font = preload("res://resources/fonts/pretendard_medium.tres")

# UI references
var _character_list: VBoxContainer = null
var _upgrade_grid: GridContainer = null
var _upgrade_scroll: ScrollContainer = null
var _right_panel: Panel = null
var _currency_label: Label = null
var _currency_icon: Control = null
var _unlock_panel: Control = null
var _button_group: ButtonGroup = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_registry = CharacterRegistry.get_instance()
	_button_group = ButtonGroup.new()
	
	_load_shop_data()
	_build_ui()
	_select_filter(GENERAL_FILTER)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		emit_signal("back_requested")
	
	# All debug keys moved to F5 Debug Menu in Level.gd


func _load_shop_data() -> void:
	var config := ConfigFile.new()
	var err := config.load(SaveManagerScript.SHOP_PATH)
	
	# Start with default unlocked characters
	_unlocked_characters.clear()
	for char_id in CharacterRegistry.DEFAULT_UNLOCKED:
		_unlocked_characters.append(char_id)
	
	if err == OK:
		# Load unlocked characters
		var saved_unlocked = config.get_value("characters", "unlocked", [])
		for char_id in saved_unlocked:
			if char_id not in _unlocked_characters:
				_unlocked_characters.append(char_id)
		
		# Load upgrade levels
		if config.has_section("upgrades"):
			for key in config.get_section_keys("upgrades"):
				_upgrade_levels[key] = config.get_value("upgrades", key, 0)
		
		# Load cores spent
		if config.has_section("cores_spent"):
			for key in config.get_section_keys("cores_spent"):
				_cores_spent[key] = config.get_value("cores_spent", key, 0)
	
	print("[ShopMenu] Loaded shop data: %d characters unlocked, %d upgrades" % [_unlocked_characters.size(), _upgrade_levels.size()])


func _save_shop_data() -> void:
	var config := ConfigFile.new()
	
	# Save unlocked characters (excluding defaults to save space)
	var extra_unlocked: Array = []
	for char_id in _unlocked_characters:
		if char_id not in CharacterRegistry.DEFAULT_UNLOCKED:
			extra_unlocked.append(char_id)
	config.set_value("characters", "unlocked", extra_unlocked)
	
	# Save upgrade levels
	for upgrade_id in _upgrade_levels:
		config.set_value("upgrades", upgrade_id, _upgrade_levels[upgrade_id])
	
	# Save cores spent
	for category in _cores_spent:
		config.set_value("cores_spent", category, _cores_spent[category])
	
	var err := config.save(SaveManagerScript.SHOP_PATH)
	if err == OK:
		print("[ShopMenu] Shop data saved")
	else:
		push_error("[ShopMenu] Failed to save shop data: " + str(err))


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
	overlay.color = Color(0, 0, 0, 0.25)
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
	
	# Title label - absolutely centered in the header, ignoring other elements
	var title_label := Label.new()
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.text = "SHOP"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _futura_bold:
		title_label.add_theme_font_override("font", _futura_bold)
	title_label.add_theme_font_size_override("font_size", 80)
	title_label.add_theme_color_override("font_color", HEADER_COLOR)
	title_label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15, 1.0))
	title_label.add_theme_constant_override("outline_size", 3)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(title_label)
	
	# Currency container - positioned at right side
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
	
	# Sci-fi danger container for Pristine Rapture Core currency
	var core_container := _PristineCoreContainer.new()
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
	_upgrade_grid.columns = 5  # 5 per row instead of 3
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
	
	var core := _PristineCoreIcon.new()
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
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
			tex_rect.modulate = Color(0.3, 0.3, 0.35, 1.0)
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
			if _pretendard_bold:
				locked_text.add_theme_font_override("font", _pretendard_bold)
			locked_text.add_theme_font_size_override("font_size", 14)
			locked_text.add_theme_color_override("font_color", CORE_COLOR)
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
	divider.color = Color(0.5, 0.5, 0.55, 0.25)  # Very subtle
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
	if _pretendard_bold:
		count_label.add_theme_font_override("font", _pretendard_bold)
	count_label.add_theme_font_size_override("font_size", 56)
	count_label.add_theme_color_override("font_color", HEADER_COLOR)
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
	var base_color := CHARACTER_NORMAL_COLOR if is_unlocked else CHARACTER_LOCKED_COLOR
	button.add_theme_stylebox_override("normal", _make_char_button_style(base_color))
	button.add_theme_stylebox_override("hover", _make_char_button_style(CHARACTER_HOVER_COLOR))
	button.add_theme_stylebox_override("pressed", _make_char_button_style(CHARACTER_SELECTED_COLOR))
	button.add_theme_stylebox_override("focus", _make_char_button_style(CHARACTER_HOVER_COLOR))


func _make_char_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(2)
	style.border_color = SEPARATOR_COLOR
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style


func _on_character_pressed(code: String) -> void:
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
	for upgrade in GENERAL_UPGRADES:
		var card := _create_upgrade_card(upgrade, "general")
		_upgrade_grid.add_child(card)
	
	# Add reset button in bottom right
	_add_reset_button_to_content("general")


func _build_character_upgrades(char_id: String) -> void:
	# For now, show a placeholder - character-specific upgrades can be added later
	var placeholder := Label.new()
	placeholder.text = "Character upgrades coming soon!"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _pretendard_medium:
		placeholder.add_theme_font_override("font", _pretendard_medium)
	placeholder.add_theme_font_size_override("font_size", 24)
	placeholder.add_theme_color_override("font_color", LABEL_COLOR)
	_upgrade_grid.add_child(placeholder)
	
	# Add reset button in bottom right
	_add_reset_button_to_content(char_id)


func _create_upgrade_card(upgrade: Dictionary, category: String) -> Control:
	var upgrade_id: String = category + "_" + upgrade["id"]
	var current_level: int = _upgrade_levels.get(upgrade_id, 0)
	var max_level: int = upgrade["max_level"]
	var is_maxed: bool = current_level >= max_level
	var cost: int = _calculate_upgrade_cost(upgrade["base_cost"], current_level)
	var can_afford: bool = GameState.get_pristine_cores() >= cost
	
	# Use interactive card class for hover effects
	var card := _UpgradeCard.new()
	card.custom_minimum_size = Vector2(200, 560)  # Twice as tall
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.setup(is_maxed)
	card.set_can_purchase(can_afford and not is_maxed)
	
	# Connect card click to purchase
	if not is_maxed:
		card.card_clicked.connect(_on_upgrade_purchased_with_card.bind(upgrade_id, cost, card))
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 24
	vbox.offset_bottom = -24
	vbox.add_theme_constant_override("separation", 20)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)
	
	# Icon centered at top
	var icon_center := CenterContainer.new()
	icon_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_center)
	
	var icon := Label.new()
	icon.text = upgrade["icon"]
	icon.add_theme_font_size_override("font_size", 96)  # Much bigger icon
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(icon)
	
	# Name centered
	var name_label := Label.new()
	name_label.text = upgrade["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pretendard_bold:
		name_label.add_theme_font_override("font", _pretendard_bold)
	name_label.add_theme_font_size_override("font_size", 48)  # Much bigger text
	name_label.add_theme_color_override("font_color", HEADER_COLOR)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)
	
	# Level indicator centered
	var level_label := Label.new()
	level_label.text = "Lv. %d / %d" % [current_level, max_level]
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pretendard_medium:
		level_label.add_theme_font_override("font", _pretendard_medium)
	level_label.add_theme_font_size_override("font_size", 36)  # Much bigger text
	level_label.add_theme_color_override("font_color", UNLOCKED_COLOR if is_maxed else LABEL_COLOR)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(level_label)
	
	# Description centered
	var desc_label := Label.new()
	desc_label.text = upgrade["desc"]
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pretendard_medium:
		desc_label.add_theme_font_override("font", _pretendard_medium)
	desc_label.add_theme_font_size_override("font_size", 28)  # Much bigger text
	desc_label.add_theme_color_override("font_color", LABEL_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)
	
	# Buy button or maxed label - centered
	var btn_center := CenterContainer.new()
	btn_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(btn_center)
	
	if is_maxed:
		var maxed_label := Label.new()
		maxed_label.text = "MAXED"
		maxed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if _pretendard_bold:
			maxed_label.add_theme_font_override("font", _pretendard_bold)
		maxed_label.add_theme_font_size_override("font_size", 36)  # Much bigger text
		maxed_label.add_theme_color_override("font_color", UNLOCKED_COLOR)
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
	var can_afford: bool = GameState.get_pristine_cores() >= cost
	
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 72)  # Much bigger button
	btn.focus_mode = Control.FOCUS_NONE
	
	# Style: sci-fi container look matching the header
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()
	
	if can_afford:
		normal.bg_color = Color(0.05, 0.02, 0.02, 0.95)
		normal.border_color = Color(1.0, 0.25, 0.2, 0.9)
		hover.bg_color = Color(0.1, 0.04, 0.04, 0.98)
		hover.border_color = Color(1.0, 0.4, 0.35, 1.0)
		pressed.bg_color = Color(0.15, 0.05, 0.05, 1.0)
		pressed.border_color = Color(1.0, 0.5, 0.45, 1.0)
	else:
		normal.bg_color = Color(0.04, 0.04, 0.05, 0.7)
		normal.border_color = Color(0.4, 0.35, 0.35, 0.5)
		hover.bg_color = Color(0.05, 0.05, 0.06, 0.8)
		hover.border_color = Color(0.5, 0.45, 0.45, 0.6)
		pressed.bg_color = Color(0.04, 0.04, 0.05, 0.7)
		pressed.border_color = Color(0.4, 0.35, 0.35, 0.5)
	
	disabled.bg_color = Color(0.03, 0.03, 0.04, 0.6)
	disabled.border_color = Color(0.3, 0.3, 0.35, 0.4)
	
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
	
	var core_icon := _create_core_icon(44)  # Much bigger icon
	core_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_section.add_child(core_icon)
	
	# Divider line
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(2, 48)  # Taller divider
	divider.color = Color(1.0, 0.3, 0.25, 0.5) if can_afford else Color(0.4, 0.4, 0.45, 0.3)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)
	
	# Cost section
	var cost_section := CenterContainer.new()
	cost_section.custom_minimum_size = Vector2(60, 0)
	cost_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cost_section)
	
	var cost_label := Label.new()
	cost_label.text = str(cost)
	if _pretendard_bold:
		cost_label.add_theme_font_override("font", _pretendard_bold)
	cost_label.add_theme_font_size_override("font_size", 36)  # Much bigger text
	cost_label.add_theme_color_override("font_color", CORE_COLOR if can_afford else LOCKED_COLOR)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_section.add_child(cost_label)
	
	btn.disabled = not can_afford
	
	# Connect with parent card for visual feedback
	if parent_card:
		btn.pressed.connect(_on_upgrade_purchased_with_card.bind(upgrade_id, cost, parent_card))
	else:
		btn.pressed.connect(_on_upgrade_purchased.bind(upgrade_id, cost))
	
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
	normal.bg_color = Color(0.08, 0.085, 0.12, 0.95)
	normal.set_border_width_all(3)
	normal.border_color = Color(0.6, 0.15, 0.15, 0.8)
	normal.set_corner_radius_all(12)
	panel_btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.12, 0.1, 0.15, 0.98)
	hover.set_border_width_all(4)
	hover.border_color = Color(1.0, 0.3, 0.3, 0.95)
	hover.set_corner_radius_all(12)
	panel_btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.15, 0.08, 0.1, 0.98)
	pressed.set_border_width_all(4)
	pressed.border_color = Color(1.0, 0.4, 0.4, 1.0)
	pressed.set_corner_radius_all(12)
	panel_btn.add_theme_stylebox_override("pressed", pressed)
	
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.06, 0.065, 0.09, 0.7)
	disabled.set_border_width_all(2)
	disabled.border_color = Color(0.3, 0.3, 0.35, 0.5)
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
	if _futura_bold:
		unlock_label.add_theme_font_override("font", _futura_bold)
	unlock_label.add_theme_font_size_override("font_size", 42)
	unlock_label.add_theme_color_override("font_color", HEADER_COLOR)
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
	if _pretendard_medium:
		hint.add_theme_font_override("font", _pretendard_medium)
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.8))
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
	var can_afford: bool = GameState.get_pristine_cores() >= cost
	
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
		if _futura_bold:
			cost_label.add_theme_font_override("font", _futura_bold)
		cost_label.add_theme_font_size_override("font_size", 48)
		cost_label.add_theme_color_override("font_color", CORE_COLOR)
		cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_row.add_child(cost_label)
	
	# Update hint text based on affordability
	var hint := content.get_node_or_null("ClickHint") as Label
	if hint:
		if can_afford:
			hint.text = "Click to Unlock"
			hint.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 0.9))
		else:
			hint.text = "Not Enough Cores"
			hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.7))
	
	# Enable/disable button
	panel_btn.disabled = not can_afford
	
	# Disconnect old signals and connect new
	for connection in panel_btn.pressed.get_connections():
		panel_btn.pressed.disconnect(connection["callable"])
	
	panel_btn.pressed.connect(_on_character_unlock.bind(char_id, cost))


func _on_upgrade_purchased(upgrade_id: String, cost: int) -> void:
	_on_upgrade_purchased_with_card(upgrade_id, cost, null)


func _on_upgrade_purchased_with_card(upgrade_id: String, cost: int, card: _UpgradeCard) -> void:
	if GameState.spend_pristine_cores(cost):
		_upgrade_levels[upgrade_id] = _upgrade_levels.get(upgrade_id, 0) + 1
		
		# Track cores spent - general upgrades go to "general", character upgrades to char_id
		var category: String = "general"
		if upgrade_id.begins_with("char_"):
			var parts := upgrade_id.split("_")
			if parts.size() >= 2:
				category = parts[1]  # Extract char_id from "char_<char_id>_<upgrade>"
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
	if GameState.spend_pristine_cores(cost):
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
	_reset_all_shop_data()


func _reset_all_shop_data() -> void:
	# Reset pristine cores to 0
	var current_cores := GameState.get_pristine_cores()
	if current_cores > 0:
		GameState.spend_pristine_cores(current_cores)
	
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
	reset_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	
	# Style the reset button as a big square
	var reset_normal := StyleBoxFlat.new()
	reset_normal.bg_color = Color(0.5, 0.15, 0.15, 0.9)
	reset_normal.set_border_width_all(3)
	reset_normal.border_color = Color(0.8, 0.3, 0.3, 0.8)
	reset_normal.set_corner_radius_all(10)
	reset_btn.add_theme_stylebox_override("normal", reset_normal)
	
	var reset_hover := StyleBoxFlat.new()
	reset_hover.bg_color = Color(0.7, 0.2, 0.2, 0.95)
	reset_hover.set_border_width_all(3)
	reset_hover.border_color = Color(1.0, 0.4, 0.4, 0.9)
	reset_hover.set_corner_radius_all(10)
	reset_btn.add_theme_stylebox_override("hover", reset_hover)
	
	var reset_pressed := StyleBoxFlat.new()
	reset_pressed.bg_color = Color(0.4, 0.1, 0.1, 0.95)
	reset_pressed.set_border_width_all(3)
	reset_pressed.border_color = Color(0.6, 0.2, 0.2, 0.9)
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
	GameState.add_pristine_cores(refund_amount)
	
	# Reset upgrade levels for this category
	var keys_to_remove: Array[String] = []
	for upgrade_id in _upgrade_levels.keys():
		if upgrade_id.begins_with(category + "_"):
			keys_to_remove.append(upgrade_id)
	for key in keys_to_remove:
		_upgrade_levels.erase(key)
	
	# Reset cores spent for this category
	_cores_spent.erase(category)
	
	# Save
	_save_shop_data()
	
	# Update UI
	_update_currency_display()
	_update_sidebar_counts()
	_rebuild_content()
	
	print("[ShopMenu] Refunded %d cores for category: %s" % [refund_amount, category])


func _update_currency_display() -> void:
	if _currency_label:
		_currency_label.text = str(GameState.get_pristine_cores())


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
	style.bg_color = BACKGROUND_COLOR
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.75, 0.75, 0.8, 0.8)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 3
	style.shadow_offset = Vector2(2, 2)
	return style


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.set_border_width_all(4)
	style.border_color = BORDER_COLOR
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6
	style.shadow_offset = Vector2(3, 3)
	return style


func _make_sidebar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.065, 0.09, 0.95)
	style.set_border_width_all(2)
	style.border_color = SEPARATOR_COLOR
	style.set_corner_radius_all(8)
	return style


func _make_content_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.08, 0.9)
	style.set_border_width_all(2)
	style.border_color = SEPARATOR_COLOR
	style.set_corner_radius_all(8)
	return style


func _make_portrait_style(is_unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 1.0)
	style.set_border_width_all(3)
	if is_unlocked:
		style.border_color = Color(1.0, 1.0, 1.0, 0.9)
	else:
		style.border_color = Color(0.4, 0.4, 0.45, 0.7)
	style.set_corner_radius_all(8)
	return style


func _make_upgrade_card_style(is_maxed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ENTRY_BG_COLOR
	style.set_border_width_all(2)
	if is_maxed:
		style.border_color = UNLOCKED_COLOR
	else:
		style.border_color = ENTRY_BORDER_COLOR.darkened(0.3)
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
	var config := ConfigFile.new()
	if config.load(SaveManagerScript.SHOP_PATH) != OK:
		return 0.0
	
	var level: int = config.get_value("upgrades", "general_" + upgrade_type, 0)
	
	match upgrade_type:
		"atk":
			return level * 0.05  # +5% per level
		"hp":
			return float(level)  # +1 HP per level
		"speed":
			return level * 0.05  # +5% per level
		"crit":
			return level * 0.02  # +2% per level
		"pickup":
			return level * 0.10  # +10% per level
		"xp":
			return level * 0.05  # +5% per level
	
	return 0.0


## Check if a character is unlocked
static func is_character_unlocked(char_id: String) -> bool:
	if char_id in CharacterRegistry.DEFAULT_UNLOCKED:
		return true
	
	var config := ConfigFile.new()
	if config.load(SaveManagerScript.SHOP_PATH) != OK:
		return false
	
	var unlocked = config.get_value("characters", "unlocked", [])
	return char_id in unlocked


# === UPGRADE CARD (Inner class) - Interactive card with hover/flash effects ===

class _UpgradeCard extends Control:
	signal card_clicked
	
	const NORMAL_BG := Color(0.1, 0.1, 0.14, 0.95)
	const HOVER_BG := Color(0.14, 0.14, 0.2, 0.98)
	const PURCHASED_BG := Color(0.25, 0.28, 0.3, 0.95)  # Light grey for purchased
	const CANT_AFFORD_BG := Color(0.35, 0.08, 0.08, 0.95)  # Red flash
	const BORDER_NORMAL := Color(0.4, 0.4, 0.45, 0.7)
	const BORDER_HOVER := Color(0.7, 0.7, 0.75, 0.9)
	const BORDER_MAXED := Color(0.392, 0.86, 0.549, 1.0)
	
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
					return  # Can't click maxed cards
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
		_flash_color = PURCHASED_BG
		_flash_time = _flash_duration
		queue_redraw()
	
	func flash_cant_afford() -> void:
		_flash_color = CANT_AFFORD_BG
		_flash_time = _flash_duration * 0.5  # Shorter red flash
		queue_redraw()
	
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		
		# Calculate current background color
		var bg_color: Color = NORMAL_BG
		if _flash_time > 0.0:
			var flash_t: float = _flash_time / _flash_duration
			bg_color = NORMAL_BG.lerp(_flash_color, flash_t)
		elif _is_hovered:
			bg_color = HOVER_BG
		
		# Border color
		var border_color: Color
		if _is_maxed:
			border_color = BORDER_MAXED
		elif _is_hovered:
			border_color = BORDER_HOVER
		else:
			border_color = BORDER_NORMAL
		
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
				_draw_rounded_rect(glow_rect, Color(0.8, 0.8, 0.9, glow_alpha), corner_radius + i * 2)
	
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
				draw_line(start_pos, end_pos, Color(1.0, 0.85, 0.4, glow_alpha), glow_width)
			draw_line(start_pos, end_pos, Color(1.0, 0.9, 0.5, 0.9), ray_width)
		
		# Pulsing outer ring
		var ring_pulse: float = 1.0 + sin(_time * 4.0) * 0.08
		var ring_radius: float = base_radius * 0.85 * ring_pulse
		for i in range(4, 0, -1):
			var alpha: float = 0.2 * float(i) / 4.0
			var r: float = ring_radius + float(i) * 3.0
			draw_arc(center, r, 0, TAU, 64, Color(1.0, 0.8, 0.3, alpha), 2.0)
		draw_arc(center, ring_radius, 0, TAU, 64, Color(1.0, 0.9, 0.5, 0.7), 3.0)
		
		# Central glowing orb
		var orb_pulse: float = 1.0 + sin(_time * 5.0) * 0.1
		var orb_radius: float = base_radius * 0.45 * orb_pulse
		
		# Orb outer glow
		for i in range(10, 0, -1):
			var glow_alpha: float = 0.12 * (1.0 - float(i) / 10.0)
			var glow_radius: float = orb_radius + float(i) * 4.0
			draw_circle(center, glow_radius, Color(1.0, 0.7, 0.2, glow_alpha))
		
		# Orb gradient fill
		var segments: int = 24
		for i in range(segments, 0, -1):
			var t: float = float(i) / float(segments)
			var r: float = orb_radius * t
			var brightness: float = 0.6 + 0.4 * (1.0 - t)
			draw_circle(center, r, Color(1.0 * brightness, 0.85 * brightness, 0.3 * brightness + 0.3 * (1.0 - t)))
		
		# Hot white center
		var core_pulse: float = 1.0 + sin(_time * 6.0) * 0.15
		draw_circle(center, orb_radius * 0.35 * core_pulse, Color(1.0, 1.0, 0.9, 1.0))
		draw_circle(center, orb_radius * 0.2 * core_pulse, Color(1.0, 1.0, 1.0, 1.0))
		
		# Floating sparkles
		var num_sparkles: int = 6
		for i in range(num_sparkles):
			var sparkle_angle: float = (float(i) / float(num_sparkles)) * TAU + _time * 1.5
			var sparkle_dist: float = base_radius * 0.6 + sin(_time * 2.5 + float(i) * 1.2) * base_radius * 0.15
			var sparkle_pos: Vector2 = center + Vector2(cos(sparkle_angle), sin(sparkle_angle)) * sparkle_dist
			var sparkle_size: float = 4.0 + sin(_time * 4.0 + float(i)) * 2.0
			var sparkle_alpha: float = 0.6 + sin(_time * 5.0 + float(i) * 0.7) * 0.3
			draw_circle(sparkle_pos, sparkle_size, Color(1.0, 1.0, 0.8, sparkle_alpha))


# === PRISTINE CORE ICON (Inner class) ===

class _PristineCoreIcon extends Control:
	func _draw() -> void:
		var center: Vector2 = size / 2.0
		var radius: float = minf(size.x, size.y) / 2.0 - 2.0
		
		# Outer glow
		for i in range(8, 0, -1):
			var glow_alpha: float = 0.15 * (1.0 - float(i) / 8.0)
			var glow_radius: float = radius + float(i) * 2.0
			draw_circle(center, glow_radius, Color(1.0, 0.2, 0.2, glow_alpha))
		
		# Main sphere gradient (darker red outer to bright inner)
		var segments: int = 32
		for i in range(segments, 0, -1):
			var t: float = float(i) / float(segments)
			var r: float = radius * t
			var color := Color(0.6 + 0.4 * (1.0 - t), 0.1 + 0.2 * (1.0 - t), 0.1 + 0.1 * (1.0 - t))
			draw_circle(center, r, color)
		
		# Inner glowing core
		var core_radius: float = radius * 0.5
		for i in range(16, 0, -1):
			var t: float = float(i) / 16.0
			var r: float = core_radius * t
			var alpha: float = 0.8 * (1.0 - t * 0.5)
			draw_circle(center, r, Color(1.0, 0.5, 0.3, alpha))
		
		# Hot center
		draw_circle(center, radius * 0.15, Color(1.0, 0.9, 0.7, 1.0))
		
		# Specular highlight
		var highlight_offset: Vector2 = Vector2(-radius * 0.25, -radius * 0.25)
		var highlight_radius: float = radius * 0.2
		draw_circle(center + highlight_offset, highlight_radius, Color(1.0, 1.0, 1.0, 0.6))
		draw_circle(center + highlight_offset, highlight_radius * 0.5, Color(1.0, 1.0, 1.0, 0.9))


# Sci-fi danger container for Pristine Rapture Core display
class _PristineCoreContainer extends Control:
	const CONTAINER_WIDTH := 180.0  # Narrower
	const CONTAINER_HEIGHT := 70.0
	const BORDER_THICKNESS := 2.0
	const CORNER_CUT := 8.0  # Smaller corner cuts
	
	const BG_COLOR := Color(0.05, 0.02, 0.02, 0.95)  # Very dark red-tinted
	const BORDER_COLOR := Color(1.0, 0.25, 0.2, 0.9)  # Danger red
	const GLOW_COLOR := Color(1.0, 0.2, 0.15, 0.4)  # Red glow
	const DIVIDER_COLOR := Color(1.0, 0.3, 0.25, 0.6)  # Divider line
	const TEXT_COLOR := Color(1.0, 0.35, 0.3, 1.0)  # Bright danger red
	
	var _core_icon: Control = null
	var _count_label: Label = null
	var _glow_time: float = 0.0
	
	func _init() -> void:
		custom_minimum_size = Vector2(CONTAINER_WIDTH, CONTAINER_HEIGHT)
	
	func _ready() -> void:
		_build_container()
	
	func _process(delta: float) -> void:
		_glow_time += delta
		queue_redraw()
	
	func get_core_icon() -> Control:
		return _core_icon
	
	func get_count_label() -> Label:
		return _count_label
	
	func _build_container() -> void:
		# Main content HBox
		var content := HBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 12
		content.offset_right = -12
		content.offset_top = 14  # Below the title
		content.offset_bottom = -6
		content.add_theme_constant_override("separation", 0)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(content)
		
		# Core icon section (left side)
		var icon_section := CenterContainer.new()
		icon_section.custom_minimum_size = Vector2(50, 0)
		content.add_child(icon_section)
		
		var icon_container := Control.new()
		icon_container.custom_minimum_size = Vector2(40, 40)
		icon_section.add_child(icon_container)
		
		_core_icon = _PristineCoreIcon.new()
		_core_icon.custom_minimum_size = Vector2(40, 40)
		_core_icon.size = Vector2(40, 40)
		icon_container.add_child(_core_icon)
		
		# Vertical divider - drawn in _draw() instead
		var divider_space := Control.new()
		divider_space.custom_minimum_size = Vector2(16, 0)
		content.add_child(divider_space)
		
		# Count section (right side)
		var count_section := CenterContainer.new()
		count_section.custom_minimum_size = Vector2(60, 0)
		count_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(count_section)
		
		_count_label = Label.new()
		_count_label.text = "0"
		_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var font: Font = preload("res://resources/fonts/futura_condensed_extra_bold.tres")
		_count_label.add_theme_font_override("font", font)
		_count_label.add_theme_font_size_override("font_size", 36)
		_count_label.add_theme_color_override("font_color", TEXT_COLOR)
		_count_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		_count_label.add_theme_constant_override("outline_size", 2)
		count_section.add_child(_count_label)
	
	func _draw() -> void:
		var w := size.x
		var h := size.y
		
		# Pulsing glow effect
		var glow_pulse: float = 0.4 + 0.15 * sin(_glow_time * 2.5)
		
		# Draw outer glow
		for i in range(4, 0, -1):
			var glow_alpha: float = glow_pulse * 0.06 * (1.0 - float(i) / 4.0)
			var offset: float = float(i) * 1.5
			var glow_rect := Rect2(-offset, -offset, w + offset * 2, h + offset * 2)
			draw_rect(glow_rect, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, glow_alpha))
		
		# Draw background with cut corners (sci-fi hexagonal look)
		var bg_points := PackedVector2Array([
			Vector2(CORNER_CUT, 0),
			Vector2(w - CORNER_CUT, 0),
			Vector2(w, CORNER_CUT),
			Vector2(w, h - CORNER_CUT),
			Vector2(w - CORNER_CUT, h),
			Vector2(CORNER_CUT, h),
			Vector2(0, h - CORNER_CUT),
			Vector2(0, CORNER_CUT)
		])
		draw_colored_polygon(bg_points, BG_COLOR)
		
		# Draw border
		for i in range(bg_points.size()):
			var p1: Vector2 = bg_points[i]
			var p2: Vector2 = bg_points[(i + 1) % bg_points.size()]
			draw_line(p1, p2, BORDER_COLOR, BORDER_THICKNESS, true)
		
		# Draw vertical divider line in the middle
		var divider_x := w * 0.42  # Position divider between icon and count
		var divider_top := 16.0
		var divider_bottom := h - 8.0
		draw_line(Vector2(divider_x, divider_top), Vector2(divider_x, divider_bottom), DIVIDER_COLOR, 1.5)
		
		# Draw "PRISTINE CORE" title at top (shorter)
		var title_font: Font = preload("res://resources/fonts/futura_condensed_extra_bold.tres")
		var title_text := "PRISTINE CORE"
		var title_size := 10
		var title_color := Color(1.0, 0.4, 0.35, 0.9)
		var title_width: float = title_font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		var title_x: float = (w - title_width) / 2.0
		draw_string(title_font, Vector2(title_x, 12), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, title_color)
		
		# Draw subtle scan lines for tech effect
		var scan_alpha: float = 0.03 + 0.02 * sin(_glow_time * 5.0)
		for y_line in range(0, int(h), 4):
			draw_line(Vector2(CORNER_CUT, y_line), Vector2(w - CORNER_CUT, y_line), 
					 Color(1.0, 0.3, 0.2, scan_alpha), 1.0)
