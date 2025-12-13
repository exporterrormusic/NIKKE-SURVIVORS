extends Node
class_name BossPhaseManager
## Manages boss phase transitions based on HP thresholds.
##
## Automatically monitors boss HP and triggers phase changes when
## HP crosses defined thresholds.
##
## Usage:
##   var manager = BossPhaseManager.new()
##   add_child(manager)
##   manager.setup(boss_node, phases_array)

## Emitted when phase changes
signal phase_changed(old_phase_index: int, new_phase_index: int)

## Emitted just before phase transition (for effects)
signal phase_transition_starting(new_phase_index: int)

## Reference to the boss node
var boss: Node = null

## Array of BossPhase resources, sorted by HP threshold (descending)
var phases: Array[BossPhase] = []

## Current active phase index
var current_phase_index: int = 0

## Whether phases have been set up
var _initialized: bool = false


## Initialize the phase manager with boss and phases
func setup(boss_node: Node, phase_array: Array[BossPhase]) -> void:
	boss = boss_node
	phases = phase_array.duplicate()
	
	# Sort phases by HP threshold (descending - highest HP first)
	phases.sort_custom(func(a, b): return a.hp_threshold > b.hp_threshold)
	
	current_phase_index = 0
	_initialized = true
	
	# Apply initial phase
	if phases.size() > 0:
		_apply_phase(0)


func _process(_delta: float) -> void:
	if not _initialized or boss == null or not is_instance_valid(boss):
		return
	
	# Check for phase transitions
	check_phase_transition()


## Check if we should transition to a new phase based on current HP
func check_phase_transition() -> void:
	if not boss.has_method("get") or not "hp" in boss or not "max_hp" in boss:
		return
	
	var current_hp: int = boss.get("hp")
	var max_hp: int = boss.get("max_hp")
	
	if max_hp <= 0:
		return
	
	var hp_ratio: float = float(current_hp) / float(max_hp)
	
	# Check if we should move to next phase
	for i in range(current_phase_index + 1, phases.size()):
		if hp_ratio <= phases[i].hp_threshold:
			_trigger_phase_transition(i)
			return


## Trigger a phase transition
func _trigger_phase_transition(new_phase_index: int) -> void:
	if new_phase_index < 0 or new_phase_index >= phases.size():
		return
	
	if new_phase_index == current_phase_index:
		return
	
	var old_phase = current_phase_index
	
	# Emit warning signal for transition effects
	phase_transition_starting.emit(new_phase_index)
	
	# Wait a frame for transition effects
	await get_tree().process_frame
	
	# Apply new phase
	_apply_phase(new_phase_index)
	current_phase_index = new_phase_index
	
	# Emit global event
	if EventBus:
		EventBus.boss_spawned.emit(boss)  # Reuse for phase changes
	
	phase_changed.emit(old_phase, new_phase_index)


## Apply phase modifiers to the boss
func _apply_phase(phase_index: int) -> void:
	if phase_index < 0 or phase_index >= phases.size():
		return
	
	var phase := phases[phase_index]
	
	# Apply speed multiplier
	if boss.has_method("set") and "base_speed" in boss:
		var base_speed = boss.get("base_speed")
		boss.set("speed", base_speed * phase.speed_multiplier)
	
	# Apply visual tint
	if boss.has_method("set") and "modulate" in boss:
		boss.set("modulate", phase.phase_tint)
	
	# Spawn transition effect
	if phase.transition_effect_path != "":
		_spawn_transition_effect(phase.transition_effect_path)


## Spawn a phase transition effect
func _spawn_transition_effect(effect_path: String) -> void:
	if not ResourceLoader.exists(effect_path):
		return
	
	var effect_scene = load(effect_path)
	if effect_scene:
		var effect = effect_scene.instantiate()
		if boss and is_instance_valid(boss):
			boss.get_parent().add_child(effect)
			if effect is Node2D and boss is Node2D:
				effect.global_position = boss.global_position


## Get the current phase
func get_current_phase() -> BossPhase:
	if current_phase_index >= 0 and current_phase_index < phases.size():
		return phases[current_phase_index]
	return null


## Get the current phase name
func get_current_phase_name() -> String:
	var phase = get_current_phase()
	return phase.phase_name if phase else ""
