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

const SaveManagerScript = preload("res://scripts/systems/SaveManager.gd")

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
# Array of top 10 runs: [{"character_id": String, "score": int, "wave": int, "difficulty": int, "goddess_fall": bool, "timestamp": int}]
var _leaderboard_entries: Array = []
var _total_score_all_time: int = 0
var _total_runs_all_time: int = 0
const MAX_LEADERBOARD_ENTRIES := 10

# --- Meta Currency ---
# Pristine Rapture Cores - earned by defeating bosses, used in main menu shop
var pristine_rapture_cores: int = 0

# --- Stage Progress ---
# Tracks which stages have been cleared (unlocks next stage)
var stages_cleared: Array[String] = []
var current_stage_id: String = "stage_1"

# --- Map Selection ---
# Selected biome and time of day from the stage selector
var selected_biome: String = "sakura_grove"
var selected_time: String = "day"

# --- Difficulty Settings ---
# Difficulty multiplier (1-100): multiplies enemy HP and boss core drops
var difficulty_multiplier: int = 1
# Goddess Fall mode: enhanced enemy abilities, boss enrage timer
var goddess_fall_mode: bool = false


func _ready() -> void:
	# Wait for MenuManager's intro screen to render before doing heavy initialization
	# This prevents blocking the walking animation on the intro screen
	if MenuManager.intro_rendered:
		_start_async_init()
	else:
		MenuManager.intro_ready.connect(_on_intro_ready, CONNECT_ONE_SHOT)


func _on_intro_ready() -> void:
	_start_async_init()


func _start_async_init() -> void:
	# Start the async initialization coroutine
	_async_init()


func _async_init() -> void:
	# Initialize ResourceManifest - generates manifest in editor, loads in exports
	# Yield a frame to let animation continue
	await get_tree().process_frame
	ResourceManifest.ensure_initialized()
	
	# Yield another frame before next task
	await get_tree().process_frame
	_load_leaderboard()
	
	await get_tree().process_frame
	_load_stage_progress()

# --- Current Run Tracking ---

## Add score during gameplay (call when enemy dies)
func add_score(points: int) -> void:
	# Multiply score by difficulty multiplier
	var multiplied_points: int = points * difficulty_multiplier
	current_score += multiplied_points
	current_kills += 1
	
	# Track kill for achievement - get current character ID
	_track_kill_for_achievement()


## Update current wave (call from WaveDirector)
func set_current_wave(wave: int) -> void:
	current_wave = wave


# Flag to prevent recording the same run multiple times
var _run_already_recorded: bool = false

## Reset current run stats (call at start of new game)
func reset_run_stats() -> void:
	current_score = 0
	current_wave = 0
	current_kills = 0
	_run_already_recorded = false
	# Reset per-character stats tracker
	var run_stats_tracker = get_node_or_null("/root/RunStatsTracker")
	if run_stats_tracker:
		run_stats_tracker.reset()


## Get run stats data from RunStatsTracker (for leaderboard entries)
func _get_run_stats_data() -> Dictionary:
	var run_stats_tracker = get_node_or_null("/root/RunStatsTracker")
	if run_stats_tracker:
		return run_stats_tracker.get_run_stats()
	return {}


## Record the result of a completed run (call on game over)
## @param character_id: The character code/id that was played
func record_run_result(character_id: String) -> void:
	# Prevent duplicate recordings (e.g., death + quit triggers both)
	if _run_already_recorded:
		print("[GameState] Run already recorded, skipping duplicate")
		return
	_run_already_recorded = true
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
	
	# Update totals
	_total_score_all_time += current_score
	_total_runs_all_time += 1
	
	# Create new entry for this run
	var new_entry := {
		"character_id": character_id,
		"score": current_score,
		"wave": current_wave,
		"difficulty": difficulty_multiplier,
		"goddess_fall": goddess_fall_mode,
		"timestamp": int(Time.get_unix_time_from_system()),
		# NEW: Squad composition (3 character indices)
		"squad_indices": Array(selected_character_indices).duplicate(),
		# NEW: Per-character stats from RunStatsTracker
		"run_stats": _get_run_stats_data()
	}
	
	# Add to leaderboard if it qualifies (top 10 by score)
	_leaderboard_entries.append(new_entry)
	
	# Sort by score descending
	_leaderboard_entries.sort_custom(func(a, b): return a["score"] > b["score"])
	
	# Keep only top 10
	if _leaderboard_entries.size() > MAX_LEADERBOARD_ENTRIES:
		_leaderboard_entries = _leaderboard_entries.slice(0, MAX_LEADERBOARD_ENTRIES)
	
	# Check if this run made it to leaderboard
	var made_leaderboard := false
	for entry in _leaderboard_entries:
		if entry["timestamp"] == new_entry["timestamp"] and entry["score"] == new_entry["score"]:
			made_leaderboard = true
			break
	
	if made_leaderboard:
		print("[GameState] New leaderboard entry! Rank: %d" % (_leaderboard_entries.find(new_entry) + 1))
	
	_save_leaderboard()


# --- Leaderboard Queries ---

## Get leaderboard entries sorted by best score
## Returns array of dictionaries with character info, score, wave, difficulty, goddess_fall
func get_leaderboard_entries(max_count: int = 10) -> Array:
	var entries: Array = []
	
	_ensure_registry()
	
	# Build display entries from stored leaderboard data
	for run in _leaderboard_entries:
		var char_id: String = run.get("character_id", "")
		var display_name: String = char_id.capitalize().replace("-", " ").replace("_", " ")
		
		# Try to get proper display name from registry
		if _character_registry:
			var char_data = _character_registry.get_character(char_id)
			if char_data and char_data.display_name != "":
				display_name = char_data.display_name
		
		entries.append({
			"display_name": display_name,
			"code": char_id,
			"best_score": run.get("score", 0),
			"best_wave": run.get("wave", 0),
			"best_difficulty": run.get("difficulty", 1),
			"best_goddess_fall": run.get("goddess_fall", false),
			"timestamp": run.get("timestamp", 0),
			"squad_indices": run.get("squad_indices", []),
			"run_stats": run.get("run_stats", {})
		})
	
	# Already sorted, just limit to max_count
	if entries.size() > max_count:
		entries = entries.slice(0, max_count)
	
	return entries


## Reset leaderboard data (but preserve currency)
func reset_leaderboard() -> void:
	_leaderboard_entries.clear()
	_total_score_all_time = 0
	_total_runs_all_time = 0
	_save_leaderboard()
	print("[GameState] Leaderboard reset!")


## Get total score across all runs
func get_total_score() -> int:
	return _total_score_all_time


## Get best score for a specific character (highest score with that character as main)
func get_best_score(character_id: String) -> int:
	for entry in _leaderboard_entries:
		if entry.get("character_id") == character_id:
			return entry.get("score", 0)
	return 0


## Get best wave for a specific character (highest wave with that character as main)
func get_best_wave(character_id: String) -> int:
	var best_wave := 0
	for entry in _leaderboard_entries:
		if entry.get("character_id") == character_id:
			var wave: int = entry.get("wave", 0)
			if wave > best_wave:
				best_wave = wave
	return best_wave


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

## Set Pristine Rapture Cores to a specific value (for debug/reset)
func set_pristine_cores(amount: int) -> void:
	pristine_rapture_cores = amount
	print("[GameState] Set Pristine Rapture Cores to: %d" % pristine_rapture_cores)
	_save_leaderboard()


# --- Persistence ---

func _save_leaderboard() -> void:
	var config := ConfigFile.new()
	
	config.set_value("stats", "total_score", _total_score_all_time)
	config.set_value("stats", "total_runs", _total_runs_all_time)
	config.set_value("stats", "pristine_rapture_cores", pristine_rapture_cores)
	config.set_value("stats", "entry_count", _leaderboard_entries.size())
	
	# Save each leaderboard entry
	for i in range(_leaderboard_entries.size()):
		var entry: Dictionary = _leaderboard_entries[i]
		var prefix := "entry_%d_" % i
		config.set_value("leaderboard", prefix + "character_id", entry.get("character_id", ""))
		config.set_value("leaderboard", prefix + "score", entry.get("score", 0))
		config.set_value("leaderboard", prefix + "wave", entry.get("wave", 0))
		config.set_value("leaderboard", prefix + "difficulty", entry.get("difficulty", 1))
		config.set_value("leaderboard", prefix + "goddess_fall", entry.get("goddess_fall", false))
		config.set_value("leaderboard", prefix + "timestamp", entry.get("timestamp", 0))
		# NEW: Save squad and stats
		config.set_value("leaderboard", prefix + "squad_indices", entry.get("squad_indices", []))
		config.set_value("leaderboard", prefix + "run_stats", entry.get("run_stats", {}))
	
	var err := config.save(SaveManagerScript.LEADERBOARD_PATH)
	if err == OK:
		print("[GameState] Leaderboard saved (%d entries)" % _leaderboard_entries.size())
	else:
		push_error("[GameState] Failed to save leaderboard: " + str(err))


func _load_leaderboard() -> void:
	var config := ConfigFile.new()
	var err := config.load(SaveManagerScript.LEADERBOARD_PATH)
	
	if err != OK:
		print("[GameState] No leaderboard file found, starting fresh")
		return
	
	_total_score_all_time = config.get_value("stats", "total_score", 0)
	_total_runs_all_time = config.get_value("stats", "total_runs", 0)
	pristine_rapture_cores = config.get_value("stats", "pristine_rapture_cores", 0)
	
	# Load leaderboard entries
	_leaderboard_entries.clear()
	var entry_count: int = config.get_value("stats", "entry_count", 0)
	
	for i in range(entry_count):
		var prefix := "entry_%d_" % i
		var entry := {
			"character_id": config.get_value("leaderboard", prefix + "character_id", ""),
			"score": config.get_value("leaderboard", prefix + "score", 0),
			"wave": config.get_value("leaderboard", prefix + "wave", 0),
			"difficulty": config.get_value("leaderboard", prefix + "difficulty", 1),
			"goddess_fall": config.get_value("leaderboard", prefix + "goddess_fall", false),
			"timestamp": config.get_value("leaderboard", prefix + "timestamp", 0),
			# NEW: Load squad and stats
			"squad_indices": config.get_value("leaderboard", prefix + "squad_indices", []),
			"run_stats": config.get_value("leaderboard", prefix + "run_stats", {})
		}
		if entry["character_id"] != "":
			_leaderboard_entries.append(entry)
	
	# Ensure sorted by score
	_leaderboard_entries.sort_custom(func(a, b): return a["score"] > b["score"])
	
	print("[GameState] Leaderboard loaded: %d entries, total score: %d, total runs: %d, cores: %d" % [_leaderboard_entries.size(), _total_score_all_time, _total_runs_all_time, pristine_rapture_cores])

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
	print("[GameState] set_player_character called with index: %d (was %d)" % [index, player_character_index])
	var old_index := player_character_index
	player_character_index = index
	# Emit to EventBus for stats tracking
	if EventBus and old_index != index:
		# slot_index is unknown here, but the character_id (registry index) is what matters
		EventBus.character_switched.emit(-1, index)

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
	var err := config.save(SaveManagerScript.STAGE_PROGRESS_PATH)
	if err != OK:
		push_warning("[GameState] Failed to save stage progress: %d" % err)

## Load stage progress from disk
func _load_stage_progress() -> void:
	var config := ConfigFile.new()
	var err := config.load(SaveManagerScript.STAGE_PROGRESS_PATH)
	if err == OK:
		var loaded = config.get_value("progress", "stages_cleared", [])
		stages_cleared.clear()
		for stage_id in loaded:
			stages_cleared.append(stage_id)
		print("[GameState] Loaded stage progress: %s" % str(stages_cleared))
	else:
		stages_cleared.clear()


# --- Achievement Tracking Helpers ---

## Track kill for the current active character (called from add_score)
func _track_kill_for_achievement() -> void:
	_ensure_registry()
	if not _character_registry:
		return
	
	# Get the character ID from the current player character index
	var char_ids: Array = _character_registry.get_all_character_ids()
	if player_character_index >= 0 and player_character_index < char_ids.size():
		var char_id: String = char_ids[player_character_index]
		if has_node("/root/AchievementManager"):
			get_node("/root/AchievementManager").on_enemy_killed(char_id)
