extends Node
class_name BiomeManager
## Manages biome definitions and application.
##
## Extracted from EnvironmentController to reduce god class size.
## Handles loading biome resources and applying biome settings.

signal biome_changed(biome_id: StringName)

const BIOMES_DIR := "res://resources/biomes/"

var biome_definitions: Array = []
var _biome_lookup: Dictionary = {}
var _active_biome: BiomeDefinition = null


## Load all biome definitions from resources
func load_biomes() -> void:
	biome_definitions.clear()
	_biome_lookup.clear()
	
	var dir := DirAccess.open(BIOMES_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var path := BIOMES_DIR + file_name
				var biome := load(path) as BiomeDefinition
				if biome:
					biome_definitions.append(biome)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	_rebuild_lookup()
	print("[BiomeManager] Loaded ", biome_definitions.size(), " biomes")


## Rebuild biome lookup dictionary
func _rebuild_lookup() -> void:
	_biome_lookup.clear()
	for biome in biome_definitions:
		if biome is BiomeDefinition:
			_biome_lookup[biome.biome_id] = biome


## Get biome by ID
func get_biome(biome_id: StringName) -> BiomeDefinition:
	if _biome_lookup.has(biome_id):
		return _biome_lookup[biome_id]
	return null


## Select and set active biome
func set_active_biome(biome_id: StringName) -> BiomeDefinition:
	var biome := get_biome(biome_id)
	if biome:
		_active_biome = biome
		biome_changed.emit(biome_id)
	return biome


## Get active biome
func get_active_biome() -> BiomeDefinition:
	return _active_biome


## Get random biome
func get_random_biome(rng: RandomNumberGenerator) -> BiomeDefinition:
	if biome_definitions.is_empty():
		return null
	var idx := rng.randi_range(0, biome_definitions.size() - 1)
	return biome_definitions[idx]


## Get all biome IDs
func get_biome_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for biome in biome_definitions:
		if biome is BiomeDefinition:
			ids.append(biome.biome_id)
	return ids
