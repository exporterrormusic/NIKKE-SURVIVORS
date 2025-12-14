extends Control
class_name MainMenu
## Main menu screen with navigation options.
## Emits signals for menu transitions and handles keyboard navigation.

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

signal play_selected
signal achievements_selected
signal settings_selected

signal leaderboards_selected
signal shop_selected

const MENU_OPTIONS: Array[Dictionary] = [
	{"id": "LEADERBOARDS", "icon": "leaderboards", "label": "LEADERBOARDS"},
	{"id": "ACHIEVEMENTS", "icon": "achievements", "label": "ACHIEVEMENTS"},
	{"id": "SHOP", "icon": "shop", "label": "SHOP"},
	{"id": "PLAY", "icon": "play", "label": "PLAY", "is_play": true},
	{"id": "THE OUTPOST", "icon": "outpost", "label": "THE OUTPOST"},
	{"id": "SETTINGS", "icon": "settings", "label": "SETTINGS"},
	{"id": "QUIT", "icon": "quit", "label": "QUIT", "accent": UI.COLOR_DANGER}
]

const TITLE_TEXT := "KINGDOM CLEANUP"
const SUBTITLE_TEXT := "A NIKKE FAN GAME"
const VERSION_TEXT := "v0.1B"

@onready var _button_row: HBoxContainer = get_node_or_null("%ButtonRow")
@onready var _title_label: Label = get_node_or_null("%TitleLabel")
@onready var _subtitle_label: Label = get_node_or_null("%SubtitleLabel")
@onready var _version_label: Label = get_node_or_null("%VersionLabel")
@onready var _coming_soon_dialog: AcceptDialog = get_node_or_null("%ComingSoonDialog")

var _buttons: Array[Button] = []
var _selected_index: int = 3  # Default to PLAY (center button)

func _ready() -> void:
	_setup_title()
	_setup_buttons()
	_connect_signals()
	_update_selection()
	
	# If we are the root scene (loaded via change_scene), register with MenuManager
	# to ensure signals are connected and navigation works
	if MenuManager and get_tree().current_scene == self:
		call_deferred("_register_with_manager")

func _register_with_manager() -> void:
	MenuManager.register_root_main_menu(self)


func _setup_title() -> void:
	if _title_label:
		_title_label.text = TITLE_TEXT
	if _subtitle_label:
		_subtitle_label.text = SUBTITLE_TEXT
	if _version_label:
		pass  # Use text from scene file directly


func _setup_buttons() -> void:
	_buttons.clear()
	print("[MainMenu] Setting up buttons, looking in: ", _button_row)
	
	# Find existing buttons in the row
	for option in MENU_OPTIONS:
		var button_name: String = option["id"]
		var button: Button = _button_row.get_node_or_null(button_name) as Button
		if button:
			print("[MainMenu] Found button: ", button_name)
			_buttons.append(button)
			
			# Connect mouse signals
			if not button.pressed.is_connected(_on_button_pressed.bind(option["id"])):
				button.pressed.connect(_on_button_pressed.bind(option["id"]))
				print("[MainMenu] Connected pressed signal for: ", button_name)
			if not button.mouse_entered.is_connected(_on_button_hovered.bind(_buttons.size() - 1)):
				button.mouse_entered.connect(_on_button_hovered.bind(_buttons.size() - 1))
		else:
			print("[MainMenu] Button NOT found: ", button_name)
	
	print("[MainMenu] Total buttons found: ", _buttons.size())


func _connect_signals() -> void:
	# Any additional signal connections
	pass


func _on_button_pressed(option_id: String) -> void:
	print("[MainMenu] Button pressed: ", option_id)
	# Play appropriate sound
	match option_id:
		"PLAY":
			UISounds.play_select()
		"QUIT":
			UISounds.play_back()
		_:
			UISounds.play_select()
	
	match option_id:
		"PLAY":
			print("[MainMenu] Emitting play_selected")
			play_selected.emit()
		"ACHIEVEMENTS":
			print("[MainMenu] Emitting achievements_selected")
			achievements_selected.emit()
		"SETTINGS":
			print("[MainMenu] Emitting settings_selected")
			settings_selected.emit()
		"QUIT":
			print("[MainMenu] Showing quit confirmation")
			_show_quit_confirmation()
		"LEADERBOARDS":
			print("[MainMenu] Emitting leaderboards_selected")
			leaderboards_selected.emit()
		"SHOP":
			print("[MainMenu] Emitting shop_selected")
			shop_selected.emit()
		"THE OUTPOST":
			print("[MainMenu] Showing Outpost coming soon popup")
			_show_outpost_coming_soon()
		_:
			print("[MainMenu] Unknown option, showing coming soon")
			_show_coming_soon()


func _on_button_hovered(index: int) -> void:
	_selected_index = index
	_update_selection()


func _update_selection() -> void:
	for i in range(_buttons.size()):
		var button := _buttons[i]
		if button.has_method("set_selected"):
			button.set_selected(i == _selected_index)


var _quit_dialog: Control = null
var _outpost_dialog: Control = null

func _unhandled_input(event: InputEvent) -> void:
	# If outpost dialog is open, handle its input first
	if _outpost_dialog and _outpost_dialog.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			_hide_outpost_dialog()
			get_viewport().set_input_as_handled()
		return
	
	# If quit dialog is open, handle its input first
	if _quit_dialog and _quit_dialog.visible:
		if event.is_action_pressed("ui_cancel"):
			_hide_quit_dialog()
			get_viewport().set_input_as_handled()
		return
	
	if event.is_action_pressed("ui_cancel"):
		# On main menu, Escape shows quit confirmation
		_show_quit_confirmation()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_move_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_current()
		get_viewport().set_input_as_handled()


func _show_quit_confirmation() -> void:
	UISounds.play_back()
	if _quit_dialog:
		_quit_dialog.visible = true
		return
	
	# Create overlay
	_quit_dialog = Control.new()
	_quit_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_quit_dialog)
	
	# Dark background
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = UI.BG_OVERLAY
	overlay.gui_input.connect(func(event): 
		if event is InputEventMouseButton and event.pressed:
			_hide_quit_dialog()
	)
	_quit_dialog.add_child(overlay)
	
	# Panel
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(400, 200)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -100
	panel.offset_bottom = 100
	
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI.BG_MID
	panel_style.border_color = UI.ACCENT_PRIMARY
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	_quit_dialog.add_child(panel)
	
	# VBox for content
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 32
	vbox.offset_right = -32
	vbox.offset_top = 24
	vbox.offset_bottom = -24
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "QUIT GAME?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	vbox.add_child(title)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Button container
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)
	
	# Cancel button
	var cancel_btn := _create_dialog_button("CANCEL", false)
	cancel_btn.pressed.connect(_hide_quit_dialog)
	btn_row.add_child(cancel_btn)
	
	# Quit button
	var quit_btn := _create_dialog_button("QUIT", true)
	quit_btn.pressed.connect(func(): get_tree().quit())
	btn_row.add_child(quit_btn)


func _create_dialog_button(text: String, is_danger: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 45)
	
	var normal := StyleBoxFlat.new()
	if is_danger:
		normal.bg_color = UI.BTN_BACK_BG
		normal.border_color = UI.COLOR_DANGER
	else:
		normal.bg_color = UI.BG_MID
		normal.border_color = UI.BORDER_DEFAULT
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	if is_danger:
		hover.bg_color = UI.BTN_BACK_HOVER_BG
		hover.border_color = UI.COLOR_DANGER
	else:
		hover.bg_color = UI.BG_LIGHT
		hover.border_color = UI.BORDER_HIGHLIGHT
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	
	return btn


func _hide_quit_dialog() -> void:
	UISounds.play_back()
	if _quit_dialog:
		_quit_dialog.visible = false


func _move_selection(direction: int) -> void:
	if _buttons.is_empty():
		return
	_selected_index = wrapi(_selected_index + direction, 0, _buttons.size())
	_update_selection()


func _activate_current() -> void:
	if _selected_index < 0 or _selected_index >= MENU_OPTIONS.size():
		return
	var option_id: String = MENU_OPTIONS[_selected_index]["id"]
	_on_button_pressed(option_id)


func _show_coming_soon() -> void:
	if _coming_soon_dialog:
		_coming_soon_dialog.popup_centered()


func _show_outpost_coming_soon() -> void:
	if _outpost_dialog:
		_outpost_dialog.visible = true
		return
	
	# Create overlay
	_outpost_dialog = Control.new()
	_outpost_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outpost_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_outpost_dialog)
	
	# Dark background
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = UI.BG_OVERLAY
	overlay.gui_input.connect(func(event): 
		if event is InputEventMouseButton and event.pressed:
			_hide_outpost_dialog()
	)
	_outpost_dialog.add_child(overlay)
	
	# Panel
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(450, 220)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -225
	panel.offset_right = 225
	panel.offset_top = -110
	panel.offset_bottom = 110
	
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI.BG_MID
	panel_style.border_color = UI.ACCENT_PRIMARY
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	_outpost_dialog.add_child(panel)
	
	# VBox for content
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 32
	vbox.offset_right = -32
	vbox.offset_top = 24
	vbox.offset_bottom = -24
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "COMING SOON!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)
	vbox.add_child(title)
	
	# Description
	var desc := Label.new()
	desc.text = "The Outpost is still under construction."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	vbox.add_child(desc)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Close button
	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)
	
	var close_btn := _create_dialog_button("CLOSE", false)
	close_btn.pressed.connect(_hide_outpost_dialog)
	btn_container.add_child(close_btn)


func _hide_outpost_dialog() -> void:
	UISounds.play_back()
	if _outpost_dialog:
		_outpost_dialog.visible = false


# --- Debug Functions ---

func _debug_unlock_all() -> void:
	## Debug: Unlock all stages (F3)
	if not GameState:
		print("[DEBUG] GameState not available")
		return
	
	# Unlock all stages
	for stage in StageRegistry.STAGES:
		var stage_id: String = stage["id"]
		if stage_id not in GameState.stages_cleared:
			GameState.stages_cleared.append(stage_id)
	
	GameState._save_stage_progress()
	
	# Show feedback
	print("[DEBUG] All stages unlocked!")
	_show_debug_notification("DEBUG: All stages unlocked!")


func _show_debug_notification(text: String) -> void:
	# Create a temporary notification label
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", UI.COLOR_SUCCESS)
	label.add_theme_color_override("font_shadow_color", UI.SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position.y = 120
	add_child(label)
	
	# Fade out and remove
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(1.0)
	tween.tween_callback(label.queue_free)
