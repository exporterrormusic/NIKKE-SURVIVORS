extends Node
## Tracks per-character damage and kill statistics during a run.
## Tracks per-character damage and kill statistics during a run.
##
## This autoload singleton listens to EventBus signals to track:
## - Damage dealt per character
## - Normal kills (normal, tank, elite enemies) per character
## - Boss kills (boss, super_boss) per character
##
## Usage:
##   RunStatsTracker.reset()  # Call at start of new run
##   RunStatsTracker.get_run_stats()  # Get stats for saving

# Per-character damage dealt
var _damage_by_character: Dictionary = {}

# Per-character kill counts
var _normal_kills_by_character: Dictionary = {}
var _boss_kills_by_character: Dictionary = {}

# Track current active character for damage attribution
var _current_character_id: int = -1

func _ready() -> void:
	# Connect to EventBus signals
	if EventBus:
		EventBus.damage_dealt.connect(_on_damage_dealt)
		EventBus.enemy_killed.connect(_on_enemy_killed)
		EventBus.character_switched.connect(_on_character_switched)
	
	# Get initial character from GameState
	if GameState:
		_current_character_id = GameState.player_character_index

## Reset all stats for a new run
func reset() -> void:
	_damage_by_character.clear()
	_normal_kills_by_character.clear()
	_boss_kills_by_character.clear()
	
	# Initialize stats for all squad members
	if GameState:
		for char_idx in GameState.selected_character_indices:
			_damage_by_character[char_idx] = 0
			_normal_kills_by_character[char_idx] = 0
			_boss_kills_by_character[char_idx] = 0
		_current_character_id = GameState.player_character_index
		print("[RunStatsTracker] Reset stats for squad: %s, current char: %d" % [str(GameState.selected_character_indices), _current_character_id])

func get_run_stats() -> Dictionary:
	# Safety check: if stats are empty (e.g. forgot to reset), try to init from current GameState
	if _damage_by_character.is_empty() and GameState:
		print("[RunStatsTracker] get_run_stats called but stats empty - forcing init")
		for char_idx in GameState.selected_character_indices:
			if not _damage_by_character.has(char_idx):
				_damage_by_character[char_idx] = 0
			if not _normal_kills_by_character.has(char_idx):
				_normal_kills_by_character[char_idx] = 0
			if not _boss_kills_by_character.has(char_idx):
				_boss_kills_by_character[char_idx] = 0
				
	return {
		"damage_by_character": _damage_by_character.duplicate(),
		"normal_kills_by_character": _normal_kills_by_character.duplicate(),
		"boss_kills_by_character": _boss_kills_by_character.duplicate()
	}

## Get total damage dealt by a specific character
func get_character_damage(char_id: int) -> int:
	return _damage_by_character.get(char_id, 0)

## Get normal kills by a specific character
func get_character_normal_kills(char_id: int) -> int:
	return _normal_kills_by_character.get(char_id, 0)

## Get boss kills by a specific character
func get_character_boss_kills(char_id: int) -> int:
	return _boss_kills_by_character.get(char_id, 0)

## Get total damage across all characters
func get_total_damage() -> int:
	var total := 0
	for dmg in _damage_by_character.values():
		total += dmg
	return total

## Get total normal kills across all characters
func get_total_normal_kills() -> int:
	var total := 0
	for kills in _normal_kills_by_character.values():
		total += kills
	return total

## Get total boss kills across all characters
func get_total_boss_kills() -> int:
	var total := 0
	for kills in _boss_kills_by_character.values():
		total += kills
	return total

func _on_damage_dealt(target: Node, info: Variant) -> void:
	# Only track damage to enemies
	if not target or not target.is_in_group("enemies"):
		return
	
	# Attribute damage to current character
	var char_id := _current_character_id
	if char_id < 0:
		return
	
	# Ensure character is tracked
	if not _damage_by_character.has(char_id):
		_damage_by_character[char_id] = 0
	
	# Add damage (use info.amount if available, works for both DamageInfo and Dictionary)
	var damage_amount := 0
	if info is Dictionary:
		damage_amount = info.get("amount", 0)
	elif info != null and "amount" in info:
		damage_amount = info.amount
	elif info != null and "damage" in info:
		damage_amount = info.damage
	else:
		damage_amount = 1  # Fallback
	
	_damage_by_character[char_id] += damage_amount
	print("[RunStatsTracker] Damage: %d to char %d (total: %d)" % [damage_amount, char_id, _damage_by_character[char_id]])

func _on_enemy_killed(enemy: Node, killer_source: String) -> void:
	# Only track player kills
	if killer_source not in ["player", "projectile", "summon", "cecil_drone"]:
		return
	
	var char_id := _current_character_id
	if char_id < 0:
		return
	
	# Ensure character is tracked
	if not _normal_kills_by_character.has(char_id):
		_normal_kills_by_character[char_id] = 0
	if not _boss_kills_by_character.has(char_id):
		_boss_kills_by_character[char_id] = 0
	
	# Determine if enemy is a boss or normal
	if enemy and (enemy.is_in_group("boss") or enemy.is_in_group("super_boss")):
		_boss_kills_by_character[char_id] += 1
		print("[RunStatsTracker] Boss kill by char %d (total: %d)" % [char_id, _boss_kills_by_character[char_id]])
	else:
		# Normal, tank, elite all count as "normal" kills
		_normal_kills_by_character[char_id] += 1
		print("[RunStatsTracker] Kill by char %d (total: %d)" % [char_id, _normal_kills_by_character[char_id]])

func _on_character_switched(slot_index: int, character_id: int) -> void:
	_current_character_id = character_id
	print("[RunStatsTracker] Character switched to slot %d, char_id %d" % [slot_index, character_id])
