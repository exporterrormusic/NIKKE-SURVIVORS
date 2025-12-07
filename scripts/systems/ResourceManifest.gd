extends Node
class_name ResourceManifest
## Auto-generates resource lists at editor time, loads from cache in exported builds.
## This solves the DirAccess limitation in exported Godot builds.
##
## IMPORTANT: Before exporting, run the game in the editor at least once,
## or call ResourceManifest.generate_manifest() from an @tool script.

const MANIFEST_PATH := "res://resources/resource_manifest.tres"

# Cached resource lists (loaded from manifest in exports)
static var battle_music: Array[String] = []
static var biome_files: Array[String] = []
static var time_of_day_files: Array[String] = []
static var map_files: Array[String] = []
static var background_files: Array[String] = []
static var character_burst_files: Array[String] = []

static var _initialized := false

## Call this to force regeneration of the manifest (useful for editor tools)
static func generate_manifest() -> void:
	_initialized = false
	_scan_all_resources()
	_save_manifest()
	_initialized = true
	print("[ResourceManifest] Manifest generated successfully!")

static func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	
	if OS.has_feature("editor"):
		# In editor: scan directories and save manifest
		_scan_all_resources()
		_save_manifest()
	else:
		# In export: load from saved manifest
		_load_manifest()

static func _scan_all_resources() -> void:
	battle_music = _scan_directory("res://assets/sounds/music", [".mp3", ".ogg", ".wav"], ["main-menu"])
	biome_files = _scan_directory("res://resources/biomes", [".tres"])
	time_of_day_files = _scan_directory("res://resources/time_of_day", [".tres"])
	map_files = _scan_directory("res://resources/maps", [".tres"])
	background_files = _scan_directory("res://assets/backgrounds", [".jpg", ".png", ".webp"])
	character_burst_files = _scan_character_bursts("res://assets/characters")
	
	print("[ResourceManifest] Scanned resources:")
	print("  Battle music: ", battle_music.size())
	print("  Biomes: ", biome_files.size())
	print("  Time of day: ", time_of_day_files.size())
	print("  Maps: ", map_files.size())
	print("  Backgrounds: ", background_files.size())
	print("  Character bursts: ", character_burst_files.size())

static func _scan_directory(path: String, extensions: Array, exclude_patterns: Array = []) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("ResourceManifest: Could not open %s" % path)
		return files
	
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var lower := entry.to_lower()
			# Skip .import files
			if not lower.ends_with(".import"):
				for ext in extensions:
					if lower.ends_with(ext):
						# Check exclusions
						var excluded := false
						for pattern in exclude_patterns:
							if lower.find(pattern) != -1:
								excluded = true
								break
						if not excluded:
							files.append("%s/%s" % [path, entry])
						break
		entry = dir.get_next()
	dir.list_dir_end()
	return files

static func _scan_character_bursts(characters_path: String) -> Array[String]:
	var bursts: Array[String] = []
	var dir := DirAccess.open(characters_path)
	if dir == null:
		return bursts
	
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var burst_path := "%s/%s/burst.png" % [characters_path, entry]
			if ResourceLoader.exists(burst_path):
				bursts.append(burst_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return bursts

static func _save_manifest() -> void:
	var manifest := Resource.new()
	manifest.set_meta("battle_music", battle_music)
	manifest.set_meta("biome_files", biome_files)
	manifest.set_meta("time_of_day_files", time_of_day_files)
	manifest.set_meta("map_files", map_files)
	manifest.set_meta("background_files", background_files)
	manifest.set_meta("character_burst_files", character_burst_files)
	
	var error := ResourceSaver.save(manifest, MANIFEST_PATH)
	if error == OK:
		print("[ResourceManifest] Saved manifest to %s" % MANIFEST_PATH)
	else:
		push_error("ResourceManifest: Failed to save manifest: %s" % error)

static func _load_manifest() -> void:
	if not ResourceLoader.exists(MANIFEST_PATH):
		push_error("ResourceManifest: No manifest found at %s - run game in editor first!" % MANIFEST_PATH)
		return
	
	var manifest := load(MANIFEST_PATH)
	if manifest == null:
		push_error("ResourceManifest: Failed to load manifest")
		return
	
	battle_music = Array(manifest.get_meta("battle_music", []), TYPE_STRING, "", null)
	biome_files = Array(manifest.get_meta("biome_files", []), TYPE_STRING, "", null)
	time_of_day_files = Array(manifest.get_meta("time_of_day_files", []), TYPE_STRING, "", null)
	map_files = Array(manifest.get_meta("map_files", []), TYPE_STRING, "", null)
	background_files = Array(manifest.get_meta("background_files", []), TYPE_STRING, "", null)
	character_burst_files = Array(manifest.get_meta("character_burst_files", []), TYPE_STRING, "", null)
	
	print("[ResourceManifest] Loaded manifest with %d battle tracks, %d biomes, %d backgrounds" % [
		battle_music.size(), biome_files.size(), background_files.size()
	])
