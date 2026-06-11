extends Node2D

const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")
const DamageLogScript = preload("res://scripts/autoload/DamageLog.gd")

@onready var environment: Node2D = $Environment
@onready var map_selector: Control = $CanvasLayer/MapSelector
@onready var player: CharacterBody2D = $Player

var _env_director: LevelEnvironmentDirector = null

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
	set_process_input(true) # Ensure we receive input events
	
	# Reset run stats for new game
	if GameManager:
		GameManager.reset_run_stats()
	
	# Clear damage log for new run
	var dl := DamageLogScript.get_instance()
	if dl:
		dl.clear()
	
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
	
	# Wave system is initialized in _initialize_stage_environment
	
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
	
	# Setup environment director (handles biome, time, ambient, lightning)
	_setup_environment_director()
	
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
	
	# Initialize environment from stage
	_initialize_stage_environment()
	
	# She Descends easter egg mode: spawn N01 immediately
	if GameManager and (GameManager.she_descends_mode or GameManager.goddess_fall_mode):
		_start_she_descends_mode()
		return # Skip normal run start
	
	# Notify run started
	if GameManager and EventBus:
		EventBus.run_started.emit(GameManager.current_stage_id)
		
	# Start background music based on initial character
	_play_character_bgm()

# Removed _on_character_switched to prevent music changing during gameplay

func _play_character_bgm(forced_index: int = -1) -> void:
	if not GameManager or not AudioDirector:
		return
		
	# Determine which character to play music for
	var main_char_idx = GameManager.player_character_index
	if forced_index != -1:
		main_char_idx = forced_index
	
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
	
	# Re-show the pause menu
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.visible = true

func _on_character_select_requested() -> void:
	get_tree().paused = false
	
	# Reset Engine logic first
	Engine.time_scale = 1.0
	if CombatJuice:
		CombatJuice.reset()
	if GameManager:
		GameManager.enemy_time_scale = 1.0
		# Record run result (as defeat/quit)
		GameManager.record_run_result("")
		
	# Update Audio
	if AudioDirector:
		AudioDirector.stop_music(0.5)
		AudioDirector.stop_ambient(0.5)
	
	TargetCache.force_refresh()

	# Standard Behavior
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
	
	# Clear target cache before scene change
	TargetCache.force_refresh()
	
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

func _setup_environment_director() -> void:
	_env_director = LevelEnvironmentDirector.new()
	_env_director.name = "EnvironmentDirector"
	add_child(_env_director)
	_env_director.environment_node = environment
	_env_director.player_node = player
	_env_director.setup_ambient_particles()

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
	
	# Delegate environment initialization to the director
	if _env_director:
		_env_director.initialize_stage_environment()
	
	# Get stage info for spawn rule handling
	var stage_id: String = GameManager.current_stage_id if GameManager else "stage_1"
	var StageRegistryClass := load("res://scripts/systems/StageRegistry.gd")
	var stage: Dictionary = StageRegistryClass.get_stage(stage_id) if StageRegistryClass else {}
	
	if stage.is_empty():
		# Fallback standard mode
		_setup_wave_system()
		return
	
	var spawn_rules: Dictionary = stage.get("spawn_rules", {})
	
	# Standard mode — set up wave system (hunt mode removed; defense mode retired)
	_setup_wave_system()
	
	# Apply modifiers
	if _enemy_spawner and spawn_rules.get("elite_only", false):
		_enemy_spawner.set_elite_only_mode(true)
		print("[Level] Elite-only mode enabled")
	if _wave_director and spawn_rules.get("endless", false):
		_wave_director.set_endless_mode(true)
		print("[Level] Endless mode enabled")

func _on_map_selected(map_id: StringName) -> void:
	if _env_director:
		_env_director.apply_map(map_id)

func _on_time_selected(time_id: StringName) -> void:
	if _env_director:
		_env_director.apply_time_of_day(time_id)

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
	
	# Connect queen spawn signal for weather trigger (works for ALL spawn methods including dev commands)
	if _enemy_spawner.has_signal("rapture_queen_spawned"):
		_enemy_spawner.rapture_queen_spawned.connect(_on_rapture_queen_spawned)
	
	# Set map bounds for spawning
	var world_size := 4000.0
	var bounds := Rect2(-world_size / 2, -world_size / 2, world_size, world_size)
	_enemy_spawner.set_map_bounds(bounds)
	
	# Set environment bounds for particle restrictions
	if environment and environment.has_method("set_world_bounds"):
		environment.set_world_bounds(bounds)
	
	# Create wave UI (hidden in exploration mode - uses progress-based HUD instead)
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
	
	# Connect queen spawn event for weather trigger
	if _wave_director.has_signal("rapture_event_started"):
		_wave_director.rapture_event_started.connect(_on_rapture_queen_spawned)
	
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
	
	# Kilo's "Core-version Overdrive" - +50% extra cores
	var extra_cores := 0
	if _has_kilo_core_boost():
		for i in range(count):
			if randf() < 0.5:
				extra_cores += 1
		if extra_cores > 0:
			print("[Level] Kilo Core-version Overdrive: +%d extra cores!" % extra_cores)
	
	var total_count := count + extra_cores
	
	# Spawn orbs
	for i in range(total_count):
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
		
	print("[Level] Spawned %d Pristine Core(s) as reward" % total_count)

	print("[Level] Spawned %d Pristine Core(s) as reward" % total_count)

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
	if not _enemy_spawner:
		print("[Level] ERROR: No enemy spawner!")
		return
	
	if enemy_type == "n01_queen":
		# Special handling for Rapture Queen
		if _enemy_spawner.has_method("spawn_rapture_queen"):
			var queen = _enemy_spawner.spawn_rapture_queen()
			if queen:
				print("[Level] Rapture Queen spawned via signal request.")
				# Track death for victory condition
				# Bind "n01_queen" as the boss_id
				var callable = _on_boss_died.bind(true, "n01_queen")
				if not queen.tree_exiting.is_connected(callable):
					queen.tree_exiting.connect(callable)
		return

	# Set random horde direction at start of horde
	if pattern == "horde":
		_enemy_spawner.start_random_horde_direction()
	
	for i in range(count):
		var enemy: Node2D = _enemy_spawner.spawn_enemy(enemy_type, pattern)
		if enemy:
			# Apply night boost
			var night_boost := _env_director.get_night_boost() if _env_director else 0.0
			if night_boost > 0.0:
				call_deferred("_apply_night_boost_to_enemy", enemy, night_boost)
			
			# Check for boss death to notify director
			if enemy.is_in_group("boss"):
				var is_super := enemy.is_in_group("super_boss")
				# Prevent duplicate signal connection (causes crash on return to menu)
				# Pass empty string for ID, or derive from metadata if needed
				var callable = _on_boss_died.bind(is_super, "")
				if not enemy.tree_exiting.is_connected(callable):
					enemy.tree_exiting.connect(callable) # Generic boss

func _on_event_started(event_type: String, event_data: Dictionary) -> void:
	if _wave_ui:
		var elapsed: float = _wave_director.get_elapsed_time() if _wave_director else 0.0
		_wave_ui.show_event(event_type, event_data, elapsed)

func _on_event_ended(_event_type: String) -> void:
	pass # Could add cleanup logic here

func _on_boss_incoming(_boss_type: String, time_until: float) -> void:
	if _wave_ui:
		_wave_ui.show_boss_warning(time_until)

func _on_boss_died(is_super_boss: bool = false, boss_id: String = "") -> void:
	# Don't award core if boss died from enrage (player loses)
	if GameManager and GameManager.has_meta("killed_by_enrage") and GameManager.get_meta("killed_by_enrage"):
		print("[Level] Boss died from enrage - no core awarded")
	else:
		# Award Pristine Rapture Core for killing a boss - spawn visual orb
		_spawn_pristine_core_orb_at_boss()
	
	if _wave_director:
		_wave_director.notify_boss_defeated(is_super_boss, boss_id)

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
	
	# Kilo's "Core-version Overdrive" - 50% chance for extra core on boss kill
	if _has_kilo_core_boost():
		if randf() < 0.5:
			var extra_orb := Area2D.new()
			extra_orb.set_script(orb_script)
			extra_orb.cores_value = 1
			# Offset slightly so they don't overlap
			extra_orb.global_position = spawn_pos + Vector2(randf_range(-50, 50), randf_range(-50, 50))
			_enemy_container.call_deferred("add_child", extra_orb)
			print("[Level] Kilo Core-version Overdrive: Extra core dropped!")

## Check if Kilo's "Core-version Overdrive" upgrade is active
func _has_kilo_core_boost() -> bool:
	if not player:
		return false
	# Check if playing Kilo
	if player.has_method("is_playing_character"):
		if not player.is_playing_character("kilo"):
			return false
	else:
		return false
	# Check if upgrade is purchased
	if ShopMenuScript and ShopMenuScript.has_character_upgrade("kilo", "core_drop"):
		return true
	return false

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
			
			# Track win achievement for the played character
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
	if _env_director:
		_env_director.trigger_rapture_weather()


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
	
	# Update HUD Text IMMEDIATELY (CanvasLayer is from scene file, already exists)
	var canvas = get_node_or_null("CanvasLayer")
	if canvas:
		var wave_display = canvas.get_node_or_null("WaveDisplay")
		if wave_display:
			wave_display.text = "DEFEAT THE QUEEN"
	
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
	if player and is_instance_valid(player) and player.hp > 0:
		# Player won this special mode
		if GameManager:
			GameManager.record_run_result("")
		# Show victory screen
		if not _pause_menu:
			_setup_pause_menu()
		_pause_menu.show_victory()

## Apply night boost shader parameter to a newly spawned enemy.
## Called via call_deferred from _on_enemy_spawn_requested.
func _apply_night_boost_to_enemy(enemy: Node, night_boost: float) -> void:
	if not is_instance_valid(enemy):
		return
	var sprite := enemy.get_node_or_null("Sprite2D") as CanvasItem
	if not sprite:
		sprite = enemy.get_node_or_null("AnimatedSprite2D") as CanvasItem
	if not sprite:
		for child in enemy.get_children():
			if child is Sprite2D or child is AnimatedSprite2D:
				sprite = child
				break
	if sprite and sprite.material is ShaderMaterial:
		var mat := sprite.material as ShaderMaterial
		if mat.shader:
			mat.set_shader_parameter("night_boost", night_boost)

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
			# Wave 12 is N01 boss fight
			if wave_number == 12:
				wave_display.text = "DEFEAT THE QUEEN"
			else:
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
	var script := preload("res://scripts/effects/visuals/LevelExplosionVisual.gd")
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


## Track win achievement for the selected character
func _track_win_achievement() -> void:
	if not has_node("/root/AchievementManager"):
		return

	var achievement_manager = get_node("/root/AchievementManager")

	# Get the selected character ID from GameManager
	var char_ids: Array = []
	if GameManager:
		var registry = CharacterRegistry.get_instance()
		if registry:
			var all_ids: Array = registry.get_all_character_ids()
			var idx: int = GameManager.player_character_index
			if idx >= 0 and idx < all_ids.size():
				char_ids.append(all_ids[idx])

	if char_ids.size() > 0:
		print("[Level] Tracking win for: %s" % str(char_ids))
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
