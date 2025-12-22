extends Node
## Unified save manager for all game persistence.
## Provides consistent file paths and save/load utilities.

# === SAVE FILE PATHS ===
const SHOP_PATH := "user://shop_data.cfg"
const ACHIEVEMENTS_PATH := "user://achievements.cfg"
const SETTINGS_PATH := "user://settings.cfg"
const LEADERBOARD_PATH := "user://leaderboard.cfg"
const STAGE_PROGRESS_PATH := "user://stage_progress.cfg"

func _ready() -> void:
	# Ensure directory exists (though user:// always exists)
	print("[SaveManager] Initialized")


# --- Utility Functions ---

func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


func delete_file(path: String) -> bool:
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		return err == OK
	return true


func load_config(path: String) -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(path)
	if err != OK:
		return {}
	
	var data := {}
	for section in config.get_sections():
		data[section] = {}
		for key in config.get_section_keys(section):
			data[section][key] = config.get_value(section, key)
	return data


func save_config(data: Dictionary, path: String) -> Error:
	var config := ConfigFile.new()
	for section in data:
		var section_data = data[section]
		if section_data is Dictionary:
			for key in section_data:
				config.set_value(section, key, section_data[key])
		else:
			# Fallback for simple data (though we prefer sectioned)
			config.set_value("data", section, section_data)
	
	return config.save(path)


# --- Path Helpers ---

func get_all_save_paths() -> Array[String]:
	return [
		SHOP_PATH,
		ACHIEVEMENTS_PATH,
		SETTINGS_PATH,
		LEADERBOARD_PATH,
		STAGE_PROGRESS_PATH
	]


func get_progress_save_paths() -> Array[String]:
	return [
		SHOP_PATH,
		ACHIEVEMENTS_PATH,
		LEADERBOARD_PATH,
		STAGE_PROGRESS_PATH
	]


# --- Mass Operations ---

func delete_all_saves() -> Dictionary:
	var results := {}
	for path in get_all_save_paths():
		results[path] = delete_file(path)
	return results


func delete_progress_saves() -> Dictionary:
	var results := {}
	for path in get_progress_save_paths():
		results[path] = delete_file(path)
	return results
