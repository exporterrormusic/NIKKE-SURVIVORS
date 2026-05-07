extends Node
## Central game state manager - handles scores, progression, stage tracking.
## Consolidates: GameState + RunStatsTracker + ResourceManifest logic.

# --- Signals ---
signal core_count_changed(new_total: int)
signal stage_unlocked(stage_id: String)
signal wave_started(wave_num: int)

# --- Character Selection ---
var selected_character_indices: Array[int] = [8, 9, 4] # Default: Cecil, Nayuta, Marian
var player_character_index: int = 9 # Index into registry
var _character_registry = null

# --- Current Run Stats ---
var current_score: int = 0
var current_wave: int = 0
var current_kills: int = 0
var run_time: float = 0.0

# Per-character stats for the run
var damage_by_character: Dictionary = {}
var kills_by_character: Dictionary = {}
var boss_kills_by_character: Dictionary = {}

# --- Global Progression ---
var pristine_rapture_cores: int = 0
var stages_cleared: Array[String] = []
var _total_score_all_time: int = 0
var _total_runs_all_time: int = 0
var skill_points: int = 0 # Persistent skill points for Talent Tree

func add_skill_points(amount: int) -> void:
	skill_points += amount
	print("[GameManager] Added %d skill points. Total: %d" % [amount, skill_points])

func get_skill_points() -> int:
	return skill_points

func spend_skill_points(amount: int) -> bool:
	if skill_points >= amount:
		skill_points -= amount
		return true
	return false

# --- Difficulty & Modes ---
var difficulty_multiplier: float = 1.0
var goddess_fall_mode: bool = false
var she_descends_mode: bool = false
var enemy_time_scale: float = 1.0

# --- Map/Biome Selection ---
var selected_biome: String = "sakura_grove"
var selected_time: String = "day"
var current_stage_id: String = "stage_1"

# --- Leaderboard Data ---
var _leaderboard_entries: Array = []
const MAX_LEADERBOARD_ENTRIES := 10

# --- Internal State ---
var _run_already_recorded: bool = false
var match_tainted: bool = false # Set true if cheats/dev menu used - blocks leaderboard/achievements

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Wait for intro or initialize immediately
	if MenuManager.intro_rendered:
		_initialize_systems()
	else:
		MenuManager.intro_ready.connect(_initialize_systems, CONNECT_ONE_SHOT)
	
	_setup_event_listeners()
	print("[GameManager] Initialized")


func _initialize_systems() -> void:
	# Load data immediately
	_load_data()
	ResourceManifest.ensure_initialized()


func _setup_event_listeners() -> void:
	if EventBus:
		EventBus.damage_dealt.connect(_on_damage_dealt)
		EventBus.enemy_killed.connect(_on_enemy_killed)
		EventBus.character_switched.connect(_on_character_switched)


func _process(delta: float) -> void:
	if current_wave > 0:
		run_time += delta


# --- Run Management ---

func reset_run_stats() -> void:
	current_score = 0
	current_wave = 0
	current_kills = 0
	run_time = 0.0
	damage_by_character.clear()
	kills_by_character.clear()
	boss_kills_by_character.clear()
	_run_already_recorded = false
	match_tainted = false # Reset tainted flag for new run
	
	# Initialize stats for current squad
	for char_idx in selected_character_indices:
		damage_by_character[char_idx] = 0
		kills_by_character[char_idx] = 0
		boss_kills_by_character[char_idx] = 0
	
	print("[GameManager] Run stats reset")


## Mark current match as tainted (cheats/dev menu used) - blocks leaderboard and achievements
func taint_match(reason: String = "") -> void:
	if not match_tainted:
		match_tainted = true
		var msg := "[GameManager] Match TAINTED - leaderboard and achievements disabled"
		if reason != "":
			msg += " (Reason: %s)" % reason
		print(msg)


func add_score(amount: int) -> void:
	current_score += int(amount * difficulty_multiplier)


func set_current_wave(wave: int) -> void:
	current_wave = wave
	wave_started.emit(wave)


# --- Event Handlers (from RunStatsTracker) ---

func _get_source_character_index(source: String) -> int:
	# Default to current player if source is generic
	if source in ["player", "projectile", "unknown", "burn_dot"]:
		return player_character_index
	
	# Check if source matches a squad member's weapon ID
	_ensure_registry()
	if _character_registry:
		for char_idx in selected_character_indices:
			# Get character ID from index
			var all_ids = _character_registry.get_all_character_ids()
			if char_idx >= 0 and char_idx < all_ids.size():
				var char_id = all_ids[char_idx]
				var char_data = _character_registry.get_character(char_id)
				if char_data:
					# Check main weapon ID
					if char_data.get("weapon_id") == source:
						return char_idx
					# Check character-specific sources (e.g. "scarlet_burn", "snow_white_trail")
					if source.begins_with(char_id):
						return char_idx
	
	# Fallback to current player
	return player_character_index

func _on_damage_dealt(target: Node, info: Variant) -> void:
	if not target or not target.is_in_group("enemies"):
		return
		
	var dmg := 0
	var source := "unknown"
	
	if info is Dictionary:
		dmg = info.get("amount", 0)
		source = info.get("source", "unknown")
	elif info != null and "amount" in info:
		dmg = info.amount
		# Try to get source from object property if available
		if "source" in info:
			source = info.source
	
	var char_idx = _get_source_character_index(source)
	damage_by_character[char_idx] = damage_by_character.get(char_idx, 0) + dmg


func _on_enemy_killed(enemy: Node, killer_source: String) -> void:
	# Allow custom sources now that we track them
	# if killer_source not in ["player", "projectile", "summon", "cecil_drone"]:
	# 	return
	current_kills += 1
	var char_idx = _get_source_character_index(killer_source)
	
	kills_by_character[char_idx] = kills_by_character.get(char_idx, 0) + 1
	
	if enemy and (enemy.is_in_group("boss") or enemy.is_in_group("super_boss")):
		boss_kills_by_character[char_idx] = boss_kills_by_character.get(char_idx, 0) + 1


func _on_character_switched(_slot: int, registry_index: int) -> void:
	player_character_index = registry_index


# --- Getters for Run Stats (RunStatsTracker Compatibility) ---

func get_character_damage(char_id: int) -> int:
	return damage_by_character.get(char_id, 0)


# --- Currency Management ---

func get_pristine_cores() -> int:
	return pristine_rapture_cores


func add_pristine_cores(amount: int) -> void:
	if amount <= 0: return
	
	pristine_rapture_cores += amount
	emit_signal("core_count_changed", pristine_rapture_cores)
	save_game() # Autosave on currency gain
	print("[GameManager] Added %d cores. Total: %d" % [amount, pristine_rapture_cores])


func spend_pristine_cores(amount: int) -> bool:
	if amount <= 0: return false
	
	if pristine_rapture_cores >= amount:
		pristine_rapture_cores -= amount
		emit_signal("core_count_changed", pristine_rapture_cores)
		save_game() # Autosave on spend
		print("[GameManager] Spent %d cores. Remaining: %d" % [amount, pristine_rapture_cores])
		return true
	
	print("[GameManager] Failed to spend %d cores. Have: %d" % [amount, pristine_rapture_cores])
	return false


func get_character_kills(char_id: int) -> int:
	return kills_by_character.get(char_id, 0)


func get_character_boss_kills(char_id: int) -> int:
	return boss_kills_by_character.get(char_id, 0)


func get_total_damage() -> int:
	var total := 0
	for dmg in damage_by_character.values():
		total += dmg
	return total


func get_total_kills() -> int:
	var total := 0
	for k in kills_by_character.values():
		total += k
	return total


func get_total_boss_kills() -> int:
	var total := 0
	for k in boss_kills_by_character.values():
		total += k
	return total


func get_run_stats() -> Dictionary:
	return {
		"damage_by_character": damage_by_character.duplicate(),
		"normal_kills_by_character": kills_by_character.duplicate(),
		"boss_kills_by_character": boss_kills_by_character.duplicate()
	}


func record_run_result(character_id: String = "") -> void:
	if _run_already_recorded:
		return
	_run_already_recorded = true
	
	# Skip leaderboard if match is tainted (cheats used)
	if match_tainted:
		print("[GameManager] Run NOT recorded to leaderboard - match tainted (cheats/dev menu used)")
		return
	
	if character_id.is_empty():
		# Try to get character_id from player_character_index
		_ensure_registry()
		if _character_registry:
			var all_ids = _character_registry.get_all_character_ids()
			if player_character_index >= 0 and player_character_index < all_ids.size():
				character_id = all_ids[player_character_index]
	
	var new_entry := {
		"character_id": character_id,
		"score": current_score,
		"wave": current_wave,
		"difficulty": difficulty_multiplier,
		"goddess_fall": goddess_fall_mode,
		"timestamp": int(Time.get_unix_time_from_system()),
		"squad_indices": selected_character_indices.duplicate(),
		"run_stats": {
			"damage": damage_by_character.duplicate(),
			"kills": kills_by_character.duplicate(),
			"boss_kills": boss_kills_by_character.duplicate(),
			"time": run_time
		}
	}
	
	_total_score_all_time += current_score
	_total_runs_all_time += 1
	
	_leaderboard_entries.append(new_entry)
	_leaderboard_entries.sort_custom(func(a, b): return a["score"] > b["score"])
	
	if _leaderboard_entries.size() > MAX_LEADERBOARD_ENTRIES:
		_leaderboard_entries.resize(MAX_LEADERBOARD_ENTRIES)
	
	save_game()
	print("[GameManager] Run recorded: %d points, wave %d" % [current_score, current_wave])


func get_leaderboard_entries(max_count: int = 10) -> Array:
	var entries: Array = []
	_ensure_registry()
	
	for run in _leaderboard_entries:
		var char_id: String = run.get("character_id", "")
		var display_name: String = char_id.capitalize().replace("-", " ").replace("_", " ")
		
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
	
	return entries.slice(0, mini(max_count, entries.size()))


func reset_leaderboard() -> void:
	_leaderboard_entries.clear()
	_total_score_all_time = 0
	_total_runs_all_time = 0
	save_game()


func get_total_score() -> int:
	return _total_score_all_time


func get_best_score(character_id: String) -> int:
	for entry in _leaderboard_entries:
		if entry.get("character_id") == character_id:
			return entry.get("score", 0)
	return 0


func get_best_wave(character_id: String) -> int:
	var best_wave := 0
	for entry in _leaderboard_entries:
		if entry.get("character_id") == character_id:
			var wave: int = entry.get("wave", 0)
			if wave > best_wave:
				best_wave = wave
	return best_wave


# --- Stage Progression ---

func mark_stage_cleared(stage_id: String) -> void:
	if stage_id not in stages_cleared:
		stages_cleared.append(stage_id)
		save_game()


func is_stage_cleared(stage_id: String) -> bool:
	return stage_id in stages_cleared


func is_stage_unlocked(stage_id: String) -> bool:
	const StageReg = preload("res://scripts/systems/StageRegistry.gd")
	var stage: Dictionary = StageReg.get_stage(stage_id)
	if stage.is_empty():
		return false
	var unlock_after = stage.get("unlock_after")
	if unlock_after == null:
		return true
	return unlock_after in stages_cleared


func get_cleared_stages() -> Array[String]:
	return stages_cleared.duplicate()


func set_current_stage(stage_id: String) -> void:
	current_stage_id = stage_id


func get_current_stage() -> String:
	return current_stage_id


# --- Persistence ---

func _load_data() -> void:
	# Migrate legacy saves on first run with consolidated file
	SaveManager.migrate_from_legacy()
	
	# Load from consolidated single file via sections
	var lb_data := SaveManager.load_section("leaderboard")
	if not lb_data.is_empty():
		pristine_rapture_cores = lb_data.get("pristine_rapture_cores", 0)
		_total_score_all_time = lb_data.get("total_score", 0)
		_total_runs_all_time = lb_data.get("total_runs", 0)
		_load_leaderboard(lb_data)
	
	var progress_data := SaveManager.load_section("progress")
	var raw_stages = progress_data.get("stages_cleared", [])
	stages_cleared.clear()
	if typeof(raw_stages) == TYPE_ARRAY:
		for stage in raw_stages:
			stages_cleared.append(str(stage))
	
	print("[GameManager] Data loaded. Cores: %d" % pristine_rapture_cores)


func _load_leaderboard(data: Dictionary) -> void:
	_leaderboard_entries.clear()
	var entries = data.get("entries", [])
	
	if entries is Array:
		_leaderboard_entries = entries
		_leaderboard_entries.sort_custom(func(a, b): return a["score"] > b["score"])


func save_game() -> void:
	var data := {
		"pristine_rapture_cores": pristine_rapture_cores,
		"total_score": _total_score_all_time,
		"total_runs": _total_runs_all_time,
		"entries": _leaderboard_entries,
	}
	SaveManager.save_section("leaderboard", data)
	
	SaveManager.save_section("progress", {
		"stages_cleared": stages_cleared,
	})


# --- Currency Management ---

func add_cores(amount: int) -> void:
	pristine_rapture_cores += amount
	core_count_changed.emit(pristine_rapture_cores)
	save_game()


# --- Character Selection Helpers ---

func set_selected_characters(indices: Array[int]) -> void:
	if indices.size() != 3:
		return
	selected_character_indices = indices.duplicate()


func get_shop_character_order() -> Array[int]:
	if selected_character_indices.size() >= 3:
		return [selected_character_indices[1], selected_character_indices[0], selected_character_indices[2]]
	return selected_character_indices.duplicate()


func get_main_character() -> int:
	if selected_character_indices.size() > 0:
		return selected_character_indices[0]
	return 0


func set_player_character(index: int) -> void:
	player_character_index = index


func get_player_character() -> int:
	return player_character_index


func is_character_selected(registry_index: int) -> bool:
	return registry_index in selected_character_indices


func get_character_data(registry_index: int) -> Dictionary:
	_ensure_registry()
	if _character_registry:
		var char_ids: Array = _character_registry.get_all_character_ids()
		if registry_index >= 0 and registry_index < char_ids.size():
			var char_id: String = char_ids[registry_index]
			return _character_registry.get_character(char_id)
	return {}


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


func _ensure_registry() -> void:
	if _character_registry == null:
		_character_registry = CharacterRegistry.get_instance()


func reset_selection() -> void:
	selected_character_indices = [8, 9, 4]


## Get the character registry instance (cached)
func get_character_registry() -> RefCounted:
	_ensure_registry()
	return _character_registry


# --- Persistence ---
