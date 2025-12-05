extends Node
## SettingsManager - Handles settings persistence and application.
## Saves/loads settings from user://settings.cfg
## Applies resolution, fullscreen, audio, and control bindings.

const SaveManagerScript = preload("res://scripts/systems/SaveManager.gd")

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
var key_bindings: Dictionary = {}

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
	load_settings()
	apply_all_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SaveManagerScript.SETTINGS_PATH)
	
	if err != OK:
		print("[SettingsManager] No saved settings found, using defaults")
		_save_default_key_bindings()
		return
	
	# Audio
	music_volume = config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)
	sfx_volume = config.get_value("audio", "sfx_volume", DEFAULT_SFX_VOLUME)
	
	# Video
	var res_x: int = config.get_value("video", "resolution_x", DEFAULT_RESOLUTION.x)
	var res_y: int = config.get_value("video", "resolution_y", DEFAULT_RESOLUTION.y)
	resolution = Vector2i(res_x, res_y)
	fullscreen = config.get_value("video", "fullscreen", DEFAULT_FULLSCREEN)
	
	# Controls
	var saved_bindings: Dictionary = config.get_value("controls", "key_bindings", {})
	key_bindings = saved_bindings
	
	print("[SettingsManager] Settings loaded - Resolution: %dx%d, Fullscreen: %s" % [resolution.x, resolution.y, fullscreen])


func save_settings() -> void:
	var config := ConfigFile.new()
	
	# Audio
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	
	# Video
	config.set_value("video", "resolution_x", resolution.x)
	config.set_value("video", "resolution_y", resolution.y)
	config.set_value("video", "fullscreen", fullscreen)
	
	# Controls - save current InputMap state
	_update_key_bindings_from_inputmap()
	config.set_value("controls", "key_bindings", key_bindings)
	
	var err := config.save(SaveManagerScript.SETTINGS_PATH)
	if err == OK:
		print("[SettingsManager] Settings saved successfully")
	else:
		push_error("[SettingsManager] Failed to save settings: " + str(err))


func _save_default_key_bindings() -> void:
	# Store current InputMap state as defaults
	_update_key_bindings_from_inputmap()


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


func apply_all_settings() -> void:
	apply_audio_settings()
	apply_video_settings()
	apply_key_bindings()


func apply_audio_settings() -> void:
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)
	# Also apply to Master if specific buses don't exist
	_apply_bus_volume("Master", music_volume)


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
		
		# Center the window on screen
		var screen_size := DisplayServer.screen_get_size()
		var window_size := DisplayServer.window_get_size()
		var centered_pos := (screen_size - window_size) / 2
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
	_apply_bus_volume("Master", music_volume)
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
