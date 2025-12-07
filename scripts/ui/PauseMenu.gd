extends CanvasLayer
class_name PauseMenu
## Pause/Game Over menu with consistent UI styling.
## Shows different options based on whether player is alive or dead.

signal restart_requested
signal resume_requested
signal settings_requested
signal character_select_requested
signal quit_requested

# Menu modes
enum MenuMode { PAUSE, DEFEAT, VICTORY }

const UIThemeScript = preload("res://scripts/ui/UITheme.gd")
const UISounds = preload("res://scripts/ui/UISoundManager.gd")

# Menu state
var _menu_mode: int = MenuMode.PAUSE
var _container: Control = null
var _panel: Panel = null
var _button_container: VBoxContainer = null
var _title_label: Label = null
var _buttons: Dictionary = {}

func _ready() -> void:
	layer = 100
	visible = false
	# Process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func _build_ui() -> void:
	# Full-screen darkened overlay
	_container = Control.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_container)
	
	# Dark overlay background
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	_container.add_child(overlay)
	
	# Center panel
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(400, 450)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -200
	_panel.offset_right = 200
	_panel.offset_top = -225
	_panel.offset_bottom = 225
	_apply_panel_style(_panel)
	_container.add_child(_panel)
	
	# VBox for content
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 32
	vbox.offset_right = -32
	vbox.offset_top = 32
	vbox.offset_bottom = -32
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)
	
	# Title
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(_title_label)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	vbox.add_child(spacer)
	
	# Button container
	_button_container = VBoxContainer.new()
	_button_container.add_theme_constant_override("separation", 12)
	_button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_button_container)

func _apply_panel_style(panel: Panel) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.98)
	style.border_color = Color(0.95, 0.95, 0.98, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)

func _create_button(text: String, callback: Callable, is_primary: bool = false, is_danger: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 50)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Normal style
	var normal := StyleBoxFlat.new()
	if is_danger:
		normal.bg_color = Color(0.6, 0.15, 0.15, 0.95)
		normal.border_color = Color(0.9, 0.3, 0.3, 0.9)
	elif is_primary:
		normal.bg_color = Color(0.15, 0.5, 0.15, 0.95)
		normal.border_color = Color(0.3, 0.8, 0.3, 0.9)
	else:
		normal.bg_color = Color(0.12, 0.15, 0.2, 0.95)
		normal.border_color = Color(0.5, 0.55, 0.65, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	# Hover style
	var hover := StyleBoxFlat.new()
	if is_danger:
		hover.bg_color = Color(0.75, 0.2, 0.2, 1.0)
		hover.border_color = Color(1.0, 0.4, 0.4)
	elif is_primary:
		hover.bg_color = Color(0.2, 0.65, 0.2, 1.0)
		hover.border_color = Color(0.4, 1.0, 0.4)
	else:
		hover.bg_color = Color(0.18, 0.22, 0.28, 1.0)
		hover.border_color = Color(0.7, 0.75, 0.85, 1.0)
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	# Pressed style
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = normal.bg_color.darkened(0.2)
	pressed.border_color = normal.border_color
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	
	btn.pressed.connect(callback)
	return btn

func _rebuild_buttons() -> void:
	# Clear existing buttons
	for child in _button_container.get_children():
		child.queue_free()
	_buttons.clear()
	
	if _menu_mode == MenuMode.VICTORY:
		# Victory menu: Show reward + RESTART, CHARACTER SELECTION, SETTINGS, QUIT
		_title_label.text = "VICTORY!"
		_title_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		
		# Reward label
		var reward_label := Label.new()
		reward_label.text = "+1 Pristine Rapture Core"
		reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward_label.add_theme_font_size_override("font_size", 20)
		reward_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		_button_container.add_child(reward_label)
		
		# Spacer
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 10
		_button_container.add_child(spacer)
		
		var restart_btn := _create_button("PLAY AGAIN", _on_restart_pressed, true)
		_button_container.add_child(restart_btn)
		_buttons["restart"] = restart_btn
		
		var char_select_btn := _create_button("CHARACTER SELECTION", _on_character_select_pressed)
		_button_container.add_child(char_select_btn)
		_buttons["character_select"] = char_select_btn
		
		var settings_btn := _create_button("SETTINGS", _on_settings_pressed)
		_button_container.add_child(settings_btn)
		_buttons["settings"] = settings_btn
		
		var quit_btn := _create_button("QUIT", _on_quit_pressed, false, true)
		_button_container.add_child(quit_btn)
		_buttons["quit"] = quit_btn
	elif _menu_mode == MenuMode.DEFEAT:
		# Defeat menu: RESTART, CHARACTER SELECTION, SETTINGS, QUIT
		_title_label.text = "DEFEATED"
		_title_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		
		var restart_btn := _create_button("RESTART", _on_restart_pressed, true)
		_button_container.add_child(restart_btn)
		_buttons["restart"] = restart_btn
		
		var char_select_btn := _create_button("CHARACTER SELECTION", _on_character_select_pressed)
		_button_container.add_child(char_select_btn)
		_buttons["character_select"] = char_select_btn
		
		var settings_btn := _create_button("SETTINGS", _on_settings_pressed)
		_button_container.add_child(settings_btn)
		_buttons["settings"] = settings_btn
		
		var quit_btn := _create_button("QUIT", _on_quit_pressed, false, true)
		_button_container.add_child(quit_btn)
		_buttons["quit"] = quit_btn
	else:
		# Pause menu: RESUME, RESTART, CHARACTER SELECTION, SETTINGS, QUIT
		_title_label.text = "PAUSED"
		_title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		
		var resume_btn := _create_button("RESUME", _on_resume_pressed, true)
		_button_container.add_child(resume_btn)
		_buttons["resume"] = resume_btn
		
		var restart_btn := _create_button("RESTART", _on_restart_pressed)
		_button_container.add_child(restart_btn)
		_buttons["restart"] = restart_btn
		
		var char_select_btn := _create_button("CHARACTER SELECTION", _on_character_select_pressed)
		_button_container.add_child(char_select_btn)
		_buttons["character_select"] = char_select_btn
		
		var settings_btn := _create_button("SETTINGS", _on_settings_pressed)
		_button_container.add_child(settings_btn)
		_buttons["settings"] = settings_btn
		
		var quit_btn := _create_button("QUIT", _on_quit_pressed, false, true)
		_button_container.add_child(quit_btn)
		_buttons["quit"] = quit_btn

func show_pause() -> void:
	_menu_mode = MenuMode.PAUSE
	_rebuild_buttons()
	visible = true
	get_tree().paused = true

func show_defeat() -> void:
	_menu_mode = MenuMode.DEFEAT
	_rebuild_buttons()
	visible = true
	get_tree().paused = true

func show_victory() -> void:
	_menu_mode = MenuMode.VICTORY
	_rebuild_buttons()
	visible = true
	get_tree().paused = true

func hide_menu() -> void:
	visible = false
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	
	# Only allow ESC to close if it's a pause menu (not defeat/victory)
	if event.is_action_pressed("ui_cancel") and _menu_mode == MenuMode.PAUSE:
		UISounds.play_back()
		hide_menu()
		get_viewport().set_input_as_handled()

func _on_restart_pressed() -> void:
	UISounds.play_confirm()
	hide_menu()
	restart_requested.emit()

func _on_resume_pressed() -> void:
	UISounds.play_back()
	hide_menu()
	resume_requested.emit()

func _on_settings_pressed() -> void:
	# No sound for pause menu options - they have their own transitions
	settings_requested.emit()

func _on_character_select_pressed() -> void:
	# No sound for pause menu options - they have their own transitions
	hide_menu()
	character_select_requested.emit()

func _on_quit_pressed() -> void:
	UISounds.play_back()
	hide_menu()
	quit_requested.emit()
