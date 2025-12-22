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
var _combat_juice: Node = null
var _score_ui: Control = null
var _core_counter: CanvasLayer = null
var _damage_layer: CanvasLayer = null
var _minimap: Control = null

func _ready():
	_rng.randomize()
	set_process_input(true) # Ensure we receive input events
	
	# Reset run stats for new game
	if GameManager:
		GameManager.reset_run_stats()
	
	# Reset achievement session tracking
	if has_node("/root/AchievementManager"):
		get_node("/root/AchievementManager").reset_session()
	
	# Connect to enemy killed signal for player upgrades (Rapunzel healing, Nayuta clones, etc.)
	if EventBus:
		EventBus.enemy_killed.connect(_on_enemy_died)
	
	# Setup achievement notification UI
	_setup_achievement_notification()
	
	# Setup pause menu immediately
	_setup_pause_menu()
	
	# Setup CombatJuice system for camera effects
	_setup_combat_juice()
	
	# Setup enemy container
	_enemy_container = Node2D.new()
	_enemy_container.name = "Enemies"
	add_child(_enemy_container)
	
	# Setup wave system
	_setup_wave_system()
	
	# Connect map selector signal (legacy, can be removed if MapSelector is no longer used)
	if map_selector:
		map_selector.map_selected.connect(_on_map_selected)
		map_selector.time_selected.connect(_on_time_selected)
		print("[Level] MapSelector connected")
	
	# Register player with environment for grass/snow interaction
	if environment and player:
		if environment.has_method("register_player"):
			environment.register_player(player)
			print("[Level] Player registered with environment for grass interaction")
			
	# Initialize Grass Mask Manager
	if not has_node("GrassMaskManager"):
		var mask_mgr = load("res://scripts/systems/GrassMaskManager.gd").new()
		mask_mgr.name = "GrassMaskManager"
		add_child(mask_mgr)
	
	# Initialize ambient particle system
	_setup_ambient_particles()
	
	# Setup main HUD (Health, etc) and Music Player
	_setup_hud()
	
	# Setup Damage Layer (Layer 20, follows viewport)
	# This ensures damage numbers are above world (night tint) but below UI, and track correctly
	_damage_layer = CanvasLayer.new()
	_damage_layer.name = "DamageLayer"
	_damage_layer.layer = 20
	_damage_layer.follow_viewport_enabled = true
	add_child(_damage_layer)
	
	# Register damage layer with EffectPool
	if EffectPool.get_instance():
		EffectPool.get_instance().set_damage_layer(_damage_layer)
		
	# Warm up projectile cache (prevents shader stutter)
	ProjectileCache.warm_up_cache(self)

func _exit_tree() -> void:
	# Clean up all static caches to prevent RID leaks
	ProjectileCache.clear_all_pools()
	TargetCache.cleanup()
	UISoundManager.cleanup()
	TextureCache.cleanup()
	CharacterInfoPanel.cleanup()
	VenetianBlindsBackground.clear_cache()
	print("[Level] Cleanup complete")

func _setup_hud() -> void:
	if not player:
		return
		
	# Instantiate Music Player (Bottom Left)
	var music_player_scene = load("res://scenes/ui/MusicPlayerUI.tscn")
	if music_player_scene:
		var mp_layer = CanvasLayer.new()
		mp_layer.layer = 126 # Layer 126 (above Pause 125)
		mp_layer.name = "MusicPlayerLayer"
		add_child(mp_layer)
		
		var mp = music_player_scene.instantiate()
		mp_layer.add_child(mp)
	
	# Initialize night glow system
	_setup_night_glow()
	
	# Set world bounds BEFORE initializing environment so grass field uses correct size
	var world_size = 4000.0
	environment.set_world_bounds(Rect2(-world_size / 2, -world_size / 2, world_size, world_size))
	
	# Initialize environment from stage (or random fallback)
	# Initialize environment from stage (or random fallback)
	_initialize_stage_environment()
	
	# She Descends easter egg mode: spawn N01 immediately
	if GameManager and (GameManager.she_descends_mode or GameManager.goddess_fall_mode):
		_start_she_descends_mode()
		return # Skip normal run start
	
	# Notify run started
	if GameManager and EventBus:
		EventBus.run_started.emit(GameManager.current_stage_id)
		
	# Start background music based on character
	# Start background music based on initial character
	_play_character_bgm()

# Removed _on_character_switched to prevent music changing during gameplay

func _play_character_bgm(forced_index: int = -1) -> void:
	if not GameManager or not AudioDirector:
		return
		
	# Determine which character to play music for
	var main_char_idx = 0
	if forced_index != -1:
		main_char_idx = forced_index
	else:
		# Default to main selected character
		var char_indices = GameManager.selected_character_indices
		if not char_indices.is_empty():
			main_char_idx = char_indices[0]
	
	var registry = CharacterRegistry.get_instance()
	if not registry:
		AudioDirector.play_random_battle_track()
		return
		
	var all_ids = registry.get_all_character_ids()
	
	# Validate index
	if main_char_idx < 0 or main_char_idx >= all_ids.size():
		print("[Level] Invalid character index: ", main_char_idx, ". Playing random track.")
		AudioDirector.play_random_battle_track()
		return
		
	var char_id = all_ids[main_char_idx]
	print("[Level] Resolving BGM for character ID: ", char_id, " (index: ", main_char_idx, ")")
	
	var music_path = ""
	match char_id:
		"snow_white":
			music_path = "res://assets/sounds/music/bgm/snow.wav"
		"rapunzel":
			music_path = "res://assets/sounds/music/bgm/rapunzel.wav"
		"sin":
			music_path = "res://assets/sounds/music/bgm/sin.wav"
		"nayuta":
			music_path = "res://assets/sounds/music/bgm/nayuta.wav"
	
	# 75% chance to play specific theme if it exists
	if music_path != "" and randf() < 0.75:
		print("[Level] Playing character BGM (75% roll hit): ", music_path)
		AudioDirector.play_music_by_path(music_path)
	else:
		print("[Level] Playing random BGM (25% roll or no specific theme)")
		AudioDirector.play_random_battle_track()

var _pause_menu: CanvasLayer = null

func _input(event: InputEvent) -> void:
	# Don't process if game is paused and pause menu is handling it
	if _pause_menu and _pause_menu.visible:
		return
	
	if event.is_action_pressed("ui_cancel"): # ESC key
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()

func _toggle_pause_menu() -> void:
	if _pause_menu.visible:
		_pause_menu.hide_menu()
	else:
		_pause_menu.show_pause()

func _setup_achievement_notification() -> void:
	var AchievementNotificationScript = load("res://scripts/ui/AchievementNotification.gd")
	var notif := CanvasLayer.new()
	notif.set_script(AchievementNotificationScript)
	notif.name = "AchievementNotification"
	add_child(notif)

func _setup_pause_menu() -> void:
	var PauseMenuScript = load("res://scripts/ui/PauseMenu.gd")
	_pause_menu = CanvasLayer.new()
	_pause_menu.set_script(PauseMenuScript)
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)
	
	# Connect signals
	_pause_menu.restart_requested.connect(_on_restart_requested)
	_pause_menu.resume_requested.connect(_on_resume_requested)
	_pause_menu.settings_requested.connect(_on_settings_requested)
	_pause_menu.character_select_requested.connect(_on_character_select_requested)
	_pause_menu.quit_requested.connect(_on_quit_requested)

func _on_restart_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_resume_requested() -> void:
	# Already handled by hide_menu
	pass

func _on_settings_requested() -> void:
	# Open settings menu in a CanvasLayer so it renders on top of everything
	var settings_scene = load("res://scenes/ui/SettingsMenu.tscn")
	if settings_scene:
		var canvas_layer := CanvasLayer.new()
		canvas_layer.layer = 101 # Above pause menu (layer 100)
		canvas_layer.name = "SettingsLayer"
		add_child(canvas_layer)
		
		var settings = settings_scene.instantiate()
		settings.process_mode = Node.PROCESS_MODE_ALWAYS # Work while paused
		canvas_layer.add_child(settings)
		
		# Connect back signal to close settings
		settings.back_requested.connect(_on_settings_closed.bind(canvas_layer))

func _on_settings_closed(canvas_layer: CanvasLayer) -> void:
	# Remove the settings menu and its canvas layer
	if canvas_layer and is_instance_valid(canvas_layer):
		canvas_layer.queue_free()

func _on_character_select_requested() -> void:
	get_tree().paused = false
	
	# Reset Engine time scale in case CombatJuice or other systems modified it
	Engine.time_scale = 1.0
	if CombatJuice:
		CombatJuice.reset()
	
	# Reset bullet time (Wells ability) in case it was active
	if GameManager:
		GameManager.enemy_time_scale = 1.0
	
	# Record the run result before leaving (save score even if player didn't die)
	if GameManager:
		GameManager.record_run_result("")
	
	# Stop battle music and ambient sounds
	if AudioDirector:
		AudioDirector.stop_music(0.5)
		AudioDirector.stop_ambient(0.5)
		
	get_tree().change_scene_to_file("res://scenes/ui/CharacterSelectMenu.tscn")

func _on_quit_requested() -> void:
	get_tree().paused = false
	
	# Reset Engine time scale in case CombatJuice or other systems modified it
	Engine.time_scale = 1.0
	if CombatJuice:
		CombatJuice.reset()
	
	# Reset bullet time (Wells ability) in case it was active
	if GameManager:
		GameManager.enemy_time_scale = 1.0
	
	# Record the run result before quitting (save score even if player didn't die)
	if GameManager:
		GameManager.record_run_result("")
	
	# Stop battle music and ambient sounds
	if AudioDirector:
		# Don't stop music here, let MenuManager handle the transition to menu music
		AudioDirector.stop_ambient(0.5)
	
	# Use MenuManager to return to main menu so signals get connected properly
	if MenuManager:
		MenuManager.return_to_main_menu()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

func show_defeat_menu() -> void:
	## Called when player dies to show the defeat screen
	if not _pause_menu:
		_setup_pause_menu()
	_pause_menu.show_defeat()

func _setup_ambient_particles() -> void:
	var AmbientParticleScript = load("res://scripts/world/AmbientParticleSystem.gd")
	if AmbientParticleScript:
		_ambient_particles = Node2D.new()
		_ambient_particles.set_script(AmbientParticleScript)
		_ambient_particles.name = "AmbientParticles"
		add_child(_ambient_particles)

func _setup_night_glow() -> void:
	# Disabled - environment CanvasModulate handles night tinting already
	# Adding extra overlays makes it too dark
	pass

func _setup_combat_juice() -> void:
	# Create CombatJuice system for camera effects
	var CombatJuiceScript = load("res://scripts/systems/CombatJuice.gd")
	if CombatJuiceScript:
		_combat_juice = Node.new()
		_combat_juice.set_script(CombatJuiceScript)
		_combat_juice.name = "CombatJuice"
		add_child(_combat_juice)
		print("[Level] CombatJuice system created")
		
		# Register camera - use call_deferred to ensure Player is ready
		call_deferred("_register_combat_juice_camera")
		
		# Add chromatic aberration overlay to CanvasLayer
		var canvas_layer = get_node_or_null("ScreenFlashLayer")
		if canvas_layer and _combat_juice.has_method("get_chromatic_overlay"):
			var overlay = _combat_juice.get_chromatic_overlay()
			if overlay:
				canvas_layer.add_child(overlay)

func _register_combat_juice_camera() -> void:
	if player:
		var camera = player.get_node_or_null("Camera2D")
		if camera and _combat_juice and _combat_juice.has_method("register_camera"):
			_combat_juice.register_camera(camera)
			print("[Level] Camera registered with CombatJuice")
		else:
			push_warning("[Level] Could not register camera - camera: ", camera, " combat_juice: ", _combat_juice)
	else:
		push_warning("[Level] Player not found for camera registration")

func _initialize_stage_environment() -> void:
	if not environment or not environment.has_method("initialize_environment"):
		return
	
	# Get stage from registry using current_stage_id
	var stage_id: String = GameManager.current_stage_id if GameManager else "stage_1"
	var StageRegistryClass := load("res://scripts/systems/StageRegistry.gd")
	var stage: Dictionary = StageRegistryClass.get_stage(stage_id) if StageRegistryClass else {}
	
	var biome: StringName
	var time: StringName
	
	# Use GameManager.selected_biome and selected_time (set by map selector in StageSelector)
	# These override the stage's default biome/time
	if GameManager.selected_biome != "" and GameManager.selected_time != "":
		biome = StringName(GameManager.selected_biome)
		time = StringName(GameManager.selected_time)
		print("[Level] Using selected map: biome=", biome, " time=", time)
	elif not stage.is_empty():
		biome = StringName(stage.biome)
		time = StringName(stage.time)
		print("[Level] Using stage default: ", stage.name, " (biome=", biome, " time=", time, ")")
	else:
		# Fallback to random if no stage selected
		var biomes := [&"snowfield", &"sakura_grove", &"grasslands", &"dunes"]
		var times := [&"day", &"night"]
		biome = biomes[_rng.randi() % biomes.size()]
		time = times[_rng.randi() % times.size()]
		print("[Level] No stage selected, using random: biome=", biome, " time=", time)
	
	# Apply spawn rules from stage to spawner and wave director
	if not stage.is_empty():
		var spawn_rules: Dictionary = stage.get("spawn_rules", {})
		
		# Check for HUNT mode - this takes precedence
		if spawn_rules.get("hunt_mode", false):
			print("[Level] HUNT mode detected - setting up hunt system...")
			_setup_hunt_mode()
			# Initialize environment AFTER hunt setup for larger map
			environment.initialize_environment(0, biome, time)
			call_deferred("_cleanup_edge_boulders")
			_update_ambient_systems(biome, time)
			return # Skip wave system setup
		
		# Check for DEFENSE mode
		if spawn_rules.get("defense_mode", false):
			print("[Level] DEFENSE mode detected - setting up defense system...")
			_setup_defense_mode()
			environment.initialize_environment(0, biome, time)
			call_deferred("_cleanup_edge_boulders")
			_update_ambient_systems(biome, time)
			return # Skip wave system setup
		
		# Standard mode - set up wave system and apply modifiers
		if _enemy_spawner and spawn_rules.get("elite_only", false):
			_enemy_spawner.set_elite_only_mode(true)
			print("[Level] Elite-only mode enabled")
		if _wave_director and spawn_rules.get("endless", false):
			_wave_director.set_endless_mode(true)
			print("[Level] Endless mode enabled")
	
	# Initialize environment
	environment.initialize_environment(0, biome, time)
	
	# Debug what script is on environment
	if environment.get_script():
		print("[Level] Environment script path: ", environment.get_script().resource_path)
	
	# Cleanup boulders near edges to prevent getting stuck
	# Call deferred to ensure they are spawned
	call_deferred("_cleanup_edge_boulders")
	
	# Update ambient particles
	_update_ambient_systems(biome, time)

func _initialize_random_environment() -> void:
	# Legacy function - redirects to stage-based initialization
	_initialize_stage_environment()

func _cleanup_edge_boulders() -> void:
	# World size is 4000 (-2000 to 2000)
	# Keep boulders away from edges (margin of 300 units = 1700 limit)
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
		print("[Level] Removed ", removed_count, " boulders near map edges to prevent stuck issues.")

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
	
	# Update EnemySpawner for future spawns
	if _enemy_spawner and _enemy_spawner.has_method("set_night_boost"):
		_enemy_spawner.set_night_boost(night_boost)
	
	# Update all existing enemies AND players
	var targets = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player")
	for child in targets:
		if child.has_method("set_night_boost"):
			child.set_night_boost(night_boost)
		else:
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
		# Debug prints removed for performance

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

var _hunt_director: Node = null
var _defense_director: Node = null

func _setup_defense_mode() -> void:
	# DEFENSE mode: Square map, defend ARK at top from enemies spawning left/right/bottom
	print("[Level] Setting up DEFENSE mode...")
	
	# Use square map (like standard mode)
	var world_size := 4000.0
	environment.set_world_bounds(Rect2(-world_size / 2, -world_size / 2, world_size, world_size))
	
	# Player spawns at center of map
	if player:
		player.global_position = Vector2(0, 0)
		print("[Level] Player positioned at center")
	
	# Create enemy spawner with defense bounds
	_enemy_spawner = Node2D.new()
	_enemy_spawner.set_script(load("res://scripts/enemies/EnemySpawner.gd"))
	_enemy_spawner.name = "EnemySpawner"
	_enemy_spawner.add_to_group("enemy_spawners")
	add_child(_enemy_spawner)
	_enemy_spawner.initialize(player, _enemy_container)
	_enemy_spawner.set_map_bounds(Rect2(-world_size / 2, -world_size / 2, world_size, world_size))
	
	# Create DefenseDirector
	_defense_director = Node.new()
	_defense_director.set_script(load("res://scripts/world/DefenseDirector.gd"))
	_defense_director.name = "DefenseDirector"
	add_child(_defense_director)
	
	# Connect DefenseDirector signals
	if _defense_director.has_signal("base_destroyed"):
		_defense_director.base_destroyed.connect(_on_base_destroyed)
	if _defense_director.has_signal("defense_complete"):
		_defense_director.defense_complete.connect(_on_defense_complete)
	
	# Start defense mode
	_defense_director.start()
	
	# Setup score UI and minimap
	_setup_score_ui()
	_setup_minimap()
	_setup_core_counter()
	
	print("[Level] DEFENSE mode started - Protect your base!")

func _on_base_destroyed() -> void:
	print("[Level] Base destroyed! Game over!")

func _on_defense_complete(waves_survived: int) -> void:
	print("[Level] Defense complete! Survived %d waves" % waves_survived)

func _setup_hunt_mode() -> void:
	# HUNT mode: Large map with INTEL objectives
	print("[Level] Setting up HUNT mode...")
	
	# Create a larger map for Hunt mode
	var world_size := 16000.0 # 16x larger than standard
	environment.set_world_bounds(Rect2(-world_size / 2, -world_size / 2, world_size, world_size))
	
	# Create enemy spawner with larger bounds
	_enemy_spawner = Node2D.new()
	_enemy_spawner.set_script(load("res://scripts/enemies/EnemySpawner.gd"))
	_enemy_spawner.name = "EnemySpawner"
	_enemy_spawner.add_to_group("enemy_spawners")
	add_child(_enemy_spawner)
	_enemy_spawner.initialize(player, _enemy_container)
	_enemy_spawner.set_map_bounds(Rect2(-world_size / 2, -world_size / 2, world_size, world_size))
	
	# Create HuntDirector instead of WaveDirector
	_hunt_director = Node.new()
	_hunt_director.set_script(load("res://scripts/world/HuntDirector.gd"))
	_hunt_director.name = "HuntDirector"
	add_child(_hunt_director)
	
	# Connect HuntDirector signals
	if _hunt_director.has_signal("intel_collected"):
		_hunt_director.intel_collected.connect(_on_intel_collected)
	if _hunt_director.has_signal("all_intel_collected"):
		_hunt_director.all_intel_collected.connect(_on_all_intel_collected)
	if _hunt_director.has_signal("hunt_complete"):
		_hunt_director.hunt_complete.connect(_on_hunt_complete)
	
	# Setup UI components FIRST (before starting hunt director!)
	_setup_score_ui()
	_setup_minimap()
	_setup_core_counter()
	
	# NOW start the hunt (after minimap exists!)
	_hunt_director.start()
	
	print("[Level] HUNT mode started - Find all INTEL boxes!")

func _on_intel_collected(intel_index: int, total: int) -> void:
	print("[Level] INTEL collected: %d/%d" % [intel_index + 1, total])

func _on_all_intel_collected() -> void:
	print("[Level] All INTEL collected! N01 has spawned...")

func _on_hunt_complete(survived: bool, time_taken: float) -> void:
	print("[Level] Hunt complete! Survived: %s, Time: %.1f seconds" % [survived, time_taken])
	if survived:
		# Victory - could trigger end screen here
		print("[Level] HUNT mode victory!")

func _setup_wave_system() -> void:
	# Create wave director
	_wave_director = Node.new()
	_wave_director.set_script(load("res://scripts/world/WaveDirector.gd"))
	_wave_director.name = "WaveDirector"
	add_child(_wave_director)
	
	# Create enemy spawner
	_enemy_spawner = Node2D.new()
	_enemy_spawner.set_script(load("res://scripts/enemies/EnemySpawner.gd"))
	_enemy_spawner.name = "EnemySpawner"
	add_child(_enemy_spawner)
	_enemy_spawner.initialize(player, _enemy_container)
	
	# Set map bounds for spawning
	var world_size := 4000.0
	_enemy_spawner.set_map_bounds(Rect2(-world_size / 2, -world_size / 2, world_size, world_size))
	
	# Create wave UI
	_wave_ui = CanvasLayer.new()
	_wave_ui.set_script(load("res://scripts/world/WaveUI.gd"))
	_wave_ui.name = "WaveUI"
	_wave_ui.layer = 10
	_wave_ui.add_to_group("wave_ui") # For Future Marian warning access
	add_child(_wave_ui)
	
	# Connect signals
	_wave_director.enemy_spawn_requested.connect(_on_enemy_spawn_requested)
	_wave_director.time_updated.connect(_wave_ui.update_time)

	_wave_director.wave_changed.connect(_wave_ui.update_wave)
	_wave_director.wave_changed.connect(_on_wave_changed)
	
	if _wave_director.has_signal("wave_reward_earned"):
		_wave_director.wave_reward_earned.connect(_on_wave_reward_earned)
	
	_wave_director.start()
	
	# Setup score UI and minimap
	_setup_score_ui()
	_setup_minimap()
	_setup_core_counter()
	
	print("[Level] Wave system setup complete")

func _on_wave_reward_earned(count: int) -> void:
	if not player:
		return
		
	var OrbScript = load("res://scripts/world/PristineCoreOrb.gd")
	if not OrbScript:
		return
		
	# Spawn orbs
	for i in range(count):
		# Create orb instance from script
		var orb = OrbScript.new()
		orb.cores_value = 1
		
		# Position near player (splashed outwards)
		# User requested at least 1/4 screen away (~450px) to prevent instant pickup
		var angle = randf() * TAU
		var dist = randf_range(450.0, 600.0)
		var offset = Vector2(cos(angle), sin(angle)) * dist
		orb.global_position = player.global_position + offset
		
		add_child(orb)
		
	print("[Level] Spawned %d Pristine Core(s) as reward" % count)

func _setup_score_ui() -> void:
	var ScoreUIScript = load("res://scripts/ui/ScoreUI.gd")
	if ScoreUIScript:
		var canvas := CanvasLayer.new()
		canvas.name = "ScoreUILayer"
		canvas.layer = 10
		add_child(canvas)
		
		_score_ui = Control.new()
		_score_ui.set_script(ScoreUIScript)
		_score_ui.name = "ScoreUI"
		canvas.add_child(_score_ui)
		print("[Level] Score UI initialized")

func _setup_minimap() -> void:
	var MiniMapScript = load("res://scripts/ui/MiniMap.gd")
	if MiniMapScript:
		var canvas := CanvasLayer.new()
		canvas.name = "MiniMapLayer"
		canvas.layer = 10
		add_child(canvas)
		
		_minimap = Control.new()
		_minimap.set_script(MiniMapScript)
		_minimap.name = "MiniMap"
		_minimap.add_to_group("minimap")
		canvas.add_child(_minimap)
		
		# Set player reference
		if player and _minimap.has_method("set_player"):
			_minimap.set_player(player)
		
		print("[Level] MiniMap initialized")

func _setup_core_counter() -> void:
	# Create core counter in bottom-right corner
	_core_counter = CanvasLayer.new()
	_core_counter.name = "CoreCounterLayer"
	_core_counter.layer = 10
	add_child(_core_counter)
	
	var counter := Control.new()
	counter.name = "CoreCounter"
	counter.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	counter.offset_left = -220
	counter.offset_top = -85
	counter.offset_right = -20
	counter.offset_bottom = -20
	_core_counter.add_child(counter)
	
	# Use the styled container like the shop
	var styled_container: Control = _PristineCoreContainer.new()
	styled_container.name = "StyledContainer"
	styled_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	counter.add_child(styled_container)
	
	print("[Level] Core counter initialized")

func _update_core_counter() -> void:
	if not _core_counter:
		return
	var counter := _core_counter.get_node_or_null("CoreCounter")
	if not counter:
		return
	# Find the styled container and update its label
	var styled := counter.get_node_or_null("StyledContainer")
	if styled and styled.has_method("update_count"):
		styled.update_count(GameManager.get_pristine_cores())

# Inner class for drawing the Pristine Core icon
class _PristineCoreIcon extends Control:
	func _draw() -> void:
		var center: Vector2 = size / 2.0
		var radius: float = minf(size.x, size.y) / 2.0 - 2.0
		
		# Outer glow
		for i in range(6, 0, -1):
			var glow_alpha: float = 0.12 * (1.0 - float(i) / 6.0)
			var glow_radius: float = radius + float(i) * 1.5
			draw_circle(center, glow_radius, Color(1.0, 0.2, 0.2, glow_alpha))
		
		# Main sphere gradient
		var segments: int = 24
		for i in range(segments, 0, -1):
			var t: float = float(i) / float(segments)
			var r: float = radius * t
			var color := Color(0.6 + 0.4 * (1.0 - t), 0.1 + 0.2 * (1.0 - t), 0.1 + 0.1 * (1.0 - t))
			draw_circle(center, r, color)
		
		# Inner glowing core
		var core_radius: float = radius * 0.5
		for i in range(12, 0, -1):
			var t: float = float(i) / 12.0
			var r: float = core_radius * t
			var alpha: float = 0.8 * (1.0 - t * 0.5)
			draw_circle(center, r, Color(1.0, 0.5, 0.3, alpha))
		
		# Hot center
		draw_circle(center, radius * 0.15, Color(1.0, 0.9, 0.7, 1.0))
		
		# Specular highlight
		var highlight_offset: Vector2 = Vector2(-radius * 0.25, -radius * 0.25)
		var highlight_radius: float = radius * 0.2
		draw_circle(center + highlight_offset, highlight_radius, Color(1.0, 1.0, 1.0, 0.6))

var _goddess_elapsed: float = 0.0

func _process(delta: float) -> void:
	# Update wave director with current enemy count (throttled for performance)
	if _wave_director and _enemy_container and Engine.get_process_frames() % 10 == 0:
		_wave_director.set_enemy_count(_enemy_container.get_child_count())
	
	# Handle Goddess Fall Timer (WaveDirector is deleted in this mode)
	if GameManager and (GameManager.goddess_fall_mode or GameManager.she_descends_mode) and _wave_director == null:
		_goddess_elapsed += delta
		if _wave_ui:
			_wave_ui.update_time(_goddess_elapsed, 175.0)

func _on_enemy_spawn_requested(enemy_type: String, count: int, pattern: String) -> void:
	# print("[Level] _on_enemy_spawn_requested: type=", enemy_type, " count=", count, " pattern=", pattern)
	if not _enemy_spawner:
		print("[Level] ERROR: No enemy spawner!")
		return
	
	# Set random horde direction at start of horde
	if pattern == "horde":
		_enemy_spawner.start_random_horde_direction()
	
	for i in range(count):
		var enemy: Node2D = _enemy_spawner.spawn_enemy(enemy_type, pattern)
		if enemy:
			# print("[Level] Enemy spawned successfully: ", enemy.name, " groups=", enemy.get_groups())
			# Apply night boost
			if _current_night_boost > 0.0:
				call_deferred("_set_enemy_night_boost", enemy, _current_night_boost)
			
			# Check for boss death to notify director
			if enemy.is_in_group("boss"):
				var is_super := enemy.is_in_group("super_boss")
				# Prevent duplicate signal connection (causes crash on return to menu)
				var callable = _on_boss_died.bind(is_super)
				if not enemy.tree_exiting.is_connected(callable):
					enemy.tree_exiting.connect(callable)
		else:
			print("[Level] ERROR: spawn_enemy returned null!")

func _on_event_started(event_type: String, event_data: Dictionary) -> void:
	if _wave_ui:
		var elapsed: float = _wave_director.get_elapsed_time() if _wave_director else 0.0
		_wave_ui.show_event(event_type, event_data, elapsed)

func _on_event_ended(_event_type: String) -> void:
	pass # Could add cleanup logic here

func _on_boss_incoming(_boss_type: String, time_until: float) -> void:
	if _wave_ui:
		_wave_ui.show_boss_warning(time_until)

func _on_boss_died(is_super_boss: bool = false) -> void:
	# Don't award core if boss died from enrage (player loses)
	if GameManager and GameManager.has_meta("killed_by_enrage") and GameManager.get_meta("killed_by_enrage"):
		print("[Level] Boss died from enrage - no core awarded")
	else:
		# Award Pristine Rapture Core for killing a boss - spawn visual orb
		_spawn_pristine_core_orb_at_boss()
	
	if _wave_director:
		_wave_director.notify_boss_defeated(is_super_boss)

func _spawn_pristine_core_orb_at_boss() -> void:
	# Spawn a core orb at the center of the screen (boss death location approximation)
	# Since the boss is already freed, we spawn at center viewport
	var camera := get_viewport().get_camera_2d()
	if not camera:
		return
	
	var spawn_pos := camera.global_position
	
	var orb_script := preload("res://scripts/world/PristineCoreOrb.gd")
	var orb := Area2D.new()
	orb.set_script(orb_script)
	orb.cores_value = 1
	orb.global_position = spawn_pos
	# Use call_deferred to safely add child during signal callback
	_enemy_container.call_deferred("add_child", orb)
	print("[Level] Spawned Pristine Core orb for boss kill")

func _on_run_complete(survived: bool, final_time: float) -> void:
	@warning_ignore("integer_division")
	var mins := int(final_time) / 60
	var secs := int(final_time) % 60
	if survived:
		print("[Level] RUN COMPLETE! Survived %d:%02d" % [mins, secs])
		# Mark stage as cleared
		if GameManager:
			GameManager.mark_stage_cleared(GameManager.current_stage_id)
			# Core is awarded via orb when boss dies, no need to add here
			
			# Track win achievement for all characters in squad
			# Track win achievement for all characters in squad
			_track_win_achievement()
			
			# Notify event bus
			if EventBus:
				EventBus.run_completed.emit(true, GameManager.current_stage_id, final_time)
		
		# Show victory screen
		var pause_menu = get_node_or_null("PauseMenu")
		if pause_menu and pause_menu.has_method("show_victory"):
			pause_menu.show_victory()
	else:
		print("[Level] Run ended at %d:%02d" % [mins, secs])

var _is_rapture_active: bool = false

func _on_time_updated(elapsed: float, remaining: float) -> void:
	if _wave_ui:
		if _is_rapture_active:
			_wave_ui.set_custom_timer_text("SURVIVE")
		else:
			_wave_ui.update_time(elapsed, remaining)

# --- RAPTURE EVENT LOGIC ---

func _on_rapture_event_started() -> void:
	_is_rapture_active = true
	print("[Level] RAPTURE EVENT STARTED! Triggering environment shifts...")
	
	# Spawn the Queen and track her death
	if _enemy_spawner and _enemy_spawner.has_method("spawn_rapture_queen"):
		var queen = _enemy_spawner.spawn_rapture_queen()
		if queen:
			queen.tree_exiting.connect(_on_rapture_queen_defeated)
	
	# Weather is handled by _on_rapture_queen_spawned (emitted by spawner), 
	# but we call it here explicitly just in case spawner fails or we want redundancy.
	_trigger_rapture_weather()
	
	# Update HUD Text
	var canvas = get_node_or_null("CanvasLayer")
	if canvas:
		var wave_display = canvas.get_node_or_null("WaveDisplay")
		if wave_display:
			wave_display.text = "ENDGAME"

func _on_rapture_queen_defeated() -> void:
	# Called when Queen node is freed (tree_exiting)
	# Reset Camera Zoom via CombatJuice
	if CombatJuice.instance:
		var tween = create_tween()
		tween.tween_property(CombatJuice.instance, "_base_zoom", Vector2.ONE, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		var camera = get_viewport().get_camera_2d()
		if camera:
			var tween = create_tween()
			tween.tween_property(camera, "zoom", Vector2.ONE, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Check if player is alive (if player dead, run lost already handled)
	if player and is_instance_valid(player) and player.hp > 0:
		print("[Level] RAPTURE QUEEN DEFEATED!")
		if _wave_director and _wave_director.has_method("notify_rapture_queen_defeated"):
			_wave_director.notify_rapture_queen_defeated()

func _on_rapture_queen_spawned() -> void:
	print("[Level] Rapture Queen detected! Enforcing weather...")
	_trigger_rapture_weather()
	
	# Cinematic Camera Zoom Out (User Request) - via CombatJuice to prevent snap-back
	if CombatJuice.instance:
		var tween = create_tween()
		tween.tween_property(CombatJuice.instance, "_base_zoom", Vector2(0.7, 0.7), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		# Fallback if CombatJuice invalid (unlikely)
		var camera = get_viewport().get_camera_2d()
		if camera:
			var tween = create_tween()
			tween.tween_property(camera, "zoom", Vector2(0.7, 0.7), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _trigger_rapture_weather() -> void:
	# 1. Force Night
	if environment and environment.has_method("set_time_of_day"):
		environment.set_time_of_day("night")
		_update_ambient_systems(_get_current_biome(), "night")
		
	# 2. Force Rain (unless Snow)
	var current_biome = _get_current_biome()
	
	# If snowfield, keep snow (particles are snow already).
	# If NOT snowfield, force "rain_forest" particle config to get Rain.
	if current_biome != "snowfield":
		if _ambient_particles:
			# Configure for rain forest (heavy rain) but keep "night" flag
			_ambient_particles.configure("rain_forest", true)
			print("[Level] Weather changed to RAIN")
			
	# 3. Start Lightning
	_start_lightning_system()


# --- SHE DESCENDS EASTER EGG MODE ---

func _start_she_descends_mode() -> void:
	## Easter egg mode: immediate N01 fight with modified rules
	print("[Level] SHE DESCENDS mode activated!")
	_is_rapture_active = true
	
	# Force night and weather effects
	_trigger_rapture_weather()
	
	# Disable wave director
	if _wave_director:
		_wave_director.queue_free()
		_wave_director = null
	
	# Force UI into Goddess Mode (Override)
	# This ensures HUD says ENDGAME even if GameManager flags are flaky
	if _wave_ui and _wave_ui.has_method("set_goddess_mode"):
		_wave_ui.set_goddess_mode(true)
	
	# Spawn N01 immediately (with short delay for dramatic effect)
	await get_tree().create_timer(1.5).timeout
	
	if _enemy_spawner and _enemy_spawner.has_method("spawn_rapture_queen"):
		var queen = _enemy_spawner.spawn_rapture_queen()
		if queen:
			# Connect defeat handler
			queen.tree_exiting.connect(_on_she_descends_queen_defeated)
			
			# Entrance animation: start above screen, descend dramatically
			_animate_queen_descent(queen)
	
	# Play timer.mp3 theme (fresh start)
	if AudioDirector:
		AudioDirector.play_music_by_path("res://assets/sounds/music/bgm/timer.mp3", true, 0.5)


func _animate_queen_descent(queen: Node2D) -> void:
	## Animate N01 descending from above the screen
	if not queen or not is_instance_valid(queen):
		return
	
	# Get player position for target
	var target_pos := Vector2.ZERO
	if player and is_instance_valid(player):
		target_pos = player.global_position + Vector2(0, -400) # Above player
	
	# Start N01 way above the screen
	var start_pos := target_pos + Vector2(0, -1200)
	queen.global_position = start_pos
	
	# Disable attacks during descent
	if queen.has_method("set_attacks_enabled"):
		queen.set_attacks_enabled(false)
	var boss_ai = queen.get_node_or_null("BossAI")
	if boss_ai:
		boss_ai.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Camera zoom out for dramatic effect
	_on_rapture_queen_spawned()
	
	# Animate descent over 3 seconds
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(queen, "global_position", target_pos, 3.0)
	
	# After descent, enable attacks
	tween.tween_callback(func():
		if queen and is_instance_valid(queen):
			if queen.has_method("set_attacks_enabled"):
				queen.set_attacks_enabled(true)
			if boss_ai:
				boss_ai.process_mode = Node.PROCESS_MODE_INHERIT
			print("[Level] N01 descent complete, attacks enabled!")
	)


func _on_she_descends_queen_defeated() -> void:
	## Called when N01 is defeated in easter egg mode
	print("[Level] SHE DESCENDS: N01 defeated!")
	
	# Reset camera
	if CombatJuice.instance:
		var tween = create_tween()
		tween.tween_property(CombatJuice.instance, "_base_zoom", Vector2.ONE, 2.0)
	
	# Reset the mode flag
	if GameManager:
		GameManager.she_descends_mode = false
	
	# Show victory screen after brief delay
	await get_tree().create_timer(2.0).timeout
	if _wave_director == null and player and is_instance_valid(player) and player.hp > 0:
		# Player won this special mode
		if GameManager:
			GameManager.record_run_result("")
		# Trigger victory/end (show defeat menu which can show victory state)
		show_defeat_menu()

func _start_lightning_system() -> void:
	# Check if already running
	if has_node("LightningTimer"): return
	
	var timer = Timer.new()
	timer.name = "LightningTimer"
	timer.wait_time = 3.0 # Initial wait
	timer.one_shot = true
	timer.timeout.connect(_on_lightning_timer)
	add_child(timer)
	timer.start()
	print("[Level] Lightning system activated")

func _on_lightning_timer() -> void:
	# Trigger Flash
	_trigger_lightning_flash()
	
	# Schedule next flash (random interval 2-8 seconds)
	var timer = get_node_or_null("LightningTimer")
	if timer:
		timer.wait_time = randf_range(2.0, 8.0)
		timer.start()

func _trigger_lightning_flash() -> void:
	# Visual Flash
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.9, 0.9, 1.0, 0.3) # Bright white-blue
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Add to a high-layer canvas
	var canvas = CanvasLayer.new()
	canvas.layer = 120 # Top top
	add_child(canvas)
	canvas.add_child(flash)
	
	# Twin: Flash fast then fade
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 1.0, 0.05) # Instant max
	tween.tween_property(flash, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func(): canvas.queue_free())
	
	# Sound (Placeholder or actual if available)
	# TODO: Play loud thunder sound
	# AudioSystem.play_sfx("thunder") if exists

func _get_current_biome() -> StringName:
	if environment and environment.has_method("get_active_biome"):
		var b = environment.get_active_biome()
		if b: return b.biome_id
	return &"grasslands" # Fallback

func _on_wave_changed(wave_number: int) -> void:
	# print("[Level] Wave changed to: ", wave_number)
	# Update GameManager with current wave for leaderboard
	if GameManager:
		GameManager.set_current_wave(wave_number)
		
	# Unlock "ABANDONED WISHES" Achievement at Wave 10
	if wave_number == 10:
		if AchievementManager:
			AchievementManager._unlock_achievement(
				AchievementManager.get_achievement_id(AchievementManager.AchievementType.ABANDONED_WISHES, ""),
				"",
				AchievementManager.AchievementType.ABANDONED_WISHES
			)
			# Refresh playlist to include new track immediately
			if AudioDirector:
				AudioDirector._update_playlist()
	
	# Update spawner with new health multiplier
	if _enemy_spawner and _wave_director:
		var health_mult: float = _wave_director.get_health_multiplier()
		# print("[Level] Setting health multiplier to: ", health_mult)
		_enemy_spawner.set_health_multiplier(health_mult)
	# Update the WaveDisplay label in the scene
	var canvas := get_node_or_null("CanvasLayer")
	if canvas:
		var wave_display := canvas.get_node_or_null("WaveDisplay") as Label
		if wave_display:
			wave_display.text = "WAVE %d" % wave_number

func _on_enemy_died(enemy: Node2D, killer_source: String = "player") -> void:
	# Handle charmed enemy deaths specially for Sin's Captivating talent
	if enemy.is_in_group("charmed_allies"):
		_on_charmed_enemy_died(enemy)
		return
	
	# Notify player for kill-based upgrades (Rapunzel healing, etc.)
	if player and player.has_method("on_enemy_killed"):
		player.on_enemy_killed(enemy, killer_source)

func _on_charmed_enemy_died(enemy: Node2D) -> void:
	"""Handle death of a charmed (mind-controlled) enemy for Sin's Captivating talent."""
	if not player:
		return
	
	# Check Sin's Captivating talent level directly from controller
	var captivating_level: int = 0
	if player.has_method("get_sin_captivating_level"):
		captivating_level = player.get_sin_captivating_level()
	
	if captivating_level <= 0:
		return
	
	# Level 1+: Explode on death (15x Sin's ATK damage)
	if captivating_level >= 1:
		_spawn_charmed_death_explosion(enemy.global_position)
	
	# Level 2+: Heal player for 1 HP
	if captivating_level >= 2:
		var heal_amount: int = 1
		player.hp = min(player.hp + heal_amount, player.max_hp)
		if player.has_method("_update_health_display"):
			player._update_health_display(heal_amount, false)

func _spawn_charmed_death_explosion(death_pos: Vector2) -> void:
	"""Spawn a rocket-sized explosion when a charmed enemy dies (Captivating Lv2+)."""
	const EXPLOSION_RADIUS := 120.0 # Rocket-sized
	
	if not player:
		return
	
	# Calculate damage as 15x Sin's ATK (uses player's calc_damage which includes level scaling)
	var base_damage: int = player.calc_damage() if player.has_method("calc_damage") else 10
	var damage: int = base_damage * 15
	
	# Damage nearby enemies
	var tree := get_tree()
	if tree:
		var enemies := tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy is Node2D:
				continue
			# Don't damage other charmed allies
			if enemy.is_in_group("charmed_allies"):
				continue
			
			var dist: float = enemy.global_position.distance_to(death_pos)
			if dist > EXPLOSION_RADIUS:
				continue
			
			if enemy.has_method("take_damage"):
				var hit_dir: Vector2 = (enemy.global_position - death_pos).normalized()
				enemy.take_damage(damage, false, hit_dir, true)
	
	# Visual explosion effect
	var visual := Node2D.new()
	visual.set_script(_create_explosion_visual_script())
	visual.set("radius", EXPLOSION_RADIUS)
	visual.set("color", Color(1.0, 0.3, 0.6, 0.8)) # Pink/magenta for Sin's charm
	add_child(visual)
	visual.global_position = death_pos

func _create_explosion_visual_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var radius: float = 120.0
var color: Color = Color(1.0, 0.3, 0.6, 0.8)
var _time: float = 0.0
var _duration: float = 0.35

func _ready() -> void:
	z_index = 200

func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	var current_radius := radius * (0.5 + progress * 0.5)
	var alpha := (1.0 - progress) * color.a
	
	# Explosion ring
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 32, Color(color.r, color.g, color.b, alpha), 6.0)
	
	# Inner flash
	var inner_alpha := alpha * 0.5 * (1.0 - progress)
	draw_circle(Vector2.ZERO, current_radius * 0.7, Color(1.0, 0.8, 1.0, inner_alpha))
"""
	script.reload()
	return script

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
	
	var margin = 200.0 # Extra distance outside viewport
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


## Track win achievement for all squad members
func _track_win_achievement() -> void:
	if not has_node("/root/AchievementManager"):
		return
	
	var achievement_manager = get_node("/root/AchievementManager")
	
	# Get squad character IDs from GameManager
	var char_ids: Array = []
	if GameManager:
		var registry = CharacterRegistry.get_instance()
		if registry:
			var all_ids: Array = registry.get_all_character_ids()
			for idx in GameManager.selected_character_indices:
				if idx >= 0 and idx < all_ids.size():
					char_ids.append(all_ids[idx])
	
	if char_ids.size() > 0:
		print("[Level] Tracking win for squad: %s" % str(char_ids))
		achievement_manager.on_game_won(char_ids)


# Styled container for Pristine Rapture Cores (matching shop style)
class _PristineCoreContainer extends Control:
	const UI := preload("res://scripts/ui/UITheme.gd")
	const CONTAINER_WIDTH := 200.0
	const CONTAINER_HEIGHT := 65.0
	const BORDER_THICKNESS := 2.0
	const CORNER_CUT := 8.0
	
	var _count_label: Label = null
	var _glow_time: float = 0.0
	var _flash_time: float = 0.0 # Time remaining for collection flash
	
	func _init() -> void:
		custom_minimum_size = Vector2(CONTAINER_WIDTH, CONTAINER_HEIGHT)
	
	func _ready() -> void:
		_build_container()
	
	func _process(delta: float) -> void:
		_glow_time += delta
		if _flash_time > 0:
			_flash_time -= delta
		queue_redraw()
	
	func update_count(value: int) -> void:
		if _count_label:
			_count_label.text = str(value)
	
	func flash_collected() -> void:
		_flash_time = 0.5 # Flash for 0.5 seconds
	
	func _build_container() -> void:
		# Main content HBox
		var content := HBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 12
		content.offset_right = -12
		content.offset_top = 16
		content.offset_bottom = -6
		content.add_theme_constant_override("separation", 8)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(content)
		
		# Core icon
		var icon := _PristineCoreIcon.new()
		icon.custom_minimum_size = Vector2(32, 32)
		content.add_child(icon)
		
		# Count label
		_count_label = Label.new()
		_count_label.text = str(GameManager.get_pristine_cores()) if GameManager else "0"
		_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_count_label.add_theme_font_size_override("font_size", 28)
		_count_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 1.0))
		_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_count_label.add_theme_constant_override("shadow_offset_x", 2)
		_count_label.add_theme_constant_override("shadow_offset_y", 2)
		content.add_child(_count_label)
	
	func _draw() -> void:
		var w := size.x
		var h := size.y
		
		# Calculate flash intensity
		var flash_intensity: float = 0.0
		if _flash_time > 0:
			flash_intensity = _flash_time / 0.5 # 0 to 1 based on remaining time
		
		# Pulsing glow effect (enhanced during flash)
		var base_pulse: float = 0.4 + 0.15 * sin(_glow_time * 2.5)
		var glow_pulse: float = base_pulse + flash_intensity * 0.6
		
		# Draw outer glow (larger and more intense during flash)
		var glow_layers := 4 + int(flash_intensity * 4)
		for i in range(glow_layers, 0, -1):
			var glow_alpha: float = glow_pulse * 0.08 * (1.0 - float(i) / float(glow_layers))
			glow_alpha += flash_intensity * 0.15
			var offset: float = float(i) * (2.0 + flash_intensity * 2.0)
			var glow_rect := Rect2(-offset, -offset, w + offset * 2, h + offset * 2)
			draw_rect(glow_rect, Color(1.0, 0.2 + flash_intensity * 0.3, 0.2, glow_alpha))
		
		# Draw background with cut corners (brighter during flash)
		var bg_brightness := 0.05 + flash_intensity * 0.15
		var bg_points := PackedVector2Array([
			Vector2(CORNER_CUT, 0),
			Vector2(w - CORNER_CUT, 0),
			Vector2(w, CORNER_CUT),
			Vector2(w, h - CORNER_CUT),
			Vector2(w - CORNER_CUT, h),
			Vector2(CORNER_CUT, h),
			Vector2(0, h - CORNER_CUT),
			Vector2(0, CORNER_CUT)
		])
		draw_colored_polygon(bg_points, Color(bg_brightness, bg_brightness * 0.8, bg_brightness * 0.8, 0.9))
		
		# Draw border (brighter during flash)
		var border_brightness := 0.8 + flash_intensity * 0.2
		for i in range(bg_points.size()):
			var p1: Vector2 = bg_points[i]
			var p2: Vector2 = bg_points[(i + 1) % bg_points.size()]
			draw_line(p1, p2, Color(border_brightness, 0.25 + flash_intensity * 0.5, 0.2, 0.9), BORDER_THICKNESS + flash_intensity * 2.0, true)
		
		# Draw "PRISTINE RAPTURE CORES" title at top
		var title_text := "PRISTINE RAPTURE CORES"
		var title_size := 9
		var font := ThemeDB.fallback_font
		var title_width: float = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		var title_x: float = (w - title_width) / 2.0
		draw_string(font, Vector2(title_x, 11), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.7, 0.7, 0.7, 0.9))
