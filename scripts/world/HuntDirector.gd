extends Node
class_name HuntDirector
## Hunt mode director - Controls INTEL objectives, super boss guardians, and N01 boss hunt.
## Uses PROXIMITY-BASED SPAWNING for performance - enemies spawn when player gets close.

signal intel_collected(intel_index: int, total: int)
signal all_intel_collected()
signal n01_spawned(position: Vector2)
signal hunt_complete(survived: bool, time: float)
signal guardian_spawned(guardian: Node2D, intel_index: int)

# Configuration
const INTEL_COUNT := 5
const MAP_SIZE := 16000.0
const INTEL_GUARD_RADIUS := 600.0
const INTEL_CAMERA_ZOOM := Vector2(0.6, 0.6)
const INTEL_ZOOM_DISTANCE := 500.0
const MIN_INTEL_SPACING := 3000.0
const BOSS_VISIBILITY_DISTANCE := 800.0

# PROXIMITY SPAWNING - only spawn when player is this close
const SPAWN_TRIGGER_DISTANCE := 2000.0
const DESPAWN_DISTANCE := 4000.0  # Despawn if player is very far

# State
var _guardian_positions: Array[Vector2] = []
var _guardians: Array[Node2D] = []
var _guardian_spawned: Array[bool] = []  # Track which guardians have been spawned
var _intel_boxes: Array[Node2D] = []
var _intel_collected: Array[bool] = []
var _current_intel_index: int = 0
var _n01_position: Vector2 = Vector2.ZERO
var _n01_spawned := false
var _difficulty_level: int = 1
var _active: bool = false
var _is_zoomed_out := false

# References
var _player: Node2D = null
var _enemy_spawner: Node2D = null
var _minimap: Control = null
var _hunt_ui: Node = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func start() -> void:
	_active = true
	_difficulty_level = 1
	_is_zoomed_out = false
	_n01_spawned = false
	_current_intel_index = 0
	
	# Find references
	_player = get_tree().get_first_node_in_group("player")
	_enemy_spawner = get_tree().get_first_node_in_group("enemy_spawners")
	_minimap = get_tree().get_first_node_in_group("minimap")
	
	# Setup HuntUI
	_setup_hunt_ui()
	
	# Generate guardian positions (not spawned yet!)
	_generate_guardian_positions()
	
	# Create ground effects at all locations (cheap visual markers)
	_spawn_ground_effects()
	
	# Initialize spawn tracking
	_guardian_spawned.clear()
	_guardians.clear()
	_intel_boxes.clear()
	for i in range(INTEL_COUNT):
		_guardian_spawned.append(false)
		_guardians.append(null)
		_intel_boxes.append(null)
	
	# Set first objective on minimap IMMEDIATELY
	_current_intel_index = 0
	call_deferred("_update_minimap_objective")
	call_deferred("_update_hunt_ui")
	
	print("[HuntDirector] Hunt started - proximity spawning enabled")

func _setup_hunt_ui() -> void:
	var HuntUIScript = load("res://scripts/ui/HuntUI.gd")
	if HuntUIScript:
		_hunt_ui = CanvasLayer.new()
		_hunt_ui.set_script(HuntUIScript)
		_hunt_ui.name = "HuntUI"
		get_parent().add_child(_hunt_ui)
		
		# Set initial target position
		if _hunt_ui.has_method("set_target_position") and _guardian_positions.size() > 0:
			_hunt_ui.set_target_position(_guardian_positions[0])

func stop() -> void:
	_active = false

func _process(delta: float) -> void:
	if not _active:
		return
	
	# Proximity spawning check
	_check_proximity_spawning()
	
	# Check camera zoom trigger
	_check_camera_zoom()
	
	# Update boss HP bar visibility
	_update_boss_visibility()
	
	# Update HuntUI target position
	if _hunt_ui and _hunt_ui.has_method("set_target_position"):
		_hunt_ui.set_target_position(get_current_objective_position())

func _generate_guardian_positions() -> void:
	_guardian_positions.clear()
	_intel_collected.clear()
	
	var half_map := MAP_SIZE / 2.0
	var margin := 1500.0
	
	var attempts := 0
	var max_attempts := 100
	
	while _guardian_positions.size() < INTEL_COUNT and attempts < max_attempts:
		attempts += 1
		
		var ring_index := _guardian_positions.size()
		var min_dist := 2000.0 + ring_index * 1500.0
		var max_dist := 3500.0 + ring_index * 2000.0
		
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(min_dist, max_dist)
		var candidate := Vector2.from_angle(angle) * distance
		
		candidate.x = clampf(candidate.x, -half_map + margin, half_map - margin)
		candidate.y = clampf(candidate.y, -half_map + margin, half_map - margin)
		
		var valid := true
		for existing in _guardian_positions:
			if candidate.distance_to(existing) < MIN_INTEL_SPACING:
				valid = false
				break
		
		if valid:
			_guardian_positions.append(candidate)
			_intel_collected.append(false)
	
	# Fallback positions
	while _guardian_positions.size() < INTEL_COUNT:
		var angle := _guardian_positions.size() * (TAU / INTEL_COUNT)
		var distance := 4000.0 + _guardian_positions.size() * 1000.0
		var pos := Vector2.from_angle(angle) * distance
		pos.x = clampf(pos.x, -half_map + margin, half_map - margin)
		pos.y = clampf(pos.y, -half_map + margin, half_map - margin)
		_guardian_positions.append(pos)
		_intel_collected.append(false)
	
	print("[HuntDirector] Generated %d guardian positions" % _guardian_positions.size())

func _spawn_ground_effects() -> void:
	# Ground effects are cheap - spawn them all for visual guidance
	for i in range(_guardian_positions.size()):
		var ground_effect := _create_ground_effect(_guardian_positions[i])
		get_parent().add_child(ground_effect)

func _create_ground_effect(pos: Vector2) -> Node2D:
	var effect := Node2D.new()
	effect.name = "IntelGroundEffect"
	effect.global_position = pos
	effect.set_script(load("res://scripts/world/IntelGroundEffect.gd"))
	return effect

func _check_proximity_spawning() -> void:
	if not _player or not is_instance_valid(_player):
		return
	
	var player_pos := _player.global_position
	
	# Check each guardian location
	for i in range(_guardian_positions.size()):
		if _intel_collected[i]:
			continue  # Already collected
		
		var guardian_pos := _guardian_positions[i]
		var distance := player_pos.distance_to(guardian_pos)
		
		# Spawn guardian and escorts when player is close enough
		if distance < SPAWN_TRIGGER_DISTANCE and not _guardian_spawned[i]:
			_spawn_guardian_at_index(i)

func _spawn_guardian_at_index(index: int) -> void:
	if _guardian_spawned[index]:
		return
	
	_guardian_spawned[index] = true
	var pos := _guardian_positions[index]
	
	print("[HuntDirector] Player approaching guardian %d - spawning..." % index)
	
	# Spawn the super boss guardian
	var guardian := _spawn_super_boss_guardian(index, pos)
	_guardians[index] = guardian
	
	# Spawn escorts around it
	var difficulty := index + 1
	_spawn_guardian_escorts(pos, difficulty)
	
	print("[HuntDirector] Guardian %d spawned with escorts" % index)

func _spawn_super_boss_guardian(index: int, pos: Vector2) -> Node2D:
	if not _enemy_spawner:
		return null
	
	var guardian: Node2D = null
	
	if _enemy_spawner.has_method("spawn_at_position"):
		guardian = _enemy_spawner.spawn_at_position("super_boss", pos)
	elif _enemy_spawner.has_method("spawn_enemy"):
		guardian = _enemy_spawner.spawn_enemy("super_boss", "center")
		if guardian:
			guardian.global_position = pos
	
	if guardian:
		guardian.name = "IntelGuardian_%d" % index
		guardian.add_to_group("intel_guardians")
		guardian.set_meta("intel_index", index)
		
		if guardian.has_signal("tree_exiting"):
			guardian.tree_exiting.connect(_on_guardian_died.bind(index, pos))
		
		emit_signal("guardian_spawned", guardian, index)
	
	return guardian

func _on_guardian_died(intel_index: int, pos: Vector2) -> void:
	print("[HuntDirector] Guardian %d defeated! Dropping INTEL..." % intel_index)
	
	# Spawn INTEL box at guardian's death location
	var intel_box := _create_intel_box(intel_index, pos)
	_intel_boxes[intel_index] = intel_box
	get_parent().add_child(intel_box)
	
	_update_minimap_objective()

func _create_intel_box(index: int, pos: Vector2) -> Node2D:
	var intel := Area2D.new()
	intel.name = "IntelBox_%d" % index
	intel.global_position = pos
	intel.set_script(load("res://scripts/world/IntelBox.gd"))
	intel.set("intel_index", index)
	intel.collected.connect(_on_intel_collected)
	return intel

func _spawn_guardian_escorts(position: Vector2, difficulty: int) -> void:
	if not _enemy_spawner:
		return
	
	# Reduced counts for performance
	var base_count := 10 + difficulty * 5
	var spawn_types: Array[Dictionary] = []
	
	match difficulty:
		1:
			spawn_types = [
				{"type": "basic", "count": base_count},
				{"type": "tank", "count": 2},
			]
		2:
			spawn_types = [
				{"type": "basic", "count": base_count},
				{"type": "tank", "count": 3},
			]
		3:
			spawn_types = [
				{"type": "basic", "count": base_count},
				{"type": "tank", "count": 4},
				{"type": "elite", "count": 1},
			]
		4:
			spawn_types = [
				{"type": "basic", "count": base_count},
				{"type": "tank", "count": 5},
				{"type": "elite", "count": 2},
			]
		5:
			spawn_types = [
				{"type": "basic", "count": base_count},
				{"type": "tank", "count": 6},
				{"type": "elite", "count": 3},
			]
	
	for spawn_data in spawn_types:
		for j in range(spawn_data.count):
			var offset := Vector2(
				_rng.randf_range(-INTEL_GUARD_RADIUS, INTEL_GUARD_RADIUS),
				_rng.randf_range(-INTEL_GUARD_RADIUS, INTEL_GUARD_RADIUS)
			)
			var spawn_pos := position + offset
			
			if _enemy_spawner.has_method("spawn_at_position"):
				_enemy_spawner.spawn_at_position(spawn_data.type, spawn_pos)

func _on_intel_collected(intel_index: int) -> void:
	if intel_index < 0 or intel_index >= _intel_collected.size():
		return
	
	_intel_collected[intel_index] = true
	_difficulty_level = _count_collected() + 1
	
	emit_signal("intel_collected", intel_index, INTEL_COUNT)
	_update_hunt_ui()
	
	# Check if all collected
	var all_done := true
	for collected in _intel_collected:
		if not collected:
			all_done = false
			break
	
	if all_done:
		emit_signal("all_intel_collected")
		_spawn_n01()
	else:
		_current_intel_index = _find_next_uncollected()
		_update_minimap_objective()

func _find_next_uncollected() -> int:
	for i in range(_intel_collected.size()):
		if not _intel_collected[i]:
			return i
	return -1

func _count_collected() -> int:
	var count := 0
	for collected in _intel_collected:
		if collected:
			count += 1
	return count

func _update_hunt_ui() -> void:
	if _hunt_ui:
		if _hunt_ui.has_method("set_intel_count"):
			_hunt_ui.set_intel_count(_count_collected(), INTEL_COUNT)
		if _hunt_ui.has_method("set_n01_phase"):
			_hunt_ui.set_n01_phase(_n01_spawned)
		if _hunt_ui.has_method("set_target_position"):
			_hunt_ui.set_target_position(get_current_objective_position())

func _spawn_n01() -> void:
	if _n01_spawned:
		return
	_n01_spawned = true
	
	var half_map := MAP_SIZE / 2.0
	var margin := 2000.0
	var angle := _rng.randf() * TAU
	var distance := _rng.randf_range(5000.0, 7000.0)
	
	_n01_position = Vector2.from_angle(angle) * distance
	_n01_position.x = clampf(_n01_position.x, -half_map + margin, half_map - margin)
	_n01_position.y = clampf(_n01_position.y, -half_map + margin, half_map - margin)
	
	if _enemy_spawner and _enemy_spawner.has_method("spawn_rapture_queen"):
		var queen = _enemy_spawner.spawn_rapture_queen()
		if queen:
			queen.global_position = _n01_position
			queen.tree_exiting.connect(_on_n01_defeated)
	
	emit_signal("n01_spawned", _n01_position)
	_update_minimap_objective()
	_update_hunt_ui()
	
	print("[HuntDirector] N01 spawned at ", _n01_position)

func _on_n01_defeated() -> void:
	_active = false
	emit_signal("hunt_complete", true, 0.0)
	print("[HuntDirector] N01 defeated! Hunt complete!")

func _update_minimap_objective() -> void:
	if not _minimap:
		_minimap = get_tree().get_first_node_in_group("minimap")
	
	var target_pos := get_current_objective_position()
	var obj_type := "n01" if _n01_spawned else "intel"
	
	if _minimap and _minimap.has_method("set_objective"):
		_minimap.set_objective(target_pos, obj_type)
		print("[HuntDirector] Minimap objective set to %s at %s" % [obj_type, target_pos])

func _check_camera_zoom() -> void:
	if not _player or not is_instance_valid(_player):
		return
	
	var player_pos := _player.global_position
	var target_pos := get_current_objective_position()
	if target_pos == Vector2.ZERO:
		return
	
	var distance := player_pos.distance_to(target_pos)
	
	if distance < INTEL_ZOOM_DISTANCE and not _is_zoomed_out:
		_is_zoomed_out = true
		_zoom_camera_out()
	elif distance > INTEL_ZOOM_DISTANCE * 1.5 and _is_zoomed_out:
		_is_zoomed_out = false
		_zoom_camera_in()

func _update_boss_visibility() -> void:
	if not _player or not is_instance_valid(_player):
		return
	
	var player_pos := _player.global_position
	
	for guardian in _guardians:
		if guardian and is_instance_valid(guardian):
			var distance := player_pos.distance_to(guardian.global_position)
			var should_show := distance < BOSS_VISIBILITY_DISTANCE
			_set_boss_hp_visibility(guardian, should_show)

func _set_boss_hp_visibility(boss: Node2D, is_visible: bool) -> void:
	var hp_bar = boss.get_node_or_null("HPBar")
	if hp_bar:
		hp_bar.visible = is_visible
	
	var boss_hud = boss.get_node_or_null("BossHUD")
	if boss_hud:
		boss_hud.visible = is_visible

func _zoom_camera_out() -> void:
	if CombatJuice.instance:
		var tween := create_tween()
		tween.tween_property(CombatJuice.instance, "_base_zoom", INTEL_CAMERA_ZOOM, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _zoom_camera_in() -> void:
	if CombatJuice.instance:
		var tween := create_tween()
		tween.tween_property(CombatJuice.instance, "_base_zoom", Vector2.ONE, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# === PUBLIC API ===

func get_current_objective_position() -> Vector2:
	if _n01_spawned:
		return _n01_position
	elif _current_intel_index >= 0 and _current_intel_index < _guardian_positions.size():
		# Point to guardian position (whether spawned or not)
		var guardian = _guardians[_current_intel_index] if _current_intel_index < _guardians.size() else null
		if guardian and is_instance_valid(guardian):
			return guardian.global_position
		elif _intel_boxes[_current_intel_index] and is_instance_valid(_intel_boxes[_current_intel_index]):
			return _intel_boxes[_current_intel_index].global_position
		else:
			# Guardian not spawned yet - point to the position where it will spawn
			return _guardian_positions[_current_intel_index]
	return Vector2.ZERO

func get_intel_count() -> int:
	return INTEL_COUNT

func get_collected_count() -> int:
	return _count_collected()

func is_n01_spawned() -> bool:
	return _n01_spawned
