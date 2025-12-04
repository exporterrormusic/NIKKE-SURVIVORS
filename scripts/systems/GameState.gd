extends Node

## Global game state singleton that persists across scenes.
## Stores character selections and links them to the shop/talent system.
## Tracks scores, waves survived, and maintains leaderboard data.
##
## Usage:
##   - Character select menu sets the 3 selected characters
##   - Shop/TalentTree reads from here to know which characters to display
##   - Level reports score/wave on game over for leaderboard tracking
##
## Access via autoload: GameState.set_selected_characters([...])

const LEADERBOARD_PATH := "user://leaderboard.cfg"

# Selected characters for the current run (character registry indices)
# Default: Cecil (8), Nayuta (9), Marian (4)
var selected_character_indices: Array[int] = [8, 9, 4]

# The character the player controls (index into selected_character_indices, or registry index)
var player_character_index: int = 9  # Default to Nayuta

# Character registry reference (loaded lazily)
var _character_registry = null

# --- Current Run Stats ---
var current_score: int = 0
var current_wave: int = 0
var current_kills: int = 0

# --- Leaderboard Data ---
# Dictionary: character_id (String) -> { "best_score": int, "best_wave": int, "total_runs": int }
var _leaderboard_data: Dictionary = {}
var _total_score_all_time: int = 0

# --- Meta Currency ---
# Pristine Rapture Cores - earned by defeating bosses, used in main menu shop
var pristine_rapture_cores: int = 0

# --- Stage Progress ---
# Tracks which stages have been cleared (unlocks next stage)
var stages_cleared: Array[String] = []
var current_stage_id: String = "stage_1"


func _ready() -> void:
	_load_leaderboard()
	_load_stage_progress()


# --- Current Run Tracking ---

## Add score during gameplay (call when enemy dies)
func add_score(points: int) -> void:
	current_score += points
	current_kills += 1


## Update current wave (call from WaveDirector)
func set_current_wave(wave: int) -> void:
	current_wave = wave


## Reset current run stats (call at start of new game)
func reset_run_stats() -> void:
	current_score = 0
	current_wave = 0
	current_kills = 0


## Record the result of a completed run (call on game over)
## @param character_id: The character code/id that was played
func record_run_result(character_id: String) -> void:
	if character_id.is_empty():
		# Try to get from current player character
		_ensure_registry()
		if _character_registry:
			var char_ids: Array = _character_registry.get_all_character_ids()
			if player_character_index >= 0 and player_character_index < char_ids.size():
				character_id = char_ids[player_character_index]
	
	if character_id.is_empty():
		push_warning("GameState: Cannot record run - no character_id")
		return
	
	print("[GameState] Recording run: character=%s, score=%d, wave=%d, kills=%d" % [character_id, current_score, current_wave, current_kills])
	
	# Get or create entry for this character
	if not _leaderboard_data.has(character_id):
		_leaderboard_data[character_id] = {
			"best_score": 0,
			"best_wave": 0,
			"total_runs": 0
		}
	
	var entry: Dictionary = _leaderboard_data[character_id]
	entry["total_runs"] = entry.get("total_runs", 0) + 1
	
	# Update best score if this run was better
	if current_score > entry.get("best_score", 0):
		entry["best_score"] = current_score
		print("[GameState] New best score for %s: %d" % [character_id, current_score])
	
	# Update best wave if this run went further
	if current_wave > entry.get("best_wave", 0):
		entry["best_wave"] = current_wave
		print("[GameState] New best wave for %s: %d" % [character_id, current_wave])
	
	# Update total score
	_total_score_all_time += current_score
	
	_leaderboard_data[character_id] = entry
	_save_leaderboard()


# --- Leaderboard Queries ---

## Get leaderboard entries sorted by best score
## Returns array of dictionaries with display_name, code, best_score, best_wave
func get_leaderboard_entries(max_count: int = 10) -> Array:
	var entries: Array = []
	
	_ensure_registry()
	
	# Build entries from all characters that have been played
	for char_id in _leaderboard_data:
		var data: Dictionary = _leaderboard_data[char_id]
		var display_name: String = char_id.capitalize().replace("-", " ").replace("_", " ")
		
		# Try to get proper display name from registry
		if _character_registry:
			var char_data = _character_registry.get_character(char_id)
			if char_data and char_data.display_name != "":
				display_name = char_data.display_name
		
		entries.append({
			"display_name": display_name,
			"code": char_id,
			"best_score": data.get("best_score", 0),
			"best_wave": data.get("best_wave", 0),
			"total_runs": data.get("total_runs", 0)
		})
	
	# Also add characters that haven't been played yet (with 0 scores)
	if _character_registry:
		var all_ids: Array = _character_registry.get_all_character_ids()
		for char_id in all_ids:
			if not _leaderboard_data.has(char_id):
				var char_data = _character_registry.get_character(char_id)
				var display_name: String = char_id.capitalize().replace("-", " ").replace("_", " ")
				if char_data and char_data.display_name != "":
					display_name = char_data.display_name
				entries.append({
					"display_name": display_name,
					"code": char_id,
					"best_score": 0,
					"best_wave": 0,
					"total_runs": 0
				})
	
	# Sort by best score descending
	entries.sort_custom(func(a, b): return a["best_score"] > b["best_score"])
	
	# Limit to max_count
	if entries.size() > max_count:
		entries = entries.slice(0, max_count)
	
	return entries


## Get total score across all runs
func get_total_score() -> int:
	return _total_score_all_time


## Get best score for a specific character
func get_best_score(character_id: String) -> int:
	if _leaderboard_data.has(character_id):
		return _leaderboard_data[character_id].get("best_score", 0)
	return 0


## Get best wave for a specific character
func get_best_wave(character_id: String) -> int:
	if _leaderboard_data.has(character_id):
		return _leaderboard_data[character_id].get("best_wave", 0)
	return 0


# --- Meta Currency ---

## Add Pristine Rapture Cores (call on boss defeat)
func add_pristine_cores(amount: int) -> void:
	pristine_rapture_cores += amount
	print("[GameState] +%d Pristine Rapture Core(s)! Total: %d" % [amount, pristine_rapture_cores])
	_save_leaderboard()

## Spend Pristine Rapture Cores (returns true if successful)
func spend_pristine_cores(amount: int) -> bool:
	if pristine_rapture_cores >= amount:
		pristine_rapture_cores -= amount
		print("[GameState] Spent %d Pristine Rapture Core(s). Remaining: %d" % [amount, pristine_rapture_cores])
		_save_leaderboard()
		return true
	return false

## Get current Pristine Rapture Core count
func get_pristine_cores() -> int:
	return pristine_rapture_cores


# --- Persistence ---

func _save_leaderboard() -> void:
	var config := ConfigFile.new()
	
	config.set_value("stats", "total_score", _total_score_all_time)
	config.set_value("stats", "pristine_rapture_cores", pristine_rapture_cores)
	
	for char_id in _leaderboard_data:
		var data: Dictionary = _leaderboard_data[char_id]
		config.set_value("characters", char_id + "_best_score", data.get("best_score", 0))
		config.set_value("characters", char_id + "_best_wave", data.get("best_wave", 0))
		config.set_value("characters", char_id + "_total_runs", data.get("total_runs", 0))
	
	var err := config.save(LEADERBOARD_PATH)
	if err == OK:
		print("[GameState] Leaderboard saved")
	else:
		push_error("[GameState] Failed to save leaderboard: " + str(err))


func _load_leaderboard() -> void:
	var config := ConfigFile.new()
	var err := config.load(LEADERBOARD_PATH)
	
	if err != OK:
		print("[GameState] No leaderboard file found, starting fresh")
		return
	
	_total_score_all_time = config.get_value("stats", "total_score", 0)
	pristine_rapture_cores = config.get_value("stats", "pristine_rapture_cores", 0)
	
	# Load character data
	_leaderboard_data.clear()
	
	# Find all character keys
	var keys: PackedStringArray = config.get_section_keys("characters") if config.has_section("characters") else PackedStringArray()
	var processed_chars: Dictionary = {}
	
	for key in keys:
		# Keys are like "scarlet_best_score", extract character id
		var parts := key.rsplit("_", true, 2)  # Split from right, max 2 splits
		if parts.size() >= 3:
			var char_id := parts[0]
			for i in range(1, parts.size() - 2):
				char_id += "_" + parts[i]
			
			if not processed_chars.has(char_id):
				processed_chars[char_id] = true
				_leaderboard_data[char_id] = {
					"best_score": config.get_value("characters", char_id + "_best_score", 0),
					"best_wave": config.get_value("characters", char_id + "_best_wave", 0),
					"total_runs": config.get_value("characters", char_id + "_total_runs", 0)
				}
	
	print("[GameState] Leaderboard loaded: %d characters, total score: %d, cores: %d" % [_leaderboard_data.size(), _total_score_all_time, pristine_rapture_cores])

## Set the 3 characters selected for this run
## @param indices: Array of 3 character registry indices
func set_selected_characters(indices: Array[int]) -> void:
	if indices.size() != 3:
		push_warning("GameState: Expected 3 character indices, got %d" % indices.size())
		return
	selected_character_indices = indices.duplicate()
	print("GameState: Selected characters set to indices: ", selected_character_indices)

## Get the 3 selected character indices for shop display
## Returns order: [Support1, Main, Support2] for left, center, right display
func get_shop_character_order() -> Array[int]:
	# selected_character_indices is [Main, Support1, Support2]
	# Shop wants: [Support1, Main, Support2] = left, center, right
	if selected_character_indices.size() >= 3:
		return [selected_character_indices[1], selected_character_indices[0], selected_character_indices[2]]
	return selected_character_indices.duplicate()

## Get the main character index (first selected, center in shop)
func get_main_character() -> int:
	if selected_character_indices.size() > 0:
		return selected_character_indices[0]
	return 0

## Set which character the player controls
## @param index: Character registry index
func set_player_character(index: int) -> void:
	player_character_index = index

## Get the player's controlled character index
func get_player_character() -> int:
	return player_character_index

## Check if a character is in the current selection
func is_character_selected(registry_index: int) -> bool:
	return registry_index in selected_character_indices

## Get character data from registry by index
func get_character_data(registry_index: int) -> Dictionary:
	_ensure_registry()
	if _character_registry:
		var char_ids: Array = _character_registry.get_all_character_ids()
		if registry_index >= 0 and registry_index < char_ids.size():
			var char_id: String = char_ids[registry_index]
			return _character_registry.get_character(char_id)
	return {}

## Get all available characters from registry
func get_all_characters() -> Array:
	_ensure_registry()
	if _character_registry:
		var result: Array = []
		var char_ids: Array = _character_registry.get_all_character_ids()
		for i in range(char_ids.size()):
			var char_data = _character_registry.get_character(char_ids[i])
			if char_data:
				result.append({
					"index": i,
					"id": char_ids[i],
					"data": char_data
				})
		return result
	return []

## Helper to load character registry
func _ensure_registry() -> void:
	if _character_registry == null:
		_character_registry = CharacterRegistry.get_instance()

## Reset to default character selection
func reset_selection() -> void:
	selected_character_indices = [8, 9, 4]  # Cecil, Nayuta, Marian

# --- Stage Progress ---

const STAGE_PROGRESS_PATH := "user://stage_progress.cfg"

## Mark a stage as cleared (unlocks next stage)
func mark_stage_cleared(stage_id: String) -> void:
	if stage_id not in stages_cleared:
		stages_cleared.append(stage_id)
		_save_stage_progress()
		print("[GameState] Stage cleared: %s" % stage_id)

## Check if a stage has been cleared
func is_stage_cleared(stage_id: String) -> bool:
	return stage_id in stages_cleared

## Check if a stage is unlocked (prerequisite stage cleared or no prereq)
func is_stage_unlocked(stage_id: String) -> bool:
	# Use preload to access static methods without warning
	const StageReg = preload("res://scripts/systems/StageRegistry.gd")
	var stage: Dictionary = StageReg.get_stage(stage_id)
	if stage.is_empty():
		return false
	var unlock_after = stage.get("unlock_after")
	if unlock_after == null:
		return true  # No prerequisite = always unlocked
	return unlock_after in stages_cleared

## Get list of cleared stages
func get_cleared_stages() -> Array[String]:
	return stages_cleared.duplicate()

## Set current stage for the run
func set_current_stage(stage_id: String) -> void:
	current_stage_id = stage_id

## Get current stage ID
func get_current_stage() -> String:
	return current_stage_id

## Save stage progress to disk
func _save_stage_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "stages_cleared", stages_cleared)
	var err := config.save(STAGE_PROGRESS_PATH)
	if err != OK:
		push_warning("[GameState] Failed to save stage progress: %d" % err)

## Load stage progress from disk
func _load_stage_progress() -> void:
	var config := ConfigFile.new()
	var err := config.load(STAGE_PROGRESS_PATH)
	if err == OK:
		var loaded = config.get_value("progress", "stages_cleared", [])
		stages_cleared.clear()
		for stage_id in loaded:
			stages_cleared.append(stage_id)
		print("[GameState] Loaded stage progress: %s" % str(stages_cleared))
	else:
		stages_cleared.clear()
		print("[GameState] No stage progress found, starting fresh")
	player_character_index = 9  # Nayuta
