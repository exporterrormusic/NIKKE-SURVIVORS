extends Node2D

@onready var environment: Node2D = $Environment
@onready var map_selector: Control = $CanvasLayer/MapSelector
@onready var player: CharacterBody2D = $Player

var _ambient_particles: Node2D = null
var _night_glow: CanvasLayer = null
var _rng := RandomNumberGenerator.new()

# Wave system
var _wave_director: Node = null
var _enemy_spawner: Node2D = null
var _wave_ui: CanvasLayer = null
var _enemy_container: Node2D = null

func _ready():
	_rng.randomize()
	
	# Setup enemy container
	_enemy_container = Node2D.new()
	_enemy_container.name = "Enemies"
	add_child(_enemy_container)
	
	# Setup wave system
	_setup_wave_system()
	
	# Connect map selector signal
	if map_selector:
		map_selector.map_selected.connect(_on_map_selected)
		map_selector.time_selected.connect(_on_time_selected)
		print("[Level] MapSelector connected")
	else:
		push_warning("[Level] MapSelector not found!")
	
	# Register player with environment for grass/snow interaction
	if environment and player:
		if environment.has_method("register_player"):
			environment.register_player(player)
			print("[Level] Player registered with environment for grass interaction")
	
	# Initialize ambient particle system
	_setup_ambient_particles()
	
	# Initialize night glow system
	_setup_night_glow()
	
	# Set world bounds BEFORE initializing environment so grass field uses correct size
	var world_size = 4000.0
	environment.set_world_bounds(Rect2(-world_size/2, -world_size/2, world_size, world_size))
	
	# Initialize environment with RANDOM biome and time
	_initialize_random_environment()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC key
		if map_selector:
			print("[Level] ESC pressed - toggling map selector")
			if map_selector.visible:
				map_selector.visible = false
			else:
				map_selector.show_selector()

func _setup_ambient_particles() -> void:
	var AmbientParticleScript = load("res://scripts/AmbientParticleSystem.gd")
	if AmbientParticleScript:
		_ambient_particles = Node2D.new()
		_ambient_particles.set_script(AmbientParticleScript)
		_ambient_particles.name = "AmbientParticles"
		add_child(_ambient_particles)

func _setup_night_glow() -> void:
	# Disabled - environment CanvasModulate handles night tinting already
	# Adding extra overlays makes it too dark
	pass

func _initialize_random_environment() -> void:
	if not environment or not environment.has_method("initialize_environment"):
		return
	
	# Available biomes and times
	var biomes := [&"snowfield", &"sakura_grove", &"grasslands", &"dunes"]
	var times := [&"day", &"night"]
	
	# Pick random biome and time
	var random_biome: StringName = biomes[_rng.randi() % biomes.size()]
	var random_time: StringName = times[_rng.randi() % times.size()]
	
	print("[Level] Randomly selected: biome=", random_biome, " time=", random_time)
	
	# Initialize environment
	environment.initialize_environment(0, random_biome, random_time)
	
	# Update ambient particles
	_update_ambient_systems(random_biome, random_time)

func _update_ambient_systems(biome_id: StringName, time_id: StringName) -> void:
	var is_night := _is_night_time(time_id)
	
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
	# Calculate night boost value
	var night_boost := 0.0
	if is_night:
		night_boost = 0.6
		if time_id == &"midnight":
			night_boost = 1.0
		elif time_id == &"twilight":
			night_boost = 0.4
	
	# Store for new enemies
	_current_night_boost = night_boost
	
	# Update all existing enemies
	for child in get_children():
		if child.is_in_group("enemies"):
			_set_enemy_night_boost(child, night_boost)

func _set_enemy_night_boost(enemy: Node, night_boost: float) -> void:
	# Find the sprite with the shader material
	var sprite := enemy.get_node_or_null("Sprite2D") as CanvasItem
	if not sprite:
		sprite = enemy.get_node_or_null("AnimatedSprite2D") as CanvasItem
	if not sprite:
		# Try to find any sprite child
		for child in enemy.get_children():
			if child is Sprite2D or child is AnimatedSprite2D:
				sprite = child
				break
	
	if sprite and sprite.material is ShaderMaterial:
		var mat := sprite.material as ShaderMaterial
		if mat.shader:
			# Check if shader has night_boost parameter
			mat.set_shader_parameter("night_boost", night_boost)

var _current_night_boost := 0.0

func _initialize_environment() -> void:
	if environment and environment.has_method("initialize_environment"):
		# Load polar_front map definition to get biome and time
		var map_def_path := "res://resources/maps/polar_front.tres"
		var map_def = load(map_def_path)
		if map_def:
			environment.initialize_environment(map_def.environment_seed, map_def.biome_id, map_def.time_of_day_id)
		else:
			# Fallback if map definition fails to load
			environment.initialize_environment(0, &"snowfield", &"night")

func _on_map_selected(map_id: StringName) -> void:
	if environment and environment.has_method("set_environment"):
		# Get the map definition to determine biome and time
		var map_def_path := "res://resources/maps/%s.tres" % map_id
		var map_def = load(map_def_path)
		if map_def:
			var time_id: StringName = map_def.time_of_day_id
			environment.set_environment(map_def.biome_id, time_id)
			_update_ambient_systems(map_def.biome_id, time_id)
			print("[Level] Environment set to biome: ", map_def.biome_id, " time: ", time_id)

func _on_time_selected(time_id: StringName) -> void:
	if environment and environment.has_method("set_time_of_day"):
		environment.set_time_of_day(time_id)
		# Get current biome for ambient update
		var current_biome := &""
		if environment.has_method("get_active_biome"):
			var biome = environment.get_active_biome()
			if biome:
				current_biome = biome.biome_id
		_update_ambient_systems(current_biome, time_id)
		print("[Level] Time of day changed to: ", time_id)
	elif environment and environment.has_method("set_environment"):
		# Fallback: get current biome and set with new time
		var current_biome := &""
		if environment.has_method("get_active_biome"):
			var biome = environment.get_active_biome()
			if biome:
				current_biome = biome.biome_id
		environment.set_environment(current_biome, time_id)
		_update_ambient_systems(current_biome, time_id)
		print("[Level] Time of day changed to: ", time_id)

# ============================================================================
# WAVE SYSTEM
# ============================================================================

func _setup_wave_system() -> void:
	# Create wave director
	_wave_director = Node.new()
	_wave_director.set_script(load("res://scripts/WaveDirector.gd"))
	_wave_director.name = "WaveDirector"
	add_child(_wave_director)
	
	# Create enemy spawner
	_enemy_spawner = Node2D.new()
	_enemy_spawner.set_script(load("res://scripts/EnemySpawner.gd"))
	_enemy_spawner.name = "EnemySpawner"
	add_child(_enemy_spawner)
	_enemy_spawner.initialize(player, _enemy_container)
	
	# Set map bounds for spawning
	var world_size := 4000.0
	_enemy_spawner.set_map_bounds(Rect2(-world_size/2, -world_size/2, world_size, world_size))
	
	# Create wave UI
	_wave_ui = CanvasLayer.new()
	_wave_ui.set_script(load("res://scripts/WaveUI.gd"))
	_wave_ui.name = "WaveUI"
	_wave_ui.layer = 10
	add_child(_wave_ui)
	
	# Connect signals
	_wave_director.enemy_spawn_requested.connect(_on_enemy_spawn_requested)
	_wave_director.event_started.connect(_on_event_started)
	_wave_director.event_ended.connect(_on_event_ended)
	_wave_director.boss_incoming.connect(_on_boss_incoming)
	_wave_director.run_complete.connect(_on_run_complete)
	_wave_director.time_updated.connect(_on_time_updated)
	_wave_director.wave_changed.connect(_on_wave_changed)
	
	_enemy_spawner.enemy_died.connect(_on_enemy_died)
	
	# Start the wave system
	_wave_director.start()
	print("[Level] Wave system started - 5 minute run!")

func _process(_delta: float) -> void:
	# Update wave director with current enemy count
	if _wave_director and _enemy_container:
		_wave_director.set_enemy_count(_enemy_container.get_child_count())

func _on_enemy_spawn_requested(enemy_type: String, count: int, pattern: String) -> void:
	if not _enemy_spawner:
		return
	
	# Set random horde direction at start of horde
	if pattern == "horde":
		_enemy_spawner.start_random_horde_direction()
	
	for i in range(count):
		var enemy: Node2D = _enemy_spawner.spawn_enemy(enemy_type, pattern)
		if enemy:
			# Apply night boost
			if _current_night_boost > 0.0:
				call_deferred("_set_enemy_night_boost", enemy, _current_night_boost)
			
			# Check for boss death to notify director
			if enemy.is_in_group("boss"):
				enemy.tree_exiting.connect(_on_boss_died)

func _on_event_started(event_type: String, event_data: Dictionary) -> void:
	if _wave_ui:
		_wave_ui.show_event(event_type, event_data)

func _on_event_ended(_event_type: String) -> void:
	pass  # Could add cleanup logic here

func _on_boss_incoming(_boss_type: String, time_until: float) -> void:
	if _wave_ui:
		_wave_ui.show_boss_warning(time_until)

func _on_boss_died() -> void:
	if _wave_director:
		_wave_director.notify_boss_defeated()

func _on_run_complete(survived: bool, final_time: float) -> void:
	@warning_ignore("integer_division")
	var mins := int(final_time) / 60
	var secs := int(final_time) % 60
	if survived:
		print("[Level] 🎉 RUN COMPLETE! Survived %d:%02d" % [mins, secs])
	else:
		print("[Level] 💀 Run ended at %d:%02d" % [mins, secs])

func _on_time_updated(elapsed: float, remaining: float) -> void:
	if _wave_ui:
		_wave_ui.update_time(elapsed, remaining)

func _on_wave_changed(wave_number: int) -> void:
	print("[Level] Wave changed to: ", wave_number)
	# Update spawner with new health multiplier
	if _enemy_spawner and _wave_director:
		var health_mult: float = _wave_director.get_health_multiplier()
		print("[Level] Setting health multiplier to: ", health_mult)
		_enemy_spawner.set_health_multiplier(health_mult)
	# Update UI wave display
	if _wave_ui and _wave_ui.has_method("update_wave"):
		_wave_ui.update_wave(wave_number)

func _on_enemy_died(_enemy: Node2D) -> void:
	pass  # Tracking handled automatically by container child count

# Legacy spawn function (kept for compatibility but no longer used by timer)
func spawn_enemy():
	if _enemy_spawner:
		_enemy_spawner.spawn_enemy("basic", "ring")

func random_edge_position(player_pos: Vector2):
	var viewport = get_viewport()
	var viewport_size = viewport.get_visible_rect().size
	var camera = viewport.get_camera_2d()
	if camera:
		viewport_size *= camera.zoom
	
	var margin = 200.0  # Extra distance outside viewport
	var spawn_distance = viewport_size.length() / 2.0 + margin
	
	var angle = randf() * TAU
	var offset = Vector2(cos(angle), sin(angle)) * spawn_distance
	var spawn_pos = player_pos + offset
	
	# Clamp to world bounds (-2000 to 2000)
	var world_min = -2000.0
	var world_max = 2000.0
	spawn_pos.x = clamp(spawn_pos.x, world_min, world_max)
	spawn_pos.y = clamp(spawn_pos.y, world_min, world_max)
	
	return spawn_pos

func set_game_paused(paused: bool) -> void:
	# Recursively pause/resume gameplay for all non-UI nodes (stop timers, disable processing)
	for child in get_children():
		if child is CanvasLayer:
			continue
		_propagate_pause(child, paused)

func _propagate_pause(node: Node, paused: bool) -> void:
	# Stop/start timers and toggle processing for this node
	if node is Timer:
		if paused:
			if not node.is_stopped():
				node.stop()
		else:
			node.start()

	# Toggle processing on nodes that support it
	if node.has_method("set_process"):
		node.set_process(not paused)
	if node.has_method("set_physics_process"):
		node.set_physics_process(not paused)

	# Call a custom pause hook if present
	if node.has_method("on_game_paused"):
		node.on_game_paused(paused)

	# Recurse into children
	for child in node.get_children():
		_propagate_pause(child, paused)
