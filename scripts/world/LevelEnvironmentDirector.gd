extends Node
class_name LevelEnvironmentDirector

## Manages environment initialization, biome/time transitions, ambient particles,
## night glow, lightning effects, and weather (rapture storm) for the level.
##
## Extracted from Level.gd to reduce god-class complexity.

# References set by Level
var environment_node: Node2D = null
var player_node: Node2D = null

# Internal state
var _ambient_particles: Node2D = null
var _night_glow: Node2D = null
var _current_night_boost: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

# ──────────────────────────────────────────────
#  Environment Initialization
# ──────────────────────────────────────────────

## Initialize the stage environment using GameManager's current_stage_id
## or GameManager.selected_biome/selected_time overrides.
## Returns the chosen biome and time so the caller can use them.
func initialize_stage_environment() -> Dictionary:
	if not environment_node or not environment_node.has_method("initialize_environment"):
		return {}
	
	# Get stage from registry using current_stage_id
	var stage_id: String = GameManager.current_stage_id if GameManager else "stage_1"
	var StageRegistryClass := load("res://scripts/systems/StageRegistry.gd")
	var stage: Dictionary = StageRegistryClass.get_stage(stage_id) if StageRegistryClass else {}
	
	var biome: StringName
	var time_id: StringName
	
	# Use GameManager.selected_biome and selected_time (set by the zone carousel in MissionSelect)
	if GameManager.selected_biome != "" and GameManager.selected_time != "":
		biome = StringName(GameManager.selected_biome)
		time_id = StringName(GameManager.selected_time)
		print("[LevelEnvironment] Using selected map: biome=", biome, " time=", time_id)
	elif not stage.is_empty():
		biome = StringName(stage.biome)
		time_id = StringName(stage.time)
		print("[LevelEnvironment] Using stage default: ", stage.name, " (biome=", biome, " time=", time_id, ")")
	else:
		# Fallback to random if no stage selected
		var biomes := [&"snowfield", &"sakura_grove", &"grasslands", &"dunes"]
		var times := [&"day", &"night"]
		biome = biomes[_rng.randi() % biomes.size()]
		time_id = times[_rng.randi() % times.size()]
		print("[LevelEnvironment] No stage selected, using random: biome=", biome, " time=", time_id)
	
	# Initialize environment with standard bounds (4000x4000)
	environment_node.set_world_bounds(Rect2(-2000, -2000, 4000, 4000))
	environment_node.initialize_environment(0, biome, time_id)
	
	# Cleanup boulders near edges to prevent getting stuck
	call_deferred("_cleanup_edge_boulders")
	
	# Update ambient particles and other systems
	_update_ambient_systems(biome, time_id)
	
	return {"biome": biome, "time": time_id}

## Legacy — redirects to stage-based init.
func initialize_random_environment() -> Dictionary:
	return initialize_stage_environment()

## Directly set environment from a map definition.
func apply_map(map_id: StringName) -> void:
	if not environment_node or not environment_node.has_method("set_environment"):
		return
	
	var map_def_path := "res://resources/maps/%s.tres" % map_id
	var map_def = load(map_def_path)
	if map_def:
		var time_id: StringName = map_def.time_of_day_id
		environment_node.set_environment(map_def.biome_id, time_id)
		_update_ambient_systems(map_def.biome_id, time_id)
		print("[LevelEnvironment] Environment set to biome: ", map_def.biome_id, " time: ", time_id)

## Apply a time-of-day change.
func apply_time_of_day(time_id: StringName) -> void:
	if environment_node and environment_node.has_method("set_time_of_day"):
		environment_node.set_time_of_day(time_id)
		var current_biome := _get_current_biome()
		_update_ambient_systems(current_biome, time_id)
		print("[LevelEnvironment] Time of day changed to: ", time_id)
	elif environment_node and environment_node.has_method("set_environment"):
		var current_biome := _get_current_biome()
		environment_node.set_environment(current_biome, time_id)
		_update_ambient_systems(current_biome, time_id)
		print("[LevelEnvironment] Time of day changed to: ", time_id)

# ──────────────────────────────────────────────
#  Ambient Particles
# ──────────────────────────────────────────────

func setup_ambient_particles() -> void:
	var AmbientParticleScript = load("res://scripts/world/AmbientParticleSystem.gd")
	if AmbientParticleScript:
		_ambient_particles = Node2D.new()
		_ambient_particles.set_script(AmbientParticleScript)
		_ambient_particles.name = "AmbientParticles"
		add_child(_ambient_particles)

# ──────────────────────────────────────────────
#  Night Glow
# ──────────────────────────────────────────────

func setup_night_glow() -> void:
	# Disabled — environment CanvasModulate handles night tinting already.
	pass

# ──────────────────────────────────────────────
#  Ambient Systems Update
# ──────────────────────────────────────────────

func _update_ambient_systems(biome_id: StringName, time_id: StringName) -> void:
	var is_night := _is_night_time(time_id)
	
	# Emit biome change for achievements/systems
	if EventBus:
		EventBus.biome_changed.emit(biome_id)
		EventBus.time_of_day_changed.emit(is_night)
	
	# Update ambient particles
	if _ambient_particles and _ambient_particles.has_method("configure"):
		_ambient_particles.configure(biome_id, is_night)
	
	# Update night glow
	if _night_glow and _night_glow.has_method("set_night_mode"):
		if is_night:
			var intensity := 0.6
			if time_id == &"midnight":
				intensity = 0.8
			elif time_id == &"twilight":
				intensity = 0.4
			_night_glow.set_night_mode(true, intensity)
		else:
			_night_glow.set_night_mode(false)
	
	# Update enemy glow for night time
	_update_enemy_night_glow(is_night, time_id)

func _is_night_time(time_id: StringName) -> bool:
	return time_id == &"night"

func _update_enemy_night_glow(is_night: bool, time_id: StringName) -> void:
	var night_boost := 0.0
	if is_night:
		night_boost = 0.6
		if time_id == &"midnight":
			night_boost = 1.0
		elif time_id == &"twilight":
			night_boost = 0.4
	
	_current_night_boost = night_boost
	
	# Update EnemySpawner for future spawns
	var spawner := get_tree().get_first_node_in_group("enemy_spawners")
	if spawner and spawner.has_method("set_night_boost"):
		spawner.set_night_boost(night_boost)
	
	# Update all existing enemies AND players
	var targets = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player")
	for child in targets:
		if child.has_method("set_night_boost"):
			child.set_night_boost(night_boost)
		else:
			_set_entity_night_boost(child, night_boost)

func _set_entity_night_boost(entity: Node, night_boost: float) -> void:
	var sprite := entity.get_node_or_null("Sprite2D") as CanvasItem
	if not sprite:
		sprite = entity.get_node_or_null("AnimatedSprite2D") as CanvasItem
	if not sprite:
		for child in entity.get_children():
			if child is Sprite2D or child is AnimatedSprite2D:
				sprite = child
				break
	
	if sprite and sprite.material is ShaderMaterial:
		var mat := sprite.material as ShaderMaterial
		if mat.shader:
			mat.set_shader_parameter("night_boost", night_boost)

## Returns the current night boost value for use by spawners.
func get_night_boost() -> float:
	return _current_night_boost

func _get_current_biome() -> StringName:
	if environment_node and environment_node.has_method("get_active_biome"):
		var b = environment_node.get_active_biome()
		if b:
			return b.biome_id
	return &"grasslands"

# ──────────────────────────────────────────────
#  Rapture Weather
# ──────────────────────────────────────────────

## Force night + rain + lightning for the Rapture Queen event.
func trigger_rapture_weather() -> void:
	# 1. Force Night
	if environment_node and environment_node.has_method("set_time_of_day"):
		environment_node.set_time_of_day("night")
		_update_ambient_systems(_get_current_biome(), "night")
	
	# 2. Force Rain on ALL biomes
	if _ambient_particles:
		_ambient_particles.configure(&"rain_forest", true)
		print("[LevelEnvironment] Weather changed to RAIN")
	
	# 3. Start Lightning
	_start_lightning_system()
	
	# 4. Play rain audio
	if AudioDirector and AudioDirector.has_method("play_rain_ambience"):
		AudioDirector.play_rain_ambience()

# ──────────────────────────────────────────────
#  Lightning System
# ──────────────────────────────────────────────

func _start_lightning_system() -> void:
	if has_node("LightningTimer"):
		return
	
	var timer = Timer.new()
	timer.name = "LightningTimer"
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(_on_lightning_timer)
	add_child(timer)
	timer.start()
	print("[LevelEnvironment] Lightning system activated")

func _on_lightning_timer() -> void:
	_trigger_lightning_flash()
	
	var timer = get_node_or_null("LightningTimer")
	if timer:
		timer.wait_time = randf_range(2.0, 8.0)
		timer.start()

func _trigger_lightning_flash() -> void:
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.9, 0.9, 1.0, 0.3)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var canvas = CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	canvas.add_child(flash)
	
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 1.0, 0.05)
	tween.tween_property(flash, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func(): canvas.queue_free())

# ──────────────────────────────────────────────
#  Edge Boulder Cleanup
# ──────────────────────────────────────────────

func _cleanup_edge_boulders() -> void:
	var limit := 1700.0
	var boulders := get_tree().get_nodes_in_group("boulders")
	var removed_count := 0
	
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var pos: Vector2 = boulder.global_position
		if abs(pos.x) > limit or abs(pos.y) > limit:
			boulder.queue_free()
			removed_count += 1
	
	if removed_count > 0:
		print("[LevelEnvironment] Removed ", removed_count, " boulders near map edges.")
