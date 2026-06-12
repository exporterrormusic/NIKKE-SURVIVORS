extends Node
## Manages menu navigation and transitions between screens.
## Load this as an autoload or instantiate in your main scene.
## IMPORTANT: This must be the FIRST autoload to ensure intro screen renders before heavy loading.

# NO PRELOADS HERE - they block startup before first frame renders!
# UITheme and DebugMenu are loaded lazily after intro screen is visible.

# Static flag that other autoloads check before doing heavy initialization
# They should wait until this is true (intro screen has rendered at least one frame)
static var intro_rendered: bool = false

# Signal emitted when intro has rendered and other systems can start loading
signal intro_ready

# Intro screen instance (visuals delegated to IntroScreen.gd)
var _intro_screen_instance: IntroScreen = null

signal game_started(character_index: int, stage_id: String)

# Menu scenes - load on demand instead of preload to speed up startup
var MainMenuScene: PackedScene = null
var SettingsMenuScene: PackedScene = null
var CharacterSelectScene: PackedScene = null
var AchievementsScene: PackedScene = null
var LeaderboardScene: PackedScene = null
var ShopScene: PackedScene = null
var _debug_menu_script: Script = null # Loaded lazily

# Scene paths for lazy loading
const SCENE_PATHS := {
	"main_menu": ScenePaths.MAIN_MENU,
	"settings": ScenePaths.SETTINGS,
	"character_select": ScenePaths.CHARACTER_SELECT,
	"achievements": ScenePaths.ACHIEVEMENTS,
	"leaderboard": ScenePaths.LEADERBOARD,
	"shop": ScenePaths.SHOP,
}

# Current menu stack (for back navigation)
var _menu_stack: Array[Control] = []
var _current_menu: Control = null

# Container for menus
var _menu_container: Control = null

# Debug menu (global, always available via F4)
var _debug_menu: CanvasLayer = null

# Music player
# Music player handled by AudioDirector now
# var _music_player: AudioStreamPlayer = null
const MENU_MUSIC_PATH := ScenePaths.MUSIC_MAIN_MENU

var _loading_main_menu: bool = false # Prevents re-entry during async load
var _resources_ready: bool = false # True when all resources are loaded
var _preinstantiated_main_menu: Control = null # Pre-instantiated main menu (hidden until ready)
var _preinstantiation_scheduled: bool = false # Prevent multiple deferred calls
var _loading_delay_timer: Timer = null # Timer to delay heavy loading until after first frames render

const LOADING_CHARACTER_SPRITES := [
	ScenePaths.CHAR_SPRITE_KILO,
	ScenePaths.CHAR_SPRITE_MARIAN,
	ScenePaths.CHAR_SPRITE_NAYUTA,
	ScenePaths.CHAR_SPRITE_SCARLET,
]
var _selected_sprite_path: String = ""


func _ready() -> void:
	# Pick a random character sprite for the walking animation
	_selected_sprite_path = LOADING_CHARACTER_SPRITES[randi() % LOADING_CHARACTER_SPRITES.size()]
	
	# Create IntroScreen instance (visuals delegated to IntroScreen.gd)
	_intro_screen_instance = IntroScreen.new()
	_intro_screen_instance.dismissed.connect(_on_intro_dismissed)
	add_child(_intro_screen_instance)
	_intro_screen_instance.start(_selected_sprite_path)
	
	# Create a delay timer - this ensures the intro screen renders for a bit
	# before we start the heavy loading work
	_loading_delay_timer = Timer.new()
	_loading_delay_timer.one_shot = true
	_loading_delay_timer.wait_time = 0.1
	_loading_delay_timer.timeout.connect(_on_loading_delay_timeout)
	add_child(_loading_delay_timer)
	_loading_delay_timer.start()
	
	# Start loading resources in background
	call_deferred("_start_background_loading")


func _on_loading_delay_timeout() -> void:
	# Timer fired - now we can allow resource checking and pre-instantiation
	print("[MenuManager] Loading delay complete - animation should be visible now")
	_loading_delay_timer.queue_free()
	_loading_delay_timer = null # Setting to null allows _check_resources_loaded to proceed


func _input(_event: InputEvent) -> void:
	# If intro is still active, don't process menu navigation
	if _intro_screen_instance and is_instance_valid(_intro_screen_instance):
		return

	# Input Switching Logic (disabled):
	# If user uses controller but focus is lost (e.g. used mouse), restore focus immediately.
	# if event is InputEventJoypadButton or event is InputEventJoypadMotion:
	# 	if event is InputEventJoypadMotion and abs(event.axis_value) < 0.5:
	# 		return  # Ignore small motion
	# 	if get_viewport().gui_get_focus_owner() == null:
	# 		if _current_menu and is_instance_valid(_current_menu):
	# 			if _current_menu.has_method("_grab_initial_focus"):
	# 				_current_menu._grab_initial_focus()
	# 			else:
	# 				var btn := _find_first_focusable(_current_menu)
	# 				if btn:
	# 					btn.grab_focus()

var _last_frame_time: int = 0
var _first_frame_rendered: bool = false

func _process(_delta: float) -> void:
	# On the very first _process call, the intro screen has rendered at least once
	# Signal other autoloads that they can now do heavy initialization
	if not _first_frame_rendered:
		_first_frame_rendered = true
		MenuManager.intro_rendered = true
		print("[MenuManager] First frame rendered - signaling intro_ready")
		intro_ready.emit()
	
	# Track frame timing for debugging freezes
	var now := Time.get_ticks_msec()
	if _last_frame_time > 0:
		var frame_delta := now - _last_frame_time
		if frame_delta > 100: # More than 100ms between frames = freeze
			print("[MenuManager] FRAME FREEZE: %dms gap detected" % frame_delta)
	_last_frame_time = now
	
	# Check if resources are ready (only while intro is showing)
	if _intro_screen_instance and is_instance_valid(_intro_screen_instance) and not _resources_ready:
		_check_resources_loaded()


func _start_background_loading() -> void:
	# Request threaded loading of all needed resources
	ResourceLoader.load_threaded_request(MENU_MUSIC_PATH)
	ResourceLoader.load_threaded_request(SCENE_PATHS.main_menu)
	ResourceLoader.load_threaded_request(SCENE_PATHS.character_select)
	ResourceLoader.load_threaded_request("res://scripts/ui/DebugMenu.gd")
	# Also request the walking character sprite
	ResourceLoader.load_threaded_request(_selected_sprite_path)
	
	# Pre-request shader for venetian blinds overlay
	ResourceLoader.load_threaded_request(ScenePaths.SHADER_HEX_GRID)
	
	# Pre-request all background textures for the venetian blinds
	# This prevents the main menu instantiation from blocking on texture loads
	var bg_files := [
		"ark.jpg", "battlefield1.jpg", "bunker-interior.jpg", "eden.jpg",
		"forest.jpg", "hg.jpg", "kingdom.jpg", "mushroom.jpg",
		"rapturefield1.jpg", "rapturefield2.jpg", "snow-day.jpg",
		"snow-night.jpg", "space.jpg"
	]
	for file in bg_files:
		ResourceLoader.load_threaded_request(ScenePaths.BG_BASE + file)
	
	# Create menu container
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 10
	menu_layer.name = "MenuLayer"
	add_child(menu_layer)
	
	_menu_container = Control.new()
	_menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(_menu_container)


func _check_resources_loaded() -> void:
	# Check if all resources are fully loaded
	# Only then do we pre-instantiate the main menu and allow clicking
	# Already done or already scheduled?
	if _resources_ready or _preinstantiation_scheduled:
		return
	
	# Wait for timer to allow animation to render first
	if _loading_delay_timer != null:
		return # Still waiting for delay
	
	# Check main menu scene
	var scene_status := ResourceLoader.load_threaded_get_status(SCENE_PATHS.main_menu)
	if scene_status != ResourceLoader.THREAD_LOAD_LOADED:
		return
	
	# Check shader
	var shader_status := ResourceLoader.load_threaded_get_status("res://resources/shaders/hexagon_grid_overlay.gdshader")
	if shader_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	
	# Check all background textures
	var bg_dir := "res://assets/backgrounds/"
	var bg_files := [
		"ark.jpg", "battlefield1.jpg", "bunker-interior.jpg", "eden.jpg",
		"forest.jpg", "hg.jpg", "kingdom.jpg", "mushroom.jpg",
		"rapturefield1.jpg", "rapturefield2.jpg", "snow-day.jpg",
		"snow-night.jpg", "space.jpg"
	]
	for file in bg_files:
		var tex_status := ResourceLoader.load_threaded_get_status(bg_dir + file)
		if tex_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
	
	# All resources are loaded - schedule pre-instantiation for next frame
	# This allows at least one more frame for the walking animation
	_preinstantiation_scheduled = true
	print("[MenuManager] Resources loaded - scheduling pre-instantiation...")
	call_deferred("_do_preinstantiate_main_menu")


func _do_preinstantiate_main_menu() -> void:
	# Actually perform the pre-instantiation (called deferred)
	if _preinstantiated_main_menu != null:
		return # Already done
	
	print("[MenuManager] Pre-instantiating main menu...")
	
	# Yield a frame before heavy work to keep animation smooth
	await get_tree().process_frame
	
	var scene: PackedScene = ResourceLoader.load_threaded_get(SCENE_PATHS.main_menu) as PackedScene
	if scene:
		# Yield another frame before instantiation (the heaviest part)
		await get_tree().process_frame
		_preinstantiated_main_menu = scene.instantiate() as Control
		if _preinstantiated_main_menu:
			# Yield before adding to tree
			await get_tree().process_frame
			# Add to container but keep hidden
			_preinstantiated_main_menu.visible = false
			_menu_container.add_child(_preinstantiated_main_menu)
			print("[MenuManager] Main menu pre-instantiated and hidden")
	
	if _preinstantiated_main_menu == null:
		push_error("[MenuManager] Failed to pre-instantiate main menu")
		_preinstantiation_scheduled = false # Allow retry
		return
	
	# Now we're truly ready!
	_resources_ready = true
	print("[MenuManager] Ready for input - main menu is pre-instantiated")
	if _intro_screen_instance and is_instance_valid(_intro_screen_instance):
		_intro_screen_instance.set_resources_ready()


func _on_intro_dismissed() -> void:
	## Called when IntroScreen emits dismissed signal.
	if _loading_main_menu:
		return
	_loading_main_menu = true
	_finish_intro_transition()


func _finish_intro_transition() -> void:
	# Remove the intro screen
	if _intro_screen_instance and is_instance_valid(_intro_screen_instance):
		_intro_screen_instance.queue_free()
		_intro_screen_instance = null
	
	# Setup music now that intro is done
	start_menu_music()
	
	# Setup debug menu now (deferred from startup to avoid blocking intro animation)
	if _debug_menu == null:
		_setup_debug_menu()
	
	# Use the pre-instantiated main menu (already added to container, just hidden)
	var main_menu := _preinstantiated_main_menu
	_preinstantiated_main_menu = null # Clear reference since it's now the active menu
	
	if main_menu:
		main_menu.visible = true # Just show it - no instantiation needed!
		_current_menu = main_menu
		_menu_stack.clear()
		_menu_stack.push_back(main_menu)
		
		# Connect signals (Robust Check)
		if main_menu.has_signal("play_selected") and not main_menu.play_selected.is_connected(_on_play_selected):
			main_menu.play_selected.connect(_on_play_selected)
		if main_menu.has_signal("settings_selected") and not main_menu.settings_selected.is_connected(_on_settings_selected):
			main_menu.settings_selected.connect(_on_settings_selected)
		if main_menu.has_signal("achievements_selected") and not main_menu.achievements_selected.is_connected(_on_achievements_selected):
			main_menu.achievements_selected.connect(_on_achievements_selected)
		if main_menu.has_signal("quit_selected") and not main_menu.quit_selected.is_connected(_on_quit_selected):
			main_menu.quit_selected.connect(_on_quit_selected)
		if main_menu.has_signal("leaderboards_selected") and not main_menu.leaderboards_selected.is_connected(_on_leaderboards_selected):
			main_menu.leaderboards_selected.connect(_on_leaderboards_selected)
		if main_menu.has_signal("shop_selected") and not main_menu.shop_selected.is_connected(_on_shop_selected):
			main_menu.shop_selected.connect(_on_shop_selected)
		
		print("[MenuManager] Main menu shown (was pre-instantiated)")
	else:
		push_error("[MenuManager] Pre-instantiated main menu not found!")


func _setup_debug_menu() -> void:
	# Use threaded-loaded script if available, otherwise load sync (fallback)
	if _debug_menu_script == null:
		var status := ResourceLoader.load_threaded_get_status("res://scripts/ui/DebugMenu.gd")
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_debug_menu_script = ResourceLoader.load_threaded_get("res://scripts/ui/DebugMenu.gd")
		else:
			# Fallback to sync load if not ready yet
			_debug_menu_script = load("res://scripts/ui/DebugMenu.gd")
	_debug_menu = CanvasLayer.new()
	_debug_menu.set_script(_debug_menu_script)
	_debug_menu.name = "GlobalDebugMenu"
	add_child(_debug_menu)


func _get_or_load_scene(scene_key: String, allow_blocking: bool = true) -> PackedScene:
	# Get scene from cache or load it (with threaded check first)
	# If allow_blocking is false, returns null if scene isn't ready yet
	var path: String = SCENE_PATHS.get(scene_key, "")
	if path.is_empty():
		return null
	
	# Check if threaded load is complete
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		return ResourceLoader.load_threaded_get(path) as PackedScene
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if allow_blocking:
			# Wait for it to complete (blocking)
			return ResourceLoader.load_threaded_get(path) as PackedScene
		else:
			# Non-blocking mode: return null, caller should try again
			return null
	else:
		# Not started
		if allow_blocking:
			# Load synchronously
			return load(path) as PackedScene
		else:
			# Start threaded load and return null
			ResourceLoader.load_threaded_request(path)
			return null


# _setup_music removed - handled by AudioDirector


func show_main_menu() -> void:
	print("[MenuManager] show_main_menu called")
	_clear_stack()
	var scene := _get_or_load_scene("main_menu")
	if not scene:
		push_error("[MenuManager] Failed to load MainMenu scene")
		return
	var menu := scene.instantiate() as Control
	_show_menu(menu)
	
	# Connect signals
	if menu.has_signal("play_selected"):
		menu.play_selected.connect(_on_play_selected)
		print("[MenuManager] Connected play_selected signal")
	if menu.has_signal("settings_selected"):
		menu.settings_selected.connect(_on_settings_selected)
		print("[MenuManager] Connected settings_selected signal")
	if menu.has_signal("achievements_selected"):
		menu.achievements_selected.connect(_on_achievements_selected)
		print("[MenuManager] Connected achievements_selected signal")
	if menu.has_signal("quit_selected"):
		menu.quit_selected.connect(_on_quit_selected)
		print("[MenuManager] Connected quit_selected signal")
	if menu.has_signal("leaderboards_selected"):
		menu.leaderboards_selected.connect(_on_leaderboards_selected)
		print("[MenuManager] Connected leaderboards_selected signal")
	if menu.has_signal("shop_selected"):
		menu.shop_selected.connect(_on_shop_selected)
		print("[MenuManager] Connected shop_selected signal")


func show_settings_menu() -> void:
	var scene := _get_or_load_scene("settings")
	if not scene:
		return
	var menu := scene.instantiate() as Control
	_push_menu(menu)
	
	if menu.has_signal("back_requested"):
		menu.back_requested.connect(_on_back_requested)


func show_character_select() -> void:
	var scene := _get_or_load_scene("character_select")
	if not scene:
		return
	var menu := scene.instantiate() as Control
	_push_menu(menu)
	
	if menu.has_signal("play_requested"):
		menu.play_requested.connect(_on_game_start_requested)
	if menu.has_signal("back_requested"):
		menu.back_requested.connect(_on_back_requested)


func show_achievements_menu() -> void:
	var scene := _get_or_load_scene("achievements")
	if not scene:
		return
	var menu := scene.instantiate() as Control
	_push_menu(menu)
	
	if menu.has_signal("back_requested"):
		menu.back_requested.connect(_on_back_requested)


func show_leaderboard_menu() -> void:
	var scene := _get_or_load_scene("leaderboard")
	if not scene:
		return
	var menu := scene.instantiate() as Control
	_push_menu(menu)
	
	if menu.has_signal("back_requested"):
		menu.back_requested.connect(_on_back_requested)


func show_shop_menu() -> void:
	var scene := _get_or_load_scene("shop")
	if not scene:
		return
	var menu := scene.instantiate() as Control
	_push_menu(menu)
	
	if menu.has_signal("back_requested"):
		menu.back_requested.connect(_on_back_requested)




func _show_menu(menu: Control) -> void:
	if _current_menu:
		_current_menu.queue_free()
	_current_menu = menu
	_menu_container.add_child(menu)


func _push_menu(menu: Control) -> void:
	if _current_menu:
		_current_menu.visible = false
		_menu_stack.append(_current_menu)
	_current_menu = menu
	_menu_container.add_child(menu)


func _pop_menu() -> void:
	if _current_menu:
		_current_menu.queue_free()
		_current_menu = null
	
	if _menu_stack.size() > 0:
		_current_menu = _menu_stack.pop_back()
		_current_menu.visible = true
	else:
		show_main_menu()


func _clear_stack() -> void:
	for menu in _menu_stack:
		if is_instance_valid(menu):
			menu.queue_free()
	_menu_stack.clear()
	
	if is_instance_valid(_current_menu):
		_current_menu.queue_free()
	_current_menu = null


func _on_play_selected() -> void:
	print("[MenuManager] _on_play_selected")
	# Mode select removed from the flow (UI refresh): PLAY goes straight to
	# character select; mode/stage choices live in the stage phase.
	show_character_select()


func _on_settings_selected() -> void:
	print("[MenuManager] _on_settings_selected")
	show_settings_menu()


func _on_achievements_selected() -> void:
	print("[MenuManager] _on_achievements_selected")
	show_achievements_menu()


func _on_leaderboards_selected() -> void:
	print("[MenuManager] _on_leaderboards_selected")
	show_leaderboard_menu()


func _on_shop_selected() -> void:
	print("[MenuManager] _on_shop_selected")
	show_shop_menu()


func _on_quit_selected() -> void:
	print("[MenuManager] _on_quit_selected")
	get_tree().quit()


func _on_back_requested() -> void:
	_pop_menu()


func _on_game_start_requested(character_index: int, stage_id: String) -> void:
	print("[MenuManager] _on_game_start_requested called with character: ", character_index, " stage: ", stage_id)

	# Save selection to GameManager
	if GameManager:
		GameManager.set_player_character(character_index)
		# Store stage_id for Level to use
		GameManager.current_stage_id = stage_id

	# Stop menu music
	stop_menu_music()

	# Emit signal for game to handle
	emit_signal("game_started", character_index, stage_id)
	
	# Clear menus and transition to game
	_clear_stack()
	
	# Change to Level scene
	print("[MenuManager] Changing to Level scene...")
	get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")


# --- Music Control API ---

func start_menu_music() -> void:
	## Start the main menu music (used when returning from game)
	if AudioDirector:
		AudioDirector.play_music_by_path(MENU_MUSIC_PATH, true, 0.5)
		print("[MenuManager] Requesting menu music via AudioDirector")


func stop_menu_music() -> void:
	## Stop the main menu music (used before starting game)
	if AudioDirector:
		AudioDirector.stop_music(0.5)
		print("[MenuManager] Requesting stop music via AudioDirector")


func return_to_main_menu() -> void:
	## Return to main menu from anywhere (game, pause menu, etc.)
	print("[MenuManager] Returning to main menu...")
	
	# Unpause in case game was paused
	get_tree().paused = false
	
	# Reset Engine time scale in case CombatJuice or other systems modified it
	Engine.time_scale = 1.0
	
	# Reset bullet time (Wells ability) in case it was active
	if GameManager:
		GameManager.enemy_time_scale = 1.0
	
	# Stop any game music/ambient sounds
	if AudioDirector:
		AudioDirector.play_ui_music() # Switch to menu music (handles fade)
		AudioDirector.stop_ambient(0.3)
	
	# Clear any She Descends mode state
	if GameManager:
		GameManager.she_descends_mode = false
	
	# Clear menu stack
	_clear_stack()
	
	# Change to main menu scene
	# Change to main menu scene
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


func register_root_main_menu(menu: Control) -> void:
	## Registers an externally loaded MainMenu (e.g. from change_scene)
	## Connects signals so MenuManager can handle navigation
	print("[MenuManager] Registering root main menu")
	
	# Ensure stack is clear (we are at root)
	_clear_stack()
	_current_menu = menu
	
	# Connect signals
	if menu.has_signal("play_selected") and not menu.play_selected.is_connected(_on_play_selected):
		menu.play_selected.connect(_on_play_selected)
	if menu.has_signal("settings_selected") and not menu.settings_selected.is_connected(_on_settings_selected):
		menu.settings_selected.connect(_on_settings_selected)
	if menu.has_signal("achievements_selected") and not menu.achievements_selected.is_connected(_on_achievements_selected):
		menu.achievements_selected.connect(_on_achievements_selected)
	if menu.has_signal("quit_selected") and not menu.quit_selected.is_connected(_on_quit_selected):
		menu.quit_selected.connect(_on_quit_selected)
	if menu.has_signal("leaderboards_selected") and not menu.leaderboards_selected.is_connected(_on_leaderboards_selected):
		menu.leaderboards_selected.connect(_on_leaderboards_selected)
	if menu.has_signal("shop_selected") and not menu.shop_selected.is_connected(_on_shop_selected):
		menu.shop_selected.connect(_on_shop_selected)


## Navigate focus to adjacent control in given direction
func _navigate_focus(direction: Vector2) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if not focused:
		# Find first focusable button in current menu
		if _current_menu and is_instance_valid(_current_menu):
			var first_button := _find_first_focusable(_current_menu)
			if first_button:
				first_button.grab_focus()
		return
	
	# Try to find valid neighbor in direction
	var neighbor: Control = null
	if direction == Vector2.UP:
		neighbor = focused.get_node_or_null(focused.focus_neighbor_top) if focused.focus_neighbor_top else focused.find_valid_focus_neighbor(SIDE_TOP)
	elif direction == Vector2.DOWN:
		neighbor = focused.get_node_or_null(focused.focus_neighbor_bottom) if focused.focus_neighbor_bottom else focused.find_valid_focus_neighbor(SIDE_BOTTOM)
	elif direction == Vector2.LEFT:
		neighbor = focused.get_node_or_null(focused.focus_neighbor_left) if focused.focus_neighbor_left else focused.find_valid_focus_neighbor(SIDE_LEFT)
	elif direction == Vector2.RIGHT:
		neighbor = focused.get_node_or_null(focused.focus_neighbor_right) if focused.focus_neighbor_right else focused.find_valid_focus_neighbor(SIDE_RIGHT)
	
	if neighbor and neighbor.visible:
		neighbor.grab_focus()


## Activate (click) the currently focused control
func _activate_focused() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		if focused is Button:
			focused.emit_signal("pressed")
		elif focused.has_method("_gui_input"):
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			focused._gui_input(click)


## Handle controller back button
func _handle_controller_back() -> void:
	# Check if Settings is open and trigger back
	if _current_menu and _current_menu.has_signal("back_requested"):
		_current_menu.emit_signal("back_requested")
	elif _menu_stack.size() > 0:
		_menu_stack.pop_back()


## Find first focusable control in a container
func _find_first_focusable(node: Node) -> Control:
	if node is Button and node.visible and node.focus_mode != Control.FOCUS_NONE:
		return node
	for child in node.get_children():
		var found := _find_first_focusable(child)
		if found:
			return found
	return null
