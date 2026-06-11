extends Node
## Unified save manager for all game persistence.
## Consolidated to a single file with section-based access.
## Old per-file paths kept as aliases for migration.

const SINGLE_SAVE_PATH := "user://save.cfg"

## Bump to invalidate old saves. v2: single-character rework (squad removed,
## talents run-only, character unlocks moved to character select).
const SAVE_VERSION := 2

# Deprecated legacy paths — still available for migration
const SHOP_PATH := "user://shop_data.cfg"
const ACHIEVEMENTS_PATH := "user://achievements.cfg"
const SETTINGS_PATH := "user://settings.cfg"
const LEADERBOARD_PATH := "user://leaderboard.cfg"
const STAGE_PROGRESS_PATH := "user://stage_progress.cfg"


func _ready() -> void:
	# Runs before other autoloads read their sections (autoload order)
	_check_save_version()


## Wipe outdated saves. User settings (audio, keybinds) survive the wipe.
func _check_save_version() -> void:
	var meta := load_section("meta")
	var version: int = meta.get("version", 1)
	if version >= SAVE_VERSION:
		return

	var settings := load_section("settings")
	delete_all_saves()
	if not settings.is_empty():
		save_section("settings", settings)
	save_section("meta", {"version": SAVE_VERSION})
	print("[SaveManager] Save data wiped (version %d -> %d)" % [version, SAVE_VERSION])


# --- Single-file Section API ---

## Save one section to the consolidated save file.
## Only re-writes the one file on disk (atomic single-write).
func save_section(section: String, data: Dictionary) -> Error:
	var config := ConfigFile.new()
	# Load existing file first to preserve other sections
	if FileAccess.file_exists(SINGLE_SAVE_PATH):
		config.load(SINGLE_SAVE_PATH)
	
	for key in data:
		config.set_value(section, key, data[key])
	
	# Write to temp, then rename for atomic safety
	var tmp_path := SINGLE_SAVE_PATH + ".tmp"
	var err := config.save(tmp_path)
	if err != OK:
		return err
	# Rename (atomic on most file systems)
	err = DirAccess.rename_absolute(tmp_path, SINGLE_SAVE_PATH)
	if err != OK:
		# Fallback: try direct save if rename fails
		err = config.save(SINGLE_SAVE_PATH)
	return err


## Load one section from the consolidated save file.
## Returns empty dict if section doesn't exist.
func load_section(section: String) -> Dictionary:
	if not FileAccess.file_exists(SINGLE_SAVE_PATH):
		return {}
	
	var config := ConfigFile.new()
	var err := config.load(SINGLE_SAVE_PATH)
	if err != OK:
		return {}
	
	if not config.has_section(section):
		return {}
	
	var data := {}
	for key in config.get_section_keys(section):
		data[key] = config.get_value(section, key)
	return data


# --- Legacy API (kept for backward compat during migration) ---

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
			config.set_value("data", section, section_data)
	
	return config.save(path)


# --- Migration Helper ---

## Migrate all old separate save files into the consolidated file.
## Call once at startup; safe to call repeatedly (checks if already migrated).
func migrate_from_legacy() -> bool:
	if FileAccess.file_exists(SINGLE_SAVE_PATH):
		return false # Already migrated
	
	var migrated := false
	var legacy_map := {
		"shop": SHOP_PATH,
		"achievements": ACHIEVEMENTS_PATH,
		"settings": SETTINGS_PATH,
		"leaderboard": LEADERBOARD_PATH,
		"progress": STAGE_PROGRESS_PATH,
	}
	
	for section in legacy_map:
		var legacy_path := legacy_map[section] as String
		if FileAccess.file_exists(legacy_path):
			var data := load_config(legacy_path)
			if not data.is_empty():
				save_section(section, data)
				migrated = true
	
	if migrated:
		print("[SaveManager] Migrated legacy save files to %s" % SINGLE_SAVE_PATH)
	return migrated


# --- Mass Operations ---

func delete_all_saves() -> Dictionary:
	var results := {}
	# Remove consolidated file
	results[SINGLE_SAVE_PATH] = delete_file(SINGLE_SAVE_PATH)
	# Also remove legacy files
	for path in [SHOP_PATH, ACHIEVEMENTS_PATH, SETTINGS_PATH, LEADERBOARD_PATH, STAGE_PROGRESS_PATH]:
		results[path] = delete_file(path)
	return results


func delete_progress_saves() -> Dictionary:
	var results := {}
	# Remove the entire consolidated file for a full reset
	results[SINGLE_SAVE_PATH] = delete_file(SINGLE_SAVE_PATH)
	return results
