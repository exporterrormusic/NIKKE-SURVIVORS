extends Node

## Global game state singleton that persists across scenes.
## Stores character selections and links them to the shop/talent system.
##
## Usage:
##   - Character select menu sets the 3 selected characters
##   - Shop/TalentTree reads from here to know which characters to display
##   - This ensures character selection and shop are always in sync
##
## Access via autoload: GameState.set_selected_characters([...])

# Selected characters for the current run (character registry indices)
# Default: Crown (5), Commander (1), Marian (4)
var selected_character_indices: Array[int] = [5, 1, 4]

# The character the player controls (index into selected_character_indices, or registry index)
var player_character_index: int = 1  # Default to Commander

# Character registry reference (loaded lazily)
var _character_registry = null

## Set the 3 characters selected for this run
## @param indices: Array of 3 character registry indices
func set_selected_characters(indices: Array[int]) -> void:
	if indices.size() != 3:
		push_warning("GameState: Expected 3 character indices, got %d" % indices.size())
		return
	selected_character_indices = indices.duplicate()
	print("GameState: Selected characters set to indices: ", selected_character_indices)

## Get the 3 selected character indices for shop display
func get_shop_character_order() -> Array[int]:
	return selected_character_indices.duplicate()

## Set which character the player controls
## @param index: Character registry index
func set_player_character(index: int) -> void:
	player_character_index = index

## Get the player's controlled character index
func get_player_character() -> int:
	return player_character_index

## Check if a character is in the current selection
func is_character_selected(registry_index: int) -> bool:
	return registry_index in selected_character_indices

## Get character data from registry by index
func get_character_data(registry_index: int) -> Dictionary:
	_ensure_registry()
	if _character_registry:
		var char_ids: Array = _character_registry.get_all_character_ids()
		if registry_index >= 0 and registry_index < char_ids.size():
			var char_id: String = char_ids[registry_index]
			return _character_registry.get_character(char_id)
	return {}

## Get all available characters from registry
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

## Helper to load character registry
func _ensure_registry() -> void:
	if _character_registry == null:
		var CharacterRegistryClass = load("res://scripts/characters/CharacterRegistry.gd")
		if CharacterRegistryClass:
			_character_registry = CharacterRegistryClass.get_instance()

## Reset to default character selection
func reset_selection() -> void:
	selected_character_indices = [5, 1, 4]  # Crown, Commander, Marian
	player_character_index = 1  # Commander
