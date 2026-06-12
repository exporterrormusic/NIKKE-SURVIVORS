class_name MapRegistry
extends RefCounted
## Central registry of playable operation zones (biome/time combos + preview
## art). Companion to StageRegistry (which holds mission MODES); a run is
## mode x zone. Add new zones here and every selector picks them up.

const MAPS := [
	{
		"id": "sakura_day",
		"name": "Ark Outskirts",
		"subtitle": "Day",
		"biome": "sakura_grove",
		"time": "day",
		"preview": "res://assets/backgrounds/forest.jpg",
	},
	{
		"id": "sakura_night",
		"name": "Ark Outskirts",
		"subtitle": "Night",
		"biome": "sakura_grove",
		"time": "night",
		"preview": "res://assets/backgrounds/rapturefield2.jpg",
	},
	{
		"id": "snow_day",
		"name": "The Frozen North",
		"subtitle": "Day",
		"biome": "snowfield",
		"time": "day",
		"preview": "res://assets/backgrounds/snow-day.jpg",
	},
	{
		"id": "snow_night",
		"name": "The Frozen North",
		"subtitle": "Night",
		"biome": "snowfield",
		"time": "night",
		"preview": "res://assets/backgrounds/snow-night.jpg",
	},
	{
		"id": "storm",
		"name": "Stormbringer",
		"subtitle": "Night",
		"biome": "rain_forest",
		"time": "night",
		"preview": "res://assets/backgrounds/rapturefield1.jpg",
	},
]


static func get_all_maps() -> Array:
	return MAPS.duplicate(true)


static func get_map(map_id: String) -> Dictionary:
	for map in MAPS:
		if map["id"] == map_id:
			return map
	return {}


static func get_map_count() -> int:
	return MAPS.size()
