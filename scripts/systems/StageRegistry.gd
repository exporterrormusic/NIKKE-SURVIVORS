extends Node

## Registry for all game stages with their properties and unlock requirements.
## Each stage has a fixed biome, time of day, and special modifiers.
## Registered as autoload: StageRegistry

# Stage definitions - Now these are MODIFIERS that apply to any map
const STAGES := [
	{
		"id": "stage_1",
		"name": "Standard",
		"biome": "sakura_grove",
		"time": "day",
		"unlock_after": null,  # Always unlocked
		"spawn_rules": {},
		"description": "Survive 11 waves of Raptures to complete the mission."
	},
	{
		"id": "stage_3",
		"name": "Endless",
		"biome": "sakura_grove",
		"time": "night",
		"unlock_after": null,  # Always unlocked
		"spawn_rules": {
			"endless": true,  # No wave limit
		},
		"description": "No wave limit. How long can you survive the endless horde?"
	},
]

## Get all stage data
static func get_all_stages() -> Array:
	return STAGES.duplicate(true)

## Get a specific stage by ID
static func get_stage(stage_id: String) -> Dictionary:
	for stage in STAGES:
		if stage["id"] == stage_id:
			return stage.duplicate(true)
	return {}

## Get stage by index (0-based)
static func get_stage_by_index(index: int) -> Dictionary:
	if index >= 0 and index < STAGES.size():
		return STAGES[index].duplicate(true)
	return {}

## Get stage count
static func get_stage_count() -> int:
	return STAGES.size()

## Get the biome ID for a stage (matches resource file naming)
static func get_biome_id(stage_id: String) -> StringName:
	var stage := get_stage(stage_id)
	if stage.is_empty():
		return &"sakura_grove"
	return StringName(stage.get("biome", "sakura_grove"))

## Get the time of day ID for a stage
static func get_time_id(stage_id: String) -> StringName:
	var stage := get_stage(stage_id)
	if stage.is_empty():
		return &"day"
	return StringName(stage.get("time", "day"))

## Check if stage has elite-only modifier
static func is_elite_only(stage_id: String) -> bool:
	var stage := get_stage(stage_id)
	if stage.is_empty():
		return false
	var rules: Dictionary = stage.get("spawn_rules", {})
	return rules.get("elite_only", false)

## Check if stage is endless mode
static func is_endless(stage_id: String) -> bool:
	var stage := get_stage(stage_id)
	if stage.is_empty():
		return false
	var rules: Dictionary = stage.get("spawn_rules", {})
	return rules.get("endless", false)

## Helper stubs for compatibility (always return false now)
static func is_hunt_mode(_stage_id: String) -> bool:
	return false

static func is_defense_mode(_stage_id: String) -> bool:
	return false
