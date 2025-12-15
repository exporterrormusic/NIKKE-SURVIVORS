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

# Inline colors for intro screen (avoids UITheme preload cascade)
const _COLOR_TEXT_MUTED := Color(0.592, 0.6, 0.694, 1.0)
const _COLOR_TEXT_SECONDARY := Color(0.784, 0.792, 0.878, 1.0)
const _COLOR_TEXT_DISABLED := Color(0.4, 0.42, 0.45, 1.0)
const _COLOR_CHAR_PORTRAIT := Color(1, 1, 1, 0.95)

signal game_started(squad: Array[int], stage_id: String)

# Menu scenes - load on demand instead of preload to speed up startup
var MainMenuScene: PackedScene = null
var SettingsMenuScene: PackedScene = null
var CharacterSelectScene: PackedScene = null
var AchievementsScene: PackedScene = null
var LeaderboardScene: PackedScene = null
var ShopScene: PackedScene = null
var _debug_menu_script: Script = null  # Loaded lazily

# Scene paths for lazy loading
const SCENE_PATHS := {
	"main_menu": "res://scenes/ui/MainMenu.tscn",
	"settings": "res://scenes/ui/SettingsMenu.tscn",
	"character_select": "res://scenes/ui/CharacterSelectMenu.tscn",
	"achievements": "res://scenes/ui/AchievementsMenu.tscn",
	"leaderboard": "res://scenes/ui/LeaderboardMenu.tscn",
	"shop": "res://scenes/ui/ShopMenu.tscn",
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
const MENU_MUSIC_PATH := "res://assets/sounds/music/menu/main-menu.mp3"

# Intro screen
var _intro_screen: Control = null
var _intro_shown: bool = false
var _intro_start_time: int = 0
var _intro_canvas_layer: CanvasLayer = null
var _loading_main_menu: bool = false  # Prevents re-entry during async load
var _resources_ready: bool = false  # True when all resources are loaded
var _continue_label: Label = null  # Reference to "Click to continue" label
var _preinstantiated_main_menu: Control = null  # Pre-instantiated main menu (hidden until ready)
var _preinstantiation_scheduled: bool = false  # Prevent multiple deferred calls
var _loading_delay_timer: Timer = null  # Timer to delay heavy loading until after first frames render
const INTRO_MIN_DISPLAY_TIME_MS := 3000  # Minimum 3 seconds before user can dismiss intro

# Walking character animation (process-based, not tween-based)
var _loading_character: AnimatedSprite2D = null
var _placeholder_node: Control = null  # Simple placeholder while sprite loads
var _walk_speed: float = 150.0  # Pixels per second
var _walk_end_x: float = 0.0
var _bob_time: float = 0.0
var _bob_base_y: float = 0.0
const LOADING_CHARACTER_SPRITES := [
	"res://assets/characters/kilo/kilo-sprite.png",
	"res://assets/characters/marian/marian-sprite.png",
	"res://assets/characters/nayuta/nayuta-sprite.png",
	"res://assets/characters/scarlet/scarlet-sprite.png",
]
var _selected_sprite_path: String = ""


func _ready() -> void:
	# Pick a random character sprite for the walking animation
	_selected_sprite_path = LOADING_CHARACTER_SPRITES[randi() % LOADING_CHARACTER_SPRITES.size()]
	
	# Show the intro/disclaimer screen immediately
	_show_intro_screen()
	
	# Create a delay timer - this ensures the intro screen renders for a bit
	# before we start the heavy loading work
	_loading_delay_timer = Timer.new()
	_loading_delay_timer.one_shot = true
	_loading_delay_timer.wait_time = 0.5  # 500ms delay to let animation run
	_loading_delay_timer.timeout.connect(_on_loading_delay_timeout)
	add_child(_loading_delay_timer)
	_loading_delay_timer.start()
	
	# Initialize DebugLog if needed (removed for production/cleanup)
	# var debug_log_script = load("res://scripts/systems/DebugLog.gd")
	# if debug_log_script:
	# 	var debug_log_node = debug_log_script.new()
	# 	debug_log_node.name = "DebugLog"
	# 	add_child(debug_log_node)
	
	# RESTORED: Start loading resources in background
	call_deferred("_start_background_loading")


func _on_loading_delay_timeout() -> void:
	# Timer fired - now we can allow resource checking and pre-instantiation
	print("[MenuManager] Loading delay complete - animation should be visible now")
	_loading_delay_timer.queue_free()
	_loading_delay_timer = null  # Setting to null allows _check_resources_loaded to proceed


var _last_frame_time: int = 0
var _first_frame_rendered: bool = false

func _process(delta: float) -> void:
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
		if frame_delta > 100:  # More than 100ms between frames = freeze
			print("[MenuManager] FRAME FREEZE: %dms gap detected" % frame_delta)
	_last_frame_time = now
	
	# Animate the walking character using _process (survives main thread hiccups)
	# Works for both the placeholder (Control) and the real animated sprite (Node2D)
	
	# Animate the real animated sprite if it exists
	if _loading_character and is_instance_valid(_loading_character):
		# Move right
		_loading_character.position.x += _walk_speed * delta
		
		# Bobbing motion
		_bob_time += delta * 8.0  # Bob frequency
		_loading_character.position.y = _bob_base_y + sin(_bob_time) * 3.0
		
		# Reset when off screen
		if _loading_character.position.x > _walk_end_x:
			_loading_character.position.x = -50.0
	elif _placeholder_node and is_instance_valid(_placeholder_node):
		# Animate the placeholder (Control uses position too)
		_placeholder_node.position.x += _walk_speed * delta
		
		# Bobbing motion
		_bob_time += delta * 8.0
		_placeholder_node.position.y = _bob_base_y - 24 + sin(_bob_time) * 3.0
		
		# Reset when off screen
		if _placeholder_node.position.x > _walk_end_x:
			_placeholder_node.position.x = -50.0
	
	# Check if resources are ready (only while intro is showing)
	if _intro_screen and is_instance_valid(_intro_screen) and not _resources_ready:
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
	ResourceLoader.load_threaded_request("res://resources/shaders/hexagon_grid_overlay.gdshader")
	
	# Pre-request all background textures for the venetian blinds
	# This prevents the main menu instantiation from blocking on texture loads
	var bg_dir := "res://assets/backgrounds/"
	var bg_files := [
		"ark.jpg", "battlefield1.jpg", "bunker-interior.jpg", "eden.jpg",
		"forest.jpg", "hg.jpg", "kingdom.jpg", "mushroom.jpg",
		"rapturefield1.jpg", "rapturefield2.jpg", "snow-day.jpg",
		"snow-night.jpg", "space.jpg"
	]
	for file in bg_files:
		ResourceLoader.load_threaded_request(bg_dir + file)
	
	# Create menu container
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 10
	menu_layer.name = "MenuLayer"
	add_child(menu_layer)
	
	_menu_container = Control.new()
	_menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(_menu_container)
	
	# Try to add walking character (will defer if sprite not ready)
	_try_add_walking_character()


func _try_add_walking_character() -> void:
	# Check if sprite is loaded
	var status := ResourceLoader.load_threaded_get_status(_selected_sprite_path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_upgrade_to_animated_character()
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		# Not ready yet, try again next frame
		call_deferred("_try_add_walking_character")


func _add_placeholder_character() -> void:
	# Create a simple colored rectangle as placeholder while real sprite loads
	# This shows immediately without any loading
	if not _intro_screen or not is_instance_valid(_intro_screen):
		return
	
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_bob_base_y = viewport_size.y - 60
	_walk_end_x = viewport_size.x + 100.0
	
	# Create a simple ColorRect as placeholder
	var placeholder := ColorRect.new()
	placeholder.size = Vector2(32, 48)
	placeholder.color = _COLOR_CHAR_PORTRAIT
	placeholder.position = Vector2(-50.0, _bob_base_y - 24)
	placeholder.name = "PlaceholderCharacter"
	_intro_screen.add_child(placeholder)
	
	# We'll use _loading_character to track the placeholder for animation
	# (It's not an AnimatedSprite2D but we can still move it in _process)
	# Store the placeholder in a temporary node reference
	_placeholder_node = placeholder


func _upgrade_to_animated_character() -> void:
	# Called when the real sprite is loaded - replace placeholder with animated sprite
	if not _intro_screen or not is_instance_valid(_intro_screen):
		return
	
	# Preserve current position from placeholder
	var current_x: float = -50.0
	if _placeholder_node and is_instance_valid(_placeholder_node):
		current_x = _placeholder_node.position.x
		_placeholder_node.queue_free()
		_placeholder_node = null
	
	var sprite_sheet: Texture2D = ResourceLoader.load_threaded_get(_selected_sprite_path) as Texture2D
	if not sprite_sheet:
		return
	
	# Sprite sheet config: 3 columns, 4 rows (down/left/right/up), row 2 = walking right
	var columns: int = 3
	var rows: int = 4
	var fps: float = 6.0
	
	var texture_size: Vector2 = sprite_sheet.get_size()
	var frame_width := int(texture_size.x / columns)
	var frame_height := int(texture_size.y / rows)
	
	# Create SpriteFrames with "right" animation
	var frames := SpriteFrames.new()
	frames.add_animation("right")
	frames.set_animation_speed("right", fps)
	frames.set_animation_loop("right", true)
	
	# Add frames for the right direction (row 2, each column is a frame)
	for col in range(columns):
		var atlas := AtlasTexture.new()
		atlas.atlas = sprite_sheet
		atlas.region = Rect2(col * frame_width, 2 * frame_height, frame_width, frame_height)
		frames.add_frame("right", atlas)
	
	# Create the animated sprite
	_loading_character = AnimatedSprite2D.new()
	_loading_character.sprite_frames = frames
	_loading_character.scale = Vector2(0.25, 0.25)
	_loading_character.animation = "right"
	_loading_character.play("right")
	_loading_character.modulate = _COLOR_CHAR_PORTRAIT
	
	# Position at bottom of screen (preserve X position from placeholder)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_bob_base_y = viewport_size.y - 60
	_walk_end_x = viewport_size.x + 100.0
	_loading_character.position = Vector2(current_x, _bob_base_y)
	_intro_screen.add_child(_loading_character)


func _show_intro_screen() -> void:
	# Create intro screen with disclaimer
	_intro_canvas_layer = CanvasLayer.new()
	_intro_canvas_layer.layer = 100
	_intro_canvas_layer.name = "IntroLayer"
	add_child(_intro_canvas_layer)
	
	_intro_screen = Control.new()
	_intro_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_screen.name = "IntroScreen"
	_intro_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_canvas_layer.add_child(_intro_screen)
	
	# Black background that receives input
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_intro_input)
	_intro_screen.add_child(bg)
	
	# Center container for text
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -500
	center.offset_right = 500
	center.offset_top = -150
	center.offset_bottom = 150
	center.add_theme_constant_override("separation", 20)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_screen.add_child(center)
	
	# Title
	var title := Label.new()
	title.text = "DISCLAIMER"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", _COLOR_TEXT_MUTED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(title)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	center.add_child(spacer)
	
	# Disclaimer lines
	var lines := [
		"This is an unofficial, fan-made game based on Goddess of Victory: NIKKE.",
		"It is not affiliated with, endorsed by, or sponsored by ShiftUp or any official partners.",
		"All trademarks and characters belong to their respective owners."
	]
	
	for line_text in lines:
		var line := Label.new()
		line.text = line_text
		line.add_theme_font_size_override("font_size", 22)
		line.add_theme_color_override("font_color", _COLOR_TEXT_SECONDARY)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(line)
	
	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 30
	center.add_child(spacer2)
	
	# Continue instruction - starts as "Loading..."
	_continue_label = Label.new()
	_continue_label.text = "Loading..."
	_continue_label.add_theme_font_size_override("font_size", 16)
	_continue_label.add_theme_color_override("font_color", _COLOR_TEXT_DISABLED)
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_continue_label)
	
	# Record start time
	_intro_start_time = Time.get_ticks_msec()
	_intro_shown = false
	_resources_ready = false
	
	# Add a simple walking placeholder immediately (upgraded later when sprite loads)
	_add_placeholder_character()


func _check_resources_loaded() -> void:
	# Check if all resources are fully loaded
	# Only then do we pre-instantiate the main menu and allow clicking
	
	# Already done or already scheduled?
	if _resources_ready or _preinstantiation_scheduled:
		return
	
	# Wait for timer to allow animation to render first
	if _loading_delay_timer != null:
		return  # Still waiting for delay
	
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
	if _continue_label and is_instance_valid(_continue_label):
		_continue_label.text = "Preparing..."
	print("[MenuManager] Resources loaded - scheduling pre-instantiation...")
	call_deferred("_do_preinstantiate_main_menu")


func _do_preinstantiate_main_menu() -> void:
	# Actually perform the pre-instantiation (called deferred)
	if _preinstantiated_main_menu != null:
		return  # Already done
	
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
		_preinstantiation_scheduled = false  # Allow retry
		return
	
	# Now we're truly ready!
	_resources_ready = true
	print("[MenuManager] Ready for input - main menu is pre-instantiated")
	if _continue_label and is_instance_valid(_continue_label):
		_continue_label.text = "Click anywhere to continue"
		_continue_label.add_theme_color_override("font_color", _COLOR_TEXT_SECONDARY)


func _on_intro_input(event: InputEvent) -> void:
	# Only handle mouse button events to avoid spam from motion events
	if not event is InputEventMouseButton:
		return
	
	# Always consume mouse button input to prevent propagation
	get_viewport().set_input_as_handled()
	
	if not _resources_ready:
		print("[MenuManager] Click blocked - resources not ready")
		return
	
	# Check minimum display time (2 seconds to read disclaimer)
	var elapsed := Time.get_ticks_msec() - _intro_start_time
	if elapsed < INTRO_MIN_DISPLAY_TIME_MS:
		print("[MenuManager] Click blocked - please wait %.1fs" % [(INTRO_MIN_DISPLAY_TIME_MS - elapsed) / 1000.0])
		return
	
	if event.pressed:
		print("[MenuManager] Click accepted - dismissing intro")
		_dismiss_intro()


func _input(event: InputEvent) -> void:
	# Handle intro screen dismissal with any key
	if _intro_screen and is_instance_valid(_intro_screen):
		# Only process key and mouse button events (not motion)
		if event is InputEventMouseButton or event is InputEventKey:
			get_viewport().set_input_as_handled()
			
			if not _resources_ready:
				return  # Don't allow input until resources are loaded
			
			# Check minimum display time (2 seconds to read disclaimer)
			var elapsed := Time.get_ticks_msec() - _intro_start_time
			if elapsed < INTRO_MIN_DISPLAY_TIME_MS:
				return
			
			# Dismiss on key press or mouse click
			if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
				print("[MenuManager] Input accepted - dismissing intro")
				_dismiss_intro()


func _dismiss_intro() -> void:
	if not _intro_screen or not is_instance_valid(_intro_screen):
		return
	if _loading_main_menu:
		return  # Already loading, don't re-trigger
	
	_intro_shown = true
	_loading_main_menu = true
	
	# Don't remove the intro screen yet - keep the walking animation going
	# while we load the main menu in the background
	_start_main_menu_load()


func _start_main_menu_load() -> void:
	# Main menu is already pre-instantiated and hidden by _check_resources_loaded()
	# Just transition to it immediately
	_finish_intro_transition()


func _finish_intro_transition() -> void:
	# Now we can remove the intro screen
	if _intro_canvas_layer and is_instance_valid(_intro_canvas_layer):
		_intro_canvas_layer.queue_free()
		_intro_canvas_layer = null
	_intro_screen = null
	_loading_character = null
	_placeholder_node = null
	
	# Setup music now that intro is done
	start_menu_music()
	
	# Setup debug menu now (deferred from startup to avoid blocking intro animation)
	if _debug_menu == null:
		_setup_debug_menu()
	
	# Use the pre-instantiated main menu (already added to container, just hidden)
	var main_menu := _preinstantiated_main_menu
	_preinstantiated_main_menu = null  # Clear reference since it's now the active menu
	
	if main_menu:
		main_menu.visible = true  # Just show it - no instantiation needed!
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
	
	# Load saved selection if available
	if GameState:
		var saved_selection := GameState.get_shop_character_order()
		if saved_selection.size() == 3 and menu.has_method("set_initial_selection"):
			menu.set_initial_selection(saved_selection)


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


func _on_game_start_requested(squad: Array[int], stage_id: String) -> void:
	print("[MenuManager] _on_game_start_requested called with squad: ", squad, " stage: ", stage_id)
	
	# Save selection to GameState
	if GameState:
		GameState.set_selected_characters(squad)
		# Set the main character (first in squad) as the player character
		if squad.size() > 0:
			GameState.set_player_character(squad[0])
		# Store stage_id for Level to use
		GameState.current_stage_id = stage_id
	
	# Stop menu music
	stop_menu_music()
	
	# Emit signal for game to handle
	emit_signal("game_started", squad, stage_id)
	
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
	
	# Stop any game music/ambient sounds
	if AudioDirector:
		AudioDirector.play_ui_music() # Switch to menu music (handles fade)
		AudioDirector.stop_ambient(0.3)
	
	# Clear any She Descends mode state
	if GameState:
		GameState.she_descends_mode = false
	
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

