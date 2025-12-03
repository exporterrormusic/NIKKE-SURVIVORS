extends Node
## Manages menu navigation and transitions between screens.
## Load this as an autoload or instantiate in your main scene.

signal game_started(squad: Array[int], map_id: StringName, time_id: StringName)

# Menu scenes
const MainMenuScene = preload("res://scenes/ui/MainMenu.tscn")
const SettingsMenuScene = preload("res://scenes/ui/SettingsMenu.tscn")
const CharacterSelectScene = preload("res://scenes/ui/CharacterSelectMenu.tscn")
const AchievementsScene = preload("res://scenes/ui/AchievementsMenu.tscn")
const LeaderboardScene = preload("res://scenes/ui/LeaderboardMenu.tscn")

# Current menu stack (for back navigation)
var _menu_stack: Array[Control] = []
var _current_menu: Control = null

# Container for menus
var _menu_container: Control = null

# Music player
var _music_player: AudioStreamPlayer = null
const MENU_MUSIC_PATH := "res://assets/sounds/music/main-menu.mp3"


func _ready() -> void:
	# Create container
	_menu_container = Control.new()
	_menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_container)
	
	# Setup and play menu music
	_setup_music()
	
	# Start with main menu
	show_main_menu()


func _setup_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MenuMusic"
	_music_player.bus = "Master"  # Ensure it uses Master bus
	add_child(_music_player)
	
	# Try to load music - file must be imported by Godot
	var music_stream = load(MENU_MUSIC_PATH)
	if music_stream == null:
		push_error("[MenuManager] Failed to load music file: " + MENU_MUSIC_PATH + " - Make sure the file is imported in Godot")
		return
	
	_music_player.stream = music_stream
	_music_player.volume_db = -8.0
	_music_player.autoplay = false
	
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
	if _music_player and not _music_player.playing:
		print("[MenuManager] Starting menu music")
		_music_player.play()


func show_main_menu() -> void:
	print("[MenuManager] show_main_menu called")
	_clear_stack()
	var menu := MainMenuScene.instantiate() as Control
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


func show_settings_menu() -> void:
	var menu := SettingsMenuScene.instantiate() as Control
	_push_menu(menu)
	
	if menu.has_signal("back_requested"):
		menu.back_requested.connect(_on_back_requested)


func show_character_select() -> void:
	var menu := CharacterSelectScene.instantiate() as Control
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
	var menu := AchievementsScene.instantiate() as Control
	_push_menu(menu)
	
	if menu.has_signal("back_requested"):
		menu.back_requested.connect(_on_back_requested)


func show_leaderboard_menu() -> void:
	var menu := LeaderboardScene.instantiate() as Control
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
		menu.queue_free()
	_menu_stack.clear()
	
	if _current_menu:
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


func _on_quit_selected() -> void:
	print("[MenuManager] _on_quit_selected")
	get_tree().quit()


func _on_back_requested() -> void:
	_pop_menu()


func _on_game_start_requested(squad: Array[int], map_id: StringName, time_id: StringName) -> void:
	print("[MenuManager] _on_game_start_requested called with squad: ", squad, " map: ", map_id, " time: ", time_id)
	
	# Save selection to GameState
	if GameState:
		GameState.set_selected_characters(squad)
		# Set the main character (first in squad) as the player character
		if squad.size() > 0:
			GameState.set_player_character(squad[0])
		# Store map and time for Level to use
		GameState.set_meta("selected_map_id", map_id)
		GameState.set_meta("selected_time_id", time_id)
	
	# Stop menu music
	if _music_player:
		print("[MenuManager] Stopping menu music...")
		_music_player.stop()
		print("[MenuManager] Music player stopped, playing=", _music_player.playing)
	else:
		print("[MenuManager] No music player found!")
	
	# Emit signal for game to handle
	emit_signal("game_started", squad, map_id, time_id)
	
	# Clear menus and transition to game
	_clear_stack()
	
	# Change to Level scene
	print("[MenuManager] Changing to Level scene...")
	get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")
