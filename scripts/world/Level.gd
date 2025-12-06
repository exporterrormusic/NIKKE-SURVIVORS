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

func _ready():
	_rng.randomize()
	set_process_input(true)  # Ensure we receive input events
	
	# Reset run stats for new game
	if GameState:
		GameState.reset_run_stats()
	
	# Reset achievement session tracking
	if has_node("/root/AchievementManager"):
		get_node("/root/AchievementManager").reset_session()
	
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
	
	# Setup wave system (must be before environment so spawn rules are ready)
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
	
	# Initialize ambient particle system
	_setup_ambient_particles()
	
	# Initialize night glow system
	_setup_night_glow()
	
	# Set world bounds BEFORE initializing environment so grass field uses correct size
	var world_size = 4000.0
	environment.set_world_bounds(Rect2(-world_size/2, -world_size/2, world_size, world_size))
	
	# Initialize environment from stage (or random fallback)
	_initialize_stage_environment()

var _pause_menu: CanvasLayer = null

func _input(event: InputEvent) -> void:
	# Don't process if game is paused and pause menu is handling it
	if _pause_menu and _pause_menu.visible:
		return
	
	if event.is_action_pressed("ui_cancel"):  # ESC key
		print("[Level] ESC pressed - toggling pause menu")
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
		canvas_layer.layer = 101  # Above pause menu (layer 100)
		canvas_layer.name = "SettingsLayer"
		add_child(canvas_layer)
		
		var settings = settings_scene.instantiate()
		settings.process_mode = Node.PROCESS_MODE_ALWAYS  # Work while paused
		canvas_layer.add_child(settings)
		
		# Connect back signal to close settings
		settings.back_requested.connect(_on_settings_closed.bind(canvas_layer))

func _on_settings_closed(canvas_layer: CanvasLayer) -> void:
	# Remove the settings menu and its canvas layer
	if canvas_layer and is_instance_valid(canvas_layer):
		canvas_layer.queue_free()

func _on_character_select_requested() -> void:
	get_tree().paused = false
	# Record the run result before leaving (save score even if player didn't die)
	if GameState:
		GameState.record_run_result("")
	get_tree().change_scene_to_file("res://scenes/ui/CharacterSelectMenu.tscn")

func _on_quit_requested() -> void:
	get_tree().paused = false
	# Record the run result before quitting (save score even if player didn't die)
	if GameState:
		GameState.record_run_result("")
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
	var stage_id: String = GameState.current_stage_id if GameState else "stage_1"
	var StageRegistryClass := load("res://scripts/systems/StageRegistry.gd")
	var stage: Dictionary = StageRegistryClass.get_stage(stage_id) if StageRegistryClass else {}
	
	var biome: StringName
	var time: StringName
	
	# Use GameState.selected_biome and selected_time (set by map selector in StageSelector)
	# These override the stage's default biome/time
	if GameState.selected_biome != "" and GameState.selected_time != "":
		biome = StringName(GameState.selected_biome)
		time = StringName(GameState.selected_time)
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
		if _enemy_spawner and spawn_rules.get("elite_only", false):
			_enemy_spawner.set_elite_only_mode(true)
			print("[Level] Elite-only mode enabled")
		if _wave_director and spawn_rules.get("endless", false):
			_wave_director.set_endless_mode(true)
			print("[Level] Endless mode enabled")
	
	# Initialize environment
	environment.initialize_environment(0, biome, time)
	
	# Update ambient particles
	_update_ambient_systems(biome, time)

func _initialize_random_environment() -> void:
	# Legacy function - redirects to stage-based initialization
	_initialize_stage_environment()

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
	_enemy_spawner.set_map_bounds(Rect2(-world_size/2, -world_size/2, world_size, world_size))
	
	# Create wave UI
	_wave_ui = CanvasLayer.new()
	_wave_ui.set_script(load("res://scripts/world/WaveUI.gd"))
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
	
	# Setup score UI in top-right corner
	_setup_score_ui()
	
	# Setup core counter in bottom-right corner
	_setup_core_counter()

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

func _setup_core_counter() -> void:
	# Create core counter in bottom-right corner
	_core_counter = CanvasLayer.new()
	_core_counter.name = "CoreCounterLayer"
	_core_counter.layer = 10
	add_child(_core_counter)
	
	var counter := Control.new()
	counter.name = "CoreCounter"
	counter.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	counter.offset_left = -180
	counter.offset_top = -70
	counter.offset_right = -20
	counter.offset_bottom = -20
	_core_counter.add_child(counter)
	
	# Background panel
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.border_color = Color(0.8, 0.25, 0.2, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	counter.add_child(panel)
	
	# HBox for icon + label - use CenterContainer for proper vertical centering
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	counter.add_child(center)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(hbox)
	
	# Pristine Core icon
	var icon := _PristineCoreIcon.new()
	icon.custom_minimum_size = Vector2(36, 36)
	hbox.add_child(icon)
	
	# Core count label
	var label := Label.new()
	label.name = "CoreLabel"
	label.text = str(GameState.get_pristine_cores())
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	hbox.add_child(label)
	
	print("[Level] Core counter initialized")

func _update_core_counter() -> void:
	if not _core_counter:
		return
	var counter := _core_counter.get_node_or_null("CoreCounter")
	if not counter:
		return
	var label := counter.get_node_or_null("HBoxContainer/CoreLabel") as Label
	if not label:
		# Try alternative path (hbox might be added directly)
		for child in counter.get_children():
			if child is HBoxContainer:
				label = child.get_node_or_null("CoreLabel") as Label
				break
	if label and GameState:
		label.text = str(GameState.get_pristine_cores())

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

func _process(_delta: float) -> void:
	# Update wave director with current enemy count
	if _wave_director and _enemy_container:
		_wave_director.set_enemy_count(_enemy_container.get_child_count())

func _on_enemy_spawn_requested(enemy_type: String, count: int, pattern: String) -> void:
	print("[Level] _on_enemy_spawn_requested: type=", enemy_type, " count=", count, " pattern=", pattern)
	if not _enemy_spawner:
		print("[Level] ERROR: No enemy spawner!")
		return
	
	# Set random horde direction at start of horde
	if pattern == "horde":
		_enemy_spawner.start_random_horde_direction()
	
	for i in range(count):
		var enemy: Node2D = _enemy_spawner.spawn_enemy(enemy_type, pattern)
		if enemy:
			print("[Level] Enemy spawned successfully: ", enemy.name, " groups=", enemy.get_groups())
			# Apply night boost
			if _current_night_boost > 0.0:
				call_deferred("_set_enemy_night_boost", enemy, _current_night_boost)
			
			# Check for boss death to notify director
			if enemy.is_in_group("boss"):
				var is_super := enemy.is_in_group("super_boss")
				enemy.tree_exiting.connect(_on_boss_died.bind(is_super))
		else:
			print("[Level] ERROR: spawn_enemy returned null!")

func _on_event_started(event_type: String, event_data: Dictionary) -> void:
	if _wave_ui:
		var elapsed: float = _wave_director.get_elapsed_time() if _wave_director else 0.0
		_wave_ui.show_event(event_type, event_data, elapsed)

func _on_event_ended(_event_type: String) -> void:
	pass  # Could add cleanup logic here

func _on_boss_incoming(_boss_type: String, time_until: float) -> void:
	if _wave_ui:
		_wave_ui.show_boss_warning(time_until)

func _on_boss_died(is_super_boss: bool = false) -> void:
	if _wave_director:
		_wave_director.notify_boss_defeated(is_super_boss)

func _on_run_complete(survived: bool, final_time: float) -> void:
	@warning_ignore("integer_division")
	var mins := int(final_time) / 60
	var secs := int(final_time) % 60
	if survived:
		print("[Level] RUN COMPLETE! Survived %d:%02d" % [mins, secs])
		# Mark stage as cleared
		if GameState:
			GameState.mark_stage_cleared(GameState.current_stage_id)
			# Award Pristine Rapture Core for defeating the boss
			GameState.add_pristine_cores(1)
			_update_core_counter()
			
			# Track win achievement for all characters in squad
			_track_win_achievement()
		
		# Show victory screen
		var pause_menu = get_node_or_null("PauseMenu")
		if pause_menu and pause_menu.has_method("show_victory"):
			pause_menu.show_victory()
	else:
		print("[Level] Run ended at %d:%02d" % [mins, secs])

func _on_time_updated(elapsed: float, remaining: float) -> void:
	if _wave_ui:
		_wave_ui.update_time(elapsed, remaining)

func _on_wave_changed(wave_number: int) -> void:
	print("[Level] Wave changed to: ", wave_number)
	
	# Update GameState with current wave for leaderboard
	if GameState:
		GameState.set_current_wave(wave_number)
	
	# Update spawner with new health multiplier
	if _enemy_spawner and _wave_director:
		var health_mult: float = _wave_director.get_health_multiplier()
		print("[Level] Setting health multiplier to: ", health_mult)
		_enemy_spawner.set_health_multiplier(health_mult)
	# Update the WaveDisplay label in the scene
	var canvas := get_node_or_null("CanvasLayer")
	if canvas:
		var wave_display := canvas.get_node_or_null("WaveDisplay") as Label
		if wave_display:
			wave_display.text = "WAVE %d" % wave_number

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


## Track win achievement for all squad members
func _track_win_achievement() -> void:
	if not has_node("/root/AchievementManager"):
		return
	
	var achievement_manager = get_node("/root/AchievementManager")
	
	# Get squad character IDs from GameState
	var char_ids: Array = []
	if GameState:
		var registry = CharacterRegistry.get_instance()
		if registry:
			var all_ids: Array = registry.get_all_character_ids()
			for idx in GameState.selected_character_indices:
				if idx >= 0 and idx < all_ids.size():
					char_ids.append(all_ids[idx])
	
	if char_ids.size() > 0:
		print("[Level] Tracking win for squad: %s" % str(char_ids))
		achievement_manager.on_game_won(char_ids)