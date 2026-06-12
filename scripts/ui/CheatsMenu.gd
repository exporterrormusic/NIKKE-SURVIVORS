extends Control

## Cheats Menu - Accessible from Pause Menu
## Toggles cheat states in CheatManager

const UI = preload("res://scripts/ui/UITheme.gd")
const CheatManagerScript = preload("res://scripts/systems/CheatManager.gd")

signal close_requested

var _input_field: LineEdit
var _list_container: VBoxContainer
var _submit_btn: Button

func _ready() -> void:
	# Set root size so CenterContainer centers us correctly
	custom_minimum_size = Vector2(400, 520)
	
	# Main Panel
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Use standard panel style from UITheme
	panel.add_theme_stylebox_override("panel", UI.create_panel_style(UI.BG_MID, UI.BORDER_DEFAULT, UI.BORDER_NORMAL, UI.CORNER_LARGE, true))
	add_child(panel)
	
	# Main Layout with Margins
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	
	var main_layout = VBoxContainer.new()
	main_layout.add_theme_constant_override("separation", 16)
	margin.add_child(main_layout)
	
	# Title
	var title = Label.new()
	title.text = "CHEATS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UI.FONT_TITLE)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	main_layout.add_child(title)
	
	# Divider
	var divider = ColorRect.new()
	divider.custom_minimum_size.y = 2
	divider.color = UI.DIVIDER_SUBTLE
	main_layout.add_child(divider)
	
	# Input Row
	var input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	main_layout.add_child(input_row)
	
	_input_field = LineEdit.new()
	_input_field.placeholder_text = "Enter code..."
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.custom_minimum_size.y = 45
	_input_field.add_theme_font_override("font", UI.FONT_MEDIUM)
	_input_field.add_theme_color_override("font_placeholder_color", UI.TEXT_MUTED)
	_input_field.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	
	# Style input field
	var style_input = UI.create_panel_style(UI.BG_DEEP, UI.BORDER_DEFAULT, UI.BORDER_THIN, UI.CORNER_SMALL, false)
	_input_field.add_theme_stylebox_override("normal", style_input)
	_input_field.add_theme_stylebox_override("focus", UI.create_panel_style(UI.BG_DEEP, UI.ACCENT_PRIMARY, UI.BORDER_THICK, UI.CORNER_SMALL, false))
	
	_input_field.text_submitted.connect(_on_submit)
	input_row.add_child(_input_field)
	
	# Create OK button with Success style (true for is_success)
	_submit_btn = _create_styled_button("OK", func(): _on_submit(_input_field.text), false, false, true)
	_submit_btn.custom_minimum_size.x = 60
	input_row.add_child(_submit_btn)
	
	# List Header
	var list_title_box = HBoxContainer.new()
	list_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main_layout.add_child(list_title_box)
	
	var list_title = Label.new()
	list_title.text = "ACTIVE CHEATS"
	list_title.uppercase = true
	list_title.add_theme_font_override("font", UI.FONT_BOLD)
	list_title.add_theme_font_size_override("font_size", 16)
	list_title.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	list_title_box.add_child(list_title)
	
	# Cheat List (Scrollable)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Scroll bg
	var scroll_bg = UI.create_panel_style(UI.BG_DEEP, UI.TRANSPARENT, 0, UI.CORNER_SMALL, false)
	scroll_bg.content_margin_left = 4
	scroll_bg.content_margin_right = 4
	scroll_bg.content_margin_top = 4
	scroll_bg.content_margin_bottom = 4
	scroll.add_theme_stylebox_override("panel", scroll_bg)
	
	main_layout.add_child(scroll)
	
	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 2) # Tight spacing like a list
	scroll.add_child(_list_container)
	
	_refresh_list()
	
	var spacer_bottom = Control.new()
	spacer_bottom.custom_minimum_size.y = 8
	main_layout.add_child(spacer_bottom)
	
	# Close Button
	var close_btn = _create_styled_button("CLOSE", _on_close) 
	# Use standard Back button style
	var style_back = StyleBoxFlat.new()
	style_back.bg_color = UI.BTN_BACK_BG
	style_back.border_color = UI.BTN_BACK_BORDER
	style_back.set_border_width_all(UI.BORDER_THIN)
	style_back.set_corner_radius_all(UI.CORNER_MEDIUM)
	
	var style_back_hover = style_back.duplicate()
	style_back_hover.bg_color = UI.BTN_BACK_HOVER_BG
	style_back_hover.border_color = UI.BTN_BACK_HOVER_BORDER
	
	close_btn.add_theme_stylebox_override("normal", style_back)
	close_btn.add_theme_stylebox_override("hover", style_back_hover)
	close_btn.add_theme_stylebox_override("pressed", style_back) 
	
	close_btn.custom_minimum_size.y = 45
	main_layout.add_child(close_btn)
	
	# Focus input immediately
	_input_field.grab_focus()

func _create_styled_button(text: String, callback: Callable, is_primary: bool = false, is_danger: bool = false, is_success: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_override("font", UI.FONT_BOLD)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	
	if is_danger:
		normal = UI.create_danger_button_style()
		hover = normal.duplicate()
		hover.bg_color = UI.BTN_DANGER_HOVER_BG
		pressed = normal.duplicate()
		pressed.bg_color = UI.BTN_DANGER_PRESSED_BG
	elif is_success:
		# Green success style
		normal = UI.create_panel_style(UI.BTN_SUCCESS_BG, UI.BTN_SUCCESS_BORDER, UI.BORDER_NORMAL, UI.CORNER_MEDIUM, true)
		hover = UI.create_panel_style(UI.BTN_SUCCESS_HOVER_BG, UI.BTN_SUCCESS_HOVER_BORDER, UI.BORDER_THICK, UI.CORNER_MEDIUM, true)
		hover.shadow_color = UI.ACCENT_PRIMARY_GLOW
		hover.shadow_size = 6
		pressed = UI.create_panel_style(UI.BTN_SUCCESS_BG.darkened(0.1), UI.BTN_SUCCESS_BORDER, UI.BORDER_NORMAL, UI.CORNER_MEDIUM, false)
		btn.add_theme_color_override("font_color", UI.BTN_SUCCESS_TEXT)
	elif is_primary:
		normal = UI.create_primary_button_style_normal()
		hover = UI.create_primary_button_style_hover()
		pressed = normal.duplicate()
	else:
		normal = UI.create_button_style_normal()
		hover = UI.create_button_style_hover()
		pressed = UI.create_button_style_pressed()
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	
	btn.pressed.connect(callback)
	return btn

func _refresh_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()
		
	var unlocked = CheatManagerScript.get_unlocked_cheats()
	if unlocked.is_empty():
		var lbl = Label.new()
		lbl.text = "No cheats unlocked yet."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", UI.TEXT_MUTED)
		lbl.add_theme_font_override("font", UI.FONT_MEDIUM)
		_list_container.add_child(lbl)
		return

	for cheat_id in unlocked:
		var is_active = unlocked[cheat_id]
		var cheat_name = CheatManagerScript.get_cheat_name(cheat_id)
		
		# Row container
		var row = PanelContainer.new()
		# Style row
		var row_style = StyleBoxFlat.new()
		row_style.bg_color = UI.ENTRY_BG
		row_style.border_color = UI.ENTRY_BORDER
		row_style.set_border_width_all(1)
		row_style.set_corner_radius_all(0)
		if is_active:
			row_style.bg_color = Color(0.15, 0.25, 0.15, 0.9) # Green tint
			row_style.border_color = UI.COLOR_UNLOCKED
		
		row.add_theme_stylebox_override("panel", row_style)
		_list_container.add_child(row)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		# Add margins inside row
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		margin.add_child(hbox)
		row.add_child(margin)
		
		var name_lbl = Label.new()
		name_lbl.text = cheat_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_override("font", UI.FONT_BOLD)
		if is_active:
			name_lbl.add_theme_color_override("font_color", UI.COLOR_UNLOCKED)
		else:
			name_lbl.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
		hbox.add_child(name_lbl)
		
		# Toggle Switch (Visual button)
		var toggle = Button.new()
		toggle.custom_minimum_size = Vector2(40, 24)
		toggle.toggle_mode = true
		toggle.button_pressed = is_active
		
		# Use explicit styles for the switch
		_update_toggle_visuals(toggle)
		
		toggle.pressed.connect(func(): 
			CheatManagerScript.set_cheat_active(cheat_id, not is_active)
			# Refresh list to update row color too
			call_deferred("_refresh_list")
		)
		hbox.add_child(toggle)

func _update_toggle_visuals(btn: Button) -> void:
	var style = StyleBoxFlat.new()
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	
	if btn.button_pressed:
		btn.text = "ON"
		style.bg_color = UI.COLOR_UNLOCKED
		style.border_color = UI.COLOR_UNLOCKED.lightened(0.2)
		btn.add_theme_color_override("font_color", Color.BLACK)
	else:
		btn.text = "OFF"
		style.bg_color = UI.BG_DEEP
		style.border_color = UI.TEXT_MUTED
		btn.add_theme_color_override("font_color", UI.TEXT_MUTED)
			
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_font_override("font", UI.FONT_BOLD)
	btn.add_theme_font_size_override("font_size", 12)

func _on_submit(text: String) -> void:
	if text.strip_edges().is_empty():
		return
		
	var success = CheatManagerScript.try_activate_cheat(text)
	if success:
		_input_field.text = ""
		_refresh_list()
		
		# Success feedback
		var feedback = Label.new()
		feedback.text = "CHEAT ACTIVATED!"
		feedback.add_theme_color_override("font_color", UI.COLOR_UNLOCKED)
		feedback.add_theme_font_override("font", UI.FONT_BOLD)
		feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Add to list temporarily
		_list_container.add_child(feedback)
		_list_container.move_child(feedback, 0)
		
		var tween = create_tween()
		tween.tween_property(feedback, "modulate:a", 0.0, 2.0)
		tween.tween_callback(feedback.queue_free)
	else:
		# Shake animation for fail?
		var tween = create_tween()
		var original_pos = _input_field.position.x
		tween.tween_property(_input_field, "position:x", original_pos + 10, 0.05)
		tween.tween_property(_input_field, "position:x", original_pos - 10, 0.05)
		tween.tween_property(_input_field, "position:x", original_pos, 0.05)
		_input_field.grab_focus() # Keep focus

func _on_close() -> void:
	close_requested.emit()
	queue_free()
