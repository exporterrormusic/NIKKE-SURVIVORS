extends Node
## Manages menu navigation and transitions between screens.
## Load this as an autoload or instantiate in your main scene.

const UI := preload("res://scripts/ui/UITheme.gd")

signal game_started(squad: Array[int], stage_id: String)

# Menu scenes - load on demand instead of preload to speed up startup
var MainMenuScene: PackedScene = null
var SettingsMenuScene: PackedScene = null
var CharacterSelectScene: PackedScene = null
var AchievementsScene: PackedScene = null
var LeaderboardScene: PackedScene = null
var ShopScene: PackedScene = null
const DebugMenuScript = preload("res://scripts/ui/DebugMenu.gd")

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
var _music_player: AudioStreamPlayer = null
const MENU_MUSIC_PATH := "res://assets/sounds/music/main-menu.mp3"

# Intro screen
var _intro_screen: Control = null
var _intro_shown: bool = false
var _loading_character: AnimatedSprite2D = null
var _loading_tween: Tween = null
var _loading_start_x: float = 0.0
var _loading_end_x: float = 0.0
var _intro_start_time: int = 0
var _preloaded_main_menu: Control = null  # Pre-instantiated main menu
var _intro_timer: Timer = null  # Timer for checking intro dismissal
const INTRO_MIN_DURATION_MS: int = 1000  # Minimum 1 second to read disclaimer

# Character sprite paths for loading animation
const LOADING_CHARACTER_SPRITES := [
	"res://assets/characters/kilo/kilo-sprite.png",
	"res://assets/characters/marian/marian-sprite.png",
	"res://assets/characters/nayuta/nayuta-sprite.png",
	"res://assets/characters/scarlet/scarlet-sprite.png",
]


func _ready() -> void:
	print("[MenuManager] _ready() called, _intro_shown = ", _intro_shown)
	# Create menu container in a CanvasLayer so rendering order is predictable
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 10  # Normal menu layer
	menu_layer.name = "MenuLayer"
	add_child(menu_layer)
	
	_menu_container = Control.new()
	_menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(_menu_container)
	
	# Setup global debug menu (available via F4 everywhere)
	_setup_debug_menu()
	
	# Show intro screen first (music starts after intro)
	if not _intro_shown:
		print("[MenuManager] Showing intro screen...")
		_show_intro_screen()
	else:
		_setup_music()
		show_main_menu()


func _show_intro_screen() -> void:
	# Record start time immediately to prevent premature auto-dismiss
	_intro_start_time = Time.get_ticks_msec()
	
	# Use a CanvasLayer to ensure intro is on top of everything
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100  # High layer to be on top
	canvas_layer.name = "IntroLayer"
	add_child(canvas_layer)
	
	_intro_screen = Control.new()
	_intro_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_screen.name = "IntroScreen"
	_intro_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(_intro_screen)
	
	print("[MenuManager] IntroScreen created in CanvasLayer")
	
	# Black background - clickable
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
	center.offset_top = -200
	center.offset_bottom = 200
	center.add_theme_constant_override("separation", 24)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_screen.add_child(center)
	
	# Title
	var title := Label.new()
	title.text = "DISCLAIMER"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UI.TEXT_MUTED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(title)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	center.add_child(spacer)
	
	# Disclaimer lines
	var lines := [
		"This is an unofficial, fan-made game based on Goddess of Victory: NIKKE.",
		"It is not affiliated with, endorsed by, or sponsored by ShiftUp or any official partners.",
		"All trademarks and characters belong to their respective owners."
	]
	
	var font_sizes := [24, 22, 22]
	
	for i in range(lines.size()):
		var line := Label.new()
		line.text = lines[i]
		line.add_theme_font_size_override("font_size", font_sizes[i])
		line.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(line)
	
	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 40
	center.add_child(spacer2)
	
	# Continue instruction
	var continue_lbl := Label.new()
	continue_lbl.text = "Click anywhere to continue"
	continue_lbl.add_theme_font_size_override("font_size", 16)
	continue_lbl.add_theme_color_override("font_color", UI.TEXT_DISABLED)
	continue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	continue_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(continue_lbl)
	
	# Loading character walking at bottom of screen
	_add_loading_character()
	
	# Fade in quickly
	_intro_screen.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_intro_screen, "modulate:a", 1.0, 0.3)
	tween.finished.connect(func(): 
		if _intro_screen and is_instance_valid(_intro_screen):
			print("[MenuManager] Intro fade-in complete, alpha=", _intro_screen.modulate.a)
	)
	
	# Debug: Print node tree
	print("[MenuManager] IntroLayer is child of: ", canvas_layer.get_parent().name)
	print("[MenuManager] Canvas layer index: ", canvas_layer.layer)
	
	# Start background loading of assets while intro is showing
	_start_background_loading()
	
	# DON'T preload main menu during intro - it causes rendering issues
	# Just preload the scene resource without instantiating
	_get_or_load_scene("main_menu")
	
	# Use a Timer node for reliable intro checking (more reliable than _process in autoloads)
	_intro_timer = Timer.new()
	_intro_timer.wait_time = 0.1
	_intro_timer.autostart = true
	_intro_timer.timeout.connect(_check_intro_timer)
	add_child(_intro_timer)
	print("[MenuManager] Intro timer started")


func _preload_main_menu() -> void:
	# Pre-instantiate the main menu hidden so it initializes
	if _preloaded_main_menu == null:
		var scene := _get_or_load_scene("main_menu")
		if scene:
			_preloaded_main_menu = scene.instantiate() as Control
			_preloaded_main_menu.visible = false
			_menu_container.add_child(_preloaded_main_menu)
			print("[MenuManager] Main menu pre-instantiated")


func _check_intro_timer() -> void:
	# Handle intro screen timing via Timer (more reliable than _process)
	if not _intro_screen or not is_instance_valid(_intro_screen):
		if _intro_timer:
			_intro_timer.stop()
			_intro_timer.queue_free()
			_intro_timer = null
		return
	
	var elapsed_ms: int = Time.get_ticks_msec() - _intro_start_time
	print("[MenuManager] Timer check: elapsed=%dms" % elapsed_ms)
	
	# Auto-dismiss after minimum time (1.5 seconds)
	if elapsed_ms >= INTRO_MIN_DURATION_MS + 500:
		print("[MenuManager] Auto-dismissing intro at %dms" % elapsed_ms)
		if _intro_timer:
			_intro_timer.stop()
			_intro_timer.queue_free()
			_intro_timer = null
		_dismiss_intro()


func _on_intro_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_dismiss_intro()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Handle intro screen dismissal with any key
	if _intro_screen and is_instance_valid(_intro_screen):
		if event is InputEventKey and event.pressed:
			_dismiss_intro()
			get_viewport().set_input_as_handled()


func _dismiss_intro() -> void:
	if not _intro_screen or not is_instance_valid(_intro_screen):
		return
	
	_intro_shown = true
	var screen := _intro_screen
	_intro_screen = null  # Clear reference immediately to prevent double-dismiss
	
	# Stop the loading animation
	if _loading_tween and _loading_tween.is_running():
		_loading_tween.kill()
	_loading_tween = null
	_loading_character = null
	
	# Remove the CanvasLayer (parent of intro screen)
	var canvas_layer := screen.get_parent()
	if canvas_layer and canvas_layer is CanvasLayer:
		canvas_layer.queue_free()
	else:
		screen.queue_free()
	
	# Setup music now that intro is done
	_setup_music()
	
	# Show the preloaded main menu (already instantiated and initialized)
	if _preloaded_main_menu and is_instance_valid(_preloaded_main_menu):
		_preloaded_main_menu.visible = true
		_current_menu = _preloaded_main_menu
		_menu_stack.clear()
		_menu_stack.push_back(_preloaded_main_menu)
		
		# Connect signals
		if _preloaded_main_menu.has_signal("play_selected"):
			_preloaded_main_menu.play_selected.connect(_on_play_selected)
		if _preloaded_main_menu.has_signal("settings_selected"):
			_preloaded_main_menu.settings_selected.connect(_on_settings_selected)
		if _preloaded_main_menu.has_signal("achievements_selected"):
			_preloaded_main_menu.achievements_selected.connect(_on_achievements_selected)
		if _preloaded_main_menu.has_signal("quit_selected"):
			_preloaded_main_menu.quit_selected.connect(_on_quit_selected)
		if _preloaded_main_menu.has_signal("leaderboards_selected"):
			_preloaded_main_menu.leaderboards_selected.connect(_on_leaderboards_selected)
		if _preloaded_main_menu.has_signal("shop_selected"):
			_preloaded_main_menu.shop_selected.connect(_on_shop_selected)
		
		_preloaded_main_menu = null  # Clear reference
		print("[MenuManager] Main menu shown (was preloaded)")
	else:
		# Fallback to normal loading
		show_main_menu()


func _add_loading_character() -> void:
	# Pick a random character sprite sheet
	var sprite_path: String = LOADING_CHARACTER_SPRITES[randi() % LOADING_CHARACTER_SPRITES.size()]
	var sprite_sheet: Texture2D = load(sprite_path)
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
	_loading_character.scale = Vector2(0.25, 0.25)  # Scale down for UI
	_loading_character.animation = "right"
	_loading_character.play("right")
	_loading_character.modulate = UI.CHAR_PORTRAIT_UNLOCKED
	
	# Position at bottom-left of screen
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_loading_start_x = -50.0
	_loading_end_x = viewport_size.x + 50.0
	_loading_character.position = Vector2(_loading_start_x, viewport_size.y - 60)
	_intro_screen.add_child(_loading_character)
	
	# Record start time for time-based animation
	_intro_start_time = Time.get_ticks_msec()
	
	# Start the loading progress update loop
	_update_loading_progress()


func _update_loading_progress() -> void:
	# Move character across screen while intro is showing
	if not _loading_character or not is_instance_valid(_loading_character):
		return
	if not _intro_screen or not is_instance_valid(_intro_screen):
		return
	
	# Walk across screen - speed adjusts based on how long intro takes
	# Character walks slower initially, speeds up as we get closer to ready
	var elapsed_ms: int = Time.get_ticks_msec() - _intro_start_time
	
	# Base walk takes 3 seconds, but continues if intro takes longer
	var base_walk_duration_ms: float = 3000.0
	
	# Progress based on elapsed time
	var progress: float = float(elapsed_ms) / base_walk_duration_ms
	
	# Clamp to 0-1 range for position calculation
	var clamped_progress: float = clampf(progress, 0.0, 1.0)
	
	# Move character based on progress
	var target_x: float = lerp(_loading_start_x, _loading_end_x, clamped_progress)
	_loading_character.position.x = lerp(_loading_character.position.x, target_x, 0.15)
	
	# Subtle bobbing while walking (only if still on screen)
	if clamped_progress < 1.0:
		var bob_offset: float = sin(Time.get_ticks_msec() * 0.012) * 4.0
		_loading_character.position.y = get_viewport().get_visible_rect().size.y - 60 + bob_offset
	
	# Continue updating if intro is still showing
	if _intro_screen and is_instance_valid(_intro_screen):
		get_tree().create_timer(0.016).timeout.connect(_update_loading_progress)  # ~60fps


func _setup_debug_menu() -> void:
	_debug_menu = CanvasLayer.new()
	_debug_menu.set_script(DebugMenuScript)
	_debug_menu.name = "GlobalDebugMenu"
	add_child(_debug_menu)


func _start_background_loading() -> void:
	# Start threaded loading of all menu scenes and music during intro
	# This happens in the background while the intro is displayed
	ResourceLoader.load_threaded_request(MENU_MUSIC_PATH)
	ResourceLoader.load_threaded_request(SCENE_PATHS.main_menu)
	ResourceLoader.load_threaded_request(SCENE_PATHS.character_select)
	# Other scenes can load later on demand


func _get_or_load_scene(scene_key: String) -> PackedScene:
	# Get scene from cache or load it (with threaded check first)
	var path: String = SCENE_PATHS.get(scene_key, "")
	if path.is_empty():
		return null
	
	# Check if threaded load is complete
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		return ResourceLoader.load_threaded_get(path) as PackedScene
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# Wait for it to complete
		return ResourceLoader.load_threaded_get(path) as PackedScene
	else:
		# Not started, load synchronously
		return load(path) as PackedScene


func _setup_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MenuMusic"
	_music_player.bus = "Music"  # Use Music bus for background music
	add_child(_music_player)
	
	# Try to get music from threaded load, fall back to sync load
	var music_stream: AudioStream = null
	var status := ResourceLoader.load_threaded_get_status(MENU_MUSIC_PATH)
	if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		music_stream = ResourceLoader.load_threaded_get(MENU_MUSIC_PATH) as AudioStream
	else:
		music_stream = load(MENU_MUSIC_PATH)
	
	if music_stream == null:
		push_error("[MenuManager] Failed to load music file: " + MENU_MUSIC_PATH + " - Make sure the file is imported in Godot")
		return
	
	_music_player.stream = music_stream
	_music_player.volume_db = -8.0
	_music_player.autoplay = false
	
	# Ensure music loops - check stream type and set loop
	if music_stream is AudioStreamMP3:
		(music_stream as AudioStreamMP3).loop = true
	elif music_stream is AudioStreamOggVorbis:
		(music_stream as AudioStreamOggVorbis).loop = true
	elif music_stream is AudioStreamWAV:
		(music_stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	
	# Start playing
	_music_player.play()
	
	if _music_player.playing:
		print("[MenuManager] Menu music playing successfully")
	else:
		push_error("[MenuManager] Music stream loaded but not playing")


## Stop menu music - can be called from anywhere
func stop_menu_music() -> void:
	if _music_player and _music_player.playing:
		print("[MenuManager] Stopping menu music")
		_music_player.stop()


## Start menu music - can be called when returning to menus
func start_menu_music() -> void:
	if _music_player == null:
		_setup_music()
		return
	
	if _music_player.stream == null:
		# Stream wasn't loaded, try to set it up again
		_setup_music()
		return
	
	if not _music_player.playing:
		print("[MenuManager] Starting menu music")
		_music_player.play()


## Return to main menu from game - clears everything and shows main menu
func return_to_main_menu() -> void:
	print("[MenuManager] return_to_main_menu called")
	
	# First change scene to remove the Level/game scene
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
	
	# Wait for scene change, then set up MenuManager's menu properly
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Get the new MainMenu that was loaded
	var root := get_tree().current_scene
	if root and root is MainMenu:
		print("[MenuManager] Found MainMenu scene, connecting signals")
		# Clear our internal state
		_clear_stack()
		_current_menu = root
		
		# Connect signals to make buttons work
		if root.has_signal("play_selected"):
			root.play_selected.connect(_on_play_selected)
		if root.has_signal("settings_selected"):
			root.settings_selected.connect(_on_settings_selected)
		if root.has_signal("achievements_selected"):
			root.achievements_selected.connect(_on_achievements_selected)
		if root.has_signal("quit_selected"):
			root.quit_selected.connect(_on_quit_selected)
		if root.has_signal("leaderboards_selected"):
			root.leaderboards_selected.connect(_on_leaderboards_selected)
		if root.has_signal("shop_selected"):
			root.shop_selected.connect(_on_shop_selected)
		
		# Start menu music
		start_menu_music()
	else:
		push_warning("[MenuManager] Could not find MainMenu scene after return")


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
	if _music_player:
		print("[MenuManager] Stopping menu music...")
		_music_player.stop()
		print("[MenuManager] Music player stopped, playing=", _music_player.playing)
	else:
		print("[MenuManager] No music player found!")
	
	# Emit signal for game to handle
	emit_signal("game_started", squad, stage_id)
	
	# Clear menus and transition to game
	_clear_stack()
	
	# Change to Level scene
	print("[MenuManager] Changing to Level scene...")
	get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")
