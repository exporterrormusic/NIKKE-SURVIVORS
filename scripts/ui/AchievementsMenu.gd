extends Control
class_name AchievementsMenu
## Achievements menu with character sidebar on the left and achievements list on the right.
## Layout: 20% left sidebar with character portraits, 80% right content with achievements.

signal back_requested

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

const GENERAL_FILTER := "GENERAL"

# Character data - loaded from CharacterRegistry (single source of truth)
var _registry: CharacterRegistry = null

# Achievement data
var _achievements: Array[Dictionary] = []
var _selected_filter: String = GENERAL_FILTER
var _completion_filter: String = "ALL" # ALL, COMPLETE, INCOMPLETE
var _character_entries: Array[Dictionary] = []

# UI references
var _character_list: VBoxContainer = null
var _achievement_list: VBoxContainer = null
var _achievement_scroll: ScrollContainer = null
var _empty_label: Label = null
var _button_group: ButtonGroup = null
var _filter_button_group: ButtonGroup = null
var _filter_buttons: Dictionary = {} # Store references to filter buttons
var _focus_in_content: bool = false # Track if focus is in the right panel (achievements)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_registry = CharacterRegistry.get_instance()
	_button_group = ButtonGroup.new()
	_filter_button_group = ButtonGroup.new()
	
	_load_achievements()
	_build_ui()
	_select_filter(GENERAL_FILTER)
	
	# Auto-focus first character for controller
	call_deferred("_grab_initial_focus")


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		UISounds.play_back()
		
		# Two-stage back: if in content area, go to categories first
		if _focus_in_content:
			_focus_in_content = false
			_grab_initial_focus() # Go back to category sidebar
		else:
			back_requested.emit() # Exit to main menu


func _load_achievements() -> void:
	# Start with empty list (all achievements now loaded from AchievementManager)
	_achievements = []
	
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
	overlay.color = UI.OVERLAY_LIGHT
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
	if UI.FONT_TITLE:
		title_label.add_theme_font_override("font", UI.FONT_TITLE)
	title_label.add_theme_font_size_override("font_size", 80)
	title_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	title_label.add_theme_color_override("font_outline_color", UI.ACH_TITLE_OUTLINE)
	title_label.add_theme_constant_override("outline_size", 3)
	top_bar.add_child(title_label)
	
	# BACK Button - Sci-fi container style
	var back_btn := SciFiBackButton.new()
	# back_btn.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	back_btn.position = Vector2(48, 30) # Absolute center for 136px header
	back_btn.custom_minimum_size = Vector2(200, 75)
	
	back_btn.pressed.connect(func():
		UISounds.play_back()
		back_requested.emit()
	)
	top_bar.add_child(back_btn)

# Sci-fi styled Back Button

	
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
	_character_list.add_theme_constant_override("separation", 10) # More padding between entries
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
	_create_filter_button(filter_row, "ALL", UI.ACCENT_PRIMARY)
	_create_filter_button(filter_row, "COMPLETE", UI.COLOR_UNLOCKED)
	_create_filter_button(filter_row, "INCOMPLETE", UI.COLOR_DANGER)
	
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
	if UI.FONT_MEDIUM:
		_empty_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	_empty_label.add_theme_font_size_override("font_size", 24)
	_empty_label.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
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
	button.focus_mode = Control.FOCUS_ALL # Enable controller focus
	button.custom_minimum_size = Vector2(0, 165) # Height for portrait
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
	portrait_panel.clip_contents = true # Clip portrait to panel bounds
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
			tex_rect.modulate = UI.ACH_PORTRAIT_LOCKED
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
			if UI.FONT_BOLD:
				locked_text.add_theme_font_override("font", UI.FONT_BOLD)
			locked_text.add_theme_font_size_override("font_size", 14)
			locked_text.add_theme_color_override("font_color", UI.ACH_LOCKED_TEXT)
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
	if UI.FONT_BOLD:
		name_label.add_theme_font_override("font", UI.FONT_BOLD)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
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
	divider.color = UI.ACH_DIVIDER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider_container.add_child(divider)
	
	# Count label container - expand to fill remaining space and center, with slight right offset
	var count_margin := MarginContainer.new()
	count_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_margin.add_theme_constant_override("margin_left", 10) # Nudge right by 10px
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
		"display": display_name,
		"button": button,
		"count_label": count_label
	}


func _apply_character_button_styles(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_char_button_style(UI.CHAR_NORMAL))
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


func _create_filter_button(parent: HBoxContainer, filter_name: String, color: Color) -> void:
	var button := Button.new()
	button.text = filter_name
	button.toggle_mode = true
	button.button_group = _filter_button_group
	button.focus_mode = Control.FOCUS_ALL # Enable controller focus
	button.custom_minimum_size = Vector2(120, 36)
	
	# Style the button
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = UI.ACH_FILTER_BG
	normal_style.set_border_width_all(2)
	normal_style.border_color = color.darkened(0.3)
	normal_style.set_corner_radius_all(4)
	normal_style.set_content_margin_all(8)
	
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = UI.ACH_FILTER_HOVER_BG
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
	
	if UI.FONT_BOLD:
		button.add_theme_font_override("font", UI.FONT_BOLD)
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
	UISounds.play_select()
	_completion_filter = filter_name
	_rebuild_achievement_list()


func _on_character_pressed(code: String) -> void:
	UISounds.play_select()
	_select_filter(code)
	# Transfer focus to content area
	call_deferred("_focus_first_content_item")


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
	container.focus_mode = Control.FOCUS_ALL # Enable controller focus
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
	if UI.FONT_BOLD:
		title_label.add_theme_font_override("font", UI.FONT_BOLD)
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", UI.COLOR_UNLOCKED if is_unlocked else UI.ACCENT_PRIMARY)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_label)
	
	if is_unlocked:
		var check := Label.new()
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 28)
		check.add_theme_color_override("font_color", UI.COLOR_UNLOCKED)
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(check)
	
	# Description
	var desc_label := Label.new()
	desc_label.text = achievement.get("desc", "")
	if UI.FONT_MEDIUM:
		desc_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
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
		if UI.FONT_MEDIUM:
			progress_label.add_theme_font_override("font", UI.FONT_MEDIUM)
		progress_label.add_theme_font_size_override("font_size", 16)
		progress_label.add_theme_color_override("font_color", UI.COLOR_LOCKED)
		progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress_row.add_child(progress_label)
	else:
		var status_label := Label.new()
		status_label.text = "Unlocked"
		if UI.FONT_MEDIUM:
			status_label.add_theme_font_override("font", UI.FONT_MEDIUM)
		status_label.add_theme_font_size_override("font_size", 16)
		status_label.add_theme_color_override("font_color", UI.COLOR_UNLOCKED)
		status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(status_label)
	
	return wrapper


# Style helper functions
func _make_letterbox_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = UI.ACH_LETTERBOX_BORDER
	style.shadow_color = UI.ACH_LETTERBOX_SHADOW
	style.shadow_size = 3
	style.shadow_offset = Vector2(2, 2)
	return style


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.set_border_width_all(4)
	style.border_color = UI.ENTRY_BORDER
	style.set_corner_radius_all(12)
	style.shadow_color = UI.ACH_PANEL_SHADOW
	style.shadow_size = 6
	style.shadow_offset = Vector2(3, 3)
	return style


func _make_sidebar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.ACH_SIDEBAR_BG
	style.set_border_width_all(2)
	style.border_color = UI.ENTRY_SEPARATOR
	style.set_corner_radius_all(8)
	return style


func _make_content_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.ACH_CONTENT_BG
	style.set_border_width_all(2)
	style.border_color = UI.ENTRY_SEPARATOR
	style.set_corner_radius_all(8)
	return style


func _make_portrait_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.ACH_PORTRAIT_BG
	style.set_border_width_all(3)
	style.border_color = UI.ACH_PORTRAIT_BORDER
	style.set_corner_radius_all(8) # Rounded corners, not circle
	return style


func _make_achievement_style(unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.ENTRY_BG.lightened(0.05) if unlocked else UI.ENTRY_BG
	style.set_border_width_all(2)
	style.border_color = UI.COLOR_UNLOCKED if unlocked else UI.ENTRY_BORDER.darkened(0.3)
	style.set_corner_radius_all(8)
	return style


func _make_progress_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.PROGRESS_BG
	style.set_corner_radius_all(4)
	return style


func _make_progress_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.PROGRESS_FILL
	style.set_corner_radius_all(4)
	return style


func _apply_achievement_button_styles(button: Button, is_unlocked: bool) -> void:
	button.add_theme_stylebox_override("normal", _make_achievement_style(is_unlocked))
	button.add_theme_stylebox_override("hover", _make_achievement_hover_style(is_unlocked))
	button.add_theme_stylebox_override("pressed", _make_achievement_style(is_unlocked))
	button.add_theme_stylebox_override("focus", UI.create_button_style_focus())


func _make_achievement_hover_style(is_unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Brighter background on hover
	if is_unlocked:
		style.bg_color = UI.ACH_ENTRY_UNLOCKED_HOVER_BG
	else:
		style.bg_color = UI.ACH_ENTRY_LOCKED_HOVER_BG
	style.set_border_width_all(2)
	style.border_color = UI.ENTRY_BORDER if is_unlocked else UI.ACH_ENTRY_LOCKED_HOVER_BORDER
	style.set_corner_radius_all(8)
	return style

func _focus_first_content_item() -> void:
	# Wait for UI updates to propagate
	if is_inside_tree():
		await get_tree().process_frame
		await get_tree().process_frame
	
	# Try filter buttons first (they're always visible in content area)
	if _filter_buttons.has("ALL"):
		_filter_buttons["ALL"].grab_focus()
		_focus_in_content = true
		return
	
	# Fallback: try achievement list
	if _achievement_list and _achievement_list.get_child_count() > 0:
		for child in _achievement_list.get_children():
			if child is Button and child.focus_mode != Control.FOCUS_NONE:
				child.grab_focus()
				_focus_in_content = true
				return


func _grab_initial_focus() -> void:
	# Focus first character in sidebar (categories)
	if not _character_entries.is_empty():
		var first_entry := _character_entries[0]
		var button: Button = first_entry.get("button")
		if button:
			button.grab_focus()
			return
	
	# Fallback to filter buttons
	if _filter_buttons.has("ALL"):
		_filter_buttons["ALL"].grab_focus()
