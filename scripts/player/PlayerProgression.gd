extends Node
class_name PlayerProgression
## Manages player progression: XP, levels, skill points.
##
## This is a helper module that can be used by PlayerCore to delegate
## progression-related functionality. Designed for gradual adoption.
##
## Usage:
##   var progression := PlayerProgression.new()
##   add_child(progression)
##   progression.configure(initial_level, initial_xp)
##   progression.add_xp(100)

signal xp_gained(amount: int, new_total: int)
signal level_up(new_level: int, skill_points_gained: int)
signal skill_point_added(total_skill_points: int)

## Current experience points
var xp: int = 0

## XP required for next level
var xp_to_next: int = 100

## Current level
var level: int = 1

## XP scaling per level (multiplier)
@export var xp_scaling: float = 1.5

## Skill points available to spend
var _skill_points: int = 0

## XP multiplier bonus (from shop upgrades, etc.)
var xp_multiplier: float = 1.0


## Configure initial progression state
func configure(initial_level: int = 1, initial_xp: int = 0, initial_xp_to_next: int = 100) -> void:
	level = initial_level
	xp = initial_xp
	xp_to_next = initial_xp_to_next
	
	# Goddess Fall mode: Start with 3 skill points
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.goddess_fall_mode:
		_skill_points = 3
		skill_point_added.emit(_skill_points)


## Add XP with optional multiplier override
func add_xp(amount: int, bonus_multiplier: float = 1.0) -> bool:
	var total_mult := xp_multiplier * bonus_multiplier
	var final_amount := int(float(amount) * total_mult)
	
	xp += final_amount
	xp_gained.emit(final_amount, xp)
	
	# Also emit global event
	if EventBus:
		EventBus.xp_gained.emit(final_amount, xp)
	
	var leveled_up := false
	var levels_gained := 0
	
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		levels_gained += 1
		xp_to_next = int(xp_to_next * xp_scaling)
		_skill_points += 1
		skill_point_added.emit(_skill_points)
	
	if levels_gained > 0:
		level_up.emit(level, levels_gained)
		if EventBus:
			EventBus.player_leveled_up.emit(level)
		leveled_up = true
	
	return leveled_up


## Set skill points (for sync)
func set_skill_points(amount: int) -> void:
	_skill_points = amount
	skill_point_added.emit(_skill_points)


## Get current skill points
func get_skill_points() -> int:
	return _skill_points


## Spend a skill point (returns false if none available)
func spend_skill_point() -> bool:
	if _skill_points <= 0:
		return false
	_skill_points -= 1
	return true


## Add skill points directly (e.g., from debug or rewards)
func add_skill_points(amount: int) -> void:
	_skill_points += amount
	skill_point_added.emit(_skill_points)


## Set the XP multiplier (from shop upgrades, character abilities, etc.)
func set_xp_multiplier(mult: float) -> void:
	xp_multiplier = mult


## Get progress to next level as a percentage (0.0 - 1.0)
func get_level_progress() -> float:
	if xp_to_next <= 0:
		return 1.0
	return float(xp) / float(xp_to_next)


## Get current state as a dictionary (for saving)
func get_state() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"xp_to_next": xp_to_next,
		"skill_points": _skill_points,
		"xp_multiplier": xp_multiplier
	}


## Restore state from a dictionary (for loading)
func set_state(state: Dictionary) -> void:
	level = state.get("level", 1)
	xp = state.get("xp", 0)
	xp_to_next = state.get("xp_to_next", 100)
	_skill_points = state.get("skill_points", 0)
	xp_multiplier = state.get("xp_multiplier", 1.0)


## Calculate damage multiplier based on level
## Formula: 1.0 at level 1, +25% per level
func get_level_damage_multiplier() -> float:
	return 1.0 + (level - 1) * 0.25
