extends Node
## SettingsManager - Handles settings persistence and application.
## Saves/loads settings from user://settings.cfg
## Applies resolution, fullscreen, audio, and control bindings.

# Removed SaveManagerScript preload - now using global SaveManager autoload

# Default values
const DEFAULT_MUSIC_VOLUME := 0.8
const DEFAULT_SFX_VOLUME := 0.8
const DEFAULT_RESOLUTION := Vector2i(1920, 1080)
const DEFAULT_FULLSCREEN := false

# Current settings (cached)
var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME
var resolution: Vector2i = DEFAULT_RESOLUTION
var fullscreen: bool = DEFAULT_FULLSCREEN
var nintendo_layout: bool = false # Controller A/B swap
var key_bindings: Dictionary = {}
var controller_bindings: Dictionary = {} # Joypad button bindings
var _save_timer: Timer = null
const SAVE_DELAY := 0.5


# Available resolutions
const AVAILABLE_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]


func _ready() -> void:
	# Setup save timer
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(_perform_save)
	add_child(_save_timer)

	# Wait for MenuManager's intro screen to render before doing heavy initialization
	if MenuManager.intro_rendered:
		_async_init()
	else:
		MenuManager.intro_ready.connect(_on_intro_ready, CONNECT_ONE_SHOT)


func _on_intro_ready() -> void:
	_async_init()


func _async_init() -> void:
	# Yield a frame to let animation continue
	await get_tree().process_frame
	load_settings()
	
	# Add default key bindings for actions that aren't in project.godot
	_add_default_key_bindings()
	
	await get_tree().process_frame
	apply_all_settings()


func load_settings() -> void:
	var data := SaveManager.load_section("settings")
	
	if data.is_empty():
		print("[SettingsManager] No saved settings found, using defaults")
		_save_default_key_bindings()
		return
	
	# Audio
	var audio_data = data.get("audio", {})
	music_volume = audio_data.get("music_volume", DEFAULT_MUSIC_VOLUME)
	sfx_volume = audio_data.get("sfx_volume", DEFAULT_SFX_VOLUME)
	
	# Video
	var video_data = data.get("video", {})
	var res_x: int = video_data.get("resolution_x", DEFAULT_RESOLUTION.x)
	var res_y: int = video_data.get("resolution_y", DEFAULT_RESOLUTION.y)
	resolution = Vector2i(res_x, res_y)
	fullscreen = video_data.get("fullscreen", DEFAULT_FULLSCREEN)
	
	# Controls
	var controls_data = data.get("controls", {})
	nintendo_layout = controls_data.get("nintendo_layout", false)
	key_bindings = controls_data.get("key_bindings", {})
	controller_bindings = controls_data.get("controller_bindings", {})
	
	print("[SettingsManager] Settings loaded - Resolution: %dx%d, Fullscreen: %s, Nintendo: %s" % [resolution.x, resolution.y, fullscreen, nintendo_layout])


func save_settings() -> void:
	# Debounce saving to prevent frame drops
	if _save_timer:
		_save_timer.start()

func _perform_save() -> void:
	print("[SettingsManager] Saving settings specific to user://settings.cfg...")
	
	_update_key_bindings_from_inputmap()
	_update_controller_bindings_from_inputmap()
	
	var data := {
		"audio": {
			"music_volume": music_volume,
			"sfx_volume": sfx_volume
		},
		"video": {
			"resolution_x": resolution.x,
			"resolution_y": resolution.y,
			"fullscreen": fullscreen
		},
		"controls": {
			"key_bindings": key_bindings,
			"controller_bindings": controller_bindings,
			"nintendo_layout": nintendo_layout
		}
	}
	
	var err := SaveManager.save_section("settings", data)
	if err == OK:
		print("[SettingsManager] Settings saved successfully")
	else:
		push_error("[SettingsManager] Failed to save settings: " + str(err))


func _save_default_key_bindings() -> void:
	# Store current InputMap state as defaults
	_update_key_bindings_from_inputmap()


func _add_default_key_bindings() -> void:
	# Add default key bindings for actions not defined in project.godot or missing events
	# BURST: Default to E
	if not InputMap.has_action("burst"):
		InputMap.add_action("burst")
	# Ensure burst has the E key if no events are bound
	var burst_events = InputMap.action_get_events("burst")
	var has_key_event = false
	for ev in burst_events:
		if ev is InputEventKey:
			has_key_event = true
			break
	if not has_key_event:
		var event = InputEventKey.new()
		event.keycode = KEY_E
		InputMap.action_add_event("burst", event)
		print("[SettingsManager] Added default E key to burst action")
		
	if not InputMap.has_action("next_character"):
		InputMap.add_action("next_character")
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP
		InputMap.action_add_event("next_character", event)
		
	if not InputMap.has_action("prev_character"):
		InputMap.add_action("prev_character")
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		InputMap.action_add_event("prev_character", event)


func _update_key_bindings_from_inputmap() -> void:
	var actions := ["move_up", "move_down", "move_left", "move_right", "dash", "burst", "special_attack", "ui_cancel"]
	for action in actions:
		if InputMap.has_action(action):
			var events := InputMap.action_get_events(action)
			for ev in events:
				if ev is InputEventKey:
					var keycode: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
					key_bindings[action] = keycode
					break


func _update_controller_bindings_from_inputmap() -> void:
	var actions := ["move_up", "move_down", "move_left", "move_right", "dash", "burst", "thrust", "ui_cancel"]
	for action in actions:
		if InputMap.has_action(action):
			var events := InputMap.action_get_events(action)
			for ev in events:
				if ev is InputEventJoypadButton:
					controller_bindings[action] = ev.button_index
					break


func apply_all_settings() -> void:
	apply_audio_settings()
	apply_video_settings()
	apply_key_bindings()
	apply_controller_bindings()
	apply_controller_layout()


func apply_controller_bindings() -> void:
	# Apply saved controller bindings to InputMap
	for action in controller_bindings:
		if not InputMap.has_action(action):
			continue
		var btn_index: int = int(controller_bindings[action])
		
		# Clear existing joypad button events for this action
		var existing := InputMap.action_get_events(action)
		for ev in existing:
			if ev is InputEventJoypadButton:
				InputMap.action_erase_event(action, ev)
		
		# Add the saved binding
		var new_event := InputEventJoypadButton.new()
		new_event.button_index = btn_index
		new_event.device = -1
		InputMap.action_add_event(action, new_event)
	print("[SettingsManager] Applied controller bindings")


func apply_controller_layout() -> void:
	# Nintendo layout support removed
	pass


func apply_audio_settings() -> void:
	# Apply music volume to Music bus (background music only)
	_apply_bus_volume("Music", music_volume)
	# Apply SFX volume to SFX bus (all sound effects: weapons, UI, etc.)
	_apply_bus_volume("SFX", sfx_volume)


func _apply_bus_volume(bus_name: String, value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return
	var linear: float = clamp(value, 0.0, 1.0)
	var db_value: float = linear_to_db(max(linear, 0.0001))
	AudioServer.set_bus_volume_db(bus_index, db_value)


func apply_video_settings() -> void:
	print("[SettingsManager] Applying video settings - Fullscreen: %s, Resolution: %dx%d" % [fullscreen, resolution.x, resolution.y])
	
	if fullscreen:
		# Switch to fullscreen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		# Windowed mode with specified resolution
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)
		
		# Center the window on the primary monitor
		var primary_screen := DisplayServer.get_primary_screen()
		var screen_pos := DisplayServer.screen_get_position(primary_screen)
		var screen_size := DisplayServer.screen_get_size(primary_screen)
		var window_size := DisplayServer.window_get_size()
		var centered_pos := screen_pos + (screen_size - window_size) / 2
		DisplayServer.window_set_position(centered_pos)
	
	# Ensure content scales properly - update viewport stretch settings via code
	# The viewport will maintain the base resolution and scale to fit
	get_tree().root.content_scale_size = Vector2i(1920, 1080)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


func apply_key_bindings() -> void:
	for action in key_bindings:
		if not InputMap.has_action(action):
			continue
		var keycode: int = int(key_bindings[action])
		if keycode == 0:
			continue
		
		# Clear existing key events and add the saved one
		var existing := InputMap.action_get_events(action)
		for ev in existing:
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		
		var new_event := InputEventKey.new()
		new_event.physical_keycode = keycode as Key
		new_event.keycode = keycode as Key
		InputMap.action_add_event(action, new_event)


# -- Public API for SettingsMenu --

func set_music_volume(value: float) -> void:
	music_volume = clamp(value, 0.0, 1.0)
	_apply_bus_volume("Music", music_volume)
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clamp(value, 0.0, 1.0)
	_apply_bus_volume("SFX", sfx_volume)
	save_settings()


func set_resolution(new_resolution: Vector2i) -> void:
	resolution = new_resolution
	apply_video_settings()
	save_settings()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_video_settings()
	save_settings()


func set_key_binding(action: String, keycode: int) -> void:
	key_bindings[action] = keycode
	save_settings()


func set_controller_binding(action: String, button_index: int) -> void:
	controller_bindings[action] = button_index
	save_settings()


func reset_to_defaults() -> void:
	print("[SettingsManager] Resetting to defaults...")
	# 1. Reset variables
	key_bindings.clear()
	controller_bindings.clear()
	nintendo_layout = false
	
	# 2. Reset InputMap to Project Settings (Global Defaults)
	InputMap.load_from_project_settings()
	
	# 3. Apply default helpers (MenuManager mappings) if needed
	# if MenuManager: 
	# 	MenuManager._setup_controller_map()
	
	# 4. Save clean state
	save_settings()
	
	print("[SettingsManager] Bindings reset complete.")


func set_nintendo_layout(enabled: bool) -> void:
	nintendo_layout = enabled
	apply_controller_layout()
	save_settings()


func is_nintendo_layout() -> bool:
	return nintendo_layout


func get_music_volume() -> float:
	return music_volume


func get_sfx_volume() -> float:
	return sfx_volume


func get_resolution() -> Vector2i:
	return resolution


func is_fullscreen() -> bool:
	return fullscreen


func get_key_bindings() -> Dictionary:
	return key_bindings.duplicate()
