extends Control
class_name AchievementsMenu
## Achievements menu with character sidebar on the left and achievements list on the right.
## Layout: 20% left sidebar with character portraits, 80% right content with achievements.

signal back_requested

# Visual constants - matching LeaderboardMenu style
const BACKGROUND_COLOR := Color(0.04, 0.055, 0.08, 0.95)
const PANEL_BG_COLOR := Color(0.04, 0.055, 0.08, 0.97)
const BORDER_COLOR := Color(0.95, 0.95, 0.98, 0.9)
const ENTRY_BG_COLOR := Color(0.1, 0.1, 0.14, 0.95)
const ENTRY_BORDER_COLOR := Color(0.95, 0.95, 0.98, 0.9)
const SEPARATOR_COLOR := Color(0.95, 0.95, 0.98, 0.3)

const HEADER_COLOR := Color(0.95, 0.95, 0.98, 1.0)
const LABEL_COLOR := Color(0.784, 0.792, 0.878, 1.0)
const UNLOCKED_COLOR := Color(0.392, 0.86, 0.549, 1.0)
const LOCKED_COLOR := Color(0.6, 0.6, 0.65, 1.0)
const PROGRESS_BG := Color(0.15, 0.15, 0.2, 1.0)
const PROGRESS_FILL := Color(0.533, 0.611, 0.98, 1.0)

const CHARACTER_NORMAL_COLOR := Color(0.08, 0.08, 0.12, 0.95)
const CHARACTER_HOVER_COLOR := Color(0.12, 0.12, 0.18, 0.98)
const CHARACTER_SELECTED_COLOR := Color(0.18, 0.18, 0.25, 1.0)

const GENERAL_FILTER := "GENERAL"

# Character data - loaded from CharacterRegistry (single source of truth)
var _registry: CharacterRegistry = null

# Achievement data
var _achievements: Array[Dictionary] = []
var _selected_filter: String = GENERAL_FILTER
var _completion_filter: String = "ALL"  # ALL, COMPLETE, INCOMPLETE
var _character_entries: Array[Dictionary] = []

# Preload fonts at compile time for better performance
const _futura_bold: Font = preload("res://resources/fonts/futura_condensed_extra_bold.tres")
const _pretendard_bold: Font = preload("res://resources/fonts/pretendard_bold.tres")
const _pretendard_medium: Font = preload("res://resources/fonts/pretendard_medium.tres")

# Filter colors
const FILTER_ALL_COLOR := Color(1.0, 1.0, 1.0, 1.0)  # White
const FILTER_COMPLETE_COLOR := Color(0.392, 0.86, 0.549, 1.0)  # Green
const FILTER_INCOMPLETE_COLOR := Color(0.9, 0.35, 0.35, 1.0)  # Red

# UI references
var _character_list: VBoxContainer = null
var _achievement_list: VBoxContainer = null
var _achievement_scroll: ScrollContainer = null
var _empty_label: Label = null
var _button_group: ButtonGroup = null
var _filter_button_group: ButtonGroup = null
var _filter_buttons: Dictionary = {}  # Store references to filter buttons

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_registry = CharacterRegistry.get_instance()
	_button_group = ButtonGroup.new()
	_filter_button_group = ButtonGroup.new()
	
	_load_achievements()
	_build_ui()
	_select_filter(GENERAL_FILTER)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		emit_signal("back_requested")


func _load_achievements() -> void:
	# Start with general achievements (these are manually defined placeholders)
	_achievements = [
		# General achievements
		{"id": "first_blood", "title": "First Blood", "desc": "Complete a Stage 1 map", "category": GENERAL_FILTER, "unlocked": false, "progress": 0, "target": 1},
		{"id": "kill_50000", "title": "Massacre", "desc": "Defeat 50,000 enemies total", "category": GENERAL_FILTER, "unlocked": false, "progress": 0, "target": 50000},
		{"id": "boss_slayer", "title": "Boss Slayer", "desc": "Defeat a boss enemy", "category": GENERAL_FILTER, "unlocked": false, "progress": 0, "target": 1},
		{"id": "no_damage", "title": "Untouchable", "desc": "Complete a wave without taking damage", "category": GENERAL_FILTER, "unlocked": false, "progress": 0, "target": 1},
		{"id": "all_maps", "title": "World Traveler", "desc": "Play on all maps", "category": GENERAL_FILTER, "unlocked": false, "progress": 2, "target": 4},
	]
	
	# Load character-specific achievements from AchievementManager
	if has_node("/root/AchievementManager"):
		var manager = get_node("/root/AchievementManager")
		var char_achievements: Array = manager.get_all_achievements()
		for ach in char_achievements:
			_achievements.append(ach)

func _build_ui() -> void:
	# Clear existing children
	for child in get_children():
		child.queue_free()
	
	# Background with venetian blinds effect
	var bg := Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.set_script(load("res://scripts/ui/components/VenetianBlindsBackground.gd"))
	add_child(bg)
	
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.25)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	
	# Top bar with title
	var top_bar := Panel.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = 24
	top_bar.offset_bottom = 160
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_stylebox_override("panel", _make_letterbox_style())
	add_child(top_bar)
	
	var title_label := Label.new()
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.offset_left = 24
	title_label.offset_right = -24
	title_label.text = "ACHIEVEMENTS"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _futura_bold:
		title_label.add_theme_font_override("font", _futura_bold)
	title_label.add_theme_font_size_override("font_size", 80)
	title_label.add_theme_color_override("font_color", HEADER_COLOR)
	title_label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15, 1.0))
	title_label.add_theme_constant_override("outline_size", 3)
	top_bar.add_child(title_label)
	
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
	_character_list.add_theme_constant_override("separation", 10)  # More padding between entries
	# Add right margin so scrollbar doesn't cover content
	var char_list_margin := MarginContainer.new()
	char_list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_list_margin.add_theme_constant_override("margin_right", 14)
	left_scroll.add_child(char_list_margin)
	char_list_margin.add_child(_character_list)
	
	# === RIGHT CONTENT (80%) ===
	var right_panel := Panel.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	right_panel.add_theme_stylebox_override("panel", _make_content_style())
	main_hbox.add_child(right_panel)
	
	var right_vbox := VBoxContainer.new()
	right_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_vbox.offset_left = 16
	right_vbox.offset_right = -16
	right_vbox.offset_top = 16
	right_vbox.offset_bottom = -16
	right_vbox.add_theme_constant_override("separation", 12)
	right_panel.add_child(right_vbox)
	
	# Filter buttons row
	var filter_row := HBoxContainer.new()
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_theme_constant_override("separation", 8)
	right_vbox.add_child(filter_row)
	
	# Add filter buttons
	_create_filter_button(filter_row, "ALL", FILTER_ALL_COLOR)
	_create_filter_button(filter_row, "COMPLETE", FILTER_COMPLETE_COLOR)
	_create_filter_button(filter_row, "INCOMPLETE", FILTER_INCOMPLETE_COLOR)
	
	# Spacer to push buttons left
	var filter_spacer := Control.new()
	filter_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(filter_spacer)
	
	# Achievement scroll
	_achievement_scroll = ScrollContainer.new()
	_achievement_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_achievement_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_achievement_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_vbox.add_child(_achievement_scroll)
	
	_achievement_list = VBoxContainer.new()
	_achievement_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_achievement_list.add_theme_constant_override("separation", 16)
	_achievement_scroll.add_child(_achievement_list)
	
	# Empty state label
	_empty_label = Label.new()
	_empty_label.text = "No achievements in this category yet."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _pretendard_medium:
		_empty_label.add_theme_font_override("font", _pretendard_medium)
	_empty_label.add_theme_font_size_override("font_size", 24)
	_empty_label.add_theme_color_override("font_color", LABEL_COLOR)
	_empty_label.visible = false
	right_vbox.add_child(_empty_label)
	
	# Build character list
	_build_character_list()


func _build_character_list() -> void:
	if not _character_list:
		return
	
	for child in _character_list.get_children():
		child.queue_free()
	_character_entries.clear()
	
	# Add "General" category first
	var general_entry := _create_character_entry(GENERAL_FILTER, "General", null)
	_character_entries.append(general_entry)
	
	# Add all characters from registry
	var char_ids := _registry.get_all_character_ids()
	var char_names := _registry.get_all_character_names()
	var portrait_paths := _registry.get_all_portrait_paths()
	
	for i in range(char_ids.size()):
		var char_name: String = char_names[i] if i < char_names.size() else ""
		var char_code: String = char_ids[i]
		var portrait: Texture2D = null
		if i < portrait_paths.size() and ResourceLoader.exists(portrait_paths[i]):
			portrait = load(portrait_paths[i])
		var entry := _create_character_entry(char_code, char_name, portrait)
		_character_entries.append(entry)
	
	_update_character_counts()


func _create_character_entry(code: String, display_name: String, portrait: Texture2D) -> Dictionary:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _button_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 165)  # Height for portrait
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_character_button_styles(button)
	
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
	portrait_panel.clip_contents = true  # Clip portrait to panel bounds
	portrait_panel.add_theme_stylebox_override("panel", _make_portrait_style())
	portrait_container.add_child(portrait_panel)
	
	if portrait != null:
		# Check if character is unlocked
		var is_unlocked := true
		if code != GENERAL_FILTER:
			is_unlocked = ShopMenu.is_character_unlocked(code)
		
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
		# Grey out if locked
		if not is_unlocked:
			tex_rect.modulate = Color(0.3, 0.3, 0.35, 1.0)
		portrait_panel.add_child(tex_rect)
		
		# Lock overlay for locked characters - ON TOP of portrait
		if not is_unlocked:
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
			locked_text.add_theme_color_override("font_color", Color(0.95, 0.7, 0.2, 1.0))  # Gold color like shop
			locked_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock_overlay.add_child(locked_text)
	else:
		# Trophy icon for General (larger to match portrait)
		var icon := Label.new()
		icon.text = "🏆"
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 72)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_panel.add_child(icon)
	
	# Name label
	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _pretendard_bold:
		name_label.add_theme_font_override("font", _pretendard_bold)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", HEADER_COLOR)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)
	
	# Subtle divider line - centered vertically
	var divider_container := CenterContainer.new()
	divider_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	divider_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(divider_container)
	
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(2, 100)
	divider.color = Color(0.5, 0.5, 0.55, 0.25)  # Very subtle
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider_container.add_child(divider)
	
	# Count label container - expand to fill remaining space and center, with slight right offset
	var count_margin := MarginContainer.new()
	count_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_margin.add_theme_constant_override("margin_left", 10)  # Nudge right by 10px
	count_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(count_margin)
	
	var count_container := CenterContainer.new()
	count_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_margin.add_child(count_container)
	
	var count_label := Label.new()
	count_label.text = "0/0"
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
		"display": display_name,
		"button": button,
		"count_label": count_label
	}


func _apply_character_button_styles(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_char_button_style(CHARACTER_NORMAL_COLOR))
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


func _create_filter_button(parent: HBoxContainer, filter_name: String, color: Color) -> void:
	var button := Button.new()
	button.text = filter_name
	button.toggle_mode = true
	button.button_group = _filter_button_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(120, 36)
	
	# Style the button
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.1, 0.1, 0.14, 0.9)
	normal_style.set_border_width_all(2)
	normal_style.border_color = color.darkened(0.3)
	normal_style.set_corner_radius_all(4)
	normal_style.set_content_margin_all(8)
	
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	hover_style.set_border_width_all(2)
	hover_style.border_color = color
	hover_style.set_corner_radius_all(4)
	hover_style.set_content_margin_all(8)
	
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = color.darkened(0.5)
	pressed_style.set_border_width_all(2)
	pressed_style.border_color = color
	pressed_style.set_corner_radius_all(4)
	pressed_style.set_content_margin_all(8)
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", hover_style)
	
	if _pretendard_bold:
		button.add_theme_font_override("font", _pretendard_bold)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color)
	button.add_theme_color_override("font_pressed_color", color)
	button.add_theme_color_override("font_focus_color", color)
	
	# Set ALL as default selected
	if filter_name == "ALL":
		button.button_pressed = true
	
	button.pressed.connect(_on_completion_filter_pressed.bind(filter_name))
	parent.add_child(button)
	_filter_buttons[filter_name] = button


func _on_completion_filter_pressed(filter_name: String) -> void:
	_completion_filter = filter_name
	_rebuild_achievement_list()


func _on_character_pressed(code: String) -> void:
	_select_filter(code)


func _select_filter(filter_code: String) -> void:
	_selected_filter = filter_code
	
	# Update button states
	for entry in _character_entries:
		var button: Button = entry.get("button")
		if button:
			button.button_pressed = (entry.get("code") == filter_code)
	
	_rebuild_achievement_list()


func _update_character_counts() -> void:
	for entry in _character_entries:
		var count_label: Label = entry.get("count_label")
		if not count_label:
			continue
		var code: String = entry.get("code")
		var counts := _calculate_counts_for(code)
		count_label.text = "%d/%d" % [counts.unlocked, counts.total]


func _calculate_counts_for(filter_code: String) -> Dictionary:
	var filtered := _filter_achievements(filter_code)
	var unlocked := 0
	for achievement in filtered:
		if achievement.get("unlocked", false):
			unlocked += 1
	return {"unlocked": unlocked, "total": filtered.size()}


func _filter_achievements(filter_code: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for achievement in _achievements:
		var category: String = achievement.get("category", GENERAL_FILTER)
		if filter_code == GENERAL_FILTER:
			if category == GENERAL_FILTER:
				result.append(achievement)
		else:
			if category.to_lower() == filter_code.to_lower():
				result.append(achievement)
	return result


func _rebuild_achievement_list() -> void:
	if not _achievement_list:
		return
	
	for child in _achievement_list.get_children():
		child.queue_free()
	
	var filtered := _filter_achievements(_selected_filter)
	
	# Apply completion filter
	if _completion_filter == "COMPLETE":
		var complete_filtered: Array[Dictionary] = []
		for ach in filtered:
			if ach.get("unlocked", false):
				complete_filtered.append(ach)
		filtered = complete_filtered
	elif _completion_filter == "INCOMPLETE":
		var incomplete_filtered: Array[Dictionary] = []
		for ach in filtered:
			if not ach.get("unlocked", false):
				incomplete_filtered.append(ach)
		filtered = incomplete_filtered
	
	# Sort: unlocked first, then by progress percentage
	filtered.sort_custom(func(a, b):
		if a.unlocked != b.unlocked:
			return a.unlocked
		var prog_a: float = float(a.progress) / float(max(a.target, 1))
		var prog_b: float = float(b.progress) / float(max(b.target, 1))
		return prog_a > prog_b
	)
	
	_empty_label.visible = filtered.is_empty()
	
	for achievement in filtered:
		var item := _create_achievement_item(achievement)
		_achievement_list.add_child(item)
	
	if _achievement_scroll:
		_achievement_scroll.set_v_scroll(0)


func _create_achievement_item(achievement: Dictionary) -> Control:
	var is_unlocked: bool = achievement.get("unlocked", false)
	
	# Wrapper to make Button size to content
	var wrapper := PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Make the panel transparent - we just use it for sizing
	var transparent_style := StyleBoxEmpty.new()
	wrapper.add_theme_stylebox_override("panel", transparent_style)
	
	# Use Button for hover effect
	var container := Button.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.focus_mode = Control.FOCUS_NONE
	container.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_apply_achievement_button_styles(container, is_unlocked)
	wrapper.add_child(container)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)
	
	# Title row
	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_row)
	
	var title_label := Label.new()
	title_label.text = achievement.get("title", "")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _pretendard_bold:
		title_label.add_theme_font_override("font", _pretendard_bold)
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", UNLOCKED_COLOR if is_unlocked else HEADER_COLOR)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_label)
	
	if is_unlocked:
		var check := Label.new()
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 28)
		check.add_theme_color_override("font_color", UNLOCKED_COLOR)
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(check)
	
	# Description
	var desc_label := Label.new()
	desc_label.text = achievement.get("desc", "")
	if _pretendard_medium:
		desc_label.add_theme_font_override("font", _pretendard_medium)
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", LABEL_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)
	
	# Progress bar (always show for non-unlocked, so all achievements look consistent)
	var target: int = achievement.get("target", 1)
	var progress: int = achievement.get("progress", 0)
	
	if not is_unlocked:
		var progress_row := HBoxContainer.new()
		progress_row.add_theme_constant_override("separation", 12)
		progress_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(progress_row)
		
		var progress_bar := ProgressBar.new()
		progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress_bar.custom_minimum_size = Vector2(0, 16)
		progress_bar.max_value = target
		progress_bar.value = progress
		progress_bar.show_percentage = false
		progress_bar.add_theme_stylebox_override("background", _make_progress_bg_style())
		progress_bar.add_theme_stylebox_override("fill", _make_progress_fill_style())
		progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress_row.add_child(progress_bar)
		
		var progress_label := Label.new()
		progress_label.text = "%d / %d" % [progress, target]
		if _pretendard_medium:
			progress_label.add_theme_font_override("font", _pretendard_medium)
		progress_label.add_theme_font_size_override("font_size", 16)
		progress_label.add_theme_color_override("font_color", LOCKED_COLOR)
		progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress_row.add_child(progress_label)
	else:
		var status_label := Label.new()
		status_label.text = "Unlocked"
		if _pretendard_medium:
			status_label.add_theme_font_override("font", _pretendard_medium)
		status_label.add_theme_font_size_override("font_size", 16)
		status_label.add_theme_color_override("font_color", UNLOCKED_COLOR)
		status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(status_label)
	
	return wrapper


# Style helper functions
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


func _make_portrait_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 1.0)
	style.set_border_width_all(3)
	style.border_color = Color(1.0, 1.0, 1.0, 0.9)  # White border like other portraits
	style.set_corner_radius_all(8)  # Rounded corners, not circle
	return style


func _make_achievement_style(unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ENTRY_BG_COLOR.lightened(0.05) if unlocked else ENTRY_BG_COLOR
	style.set_border_width_all(2)
	style.border_color = UNLOCKED_COLOR if unlocked else ENTRY_BORDER_COLOR.darkened(0.3)
	style.set_corner_radius_all(8)
	return style


func _make_progress_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PROGRESS_BG
	style.set_corner_radius_all(4)
	return style


func _make_progress_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PROGRESS_FILL
	style.set_corner_radius_all(4)
	return style


func _apply_achievement_button_styles(button: Button, is_unlocked: bool) -> void:
	button.add_theme_stylebox_override("normal", _make_achievement_style(is_unlocked))
	button.add_theme_stylebox_override("hover", _make_achievement_hover_style(is_unlocked))
	button.add_theme_stylebox_override("pressed", _make_achievement_style(is_unlocked))
	button.add_theme_stylebox_override("focus", _make_achievement_hover_style(is_unlocked))


func _make_achievement_hover_style(is_unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Brighter background on hover
	if is_unlocked:
		style.bg_color = Color(0.14, 0.16, 0.22, 0.98)
	else:
		style.bg_color = Color(0.12, 0.12, 0.18, 0.98)
	style.set_border_width_all(2)
	style.border_color = ENTRY_BORDER_COLOR if is_unlocked else Color(0.5, 0.5, 0.55, 0.5)
	style.set_corner_radius_all(8)
	return style
