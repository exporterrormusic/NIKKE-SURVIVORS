extends Node
class_name ShopCharacterList
## Left sidebar character list for ShopMenu.
## Builds and manages character portrait buttons with selection and core count display.
##
## Usage: var list = ShopCharacterList.new()
##        list.setup(character_list_vbox, button_group, registry)
##        list.character_selected.connect(_on_character_selected)
##        list.build(unlocked_chars, cores_spent)

const UI := preload("res://scripts/ui/UITheme.gd")
const GENERAL_FILTER := "GENERAL"

signal character_selected(code: String)

var _character_list: VBoxContainer
var _button_group: ButtonGroup
var _character_entries: Array[Dictionary] = []
var _registry: CharacterRegistry


func setup(character_list: VBoxContainer, button_group: ButtonGroup, registry: CharacterRegistry) -> void:
	_character_list = character_list
	_button_group = button_group
	_registry = registry


func build(unlocked_characters: Array[String], cores_spent: Dictionary) -> void:
	if not _character_list:
		return
	
	for child in _character_list.get_children():
		child.queue_free()
	_character_entries.clear()
	
	# Add "General" category first
	var general_entry := _create_entry(GENERAL_FILTER, "General", null, true)
	_character_entries.append(general_entry)
	
	# Add all characters from registry
	var char_ids := _registry.get_all_character_ids()
	var char_names := _registry.get_all_character_names()
	var portrait_paths := _registry.get_all_portrait_paths()
	
	for i in range(char_ids.size()):
		var char_name: String = char_names[i] if i < char_names.size() else ""
		var char_id: String = char_ids[i]
		var is_unlocked: bool = char_id in unlocked_characters
		var portrait: Texture2D = null
		if i < portrait_paths.size() and ResourceLoader.exists(portrait_paths[i]):
			portrait = load(portrait_paths[i])
		var entry := _create_entry(char_id, char_name, portrait, is_unlocked)
		_character_entries.append(entry)
	
	update_counts(cores_spent)


func update_selection(filter_code: String) -> void:
	for entry in _character_entries:
		var button: Button = entry.get("button")
		if button:
			button.button_pressed = (entry.get("code") == filter_code)


func update_counts(cores_spent: Dictionary) -> void:
	for entry in _character_entries:
		var code: String = entry.get("code", "")
		var count_label: Label = entry.get("count_label")
		if count_label:
			var spent: int = cores_spent.get(code, 0)
			count_label.text = str(spent)


func _create_entry(code: String, _display_name: String, portrait: Texture2D, is_unlocked: bool) -> Dictionary:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _button_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 165)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_styles(button, is_unlocked)
	
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
	
	button.pressed.connect(_on_entry_pressed.bind(code))
	_character_list.add_child(button)
	
	return {
		"code": code,
		"button": button,
		"count_label": count_label,
		"is_unlocked": is_unlocked
	}


func _apply_button_styles(button: Button, is_unlocked: bool) -> void:
	var base_color := UI.CHAR_NORMAL if is_unlocked else UI.CHAR_LOCKED
	button.add_theme_stylebox_override("normal", _make_char_button_style(base_color))
	button.add_theme_stylebox_override("hover", _make_char_button_style(UI.CHAR_HOVER))
	button.add_theme_stylebox_override("pressed", _make_char_button_style(UI.CHAR_SELECTED))
	button.add_theme_stylebox_override("focus", _make_char_button_style(UI.CHAR_HOVER))


static func _make_char_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(2)
	style.border_color = UI.ENTRY_SEPARATOR
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style


func _on_entry_pressed(code: String) -> void:
	character_selected.emit(code)


static func _make_portrait_style(is_unlocked: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.SHOP_PANEL_ACTIVE_BG
	style.set_border_width_all(3)
	if is_unlocked:
		style.border_color = UI.SHOP_PANEL_ACTIVE_BORDER_SELECTED
	else:
		style.border_color = UI.SHOP_PANEL_ACTIVE_BORDER
	style.set_corner_radius_all(8)
	return style


# === GENERAL UPGRADE ICON - Animated star burst ===

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
			var angle: float = _time * 0.8 + (TAU / num_rays) * i
			var ray_len: float = base_radius * (0.6 + 0.4 * (sin(_time * 1.2 + i * 1.5) * 0.5 + 0.5))
			var alpha: float = 0.3 + 0.3 * (sin(_time * 0.9 + i * 0.7) * 0.5 + 0.5)
			
			var from := center + Vector2(cos(angle), sin(angle)) * base_radius * 0.3
			var to := center + Vector2(cos(angle), sin(angle)) * ray_len
			
			draw_line(from, to, Color(UI.COLOR_CORE.r, UI.COLOR_CORE.g, UI.COLOR_CORE.b, alpha), 3.0, true)
		
		# Center pulsing circle
		var pulse: float = 0.8 + 0.2 * (sin(_time * 1.5) * 0.5 + 0.5)
		draw_circle(center, base_radius * 0.5 * pulse, Color(UI.COLOR_CORE.r, UI.COLOR_CORE.g, UI.COLOR_CORE.b, 0.5))
		
		# Inner bright core
		draw_circle(center, base_radius * 0.25, UI.COLOR_CORE)
