class_name CheatManager
extends RefCounted

## Manages cheat codes and their active states.
## State persists between matches (static) but resets on app restart.

# Defines available cheats and their internal IDs
# Defines available cheats and their internal IDs
const CHEATS = {
	"OUTOFCONTEXT": "infinite_burst",
	"WOLVES": "one_hit_kill",
	"OTTER": "pristine_drops",
	"SLEEPY": "invincible",
	"BLEED": "give_skill_points",
	"RECIPES": "xp_boost"
}

# Display names for the UI
const CHEAT_NAMES = {
	"infinite_burst": "Infinite Burst",
	"one_hit_kill": "One Hit Kill",
	"pristine_drops": "Pristine Core Drops",
	"invincible": "Invincibility",
	"give_skill_points": "99 Skill Points",
	"xp_boost": "50x XP Gain"
}

# Current state
# Dictionary mapping cheat_id (String) -> is_active (bool)
# Only unlocked cheats are in this dictionary.
static var _active_cheats: Dictionary = {}

# Session tracker: true if ANY cheat was ever activated this session
static var _cheat_used_this_session: bool = false

static func try_activate_cheat(input_code: String) -> bool:
	var normalized_input = input_code.strip_edges().replace(" ", "").to_upper()
	var activated_any = false
	
	for cheat_key in CHEATS:
		if normalized_input.contains(cheat_key):
			var cheat_id = CHEATS[cheat_key]
			if not _active_cheats.has(cheat_id):
				_active_cheats[cheat_id] = true
				print("[CheatManager] Cheat Unlocked: ", cheat_id)
				activated_any = true
				_cheat_used_this_session = true
			else:
				# Already unlocked, ensure it's active
				_active_cheats[cheat_id] = true
				activated_any = true
				
			# Mark session as cheated regardless of unlock status
			if CHEATS[cheat_key] != "give_skill_points": # give_skill_points is one-shot, but still counts? 
				# Yes, user said "When cheats are active". But logic implies any cheat usage invalidates run.
				_cheat_used_this_session = true
	
	if activated_any:
		_cheat_used_this_session = true
		
	return activated_any

static func is_cheat_active(cheat_id: String) -> bool:
	return _active_cheats.get(cheat_id, false)

static func set_cheat_active(cheat_id: String, active: bool) -> void:
	if _active_cheats.has(cheat_id):
		_active_cheats[cheat_id] = active

static func has_cheated_this_session() -> bool:
	return _cheat_used_this_session

static func get_unlocked_cheats() -> Dictionary:
	return _active_cheats.duplicate()

static func get_cheat_name(cheat_id: String) -> String:
	return CHEAT_NAMES.get(cheat_id, cheat_id)
