extends Control
class_name SettingsMenu
## Settings menu with Audio, Video, and Controls tabs.
## Provides volume sliders, resolution options, fullscreen toggle, and key rebinding.

signal back_requested
signal master_volume_changed(value: float)
signal music_volume_changed(value: float)
signal sfx_volume_changed(value: float)
signal resolution_changed(size: Vector2i)
signal fullscreen_toggled(enabled: bool)
signal key_binding_changed(action: String, keycode: int)

const UI := preload("res://scripts/ui/UITheme.gd")

const TAB_AUDIO := "audio"
const TAB_VIDEO := "video"
const TAB_CONTROLS := "controls"
const TAB_ORDER := [TAB_AUDIO, TAB_VIDEO, TAB_CONTROLS]

const DEFAULT_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

const CONTROL_ACTION_DEFINITIONS := [
	{"action": "move_up", "label": "Move Up", "node": "%MoveUpButton"},
	{"action": "move_down", "label": "Move Down", "node": "%MoveDownButton"},
	{"action": "move_left", "label": "Move Left", "node": "%MoveLeftButton"},
	{"action": "move_right", "label": "Move Right", "node": "%MoveRightButton"},
	{"action": "dash", "label": "Dash", "node": "%DashButton"},
	{"action": "burst", "label": "Burst", "node": "%BurstButton"},
	{"action": "special_attack", "label": "Special Attack", "node": "%SpecialAttackButton"},
	{"action": "ui_cancel", "label": "Pause", "node": "%PauseButton"}
]

@onready var _tabs: Dictionary = {
	TAB_AUDIO: %AudioTab,
	TAB_VIDEO: %VideoTab,
	TAB_CONTROLS: %ControlsTab
}

@onready var _panels: Dictionary = {
	TAB_AUDIO: %AudioPanel,
	TAB_VIDEO: %VideoPanel,
	TAB_CONTROLS: %ControlsPanel
}

# Audio controls
@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _sfx_value: Label = %SfxValue

# Video controls
@onready var _resolution_options: OptionButton = %ResolutionOptions
@onready var _fullscreen_options: OptionButton = %FullscreenOptions

# Control bindings
var _control_buttons: Dictionary = {}

var _available_resolutions: Array[Vector2i] = []
var _current_tab: String = TAB_AUDIO
var _capturing_action: String = ""
var _capturing_button: Button = null
var _capturing_original_text: String = ""
var _suppress_signals: bool = false

func _ready() -> void:
	# Setup tab buttons
	for tab_name in TAB_ORDER:
		var button: Button = _tabs.get(tab_name)
		if button:
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_on_tab_pressed.bind(tab_name))

	# Setup audio sliders
	if _music_slider:
		_music_slider.value_changed.connect(_on_music_slider_value_changed)
	if _sfx_slider:
		_sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)

	# Setup video options
	if _resolution_options:
		_resolution_options.item_selected.connect(_on_resolution_selected)
	if _fullscreen_options:
		_fullscreen_options.item_selected.connect(_on_fullscreen_selected)

	# Setup control buttons
	for definition in CONTROL_ACTION_DEFINITIONS:
		var button: Button = get_node_or_null(definition["node"])
		if button:
			button.focus_mode = Control.FOCUS_NONE
			var action_name: String = String(definition["action"])
			button.pressed.connect(_begin_key_capture.bind(action_name, button))
			_control_buttons[definition["action"]] = button

	_initialize_resolutions()
	_initialize_dropdowns()
	_current_tab = ""
	_switch_tab(TAB_AUDIO)
	
	# Load saved settings from SettingsManager
	_load_from_settings_manager()
	
	_refresh_key_binding_labels()
	set_process_unhandled_input(true)


func _load_from_settings_manager() -> void:
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if not settings_mgr:
		# Fallback - use default values
		_update_music_label(_music_slider.value if _music_slider else 1.0)
		_update_sfx_label(_sfx_slider.value if _sfx_slider else 1.0)
		return
	
	_suppress_signals = true
	
	# Audio
	if _music_slider:
		_music_slider.value = settings_mgr.get_music_volume()
		_update_music_label(_music_slider.value)
	if _sfx_slider:
		_sfx_slider.value = settings_mgr.get_sfx_volume()
		_update_sfx_label(_sfx_slider.value)
	
	# Video
	set_resolution(settings_mgr.get_resolution())
	set_fullscreen(settings_mgr.is_fullscreen())
	
	_suppress_signals = false


func _initialize_resolutions() -> void:
	_available_resolutions = DEFAULT_RESOLUTIONS.duplicate()
	_available_resolutions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	_refresh_resolution_options()


func _refresh_resolution_options() -> void:
	if not _resolution_options:
		return
	_resolution_options.clear()
	for resolution in _available_resolutions:
		_resolution_options.add_item("%d x %d" % [resolution.x, resolution.y])


func _initialize_dropdowns() -> void:
	if _fullscreen_options:
		_fullscreen_options.clear()
		_fullscreen_options.add_item("ON")
		_fullscreen_options.add_item("OFF")


func _on_tab_pressed(tab_name: String) -> void:
	_switch_tab(tab_name)


func _switch_tab(tab_name: String) -> void:
	if _current_tab == tab_name:
		return
	
	# Hide current panel
	if _panels.has(_current_tab):
		var panel = _panels[_current_tab]
		if panel:
			panel.visible = false
	if _tabs.has(_current_tab):
		var tab = _tabs[_current_tab]
		if tab:
			tab.button_pressed = false
	
	_current_tab = tab_name
	
	# Show new panel
	if _panels.has(_current_tab):
		var panel = _panels[_current_tab]
		if panel:
			panel.visible = true
	if _tabs.has(_current_tab):
		var tab = _tabs[_current_tab]
		if tab:
			tab.button_pressed = true
	
	_update_tab_colors()


func _update_tab_colors() -> void:
	# Create styles for active/inactive tabs
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = UI.SETTINGS_TAB_ACTIVE_BG
	active_style.set_border_width_all(0)
	active_style.border_width_bottom = 4
	active_style.border_color = UI.SETTINGS_TAB_ACTIVE_BORDER
	active_style.corner_radius_top_left = 4
	active_style.corner_radius_top_right = 4
	
	var inactive_style := StyleBoxFlat.new()
	inactive_style.bg_color = UI.SETTINGS_TAB_INACTIVE_BG
	inactive_style.set_border_width_all(0)
	inactive_style.border_width_bottom = 2
	inactive_style.border_color = UI.SETTINGS_TAB_INACTIVE_BORDER
	inactive_style.corner_radius_top_left = 4
	inactive_style.corner_radius_top_right = 4
	
	# Colors
	var inactive_color := UI.TEXT_PRIMARY
	var inactive_hover := UI.ACCENT_HOVER
	var active_color := UI.TEXT_DARK
	var active_hover := UI.SETTINGS_TAB_ACTIVE_HOVER
	
	for tab_name in TAB_ORDER:
		if not _tabs.has(tab_name):
			continue
		var button: Button = _tabs[tab_name]
		if not button:
			continue
		var active: bool = _current_tab == tab_name
		if active:
			button.add_theme_stylebox_override("normal", active_style)
			button.add_theme_stylebox_override("hover", active_style)
			button.add_theme_stylebox_override("pressed", active_style)
			button.add_theme_stylebox_override("focus", active_style)
			button.add_theme_color_override("font_color", active_color)
			button.add_theme_color_override("font_pressed_color", active_color)
			button.add_theme_color_override("font_hover_color", active_hover)
			button.add_theme_color_override("font_hover_pressed_color", active_hover)
		else:
			button.add_theme_stylebox_override("normal", inactive_style)
			button.add_theme_stylebox_override("hover", inactive_style)
			button.add_theme_stylebox_override("pressed", active_style)
			button.add_theme_stylebox_override("focus", inactive_style)
			button.add_theme_color_override("font_color", inactive_color)
			button.add_theme_color_override("font_hover_color", inactive_hover)
			button.add_theme_color_override("font_pressed_color", active_color)
			button.add_theme_color_override("font_hover_pressed_color", active_color)


func _on_music_slider_value_changed(value: float) -> void:
	_update_music_label(value)
	if _suppress_signals:
		return
	emit_signal("music_volume_changed", value)
	emit_signal("master_volume_changed", value)
	# Apply and save via SettingsManager
	if Engine.has_singleton("SettingsManager") or get_node_or_null("/root/SettingsManager"):
		get_node("/root/SettingsManager").set_music_volume(value)
	else:
		_apply_bus_volume("Music", value)


func _on_sfx_slider_value_changed(value: float) -> void:
	_update_sfx_label(value)
	if _suppress_signals:
		return
	emit_signal("sfx_volume_changed", value)
	# Apply and save via SettingsManager
	if get_node_or_null("/root/SettingsManager"):
		get_node("/root/SettingsManager").set_sfx_volume(value)
	else:
		_apply_bus_volume("SFX", value)


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _available_resolutions.size():
		return
	if _suppress_signals:
		return
	var new_resolution: Vector2i = _available_resolutions[index]
	emit_signal("resolution_changed", new_resolution)
	# Apply and save via SettingsManager
	if get_node_or_null("/root/SettingsManager"):
		get_node("/root/SettingsManager").set_resolution(new_resolution)


func _on_fullscreen_selected(index: int) -> void:
	if _suppress_signals:
		return
	var enabled: bool = index == 0
	emit_signal("fullscreen_toggled", enabled)
	# Apply and save via SettingsManager
	if get_node_or_null("/root/SettingsManager"):
		get_node("/root/SettingsManager").set_fullscreen(enabled)


func _begin_key_capture(action: String, button: Button) -> void:
	if _capturing_action == action:
		return
	_cancel_key_capture()
	_capturing_action = action
	_capturing_button = button
	_capturing_original_text = button.text
	button.text = "PRESS KEY..."
	button.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.is_pressed() or key_event.is_echo():
		return
	
	var is_escape: bool = key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE
	
	# Handle key capture mode
	if _capturing_action != "":
		# If escape pressed while capturing, cancel the capture instead of binding
		if is_escape:
			_cancel_key_capture()
			get_viewport().set_input_as_handled()
			return
		_apply_key_binding(_capturing_action, key_event)
		get_viewport().set_input_as_handled()
		return
	
	# Handle escape/back to return to previous menu
	if is_escape:
		emit_signal("back_requested")
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Also catch escape in _input in case _unhandled_input doesn't receive it
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.is_pressed() or key_event.is_echo():
		return
	
	var is_escape: bool = key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE
	if is_escape and _capturing_action == "":
		emit_signal("back_requested")
		get_viewport().set_input_as_handled()


func _apply_key_binding(action: String, event: InputEventKey) -> void:
	var copy: InputEventKey = InputEventKey.new()
	copy.physical_keycode = event.physical_keycode
	copy.keycode = event.keycode if event.keycode != 0 else event.physical_keycode
	copy.shift_pressed = event.shift_pressed
	copy.ctrl_pressed = event.ctrl_pressed
	copy.alt_pressed = event.alt_pressed
	copy.meta_pressed = event.meta_pressed

	var existing: Array = InputMap.action_get_events(action)
	for ev in existing:
		InputMap.action_erase_event(action, ev)
	InputMap.action_add_event(action, copy)
	
	_update_button_for_action(action, copy.physical_keycode)
	if not _suppress_signals:
		emit_signal("key_binding_changed", action, copy.physical_keycode)
		# Save via SettingsManager
		if get_node_or_null("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_key_binding(action, copy.physical_keycode)
	_cancel_key_capture()


func _update_button_for_action(action: String, keycode: int) -> void:
	if not _control_buttons.has(action):
		return
	var button: Button = _control_buttons[action]
	var label: String = _keycode_to_string(keycode)
	button.text = label
	button.remove_theme_color_override("font_color")
	button.remove_theme_color_override("font_color_pressed")
	button.remove_theme_color_override("font_color_hover")
	button.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	button.add_theme_color_override("font_color_hover", UI.ACCENT_HOVER)
	button.add_theme_color_override("font_color_pressed", UI.TEXT_DARK)


func _cancel_key_capture() -> void:
	if _capturing_button:
		if _capturing_original_text != "":
			_capturing_button.text = _capturing_original_text
		_capturing_button.remove_theme_color_override("font_color")
	_capturing_action = ""
	_capturing_button = null
	_capturing_original_text = ""


func _update_music_label(value: float) -> void:
	if _music_value:
		_music_value.text = "%d%%" % int(round(value * 100.0))


func _update_sfx_label(value: float) -> void:
	if _sfx_value:
		_sfx_value.text = "%d%%" % int(round(value * 100.0))


func _apply_bus_volume(bus_name: String, value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	# Fall back to Master bus if the specific bus doesn't exist
	if bus_index == -1:
		bus_index = AudioServer.get_bus_index("Master")
	if bus_index == -1:
		push_warning("[SettingsMenu] No audio bus found for: " + bus_name)
		return
	var linear: float = clamp(value, 0.0, 1.0)
	var db_value: float = linear_to_db(max(linear, 0.0001))
	AudioServer.set_bus_volume_db(bus_index, db_value)
	print("[SettingsMenu] Set bus '", bus_name, "' (index ", bus_index, ") to ", linear * 100, "% (", db_value, " dB)")


func _keycode_to_string(keycode: int) -> String:
	if keycode == 0:
		return "UNBOUND"
	return OS.get_keycode_string(keycode)


# -- Public setters -----------------------------------------------------------------

func set_master_volume(value: float) -> void:
	set_music_volume(value)


func set_music_volume(value: float) -> void:
	_suppress_signals = true
	if _music_slider:
		_music_slider.value = clamp(value, _music_slider.min_value, _music_slider.max_value)
		_update_music_label(_music_slider.value)
	_suppress_signals = false


func set_sfx_volume(value: float) -> void:
	_suppress_signals = true
	if _sfx_slider:
		_sfx_slider.value = clamp(value, _sfx_slider.min_value, _sfx_slider.max_value)
		_update_sfx_label(_sfx_slider.value)
	_suppress_signals = false


func set_resolution(target: Vector2i) -> void:
	if not _available_resolutions.has(target):
		_available_resolutions.append(target)
		_available_resolutions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x or (a.x == b.x and a.y < b.y)
		)
		_refresh_resolution_options()
	var index: int = _available_resolutions.find(target)
	if index != -1 and _resolution_options:
		_suppress_signals = true
		_resolution_options.select(index)
		_suppress_signals = false


func set_fullscreen(enabled: bool) -> void:
	if _fullscreen_options:
		_suppress_signals = true
		_fullscreen_options.select(0 if enabled else 1)
		_suppress_signals = false


func set_key_bindings(bindings: Dictionary) -> void:
	_suppress_signals = true
	for definition in CONTROL_ACTION_DEFINITIONS:
		var action: String = definition["action"]
		if bindings.has(action):
			var keycode: int = int(bindings[action])
			var event: InputEventKey = InputEventKey.new()
			event.physical_keycode = keycode as Key
			event.keycode = keycode as Key
			var existing: Array = InputMap.action_get_events(action)
			for ev in existing:
				InputMap.action_erase_event(action, ev)
			InputMap.action_add_event(action, event)
			_update_button_for_action(action, keycode)
	_suppress_signals = false
	_refresh_key_binding_labels()


func clear_capture_state() -> void:
	_cancel_key_capture()


func _refresh_key_binding_labels() -> void:
	for definition in CONTROL_ACTION_DEFINITIONS:
		var action: String = definition["action"]
		if not InputMap.has_action(action):
			continue
		var events: Array = InputMap.action_get_events(action)
		var keycode: int = 0
		for ev in events:
			if ev is InputEventKey:
				var key_event: InputEventKey = ev
				keycode = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
				break
		_update_button_for_action(action, keycode)
