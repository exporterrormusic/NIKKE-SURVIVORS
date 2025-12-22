extends Node
class_name CharacterSwitcher
## Manages character squad and switching.
## Extracted from PlayerCore for modularity.

signal character_switched(slot_index: int, registry_index: int)
signal character_unlocked(slot_index: int)

## Character registry reference
var _registry: RefCounted = null

## Controllers for each character slot
var _controllers: Array = []

## Registry indices for selected characters
var _selected_indices: Array[int] = []

## Currently active slot (0 = Main, 1 = Support1, 2 = Support2)
var current_slot: int = 0

## Unlocked character slots
var unlocked_slots: Array[int] = [0]

## Reference to player
var _player: Node = null

## Burst sounds for each slot
var _burst_sounds: Array = []

const CharacterRegistryScript = preload("res://scripts/characters/CharacterRegistry.gd")
const CharacterSwapEffectScript = preload("res://scripts/effects/CharacterSwapEffect.gd")

var _swap_effect: Node2D = null


func initialize(player: Node, selected_indices: Array[int]) -> void:
	_player = player
	_selected_indices = selected_indices.duplicate()
	_registry = CharacterRegistryScript.get_instance()
	
	# Create controllers for selected characters
	_controllers.clear()
	_burst_sounds.clear()
	var all_ids: Array = _registry.get_all_character_ids()
	
	for char_idx in _selected_indices:
		if char_idx >= 0 and char_idx < all_ids.size():
			var char_id: String = all_ids[char_idx]
			var controller = _registry.create_controller(char_id, _player)
			_controllers.append(controller)
			# Load burst sound
			var sound = _registry.get_burst_sound(char_id)
			_burst_sounds.append(sound)
			print("[CharacterSwitcher] Created controller for %s (index %d)" % [char_id, char_idx])
		else:
			_controllers.append(null)
			_burst_sounds.append(null)
			push_warning("[CharacterSwitcher] Invalid character index: %d" % char_idx)
	
	# Start with Main character
	current_slot = 0
	unlocked_slots = [0]


func get_current_controller() -> RefCounted:
	if current_slot < 0 or current_slot >= _controllers.size():
		return null
	return _controllers[current_slot]


func get_controller_at_slot(slot: int) -> RefCounted:
	if slot < 0 or slot >= _controllers.size():
		return null
	return _controllers[slot]


func get_current_registry_index() -> int:
	if current_slot < 0 or current_slot >= _selected_indices.size():
		return 0
	return _selected_indices[current_slot]


func get_registry_index_for_slot(slot: int) -> int:
	if slot < 0 or slot >= _selected_indices.size():
		return 0
	return _selected_indices[slot]


func get_character_id_for_slot(slot: int) -> String:
	var idx := get_registry_index_for_slot(slot)
	if _registry:
		var all_ids: Array = _registry.get_all_character_ids()
		if idx >= 0 and idx < all_ids.size():
			return all_ids[idx]
	return ""


func get_burst_sound() -> AudioStream:
	if current_slot < 0 or current_slot >= _burst_sounds.size():
		return null
	return _burst_sounds[current_slot]


func switch(direction: int) -> void:
	"""Switch to next/previous character. Direction: 1 = next, -1 = previous."""
	if unlocked_slots.size() <= 1:
		return
	
	# Cleanup old controller
	var old_controller := get_current_controller()
	if old_controller and old_controller.has_method("cleanup"):
		old_controller.cleanup()
	
	# Find next unlocked slot
	var idx := unlocked_slots.find(current_slot)
	idx = (idx + direction + unlocked_slots.size()) % unlocked_slots.size()
	current_slot = unlocked_slots[idx]
	
	_trigger_swap_effect()
	character_switched.emit(current_slot, get_current_registry_index())
	# Also emit to EventBus for global listeners (like GameManager)
	if EventBus:
		EventBus.character_switched.emit(current_slot, get_current_registry_index())


func unlock_slot(slot: int) -> void:
	"""Unlock a character slot."""
	if slot in unlocked_slots:
		return
	if slot < 0 or slot >= _controllers.size():
		return
	
	unlocked_slots.append(slot)
	unlocked_slots.sort()
	character_unlocked.emit(slot)
	print("[CharacterSwitcher] Unlocked slot %d" % slot)


func is_slot_unlocked(slot: int) -> bool:
	return slot in unlocked_slots


func get_all_controllers() -> Array:
	return _controllers


func _trigger_swap_effect() -> void:
	if not _player:
		return
	
	if not is_instance_valid(_swap_effect):
		_swap_effect = Node2D.new()
		_swap_effect.set_script(CharacterSwapEffectScript)
		_swap_effect.name = "SwapEffect"
		_swap_effect.z_index = 50
		_player.get_parent().add_child(_swap_effect)
	
	if _swap_effect.has_method("trigger"):
		_swap_effect.trigger(current_slot, _player.global_position)
