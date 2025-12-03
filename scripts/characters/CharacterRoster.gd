class_name CharacterRoster
extends Resource
## Manages the collection of playable characters.
## This resource holds references to all CharacterData resources and provides
## lookup methods for the UI and game systems.
##
## To add a new character:
## 1. Create a CharacterData .tres file in resources/characters/
## 2. Add it to the characters array in the roster resource

const DEFAULT_PORTRAIT_PATH := "res://assets/icon.svg"

## Array of all character data resources
@export var characters: Array[CharacterData] = []

## Whether to include locked characters in searches
@export var include_locked_in_searches: bool = false

var _loaded: bool = false
var _character_lookup: Dictionary = {}  # code_name -> CharacterData

## Ensure the roster is fully loaded and indexed
func ensure_loaded() -> void:
	if _loaded:
		return
	_build_lookup()
	_loaded = true

## Rebuild the character lookup dictionary
func _build_lookup() -> void:
	_character_lookup.clear()
	for character in characters:
		if character == null:
			continue
		var code = character.get_code_name()
		if not code.is_empty():
			_character_lookup[code] = character
		# Also index by id if different
		if not character.id.is_empty() and character.id != code:
			_character_lookup[character.id] = character

## Get the default (first) character
func get_default_character() -> CharacterData:
	ensure_loaded()
	if characters.is_empty():
		return null
	return characters[0]

## Get a character by code name or id
func get_character_by_code(code_name: String) -> CharacterData:
	ensure_loaded()
	return _character_lookup.get(code_name, null)

## Get the index of a character in the array
func get_index_for_character(target: CharacterData) -> int:
	ensure_loaded()
	return characters.find(target)

## Get a character by index
func get_character_at_index(index: int) -> CharacterData:
	ensure_loaded()
	if index < 0 or index >= characters.size():
		return null
	return characters[index]

## Get all unlocked characters
func get_unlocked_characters() -> Array[CharacterData]:
	ensure_loaded()
	var unlocked: Array[CharacterData] = []
	for character in characters:
		if character and character.is_unlocked:
			unlocked.append(character)
	return unlocked

## Get the count of characters
func get_character_count() -> int:
	ensure_loaded()
	return characters.size()

## Get the count of unlocked characters
func get_unlocked_count() -> int:
	ensure_loaded()
	var count := 0
	for character in characters:
		if character and character.is_unlocked:
			count += 1
	return count

## Check if a character exists by code name
func has_character(code_name: String) -> bool:
	ensure_loaded()
	return _character_lookup.has(code_name)

## Add a character to the roster (runtime)
func add_character(character: CharacterData) -> void:
	if character == null:
		return
	characters.append(character)
	var code = character.get_code_name()
	if not code.is_empty():
		_character_lookup[code] = character
	if not character.id.is_empty() and character.id != code:
		_character_lookup[character.id] = character

## Remove a character from the roster (runtime)
func remove_character(code_name: String) -> bool:
	var character = get_character_by_code(code_name)
	if character == null:
		return false
	characters.erase(character)
	_character_lookup.erase(code_name)
	if not character.id.is_empty():
		_character_lookup.erase(character.id)
	return true

## Reload the roster (for editor use)
func reload() -> void:
	_loaded = false
	ensure_loaded()
