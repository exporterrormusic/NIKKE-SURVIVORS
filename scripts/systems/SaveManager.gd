class_name SaveManager
extends RefCounted
## SaveManager - Centralized save file path management.
## Single source of truth for all save file locations.
## Provides utility functions for loading, saving, and resetting save data.

# === SAVE FILE PATHS ===
# All save files stored in user:// directory
const SHOP_PATH := "user://shop_data.cfg"
const ACHIEVEMENTS_PATH := "user://achievements.cfg"
const SETTINGS_PATH := "user://settings.cfg"
const LEADERBOARD_PATH := "user://leaderboard.cfg"
const STAGE_PROGRESS_PATH := "user://stage_progress.cfg"

## Get all save file paths as an array
static func get_all_save_paths() -> Array[String]:
	return [
		SHOP_PATH,
		ACHIEVEMENTS_PATH,
		SETTINGS_PATH,
		LEADERBOARD_PATH,
		STAGE_PROGRESS_PATH
	]

## Get paths for game progress data only (excludes settings)
static func get_progress_save_paths() -> Array[String]:
	return [
		SHOP_PATH,
		ACHIEVEMENTS_PATH,
		LEADERBOARD_PATH,
		STAGE_PROGRESS_PATH
	]

## Check if a save file exists
static func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

## Delete a save file
static func delete_file(path: String) -> bool:
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		return err == OK
	return true  # File didn't exist, so technically succeeded

## Delete all save files
static func delete_all_saves() -> Dictionary:
	var results := {}
	for path in get_all_save_paths():
		results[path] = delete_file(path)
	return results

## Delete progress saves only (keeps settings)
static func delete_progress_saves() -> Dictionary:
	var results := {}
	for path in get_progress_save_paths():
		results[path] = delete_file(path)
	return results

## Load a ConfigFile from a path
static func load_config(path: String) -> ConfigFile:
	var config := ConfigFile.new()
	config.load(path)  # Errors handled by caller checking values
	return config

## Save a ConfigFile to a path
static func save_config(config: ConfigFile, path: String) -> Error:
	return config.save(path)
