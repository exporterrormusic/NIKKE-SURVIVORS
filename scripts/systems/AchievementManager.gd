extends Node

## Global achievement tracking system.
## Tracks character-specific achievements: unlocks, kills, skill purchases, wins.
## Saves/loads achievement data to persistent storage.
## Accessed as autoload: /root/AchievementManager

# Removed SaveManagerScript preload - now using global SaveManager autoload

signal achievement_unlocked(achievement_id: String, achievement_data: Dictionary)

# Character data loaded from CharacterRegistry (single source of truth)
var _registry: CharacterRegistry = null

# Kill milestone for achievement
const KILL_MILESTONE := 10000

# Total skill purchases per character to max tree
# 7 nodes but special upgrades have max level 3: unlock(1) + special(1) + 2x special_upgrades(3+3) + burst(1) + 2x burst_upgrades(1+1) = 11
const SKILL_PURCHASES_PER_CHARACTER := 11

# Achievement types
enum AchievementType {
	SHOP_UNLOCK, # Unlock character in shop
	KILL_COUNT, # Kill 10,000 Raptures as character
	ALL_SKILLS, # Purchase all skills in a single match
	WIN_GAME, # Win a game with character in squad
	# General Achievements
	MASSACRE, # Kill 50,000 Raptures total
	BOSS_SLAYER, # Defeat a boss enemy
	FIRST_BLOOD, # Complete a Stage 1 map
	NO_DAMAGE, # Complete a wave without taking damage
	ALL_MAPS, # Play on all maps
	ABANDONED_WISHES, # Reach Wave 10
	SHE_DESCENDS # Spawn N01
}

const GENERAL_ID := "general"
const MASSACRE_GOAL := 50000
const MAP_TARGET_COUNT := 4

# --- Persistent Data ---
# Dictionary: achievement_id -> { "unlocked": bool, "progress": int, "unlocked_at": int (timestamp) }
var _achievements: Dictionary = {}

# Runtime kill tracking (per character, resets on game end)
var _session_kills: Dictionary = {} # char_id -> kills this run

# Runtime skill tracking (per character, resets on game end)
var _session_skills: Dictionary = {} # char_index -> total skill purchases this run (int)

# Track current active character
var _current_character_id: String = ""
var _current_map_id: String = ""
var _wave_damaged: bool = false


func _ready() -> void:
	# Connect to EventBus signals for tracking
	if EventBus:
		EventBus.enemy_killed.connect(_on_enemy_killed_event)
		EventBus.character_switched.connect(_on_character_switched)
		
		# New Signals for General Achievements
		if EventBus.has_signal("run_started"):
			EventBus.run_started.connect(_on_run_started)
		if EventBus.has_signal("run_completed"):
			EventBus.run_completed.connect(_on_run_completed)
		if EventBus.has_signal("wave_started"):
			EventBus.wave_started.connect(_on_wave_started)
		if EventBus.has_signal("wave_completed"):
			EventBus.wave_completed.connect(_on_wave_completed)
		if EventBus.has_signal("biome_changed"):
			EventBus.biome_changed.connect(_on_biome_changed)
		if EventBus.has_signal("player_damaged"):
			EventBus.player_damaged.connect(_on_player_damaged)
		if EventBus.has_signal("boss_spawned"):
			EventBus.boss_spawned.connect(_on_boss_spawned)
	
	# Wait for MenuManager's intro screen to render before doing heavy initialization
	# CharacterRegistry has many preloads that cascade to other scripts
	if MenuManager.intro_rendered:
		_async_init()
	else:
		MenuManager.intro_ready.connect(_on_intro_ready, CONNECT_ONE_SHOT)


func _on_intro_ready() -> void:
	_async_init()


func _async_init() -> void:
	# Yield a frame to let animation continue
	await get_tree().process_frame
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		_registry = game_manager.get_character_registry()
	else:
		_registry = CharacterRegistry.get_instance()
	
	await get_tree().process_frame
	_load_achievements()


func _ensure_registry() -> void:
	# Ensure registry is loaded if accessed before deferred init completed
	if _registry == null:
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager:
			_registry = game_manager.get_character_registry()
		else:
			_registry = CharacterRegistry.get_instance()


# --- Achievement Definition Helpers ---

## Get display name for a character
func get_character_display_name(char_id: String) -> String:
	_ensure_registry()
	return _registry.get_character_name(char_id)


## Get achievement ID for a specific type and character
func get_achievement_id(type: AchievementType, char_id: String) -> String:
	match type:
		AchievementType.SHOP_UNLOCK:
			return "unlock_%s" % char_id
		AchievementType.KILL_COUNT:
			return "kills_%s" % char_id
		AchievementType.ALL_SKILLS:
			return "all_skills_%s" % char_id
		AchievementType.WIN_GAME:
			return "win_%s" % char_id
		AchievementType.MASSACRE:
			return "kill_50000"
		AchievementType.BOSS_SLAYER:
			return "boss_slayer"
		AchievementType.FIRST_BLOOD:
			return "first_blood"
		AchievementType.NO_DAMAGE:
			return "no_damage"
		AchievementType.ALL_MAPS:
			return "all_maps"
		AchievementType.ABANDONED_WISHES:
			return "abandoned_wishes"
		AchievementType.SHE_DESCENDS:
			return "she_descends"
	return ""


## Get all achievements for a character
func get_character_achievements(char_id: String) -> Array[Dictionary]:
	var achievements: Array[Dictionary] = []
	
	# General Achievements
	if char_id == GENERAL_ID:
		# Massacre
		var massacre_id := get_achievement_id(AchievementType.MASSACRE, "")
		var massacre_data: Dictionary = _achievements.get(massacre_id, {"unlocked": false, "progress": 0})
		achievements.append({
			"id": massacre_id,
			"title": "Massacre",
			"desc": "Defeat %s enemies total" % _format_number(MASSACRE_GOAL),
			"category": "GENERAL",
			"unlocked": massacre_data.get("unlocked", false),
			"progress": massacre_data.get("progress", 0),
			"target": MASSACRE_GOAL
		})
		
		# Boss Slayer
		var boss_id := get_achievement_id(AchievementType.BOSS_SLAYER, "")
		var boss_data: Dictionary = _achievements.get(boss_id, {"unlocked": false, "progress": 0})
		achievements.append({
			"id": boss_id,
			"title": "Boss Slayer",
			"desc": "Defeat a boss enemy",
			"category": "GENERAL",
			"unlocked": boss_data.get("unlocked", false),
			"progress": boss_data.get("progress", 0),
			"target": 1
		})
		
		# First Blood
		var fb_id := get_achievement_id(AchievementType.FIRST_BLOOD, "")
		var fb_data: Dictionary = _achievements.get(fb_id, {"unlocked": false, "progress": 0})
		achievements.append({
			"id": fb_id,
			"title": "First Blood",
			"desc": "Complete a Stage 1 map",
			"category": "GENERAL",
			"unlocked": fb_data.get("unlocked", false),
			"progress": fb_data.get("progress", 0),
			"target": 1
		})
		
		# No Damage
		var nd_id := get_achievement_id(AchievementType.NO_DAMAGE, "")
		var nd_data: Dictionary = _achievements.get(nd_id, {"unlocked": false, "progress": 0})
		achievements.append({
			"id": nd_id,
			"title": "Untouchable",
			"desc": "Complete a wave without taking damage",
			"category": "GENERAL",
			"unlocked": nd_data.get("unlocked", false),
			"progress": nd_data.get("progress", 0),
			"target": 1
		})
		
		# All Maps
		var am_id := get_achievement_id(AchievementType.ALL_MAPS, "")
		var am_data: Dictionary = _achievements.get(am_id, {"unlocked": false, "progress": 0})
		achievements.append({
			"id": am_id,
			"title": "World Traveler",
			"desc": "Play on all maps",
			"category": "GENERAL",
			"unlocked": am_data.get("unlocked", false),
			"progress": am_data.get("progress", 0),
			"target": MAP_TARGET_COUNT
		})
		
		# Abandoned Wishes
		var aw_id := get_achievement_id(AchievementType.ABANDONED_WISHES, "")
		var aw_data: Dictionary = _achievements.get(aw_id, {"unlocked": false, "progress": 0})
		achievements.append({
			"id": aw_id,
			"title": "Abandoned Wishes",
			"desc": "Reach Wave 10",
			"category": "GENERAL",
			"unlocked": aw_data.get("unlocked", false),
			"progress": aw_data.get("progress", 0),
			"target": 1
		})
		
		# She Descends
		var sd_id := get_achievement_id(AchievementType.SHE_DESCENDS, "")
		var sd_data: Dictionary = _achievements.get(sd_id, {"unlocked": false, "progress": 0})
		achievements.append({
			"id": sd_id,
			"title": "She Descends",
			"desc": "Spawn N01",
			"category": "GENERAL",
			"unlocked": sd_data.get("unlocked", false),
			"progress": sd_data.get("progress", 0),
			"target": 1
		})
		
		return achievements

	var display_name := get_character_display_name(char_id)
	
	# Unlock achievement (only for non-default characters)
	if char_id not in CharacterRegistry.DEFAULT_UNLOCKED:
		var unlock_id := get_achievement_id(AchievementType.SHOP_UNLOCK, char_id)
		var unlock_data: Dictionary = _achievements.get(unlock_id, {"unlocked": false, "progress": 0})
		achievements.append({
			"id": unlock_id,
			"title": "Unlock %s in SHOP" % display_name,
			"desc": "Unlock %s using Pristine Rapture Cores in the main menu shop" % display_name,
			"category": char_id,
			"unlocked": unlock_data.get("unlocked", false),
			"progress": unlock_data.get("progress", 0),
			"target": 1
		})
	
	# Kill achievement
	var kill_id := get_achievement_id(AchievementType.KILL_COUNT, char_id)
	var kill_data: Dictionary = _achievements.get(kill_id, {"unlocked": false, "progress": 0})
	achievements.append({
		"id": kill_id,
		"title": "Kill 10,000 Raptures as %s" % display_name,
		"desc": "Defeat 10,000 enemies while playing as %s" % display_name,
		"category": char_id,
		"unlocked": kill_data.get("unlocked", false),
		"progress": kill_data.get("progress", 0),
		"target": KILL_MILESTONE
	})
	
	# All skills achievement
	var skills_id := get_achievement_id(AchievementType.ALL_SKILLS, char_id)
	var skills_data: Dictionary = _achievements.get(skills_id, {"unlocked": false, "progress": 0})
	achievements.append({
		"id": skills_id,
		"title": "Purchase all skills for %s" % display_name,
		"desc": "Buy all %d skill nodes for %s during a single match" % [SKILL_PURCHASES_PER_CHARACTER, display_name],
		"category": char_id,
		"unlocked": skills_data.get("unlocked", false),
		"progress": skills_data.get("progress", 0),
		"target": 1
	})
	
	# Win achievement
	var win_id := get_achievement_id(AchievementType.WIN_GAME, char_id)
	var win_data: Dictionary = _achievements.get(win_id, {"unlocked": false, "progress": 0})
	achievements.append({
		"id": win_id,
		"title": "Win a game with %s" % display_name,
		"desc": "Complete a run with %s in your squad" % display_name,
		"category": char_id,
		"unlocked": win_data.get("unlocked", false),
		"progress": win_data.get("progress", 0),
		"target": 1
	})
	
	return achievements


## Get all achievements across all characters
func get_all_achievements() -> Array[Dictionary]:
	_ensure_registry()
	var all: Array[Dictionary] = []
	
	# Add General Achievements first
	all.append_array(get_character_achievements(GENERAL_ID))
	
	var char_ids := _registry.get_all_character_ids()
	for char_id in char_ids:
		all.append_array(get_character_achievements(char_id))
	return all


## Check if achievement is unlocked
func is_achievement_unlocked(achievement_id: String) -> bool:
	return _achievements.get(achievement_id, {}).get("unlocked", false)


## Get achievement progress (0 to target)
func get_achievement_progress(achievement_id: String) -> int:
	return _achievements.get(achievement_id, {}).get("progress", 0)


## Get achievement data
func get_achievement_data(achievement_id: String) -> Dictionary:
	return _achievements.get(achievement_id, {"unlocked": false, "progress": 0})


# --- Tracking Functions ---

## Call when a character is unlocked in the shop
func on_character_unlocked_in_shop(char_id: String) -> void:
	if char_id in CharacterRegistry.DEFAULT_UNLOCKED:
		return # No achievement for default characters
	
	var achievement_id := get_achievement_id(AchievementType.SHOP_UNLOCK, char_id)
	_unlock_achievement(achievement_id, char_id, AchievementType.SHOP_UNLOCK)


## Call when an enemy is killed (pass the current active character id)
func on_enemy_killed(char_id: String) -> void:
	if char_id.is_empty():
		return
	
	var achievement_id := get_achievement_id(AchievementType.KILL_COUNT, char_id)
	
	# Initialize if needed
	if not _achievements.has(achievement_id):
		_achievements[achievement_id] = {"unlocked": false, "progress": 0}
	
	# Increment progress
	_achievements[achievement_id]["progress"] += 1
	var progress: int = _achievements[achievement_id]["progress"]
	
	# Check for milestone
	if progress >= KILL_MILESTONE and not _achievements[achievement_id].get("unlocked", false):
		_unlock_achievement(achievement_id, char_id, AchievementType.KILL_COUNT)
	
	# Save periodically (every 100 kills to avoid too many writes)
	if progress % 100 == 0:
		_save_achievements()


## Call when a skill is purchased in talent tree (char_id is registry string ID, skill_id is the talent id)
func on_skill_purchased(char_id, _skill_id: String) -> void:
	_ensure_registry()
	
	# Handle both String (from TalentTree) and int (legacy) calls
	var char_index: int = -1
	if char_id is String:
		char_index = _registry.get_character_index(char_id)
	elif char_id is int:
		char_index = char_id
	
	var char_count := _registry.get_character_count()
	if char_index < 0 or char_index >= char_count:
		print("[AchievementManager] Invalid char_id for skill purchase: %s" % str(char_id))
		return
	
	# Initialize skill counter if not exists, pre-crediting squad members with their unlock
	if not _session_skills.has(char_index):
		_session_skills[char_index] = _get_initial_skill_credit(char_index)
	
	_session_skills[char_index] += 1
	
	# Check if all skills are now purchased (11 total points to max a tree)
	var skills_count: int = _session_skills[char_index]
	print("[AchievementManager] Character %s (idx %d) now has %d/%d skills" % [str(char_id), char_index, skills_count, SKILL_PURCHASES_PER_CHARACTER])
	
	if skills_count >= SKILL_PURCHASES_PER_CHARACTER:
		var resolved_char_id: String = _registry.get_character_id(char_index)
		var achievement_id := get_achievement_id(AchievementType.ALL_SKILLS, resolved_char_id)
		_unlock_achievement(achievement_id, resolved_char_id, AchievementType.ALL_SKILLS)


## Get initial skill credit for a character (1 if they're in the selected squad, 0 otherwise)
func _get_initial_skill_credit(char_index: int) -> int:
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.selected_character_indices:
		if char_index in game_manager.selected_character_indices:
			print("[AchievementManager] Character %d is in squad, pre-crediting unlock skill" % char_index)
			return 1 # They start with unlock already purchased
	return 0


## Call when a game is won (pass array of squad character IDs)
func on_game_won(squad_char_ids: Array) -> void:
	_ensure_registry()
	var all_char_ids := _registry.get_all_character_ids()
	for char_id in squad_char_ids:
		if char_id is String and char_id in all_char_ids:
			var achievement_id := get_achievement_id(AchievementType.WIN_GAME, char_id)
			_unlock_achievement(achievement_id, char_id, AchievementType.WIN_GAME)


## Reset session tracking (call at start of each game)
func reset_session() -> void:
	_session_kills.clear()
	_session_skills.clear()
	print("[AchievementManager] Session tracking reset")


# --- Internal Helpers ---

func _unlock_achievement(achievement_id: String, char_id: String, type: AchievementType) -> void:
	if _achievements.get(achievement_id, {}).get("unlocked", false):
		return # Already unlocked
	
	# Initialize if needed
	if not _achievements.has(achievement_id):
		_achievements[achievement_id] = {"unlocked": false, "progress": 0}
	
	_achievements[achievement_id]["unlocked"] = true
	_achievements[achievement_id]["progress"] = _get_target_for_type(type)
	_achievements[achievement_id]["unlocked_at"] = int(Time.get_unix_time_from_system())
	
	var display_name := get_character_display_name(char_id)
	var title := _get_achievement_title(type, display_name)
	
	print("[AchievementManager] ACHIEVEMENT UNLOCKED: %s" % title)
	
	_save_achievements()
	
	# Emit signal for UI notification
	emit_signal("achievement_unlocked", achievement_id, {
		"title": title,
		"character": display_name,
		"type": type
	})


func _get_target_for_type(type: AchievementType) -> int:
	match type:
		AchievementType.SHOP_UNLOCK:
			return 1
		AchievementType.KILL_COUNT:
			return KILL_MILESTONE
		AchievementType.ALL_SKILLS:
			return 1
		AchievementType.WIN_GAME:
			return 1
		AchievementType.MASSACRE:
			return MASSACRE_GOAL
		AchievementType.BOSS_SLAYER:
			return 1
		AchievementType.FIRST_BLOOD:
			return 1
		AchievementType.NO_DAMAGE:
			return 1
		AchievementType.ALL_MAPS:
			return MAP_TARGET_COUNT
		AchievementType.ABANDONED_WISHES:
			return 1
		AchievementType.SHE_DESCENDS:
			return 1
	return 1


func _get_achievement_title(type: AchievementType, display_name: String) -> String:
	match type:
		AchievementType.SHOP_UNLOCK:
			return "Unlock %s in SHOP" % display_name
		AchievementType.KILL_COUNT:
			return "Kill 10,000 Raptures as %s" % display_name
		AchievementType.ALL_SKILLS:
			return "Purchase all skills for %s" % display_name
		AchievementType.WIN_GAME:
			return "Win a game with %s" % display_name
		AchievementType.MASSACRE:
			return "Massacre"
		AchievementType.BOSS_SLAYER:
			return "Boss Slayer"
		AchievementType.FIRST_BLOOD:
			return "First Blood"
		AchievementType.NO_DAMAGE:
			return "Untouchable"
		AchievementType.ALL_MAPS:
			return "World Traveler"
		AchievementType.ABANDONED_WISHES:
			return "Abandoned Wishes"
		AchievementType.SHE_DESCENDS:
			return "She Descends"
	return "Unknown Achievement"


# --- Event Handlers ---

func _on_character_switched(slot_idx: int, char_index: int) -> void:
	# Update current character ID for tracking
	_ensure_registry()
	if _registry:
		_current_character_id = _registry.get_character_id(char_index)


func _on_enemy_killed_event(enemy: Node, killer_source: String) -> void:
	# Ignore if not killed by player
	if killer_source not in ["player", "projectile", "summon", "cecil_drone"]:
		return
	
	# Track general kills (Massacre)
	_track_massacre_progress()
	
	# Track boss kill (Boss Slayer)
	if enemy.is_in_group("boss") or enemy.is_in_group("super_boss"):
		_unlock_achievement(get_achievement_id(AchievementType.BOSS_SLAYER, ""), "", AchievementType.BOSS_SLAYER)
	
	# Ensure we have a valid character ID (fallback to current squad's first character)
	if _current_character_id.is_empty():
		_ensure_registry()
		var game_manager = get_node_or_null("/root/GameManager")
		if game_manager and game_manager.selected_character_indices.size() > 0:
			var first_idx = game_manager.selected_character_indices[0]
			if _registry:
				_current_character_id = _registry.get_character_id(first_idx)
		print("[AchievementManager] Fallback character ID: %s" % _current_character_id)
	
	# Track per-character kills
	if not _current_character_id.is_empty():
		on_enemy_killed(_current_character_id)


func _on_run_started(map_id: String) -> void:
	_current_map_id = map_id
	_wave_damaged = false


func _on_run_completed(is_win: bool, map_id: String, _duration: float) -> void:
	# Track first blood (Stage 1)
	if is_win and map_id == "stage_1":
		_unlock_achievement(get_achievement_id(AchievementType.FIRST_BLOOD, ""), "", AchievementType.FIRST_BLOOD)
		
func _on_biome_changed(biome_id: StringName) -> void:
	# Track biome for World Traveler (Play on all environments)
	_track_world_traveler_progress(str(biome_id))


func _on_wave_started(wave_number: int) -> void:
	_wave_damaged = false
	# Track "Abandoned Wishes" - Reach Wave 10
	_track_abandoned_wishes(wave_number)


func _on_wave_completed(_wave_number: int) -> void:
	if not _wave_damaged:
		_unlock_achievement(get_achievement_id(AchievementType.NO_DAMAGE, ""), "", AchievementType.NO_DAMAGE)


func _on_player_damaged(_amount: int, _source: Node) -> void:
	_wave_damaged = true


func _on_boss_spawned(boss: Node) -> void:
	# Check if this is N01 (Rapture Queen) - triggers "She Descends" achievement
	if boss and (boss.name.contains("N01") or boss.name.contains("RaptureQueen") or boss.is_in_group("super_boss")):
		print("[AchievementManager] N01 spawned! Unlocking She Descends achievement")
		_unlock_achievement(get_achievement_id(AchievementType.SHE_DESCENDS, ""), "", AchievementType.SHE_DESCENDS)


func _track_abandoned_wishes(wave_number: int) -> void:
	# "Abandoned Wishes" - Reach Wave 10
	if wave_number >= 10:
		_unlock_achievement(get_achievement_id(AchievementType.ABANDONED_WISHES, ""), "", AchievementType.ABANDONED_WISHES)

func _track_massacre_progress() -> void:
	var achievement_id := get_achievement_id(AchievementType.MASSACRE, "")
	if not _achievements.has(achievement_id):
		_achievements[achievement_id] = {"unlocked": false, "progress": 0}
	
	_achievements[achievement_id]["progress"] += 1
	var progress: int = _achievements[achievement_id]["progress"]
	
	if progress >= MASSACRE_GOAL and not _achievements[achievement_id].get("unlocked", false):
		_unlock_achievement(achievement_id, "", AchievementType.MASSACRE)
	
	if progress % 100 == 0:
		_save_achievements()


func _track_world_traveler_progress(biome_id: String) -> void:
	var achievement_id := get_achievement_id(AchievementType.ALL_MAPS, "")
	if not _achievements.has(achievement_id):
		_achievements[achievement_id] = {"unlocked": false, "progress": 0, "biomes_played": []}
	
	# Check if using legacy key "maps_played" and migrate if needed
	if _achievements[achievement_id].has("maps_played"):
		_achievements[achievement_id]["biomes_played"] = _achievements[achievement_id]["maps_played"]
		_achievements[achievement_id].erase("maps_played")
	
	var played_biomes: Array = _achievements[achievement_id].get("biomes_played", [])
	if biome_id not in played_biomes:
		played_biomes.append(biome_id)
		_achievements[achievement_id]["biomes_played"] = played_biomes
		_achievements[achievement_id]["progress"] = played_biomes.size()
		
		print("[AchievementManager] World Traveler progress: Visited %s (%d/%d)" % [biome_id, played_biomes.size(), MAP_TARGET_COUNT])
		
		if played_biomes.size() >= MAP_TARGET_COUNT:
			_unlock_achievement(achievement_id, "", AchievementType.ALL_MAPS)
		
		_save_achievements()


func _format_number(value: int) -> String:
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return result


# --- Persistence ---

func _load_achievements() -> void:
	var data := SaveManager.load_config(SaveManager.ACHIEVEMENTS_PATH)
	
	if not data.is_empty():
		var achievements_data = data.get("achievements", {})
		if achievements_data is Dictionary:
			for key in achievements_data:
				_achievements[key] = achievements_data[key]
		print("[AchievementManager] Loaded %d achievements" % _achievements.size())
	else:
		print("[AchievementManager] No save file found, starting fresh")


func _save_achievements() -> void:
	var data := {
		"achievements": _achievements
	}
	
	var err := SaveManager.save_config(data, SaveManager.ACHIEVEMENTS_PATH)
	if err == OK:
		print("[AchievementManager] Saved %d achievements" % _achievements.size())
	else:
		push_error("[AchievementManager] Failed to save achievements: " + str(err))


# --- Stats Summary ---

## Get total unlocked achievements count
func get_unlocked_count() -> int:
	_ensure_registry()
	var count := 0
	var char_ids := _registry.get_all_character_ids()
	for char_id in char_ids:
		var achievements := get_character_achievements(char_id)
		for ach in achievements:
			if ach.get("unlocked", false):
				count += 1
	return count


## Get total achievements count
func get_total_count() -> int:
	_ensure_registry()
	var count := 0
	var char_ids := _registry.get_all_character_ids()
	for char_id in char_ids:
		count += get_character_achievements(char_id).size()
	return count
