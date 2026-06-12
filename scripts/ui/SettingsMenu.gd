extends Control
class_name SettingsMenu
## Settings menu - NIKKE "category rail" (light admin register, approved
## mockup docs/mockups/settings_v2.html). Left rail: AUDIO / VIDEO /
## GAMEPLAY / CONTROLS; right: white content card per category.
## Persistence + application live in SettingsManager; this screen is wiring.
## Static chrome lives in SettingsMenu.tscn; binding rows are data-driven.

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

signal back_requested

const PANE_AUDIO := "audio"
const PANE_VIDEO := "video"
const PANE_GAMEPLAY := "gameplay"
const PANE_CONTROLS := "controls"
const PANE_ORDER := [PANE_AUDIO, PANE_VIDEO, PANE_GAMEPLAY, PANE_CONTROLS]

const DEFAULT_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

const CONTROL_ACTIONS := [
	{"action": "move_up", "label": "Move Up"},
	{"action": "move_down", "label": "Move Down"},
	{"action": "move_left", "label": "Move Left"},
	{"action": "move_right", "label": "Move Right"},
	{"action": "dash", "label": "Dash"},
	{"action": "burst", "label": "Burst"},
	{"action": "thrust", "label": "Special Attack"},
	{"action": "ui_cancel", "label": "Pause"}
]

var _available_resolutions: Array[Vector2i] = []
var _current_pane: String = PANE_AUDIO
var _control_buttons: Dictionary = {}  # action -> keycap Button
var _capturing_action: String = ""
var _capturing_button: Button = null
var _capturing_original_text: String = ""
var _suppress_signals := false

@onready var _header_title: Label = %HeaderTitle
@onready var _header_sub: Label = %HeaderSub
@onready var _back_button: Button = %BackButton
@onready var _content_panel: Panel = %ContentPanel
@onready var _rails: Dictionary = {
	PANE_AUDIO: %AudioRail,
	PANE_VIDEO: %VideoRail,
	PANE_GAMEPLAY: %GameplayRail,
	PANE_CONTROLS: %ControlsRail,
}
@onready var _panes: Dictionary = {
	PANE_AUDIO: %AudioPane,
	PANE_VIDEO: %VideoPane,
	PANE_GAMEPLAY: %GameplayPane,
	PANE_CONTROLS: %ControlsPane,
}
@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _sfx_value: Label = %SfxValue
@onready var _resolution_options: OptionButton = %ResolutionOptions
# NikkeSegmentToggle instances (untyped: class_name indexing lags fresh files)
@onready var _fullscreen_toggle = %FullscreenToggle
@onready var _shake_toggle = %ShakeToggle
@onready var _damage_toggle = %DamageToggle
@onready var _bind_grid: GridContainer = %BindGrid
@onready var _reset_binds_button: Button = %ResetBindsButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_style_chrome()
	_build_binding_rows()
	_initialize_resolutions()

	_back_button.pressed.connect(func():
		UISounds.play_back()
		back_requested.emit()
	)
	for pane_name in PANE_ORDER:
		_rails[pane_name].pressed.connect(_on_rail_pressed.bind(pane_name))

	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_resolution_options.item_selected.connect(_on_resolution_selected)
	_fullscreen_toggle.toggled_changed.connect(_on_fullscreen_changed)
	_shake_toggle.toggled_changed.connect(_on_shake_changed)
	_damage_toggle.toggled_changed.connect(_on_damage_numbers_changed)
	_reset_binds_button.pressed.connect(_on_reset_binds_pressed)

	_load_from_settings_manager()
	_refresh_key_binding_labels()
	_switch_pane(PANE_AUDIO)
	set_process_unhandled_input(true)


# =============================================================================
# CHROME
# =============================================================================

func _style_chrome() -> void:
	UI.style_header_label(_header_title, 56, UI.ADMIN_TEXT)
	UI.style_subtitle_label(_header_sub, 17, UI.ADMIN_TEXT_DIM)
	_content_panel.add_theme_stylebox_override("panel", UI.create_admin_card_style())

	for pane_name in PANE_ORDER:
		var pane: VBoxContainer = _panes[pane_name]
		# Section caption (HBox: cyan tick + label)
		var cap_row: HBoxContainer = pane.get_child(0)
		var cap_label: Label = cap_row.get_child(1)
		UI.style_subtitle_label(cap_label, 17, UI.ADMIN_TEXT_DIM)
		# Row labels
		for row in pane.get_children():
			if row is HBoxContainer and row != cap_row and row.get_child_count() > 0:
				var label := row.get_child(0)
				if label is Label:
					label.add_theme_font_override("font", UI.FONT_BOLD)
					label.add_theme_font_size_override("font_size", 21)
					label.add_theme_color_override("font_color", UI.ADMIN_TEXT)
					label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	for value_label in [_music_value, _sfx_value]:
		value_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
		value_label.add_theme_font_size_override("font_size", 36)
		value_label.add_theme_color_override("font_color", UI.ACCENT_CYAN_DEEP)

	for hint in [%ShakeHint, %DamageHint]:
		hint.add_theme_font_override("font", UI.FONT_MEDIUM)
		hint.add_theme_font_size_override("font_size", 17)
		hint.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)

	for slider in [_music_slider, _sfx_slider]:
		var grabber := StyleBoxFlat.new()
		grabber.bg_color = UI.ACCENT_CYAN
		grabber.set_corner_radius_all(0)
		grabber.content_margin_left = 10
		grabber.content_margin_right = 10
		grabber.content_margin_top = 16
		grabber.content_margin_bottom = 16
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.235, 0.275, 0.322, 0.22)
		track.set_corner_radius_all(0)
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		slider.add_theme_stylebox_override("slider", track)
		slider.add_theme_stylebox_override("grabber_area", grabber)
		slider.add_theme_stylebox_override("grabber_area_highlight", grabber)

	_resolution_options.add_theme_font_override("font", UI.FONT_BOLD)
	_resolution_options.add_theme_font_size_override("font_size", 19)
	var opt_style := StyleBoxFlat.new()
	opt_style.bg_color = Color.WHITE
	opt_style.border_color = Color(0.784, 0.804, 0.827, 1.0)
	opt_style.set_border_width_all(1)
	opt_style.set_corner_radius_all(0)
	opt_style.content_margin_left = 18
	var opt_hover := opt_style.duplicate()
	opt_hover.border_color = UI.ACCENT_CYAN_DEEP
	_resolution_options.add_theme_stylebox_override("normal", opt_style)
	_resolution_options.add_theme_stylebox_override("hover", opt_hover)
	_resolution_options.add_theme_stylebox_override("pressed", opt_hover)
	_resolution_options.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_resolution_options.add_theme_color_override(state, UI.ADMIN_TEXT)

	_reset_binds_button.add_theme_font_override("font", UI.FONT_BOLD)
	_reset_binds_button.add_theme_font_size_override("font_size", 19)
	var reset_normal := StyleBoxFlat.new()
	reset_normal.bg_color = Color.WHITE
	reset_normal.border_color = Color(0.769, 0.153, 0.11, 1.0)
	reset_normal.set_border_width_all(1)
	reset_normal.set_corner_radius_all(0)
	var reset_hover := reset_normal.duplicate()
	reset_hover.bg_color = Color(0.992, 0.941, 0.937, 1.0)
	_reset_binds_button.add_theme_stylebox_override("normal", reset_normal)
	_reset_binds_button.add_theme_stylebox_override("hover", reset_hover)
	_reset_binds_button.add_theme_stylebox_override("pressed", reset_hover)
	_reset_binds_button.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_reset_binds_button.add_theme_color_override(state, Color(0.769, 0.153, 0.11, 1.0))


func _build_binding_rows() -> void:
	for definition in CONTROL_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.custom_minimum_size = Vector2(560, 0)

		var label := Label.new()
		label.text = str(definition["label"]).to_upper()
		label.add_theme_font_override("font", UI.FONT_BOLD)
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", UI.ADMIN_TEXT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var keycap := Button.new()
		keycap.custom_minimum_size = Vector2(165, 60)
		keycap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		keycap.add_theme_font_override("font", UI.FONT_BOLD)
		keycap.add_theme_font_size_override("font_size", 19)
		_style_keycap(keycap, false)
		keycap.pressed.connect(_begin_key_capture.bind(String(definition["action"]), keycap))
		row.add_child(keycap)

		_bind_grid.add_child(row)
		_control_buttons[definition["action"]] = keycap


func _style_keycap(btn: Button, capturing: bool) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(0)
	if capturing:
		style.bg_color = UI.ACCENT_SECONDARY
		style.border_color = Color(0.851, 0.671, 0.0, 1.0)
		style.set_border_width_all(1)
		style.border_width_bottom = 4
	else:
		style.bg_color = Color.WHITE
		style.border_color = Color(0.784, 0.804, 0.827, 1.0)
		style.set_border_width_all(1)
		style.border_width_bottom = 4
		style.border_color = Color(0.784, 0.804, 0.827, 1.0)
	var hover := style.duplicate()
	hover.border_color = UI.ACCENT_CYAN_DEEP
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style if capturing else hover)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	var font_color := Color(0.353, 0.278, 0.0, 1.0) if capturing else UI.ADMIN_TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, font_color)


# =============================================================================
# RAIL / PANES
# =============================================================================

func _on_rail_pressed(pane_name: String) -> void:
	if pane_name == _current_pane:
		return
	UISounds.play_select()
	_switch_pane(pane_name)


func _switch_pane(pane_name: String) -> void:
	_cancel_key_capture()
	_current_pane = pane_name
	for name_key in PANE_ORDER:
		_panes[name_key].visible = (name_key == pane_name)
		_rails[name_key].set_selected(name_key == pane_name)


# =============================================================================
# VALUES <-> SETTINGSMANAGER
# =============================================================================

func _load_from_settings_manager() -> void:
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	_suppress_signals = true
	if settings_mgr:
		_music_slider.value = settings_mgr.get_music_volume()
		_sfx_slider.value = settings_mgr.get_sfx_volume()
		_select_resolution(settings_mgr.get_resolution())
		_fullscreen_toggle.value = settings_mgr.is_fullscreen()
		_shake_toggle.value = settings_mgr.is_screen_shake_enabled()
		_damage_toggle.value = settings_mgr.is_damage_numbers_enabled()
	_update_volume_labels()
	_suppress_signals = false


func _update_volume_labels() -> void:
	_music_value.text = "%d%%" % roundi(_music_slider.value * 100.0)
	_sfx_value.text = "%d%%" % roundi(_sfx_slider.value * 100.0)


func _on_music_changed(value: float) -> void:
	_update_volume_labels()
	if _suppress_signals:
		return
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_music_volume(value)


func _on_sfx_changed(value: float) -> void:
	_update_volume_labels()
	if _suppress_signals:
		return
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_sfx_volume(value)


func _initialize_resolutions() -> void:
	_available_resolutions = DEFAULT_RESOLUTIONS.duplicate()
	_refresh_resolution_options()


func _refresh_resolution_options() -> void:
	_resolution_options.clear()
	for resolution in _available_resolutions:
		_resolution_options.add_item("%d x %d" % [resolution.x, resolution.y])


func _select_resolution(target: Vector2i) -> void:
	if not _available_resolutions.has(target):
		_available_resolutions.append(target)
		_available_resolutions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x or (a.x == b.x and a.y < b.y)
		)
		_refresh_resolution_options()
	var index := _available_resolutions.find(target)
	if index != -1:
		_resolution_options.select(index)


func _on_resolution_selected(index: int) -> void:
	if _suppress_signals or index < 0 or index >= _available_resolutions.size():
		return
	UISounds.play_select()
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_resolution(_available_resolutions[index])


func _on_fullscreen_changed(enabled: bool) -> void:
	if _suppress_signals:
		return
	UISounds.play_select()
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_fullscreen(enabled)


func _on_shake_changed(enabled: bool) -> void:
	if _suppress_signals:
		return
	UISounds.play_select()
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_screen_shake_enabled(enabled)


func _on_damage_numbers_changed(enabled: bool) -> void:
	if _suppress_signals:
		return
	UISounds.play_select()
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_damage_numbers_enabled(enabled)


func _on_reset_binds_pressed() -> void:
	UISounds.play_confirm()
	_cancel_key_capture()
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.reset_to_defaults()
	_refresh_key_binding_labels()


# =============================================================================
# KEY CAPTURE (logic preserved from the previous menu)
# =============================================================================

func _begin_key_capture(action: String, button: Button) -> void:
	if _capturing_action == action:
		return
	_cancel_key_capture()
	_capturing_action = action
	_capturing_button = button
	_capturing_original_text = button.text
	button.text = "PRESS KEY..."
	_style_keycap(button, true)


func _unhandled_input(event: InputEvent) -> void:
	if _capturing_action != "":
		# Block ALL input during capture to prevent UI bleed-through
		get_viewport().set_input_as_handled()

		if event is InputEventKey:
			var key_event: InputEventKey = event
			if not key_event.is_pressed() or key_event.is_echo():
				return
			var is_escape: bool = key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE
			if is_escape:
				# Exception: allow binding Escape to 'ui_cancel' (Pause)
				if _capturing_action == "ui_cancel":
					_apply_key_binding(_capturing_action, key_event)
					return
				_cancel_key_capture()
				return
			_apply_key_binding(_capturing_action, key_event)
			return

		if event is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = event
			if not mouse_event.pressed:
				return
			# Wheel/extra buttons only (not left/right click, to avoid UI issues)
			if mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
				_apply_mouse_binding(_capturing_action, mouse_event)
		return


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.is_pressed() or key_event.is_echo():
		return
	var is_escape: bool = key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE
	if is_escape and _capturing_action == "":
		UISounds.play_back()
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _apply_key_binding(action: String, event: InputEventKey) -> void:
	var copy := InputEventKey.new()
	copy.physical_keycode = event.physical_keycode
	copy.keycode = event.keycode if event.keycode != 0 else event.physical_keycode
	copy.shift_pressed = event.shift_pressed
	copy.ctrl_pressed = event.ctrl_pressed
	copy.alt_pressed = event.alt_pressed
	copy.meta_pressed = event.meta_pressed

	for ev in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, ev)
	InputMap.action_add_event(action, copy)

	_update_button_for_action(action, copy.physical_keycode)
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_key_binding(action, copy.physical_keycode)

	_capturing_original_text = ""
	_cancel_key_capture()
	UISounds.play_confirm()


func _apply_mouse_binding(action: String, event: InputEventMouseButton) -> void:
	var copy := InputEventMouseButton.new()
	copy.button_index = event.button_index

	for ev in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, ev)
	InputMap.action_add_event(action, copy)

	_update_button_for_action(action, 0, event.button_index)
	_capturing_original_text = ""
	_cancel_key_capture()
	UISounds.play_confirm()


func _cancel_key_capture() -> void:
	if _capturing_button:
		if _capturing_original_text != "":
			_capturing_button.text = _capturing_original_text
		_style_keycap(_capturing_button, false)
	_capturing_action = ""
	_capturing_button = null
	_capturing_original_text = ""


func _update_button_for_action(action: String, keycode: int, button_index: int = 0) -> void:
	if not _control_buttons.has(action):
		return
	var button: Button = _control_buttons[action]
	button.text = _keycode_to_string(keycode, button_index)
	_style_keycap(button, false)


func _refresh_key_binding_labels() -> void:
	for definition in CONTROL_ACTIONS:
		var action: String = definition["action"]
		if not InputMap.has_action(action):
			continue
		var keycode := 0
		var button_index := 0
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keycode = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
				break
			elif ev is InputEventMouseButton:
				button_index = ev.button_index
				break
		_update_button_for_action(action, keycode, button_index)


func _keycode_to_string(keycode: int, button_index: int = 0) -> String:
	if button_index != 0:
		match button_index:
			MOUSE_BUTTON_LEFT: return "LEFT CLICK"
			MOUSE_BUTTON_RIGHT: return "RIGHT CLICK"
			MOUSE_BUTTON_MIDDLE: return "MIDDLE CLICK"
			MOUSE_BUTTON_WHEEL_UP: return "WHEEL UP"
			MOUSE_BUTTON_WHEEL_DOWN: return "WHEEL DOWN"
			_: return "MOUSE %d" % button_index
	if keycode == 0:
		return "UNBOUND"
	return OS.get_keycode_string(keycode).to_upper()


func clear_capture_state() -> void:
	_cancel_key_capture()
