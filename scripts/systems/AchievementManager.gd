extends Node

## Global achievement tracking system.
## Tracks character-specific achievements: unlocks, kills, skill purchases, wins.
## Saves/loads achievement data to persistent storage.
## Accessed as autoload: /root/AchievementManager

const SaveManagerScript = preload("res://scripts/systems/SaveManager.gd")

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
	SHOP_UNLOCK,      # Unlock character in shop
	KILL_COUNT,       # Kill 10,000 Raptures as character
	ALL_SKILLS,       # Purchase all skills in a single match
	WIN_GAME          # Win a game with character in squad
}

# --- Persistent Data ---
# Dictionary: achievement_id -> { "unlocked": bool, "progress": int, "unlocked_at": int (timestamp) }
var _achievements: Dictionary = {}

# Runtime kill tracking (per character, resets on game end)
var _session_kills: Dictionary = {}  # char_id -> kills this run

# Runtime skill tracking (per character, resets on game end)
var _session_skills: Dictionary = {}  # char_index -> total skill purchases this run (int)


func _ready() -> void:
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
	_registry = CharacterRegistry.get_instance()
	
	await get_tree().process_frame
	_load_achievements()


func _ensure_registry() -> void:
	# Ensure registry is loaded if accessed before deferred init completed
	if _registry == null:
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
	return ""


## Get all achievements for a character
func get_character_achievements(char_id: String) -> Array[Dictionary]:
	var achievements: Array[Dictionary] = []
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
		return  # No achievement for default characters
	
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


## Call when a skill is purchased in talent tree (char_index is registry index, skill_id is the talent id)
func on_skill_purchased(char_index: int, _skill_id: String) -> void:
	_ensure_registry()
	var char_count := _registry.get_character_count()
	if char_index < 0 or char_index >= char_count:
		return
	
	# Track total skill purchases this session (not unique - each level counts)
	if not _session_skills.has(char_index):
		_session_skills[char_index] = 0
	
	_session_skills[char_index] += 1
	
	# Check if all skills are now purchased (11 total points to max a tree)
	var skills_count: int = _session_skills[char_index]
	print("[AchievementManager] Character %d now has %d/%d skills" % [char_index, skills_count, SKILL_PURCHASES_PER_CHARACTER])
	
	if skills_count >= SKILL_PURCHASES_PER_CHARACTER:
		var char_id: String = _registry.get_character_id(char_index)
		var achievement_id := get_achievement_id(AchievementType.ALL_SKILLS, char_id)
		_unlock_achievement(achievement_id, char_id, AchievementType.ALL_SKILLS)


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
		return  # Already unlocked
	
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
	return "Unknown Achievement"


# --- Persistence ---

func _load_achievements() -> void:
	var config := ConfigFile.new()
	var err := config.load(SaveManagerScript.ACHIEVEMENTS_PATH)
	
	if err == OK:
		if config.has_section("achievements"):
			for key in config.get_section_keys("achievements"):
				_achievements[key] = config.get_value("achievements", key, {"unlocked": false, "progress": 0})
		print("[AchievementManager] Loaded %d achievements" % _achievements.size())
	else:
		print("[AchievementManager] No save file found, starting fresh")


func _save_achievements() -> void:
	var config := ConfigFile.new()
	
	for achievement_id in _achievements:
		config.set_value("achievements", achievement_id, _achievements[achievement_id])
	
	var err := config.save(SaveManagerScript.ACHIEVEMENTS_PATH)
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
