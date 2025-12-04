extends Control
class_name ShopMenu
## Main Menu Shop - Permanent upgrades purchased with Pristine Rapture Cores.
## Layout: Left sidebar with character portraits + GENERAL, right side with upgrade grid.
## Characters can be unlocked here. Default unlocked: Snow White, Rapunzel, Scarlet.

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
const SAVE_PATH := "user://shop_data.cfg"

# Character data - same order as CharacterRegistry
const CHARACTER_NAMES := ["Snow White", "Scarlet", "Rapunzel", "Nayuta", "Commander", "Marian", "Crown", "Kilo", "Cecil", "Sin"]
const CHARACTER_IDS := ["snow_white", "scarlet", "rapunzel", "nayuta", "commander", "marian", "crown", "kilo", "cecil", "sin"]
const PORTRAIT_PATHS := [
	"res://assets/characters/scarlet/portrait-sq.png",
	"res://assets/characters/commander/portrait-sq.png",
	"res://assets/characters/rapunzel/portrait-sq.png",
	"res://assets/characters/kilo/portrait-sq.png",
	"res://assets/characters/marian/portrait-sq.png",
	"res://assets/characters/crown/portrait-sq.png",
	"res://assets/characters/snow-white/portrait-sq.png",
	"res://assets/characters/sin/portrait-sq.png",
	"res://assets/characters/cecil/portrait-sq.png",
	"res://assets/characters/nayuta/portrait-sq.png",
]

# Default unlocked characters
const DEFAULT_UNLOCKED := ["snow_white", "rapunzel", "scarlet"]

# Character unlock costs
const CHARACTER_UNLOCK_COST := 3  # Pristine Rapture Cores to unlock a character

# General upgrades (apply to all characters)
const GENERAL_UPGRADES := [
	{"id": "atk", "name": "ATK", "desc": "+5% Attack Damage", "max_level": 10, "base_cost": 1, "icon": "⚔️"},
	{"id": "hp", "name": "HP", "desc": "+1 Max HP", "max_level": 10, "base_cost": 1, "icon": "❤️"},
	{"id": "speed", "name": "SPD", "desc": "+3% Movement Speed", "max_level": 10, "base_cost": 1, "icon": "👟"},
	{"id": "crit", "name": "CRIT", "desc": "+2% Critical Chance", "max_level": 10, "base_cost": 1, "icon": "💥"},
	{"id": "xp", "name": "XP", "desc": "+5% Experience Gain", "max_level": 5, "base_cost": 2, "icon": "⭐"},
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
	var err := config.load(SAVE_PATH)
	
	# Start with default unlocked characters
	_unlocked_characters.clear()
	for char_id in DEFAULT_UNLOCKED:
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
		if char_id not in DEFAULT_UNLOCKED:
			extra_unlocked.append(char_id)
	config.set_value("characters", "unlocked", extra_unlocked)
	
	# Save upgrade levels
	for upgrade_id in _upgrade_levels:
		config.set_value("upgrades", upgrade_id, _upgrade_levels[upgrade_id])
	
	# Save cores spent
	for category in _cores_spent:
		config.set_value("cores_spent", category, _cores_spent[category])
	
	var err := config.save(SAVE_PATH)
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
	
	# Title and currency row
	var title_row := HBoxContainer.new()
	title_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_row.offset_left = 48
	title_row.offset_right = -48
	title_row.add_theme_constant_override("separation", 24)
	top_bar.add_child(title_row)
	
	# Left placeholder for centering balance
	var left_placeholder := Control.new()
	left_placeholder.custom_minimum_size = Vector2(150, 0)  # Match right side
	left_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(left_placeholder)
	
	# Left spacer for true centering
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(left_spacer)
	
	var title_label := Label.new()
	title_label.text = "SHOP"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _futura_bold:
		title_label.add_theme_font_override("font", _futura_bold)
	title_label.add_theme_font_size_override("font_size", 80)
	title_label.add_theme_color_override("font_color", HEADER_COLOR)
	title_label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15, 1.0))
	title_label.add_theme_constant_override("outline_size", 3)
	title_row.add_child(title_label)
	
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(right_spacer)
	
	# Currency display (top right)
	var currency_container := HBoxContainer.new()
	currency_container.custom_minimum_size = Vector2(150, 0)  # Match left placeholder
	currency_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	currency_container.add_theme_constant_override("separation", 12)
	title_row.add_child(currency_container)
	
	# Pristine Rapture Core icon
	_currency_icon = _create_core_icon(48)
	currency_container.add_child(_currency_icon)
	
	_currency_label = Label.new()
	_currency_label.text = "0"
	_currency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _futura_bold:
		_currency_label.add_theme_font_override("font", _futura_bold)
	_currency_label.add_theme_font_size_override("font_size", 48)
	_currency_label.add_theme_color_override("font_color", CORE_COLOR)
	currency_container.add_child(_currency_label)
	
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
	_upgrade_grid.columns = 3
	_upgrade_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_grid.add_theme_constant_override("h_separation", 16)
	_upgrade_grid.add_theme_constant_override("v_separation", 16)
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
	
	# Add all characters
	for i in range(CHARACTER_NAMES.size()):
		var char_name: String = CHARACTER_NAMES[i]
		var char_id: String = CHARACTER_IDS[i]
		var is_unlocked: bool = char_id in _unlocked_characters
		var portrait: Texture2D = null
		if i < PORTRAIT_PATHS.size() and ResourceLoader.exists(PORTRAIT_PATHS[i]):
			portrait = load(PORTRAIT_PATHS[i])
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
	var count_margin := MarginContainer.new()
	count_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_margin.add_theme_constant_override("margin_left", 10)
	count_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(count_margin)
	
	var count_container := CenterContainer.new()
	count_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_margin.add_child(count_container)
	
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
	var cost: int = upgrade["base_cost"] + current_level  # Cost increases with level
	
	var card := Panel.new()
	card.custom_minimum_size = Vector2(220, 180)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_upgrade_card_style(is_maxed))
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)
	
	# Icon and name row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	
	var icon := Label.new()
	icon.text = upgrade["icon"]
	icon.add_theme_font_size_override("font_size", 32)
	header.add_child(icon)
	
	var name_label := Label.new()
	name_label.text = upgrade["name"]
	if _pretendard_bold:
		name_label.add_theme_font_override("font", _pretendard_bold)
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", HEADER_COLOR)
	header.add_child(name_label)
	
	# Level indicator
	var level_label := Label.new()
	level_label.text = "Lv. %d / %d" % [current_level, max_level]
	if _pretendard_medium:
		level_label.add_theme_font_override("font", _pretendard_medium)
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_color", UNLOCKED_COLOR if is_maxed else LABEL_COLOR)
	vbox.add_child(level_label)
	
	# Description
	var desc_label := Label.new()
	desc_label.text = upgrade["desc"]
	if _pretendard_medium:
		desc_label.add_theme_font_override("font", _pretendard_medium)
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", LABEL_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Buy button
	if is_maxed:
		var maxed_label := Label.new()
		maxed_label.text = "MAXED"
		maxed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if _pretendard_bold:
			maxed_label.add_theme_font_override("font", _pretendard_bold)
		maxed_label.add_theme_font_size_override("font_size", 18)
		maxed_label.add_theme_color_override("font_color", UNLOCKED_COLOR)
		vbox.add_child(maxed_label)
	else:
		var buy_btn := _create_buy_button(cost, upgrade_id)
		vbox.add_child(buy_btn)
	
	return card


func _create_buy_button(cost: int, upgrade_id: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Button content: icon + cost
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)
	
	var core_icon := _create_core_icon(24)
	hbox.add_child(core_icon)
	
	var cost_label := Label.new()
	cost_label.text = str(cost)
	if _pretendard_bold:
		cost_label.add_theme_font_override("font", _pretendard_bold)
	cost_label.add_theme_font_size_override("font_size", 18)
	cost_label.add_theme_color_override("font_color", Color(1, 1, 1))
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(cost_label)
	
	var can_afford: bool = GameState.get_pristine_cores() >= cost
	
	var normal := StyleBoxFlat.new()
	if can_afford:
		normal.bg_color = Color(0.2, 0.5, 0.2, 0.95)
		normal.border_color = Color(0.3, 0.8, 0.3, 0.9)
	else:
		normal.bg_color = Color(0.2, 0.2, 0.25, 0.6)
		normal.border_color = Color(0.4, 0.4, 0.45, 0.5)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	if can_afford:
		hover.bg_color = Color(0.25, 0.6, 0.25, 1.0)
		hover.border_color = Color(0.4, 1.0, 0.4)
	else:
		hover.bg_color = Color(0.25, 0.25, 0.3, 0.7)
		hover.border_color = Color(0.5, 0.5, 0.55, 0.6)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover)
	
	btn.disabled = not can_afford
	btn.pressed.connect(_on_upgrade_purchased.bind(upgrade_id, cost))
	
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
	var char_name := ""
	for i in range(CHARACTER_IDS.size()):
		if CHARACTER_IDS[i] == char_id:
			char_name = CHARACTER_NAMES[i]
			break
	
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
	if GameState.spend_pristine_cores(cost):
		_upgrade_levels[upgrade_id] = _upgrade_levels.get(upgrade_id, 0) + 1
		
		# Track cores spent - general upgrades go to "general", character upgrades to char_id
		var category: String = "general"
		if upgrade_id.begins_with("char_"):
			var parts := upgrade_id.split("_")
			if parts.size() >= 2:
				category = parts[1]  # Extract char_id from "char_<char_id>_<upgrade>"
		_cores_spent[category] = _cores_spent.get(category, 0) + cost
		
		_save_shop_data()
		_update_currency_display()
		_update_sidebar_counts()
		_rebuild_content()
		print("[ShopMenu] Purchased upgrade: %s (now level %d)" % [upgrade_id, _upgrade_levels[upgrade_id]])


func _on_character_unlock(char_id: String, cost: int) -> void:
	if GameState.spend_pristine_cores(cost):
		_unlocked_characters.append(char_id)
		
		# Track cores spent for unlocking
		_cores_spent[char_id] = _cores_spent.get(char_id, 0) + cost
		
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
	for char_id in DEFAULT_UNLOCKED:
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

## Get total bonus for an upgrade type (for use by game systems)
static func get_upgrade_bonus(upgrade_type: String) -> float:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return 0.0
	
	var level: int = config.get_value("upgrades", "general_" + upgrade_type, 0)
	
	match upgrade_type:
		"atk":
			return level * 0.05  # +5% per level
		"hp":
			return float(level)  # +1 HP per level
		"speed":
			return level * 0.03  # +3% per level
		"crit":
			return level * 0.02  # +2% per level
		"pickup":
			return level * 0.10  # +10% per level
		"xp":
			return level * 0.05  # +5% per level
	
	return 0.0


## Check if a character is unlocked
static func is_character_unlocked(char_id: String) -> bool:
	if char_id in DEFAULT_UNLOCKED:
		return true
	
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	
	var unlocked = config.get_value("characters", "unlocked", [])
	return char_id in unlocked


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
