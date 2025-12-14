extends CanvasLayer
class_name DebugMenu

## Debug menu accessible via F4 key
## Provides toggles and buttons for testing/debugging
## Organized with tabs for better navigation

const SaveManagerScript = preload("res://scripts/systems/SaveManager.gd")
# UITheme loaded lazily in _setup_ui to avoid blocking startup
var UI = null

# Tab constants
const TAB_TOGGLES := "toggles"
const TAB_PLAYER := "player"
const TAB_SPAWN := "spawn"
const TAB_PROGRESS := "progress"
const TAB_DATA := "data"
const TAB_ORDER := [TAB_TOGGLES, TAB_PLAYER, TAB_SPAWN, TAB_PROGRESS, TAB_DATA]

var _panel: PanelContainer
var _tab_container: HBoxContainer
var _content_container: Control
var _tabs: Dictionary = {}
var _panels: Dictionary = {}
var _current_tab: String = ""
var _is_visible: bool = false

# Toggle states
var _invincibility_enabled: bool = false
var _infinite_burst_enabled: bool = false
var _one_hit_kill_enabled: bool = false
var _infinite_stamina_enabled: bool = false

# Toggle button references for state updates
var _toggle_buttons: Dictionary = {}

# References
var _player: Node2D = null
var _level: Node = null
var _enemy_spawner: Node = null

func _ready() -> void:
	layer = 100  # On top of everything
	_setup_ui()
	hide()

func _setup_ui() -> void:
	# Load UITheme lazily (not at script parse time)
	if UI == null:
		UI = load("res://scripts/ui/UITheme.gd")
	
	# Dark semi-transparent background
	var bg := ColorRect.new()
	bg.color = UI.BG_OVERLAY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	
	# Main panel - wider to accommodate tabs
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 580)
	_panel.position = Vector2(-210, -290)
	
	var style := StyleBoxFlat.new()
	style.bg_color = UI.DEBUG_PANEL_BG
	style.border_color = UI.DEBUG_PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	
	# Main vertical layout
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(main_vbox)
	
	# Title row with close button
	var title_row := HBoxContainer.new()
	main_vbox.add_child(title_row)
	
	var title := Label.new()
	title.text = "DEBUG MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_color_override("font_color", UI.DEBUG_TITLE)
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_toggle_menu)
	close_btn.custom_minimum_size = Vector2(32, 32)
	_style_button(close_btn, UI.DEBUG_BTN_CLOSE)
	title_row.add_child(close_btn)
	
	# Tab bar
	_tab_container = HBoxContainer.new()
	_tab_container.add_theme_constant_override("separation", 4)
	main_vbox.add_child(_tab_container)
	
	# Create tab buttons
	for tab_name in TAB_ORDER:
		var tab_btn := Button.new()
		tab_btn.text = _get_tab_display_name(tab_name)
		tab_btn.toggle_mode = true
		tab_btn.focus_mode = Control.FOCUS_NONE
		tab_btn.pressed.connect(_on_tab_pressed.bind(tab_name))
		tab_btn.custom_minimum_size = Vector2(70, 28)
		_tab_container.add_child(tab_btn)
		_tabs[tab_name] = tab_btn
	
	# Separator under tabs
	var tab_separator := HSeparator.new()
	tab_separator.add_theme_constant_override("separation", 4)
	main_vbox.add_child(tab_separator)
	
	# Content area with scroll
	_content_container = Control.new()
	_content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_container.custom_minimum_size = Vector2(396, 440)
	main_vbox.add_child(_content_container)
	
	# Create panels for each tab
	_create_toggles_panel()
	_create_player_panel()
	_create_spawn_panel()
	_create_progress_panel()
	_create_data_panel()
	
	# Hide all panels initially
	for panel in _panels.values():
		panel.visible = false
	
	# Bottom row with shortcut hint
	var hint := Label.new()
	hint.text = "Press F4 or ESC to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 0.8))
	hint.add_theme_font_size_override("font_size", 12)
	main_vbox.add_child(hint)
	
	# Switch to first tab
	_switch_tab(TAB_TOGGLES)

func _get_tab_display_name(tab_name: String) -> String:
	match tab_name:
		TAB_TOGGLES: return "Cheats"
		TAB_PLAYER: return "Player"
		TAB_SPAWN: return "Spawn"
		TAB_PROGRESS: return "Progress"
		TAB_DATA: return "Data"
		_: return tab_name.capitalize()

func _create_panel_base() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_container.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	
	scroll.set_meta("vbox", vbox)
	return scroll

func _create_toggles_panel() -> void:
	var scroll := _create_panel_base()
	var vbox: VBoxContainer = scroll.get_meta("vbox")
	_panels[TAB_TOGGLES] = scroll
	
	_add_section_label(vbox, "CHEAT TOGGLES")
	_add_description(vbox, "Enable cheats for testing. These persist until you close the menu.")
	
	_toggle_buttons["invincibility"] = _add_toggle_button(vbox, "Player Invincibility", "Take no damage", _on_toggle_invincibility)
	_toggle_buttons["infinite_burst"] = _add_toggle_button(vbox, "Infinite Burst", "Burst gauge never depletes", _on_toggle_infinite_burst)
	_toggle_buttons["one_hit_kill"] = _add_toggle_button(vbox, "One-Hit Kill", "Enemies die in one hit", _on_toggle_one_hit_kill)
	_toggle_buttons["infinite_stamina"] = _add_toggle_button(vbox, "Infinite Stamina", "Dash and run without limit", _on_toggle_infinite_stamina)
	_toggle_buttons["show_fps"] = _add_toggle_button(vbox, "Show FPS", "Show FPS counter in HUD", _on_toggle_show_fps)

func _create_player_panel() -> void:
	var scroll := _create_panel_base()
	var vbox: VBoxContainer = scroll.get_meta("vbox")
	_panels[TAB_PLAYER] = scroll
	
	_add_section_label(vbox, "PLAYER ACTIONS")
	_add_description(vbox, "Instant player buffs and stat modifications.")
	
	_add_button(vbox, "Fill Burst Gauge", "Max out burst energy", _on_fill_burst)
	_add_button(vbox, "Force Level Up", "Instantly gain a level", _on_force_level_up)
	_add_button(vbox, "Add 1000 XP", "Gain 1000 experience points", _on_add_xp)
	_add_button(vbox, "Full Heal", "Restore HP to maximum", _on_full_heal)
	_add_button(vbox, "Restore Stamina", "Refill stamina bar", _on_restore_stamina)
	
	_add_separator(vbox)
	_add_section_label(vbox, "SKILL POINTS")
	_add_button(vbox, "+5 Skill Points", "Add skill points for talent tree", _on_add_skill_points)

func _create_spawn_panel() -> void:
	var scroll := _create_panel_base()
	var vbox: VBoxContainer = scroll.get_meta("vbox")
	_panels[TAB_SPAWN] = scroll
	
	_add_section_label(vbox, "SPAWN ENEMIES")
	_add_description(vbox, "Spawn enemies for testing combat.")
	
	_add_button(vbox, "Spawn 10 Basic", "Spawn a wave of basic enemies", _on_spawn_basic_wave)
	_add_button(vbox, "Spawn Tank", "Spawn a tank enemy", _on_spawn_tank)
	_add_button(vbox, "Spawn Shielder", "Spawn a shielder (blue shield)", _on_spawn_shielder)
	_add_button(vbox, "Spawn Exploder", "Spawn an exploder (red strobe)", _on_spawn_exploder)
	_add_button(vbox, "Spawn Elite", "Spawn an elite enemy", _on_spawn_elite)
	_add_button(vbox, "Spawn Boss", "Spawn a boss enemy", _on_spawn_boss)
	_add_button(vbox, "Spawn Super Boss", "Spawn a super boss enemy", _on_spawn_super_boss)
	_add_button(vbox, "Spawn N01", "Spawn RAPTURE QUEEN - N01", _on_spawn_n01)
	
	_add_separator(vbox)
	_add_section_label(vbox, "WAVE CONTROL")
	_add_button(vbox, "Kill All Enemies", "Instantly kill all enemies on screen", _on_kill_all_enemies)

	_add_button(vbox, "Skip to Next Wave", "Advance to the next wave", _on_skip_wave)
	_add_button(vbox, "Jump to Wave 11", "Instant jump to final wave", _on_jump_wave_11)
	_add_button(vbox, "Start Rapture Event", "Trigger Queen Event + Flood", _on_start_rapture_event)

func _create_progress_panel() -> void:
	var scroll := _create_panel_base()
	var vbox: VBoxContainer = scroll.get_meta("vbox")
	_panels[TAB_PROGRESS] = scroll
	
	_add_section_label(vbox, "CURRENCY")
	_add_description(vbox, "Add resources for testing shop purchases.")
	
	_add_button(vbox, "+1 Pristine Core", "Add 1 core", _on_add_pristine_core)
	_add_button(vbox, "+10 Pristine Cores", "Add 10 cores", _on_add_pristine_cores_10)
	_add_button(vbox, "+100 Pristine Cores", "Add 100 cores", _on_add_pristine_cores_100)
	
	_add_separator(vbox)
	_add_section_label(vbox, "UNLOCKS")
	_add_button(vbox, "Unlock All Stages", "Make all stages available", _on_unlock_all_stages)
	_add_button(vbox, "Unlock All Characters", "Make all characters available", _on_unlock_all_characters)
	_add_button(vbox, "Complete All Achievements", "Unlock all achievements", _on_complete_achievements)

func _create_data_panel() -> void:
	var scroll := _create_panel_base()
	var vbox: VBoxContainer = scroll.get_meta("vbox")
	_panels[TAB_DATA] = scroll
	
	_add_section_label(vbox, "SAVE DATA")
	_add_description(vbox, "View and manage save files.")
	
	_add_button(vbox, "Open Save Folder", "Open save directory in explorer", _on_open_save_folder)
	
	_add_separator(vbox)
	_add_section_label(vbox, "DANGER ZONE")
	_add_description(vbox, "These actions cannot be undone!")
	
	_add_danger_button(vbox, "Reset Shop Data", "Reset purchases and currency", _on_reset_shop)
	_add_danger_button(vbox, "Reset Leaderboards", "Clear high scores/runs", _on_reset_leaderboards)
	_add_danger_button(vbox, "Reset Achievements", "Clear all achievement progress", _on_reset_achievements)
	_add_danger_button(vbox, "RESET ALL DATA", "Delete all save data", _on_reset_all_data)

# === UI BUILDER HELPERS ===

func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UI.DEBUG_SECTION_LABEL)
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)

func _add_description(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.9))
	label.add_theme_font_size_override("font_size", 11)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _add_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	parent.add_child(sep)

func _add_button(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.pressed.connect(callback)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn, UI.DEBUG_BTN_NORMAL)
	parent.add_child(btn)
	return btn

func _add_toggle_button(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)
	
	var btn := Button.new()
	btn.text = text + "  [OFF]"
	btn.tooltip_text = tooltip
	btn.pressed.connect(func(): callback.call(btn))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.set_meta("base_text", text)
	_style_button(btn, UI.DEBUG_BTN_TOGGLE)
	hbox.add_child(btn)
	
	return btn

func _add_danger_button(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.pressed.connect(callback)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn, UI.DEBUG_BTN_DANGER)
	parent.add_child(btn)
	return btn

func _style_button(btn: Button, base_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = base_color
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	
	var hover := style.duplicate()
	hover.bg_color = base_color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := style.duplicate()
	pressed.bg_color = base_color.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", pressed)

func _update_toggle_button(btn: Button, enabled: bool) -> void:
	var base_text: String = btn.get_meta("base_text", "Toggle")
	if enabled:
		btn.text = base_text + "  [ON]"
		var style := btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		style.bg_color = UI.DEBUG_TOGGLE_ON
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = UI.DEBUG_TOGGLE_ON.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)
	else:
		btn.text = base_text + "  [OFF]"
		var style := btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		style.bg_color = UI.DEBUG_TOGGLE_OFF
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = UI.DEBUG_TOGGLE_OFF.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover)

# === TAB NAVIGATION ===

func _on_tab_pressed(tab_name: String) -> void:
	_switch_tab(tab_name)

func _switch_tab(tab_name: String) -> void:
	if _current_tab == tab_name:
		return
	
	# Hide current panel and deactivate tab
	if _panels.has(_current_tab):
		_panels[_current_tab].visible = false
	if _tabs.has(_current_tab):
		_tabs[_current_tab].button_pressed = false
	
	_current_tab = tab_name
	
	# Show new panel and activate tab
	if _panels.has(_current_tab):
		_panels[_current_tab].visible = true
	if _tabs.has(_current_tab):
		_tabs[_current_tab].button_pressed = true
	
	_update_tab_styles()

func _update_tab_styles() -> void:
	for tab_name in TAB_ORDER:
		if not _tabs.has(tab_name):
			continue
		var btn: Button = _tabs[tab_name]
		var active: bool = _current_tab == tab_name
		
		var style := StyleBoxFlat.new()
		if active:
			style.bg_color = UI.DEBUG_TITLE.darkened(0.3)
			style.border_color = UI.DEBUG_TITLE
		else:
			style.bg_color = Color(0.2, 0.2, 0.25, 0.8)
			style.border_color = Color(0.4, 0.4, 0.5, 0.5)
		
		style.set_border_width_all(0)
		style.border_width_bottom = 2 if active else 1
		style.set_corner_radius_all(4)
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		style.set_content_margin_all(4)
		
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		
		btn.add_theme_color_override("font_color", UI.DEBUG_TITLE if active else Color(0.7, 0.7, 0.8))
		btn.add_theme_font_size_override("font_size", 11)

# === INPUT HANDLING ===

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F4:
			_toggle_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _is_visible:
			_toggle_menu()
			get_viewport().set_input_as_handled()

func _toggle_menu() -> void:
	_is_visible = not _is_visible
	visible = _is_visible
	
	if _is_visible:
		_find_references()
		get_tree().paused = true
		process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		get_tree().paused = false

func _find_references() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_level = get_tree().get_first_node_in_group("level")
	if not _level:
		_level = get_tree().current_scene
	
	if _level and _level.has_node("EnemySpawner"):
		_enemy_spawner = _level.get_node("EnemySpawner")

# === TOGGLE CALLBACKS ===

func _on_toggle_invincibility(btn: Button) -> void:
	_invincibility_enabled = not _invincibility_enabled
	_update_toggle_button(btn, _invincibility_enabled)
	
	if _player and _player.has_method("set_invincible"):
		_player.set_invincible(_invincibility_enabled)
	elif _player:
		_player.set_meta("debug_invincible", _invincibility_enabled)
	
	print("[DEBUG] Invincibility: ", _invincibility_enabled)

func _on_toggle_infinite_burst(btn: Button) -> void:
	_infinite_burst_enabled = not _infinite_burst_enabled
	_update_toggle_button(btn, _infinite_burst_enabled)
	
	if _player:
		_player.set_meta("debug_infinite_burst", _infinite_burst_enabled)
		# Also fill burst gauge to max when enabling - use BurstSystem
		if _infinite_burst_enabled:
			if "_burst_system" in _player and _player._burst_system:
				_player._burst_system.burst_current = _player._burst_system.burst_max
			elif "burst_current" in _player and "burst_max" in _player:
				_player.burst_current = _player.burst_max
	
	print("[DEBUG] Infinite Burst: ", _infinite_burst_enabled)

func _on_toggle_one_hit_kill(btn: Button) -> void:
	_one_hit_kill_enabled = not _one_hit_kill_enabled
	_update_toggle_button(btn, _one_hit_kill_enabled)
	
	if _player:
		_player.set_meta("debug_one_hit_kill", _one_hit_kill_enabled)
	
	print("[DEBUG] One-Hit Kill: ", _one_hit_kill_enabled)

func _on_toggle_infinite_stamina(btn: Button) -> void:
	_infinite_stamina_enabled = not _infinite_stamina_enabled
	_update_toggle_button(btn, _infinite_stamina_enabled)
	
	if _player:
		_player.set_meta("debug_infinite_stamina", _infinite_stamina_enabled)
	
	print("[DEBUG] Infinite Stamina: ", _infinite_stamina_enabled)

func _on_toggle_show_fps(btn: Button) -> void:
	DebugSettings.show_fps = not DebugSettings.show_fps
	_update_toggle_button(btn, DebugSettings.show_fps)
	print("[DEBUG] Show FPS: ", DebugSettings.show_fps)

# === PLAYER CALLBACKS ===

func _on_fill_burst() -> void:
	if _player:
		# Use BurstSystem if available
		if "_burst_system" in _player and _player._burst_system:
			_player._burst_system.burst_current = _player._burst_system.burst_max
			# Emit signal to update UI
			_player._burst_system.burst_changed.emit(_player._burst_system.burst_current, _player._burst_system.burst_max)
			print("[DEBUG] Burst gauge filled via BurstSystem")
		elif "burst_current" in _player and "burst_max" in _player:
			_player.burst_current = _player.burst_max
			if _player.has_node("PlayerHud"):
				_player.get_node("PlayerHud").update_burst(_player.burst_current, _player.burst_max, true)
			if "overhead_hud" in _player and _player.overhead_hud:
				_player.overhead_hud.update_burst(_player.burst_current, _player.burst_max)
			print("[DEBUG] Burst gauge filled (legacy)")

func _on_force_level_up() -> void:
	if _player and _player.has_method("add_xp"):
		var xp_needed: int = 100
		if "xp_to_next_level" in _player:
			xp_needed = _player.xp_to_next_level - _player.current_xp + 1
		_player.add_xp(xp_needed)
		print("[DEBUG] Forced level up")

func _on_add_xp() -> void:
	if _player and _player.has_method("add_xp"):
		_player.add_xp(1000)
		print("[DEBUG] Added 1000 XP")

func _on_full_heal() -> void:
	if _player and "current_hp" in _player and "max_hp" in _player:
		_player.current_hp = _player.max_hp
		if _player.has_method("_update_hp_bar"):
			_player._update_hp_bar()
		print("[DEBUG] Fully healed")

func _on_restore_stamina() -> void:
	if _player and "stamina" in _player and "max_stamina" in _player:
		_player.stamina = _player.max_stamina
		print("[DEBUG] Stamina restored")

func _on_add_skill_points() -> void:
	if _player and "skill_points" in _player:
		_player.skill_points += 5
		print("[DEBUG] Added 5 skill points")

# === SPAWN CALLBACKS ===

func _on_spawn_tank() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		_enemy_spawner.spawn_enemy("tank", "ring")
		print("[DEBUG] Spawned Tank")

func _on_spawn_shielder() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		_enemy_spawner.spawn_enemy("shielder", "ring")
		print("[DEBUG] Spawned Shielder")

func _on_spawn_exploder() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		_enemy_spawner.spawn_enemy("exploder", "ring")
		print("[DEBUG] Spawned Exploder")

func _on_spawn_elite() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		_enemy_spawner.spawn_enemy("basic", "elite")
		print("[DEBUG] Spawned Elite")

func _on_spawn_boss() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		_enemy_spawner.spawn_enemy("boss", "ring")
		print("[DEBUG] Spawned Boss")

func _on_spawn_basic_wave() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		for i in range(10):
			_enemy_spawner.spawn_enemy("basic", "ring")
		print("[DEBUG] Spawned 10 basic enemies")

func _on_spawn_super_boss() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		_enemy_spawner.spawn_enemy("super_boss", "ring")
		print("[DEBUG] Spawned Super Boss")

func _on_spawn_n01() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_rapture_queen"):
		_enemy_spawner.spawn_rapture_queen()
		print("[DEBUG] Spawned N01 via Spawner (Env Triggers Active)")
	else:
		print("[DEBUG] Spawner missing spawn_rapture_queen method!")

func _on_jump_wave_11() -> void:
	if _level and "_wave_director" in _level:
		var dir = _level._wave_director
		if dir and dir.has_method("debug_jump_to_wave"):
			dir.debug_jump_to_wave(11)

func _on_start_rapture_event() -> void:
	if _level and "_wave_director" in _level:
		var dir = _level._wave_director
		if dir and dir.has_method("debug_start_rapture_event"):
			dir.debug_start_rapture_event()

func _on_kill_all_enemies() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var count := 0
	for enemy in enemies:
		if enemy.has_method("die"):
			enemy.die()
			count += 1
		elif enemy.has_method("take_damage"):
			enemy.take_damage(99999)
			count += 1
	print("[DEBUG] Killed %d enemies" % count)

func _on_skip_wave() -> void:
	# Try to access WaveDirector through Level
	if _level and "_wave_director" in _level:
		var wave_director = _level._wave_director
		if wave_director and wave_director.has_method("debug_skip_wave"):
			wave_director.debug_skip_wave()
			print("[DEBUG] Skipped to next wave via WaveDirector")
			return
	
	# Fallback: try legacy methods
	if _level and _level.has_method("_advance_wave"):
		_level._advance_wave()
		print("[DEBUG] Skipped to next wave")
	elif _enemy_spawner and "current_wave" in _enemy_spawner:
		_enemy_spawner.current_wave += 1
		print("[DEBUG] Advanced wave counter")
	else:
		print("[DEBUG] Could not find wave system to skip")

# === PROGRESS CALLBACKS ===

func _on_unlock_all_stages() -> void:
	if not GameState:
		print("[DEBUG] GameState not available")
		return
	
	var StageRegistryScript = load("res://scripts/systems/StageRegistry.gd")
	if StageRegistryScript and "STAGES" in StageRegistryScript:
		for stage in StageRegistryScript.STAGES:
			var stage_id: String = stage["id"]
			if stage_id not in GameState.stages_cleared:
				GameState.stages_cleared.append(stage_id)
		GameState._save_stage_progress()
		print("[DEBUG] All stages unlocked!")

func _on_unlock_all_characters() -> void:
	# Get all character IDs from the CharacterRegistry CONTROLLER_SCRIPTS
	var CharacterRegistryScript = load("res://scripts/characters/CharacterRegistry.gd")
	if not CharacterRegistryScript:
		print("[DEBUG] Failed to load CharacterRegistry")
		return
	
	# Get character IDs from CONTROLLER_SCRIPTS keys
	var all_ids: Array = []
	if "CONTROLLER_SCRIPTS" in CharacterRegistryScript:
		for char_id in CharacterRegistryScript.CONTROLLER_SCRIPTS.keys():
			all_ids.append(char_id)
	
	if all_ids.is_empty():
		print("[DEBUG] No character IDs found")
		return
	
	# Save to shop data - only save non-default characters as per shop format
	var default_unlocked: Array = []
	if "DEFAULT_UNLOCKED" in CharacterRegistryScript:
		default_unlocked = Array(CharacterRegistryScript.DEFAULT_UNLOCKED)
	
	var extra_unlocked: Array = []
	for char_id in all_ids:
		if char_id not in default_unlocked:
			extra_unlocked.append(char_id)
	
	var config := ConfigFile.new()
	# Load existing data first to preserve upgrades
	config.load(SaveManagerScript.SHOP_PATH)
	config.set_value("characters", "unlocked", extra_unlocked)
	var err := config.save(SaveManagerScript.SHOP_PATH)
	
	if err == OK:
		print("[DEBUG] All characters unlocked! (%d total, %d non-default saved)" % [all_ids.size(), extra_unlocked.size()])
	else:
		print("[DEBUG] Failed to save character unlocks: %d" % err)

func _on_complete_achievements() -> void:
	var achievement_manager := get_node_or_null("/root/AchievementManager")
	if not achievement_manager:
		print("[DEBUG] AchievementManager not available")
		return
	
	# Get all character IDs from registry
	var CharacterRegistryScript = load("res://scripts/characters/CharacterRegistry.gd")
	if not CharacterRegistryScript or not "CONTROLLER_SCRIPTS" in CharacterRegistryScript:
		print("[DEBUG] Failed to load CharacterRegistry")
		return
	
	var char_ids: Array = CharacterRegistryScript.CONTROLLER_SCRIPTS.keys()
	var count := 0
	
	# Unlock all achievements for each character
	for char_id in char_ids:
		# Achievement types: unlock (non-default only), kills, all_skills, win
		var achievement_types := ["kills", "all_skills", "win"]
		
		# Add unlock achievement for non-default characters
		if "DEFAULT_UNLOCKED" in CharacterRegistryScript:
			if char_id not in CharacterRegistryScript.DEFAULT_UNLOCKED:
				achievement_types.insert(0, "unlock")
		
		for ach_type in achievement_types:
			var ach_id: String = "%s_%s" % [ach_type, char_id]
			achievement_manager._achievements[ach_id] = {
				"unlocked": true,
				"progress": 10000 if ach_type == "kills" else 1,
				"unlocked_at": int(Time.get_unix_time_from_system())
			}
			count += 1
	
	# Save achievements
	if achievement_manager.has_method("_save_achievements"):
		achievement_manager._save_achievements()
	
	# Also unlock general achievements
	var general_achievements := [
		"first_blood",        # First Blood
		"kill_50000",         # Massacre
		"boss_slayer",        # Boss Slayer
		"no_damage",          # Untouchable
		"all_maps",           # World Traveler
		"abandoned_wishes",   # Abandoned Wishes
		"she_descends"        # She Descends
	]
	
	for ach_id in general_achievements:
		achievement_manager._achievements[ach_id] = {
			"unlocked": true,
			"progress": 100,
			"unlocked_at": int(Time.get_unix_time_from_system())
		}
		count += 1
	
	# Save again with general achievements
	if achievement_manager.has_method("_save_achievements"):
		achievement_manager._save_achievements()
	
	print("[DEBUG] Completed %d achievements (including general)!" % count)

func _on_add_pristine_core() -> void:
	if GameState and GameState.has_method("add_pristine_cores"):
		GameState.add_pristine_cores(1)
		print("[DEBUG] Added 1 Pristine Core. Total: %d" % GameState.get_pristine_cores())

func _on_add_pristine_cores_10() -> void:
	if GameState and GameState.has_method("add_pristine_cores"):
		GameState.add_pristine_cores(10)
		print("[DEBUG] Added 10 Pristine Cores. Total: %d" % GameState.get_pristine_cores())

func _on_add_pristine_cores_100() -> void:
	if GameState and GameState.has_method("add_pristine_cores"):
		GameState.add_pristine_cores(100)
		print("[DEBUG] Added 100 Pristine Cores. Total: %d" % GameState.get_pristine_cores())

# === DATA CALLBACKS ===

func _on_open_save_folder() -> void:
	var save_path := OS.get_user_data_dir()
	OS.shell_open(save_path)
	print("[DEBUG] Opened save folder: %s" % save_path)

func _on_reset_shop() -> void:
	if GameState:
		GameState.set_pristine_cores(0)
	
	var config := ConfigFile.new()
	config.set_value("currency", "pristine_cores", 0)
	var CharacterRegistryScript = load("res://scripts/characters/CharacterRegistry.gd")
	if CharacterRegistryScript and "DEFAULT_UNLOCKED" in CharacterRegistryScript:
		config.set_value("characters", "unlocked", CharacterRegistryScript.DEFAULT_UNLOCKED.duplicate())
	config.set_value("upgrades", "data", {})
	config.save(SaveManagerScript.SHOP_PATH)
	
	print("[DEBUG] Shop data reset!")

func _on_reset_leaderboards() -> void:
	if GameState:
		GameState.reset_leaderboard()
		print("[DEBUG] Requested leaderboard reset")

func _on_reset_achievements() -> void:
	var achievement_manager := get_node_or_null("/root/AchievementManager")
	if achievement_manager:
		if "_character_progress" in achievement_manager:
			achievement_manager._character_progress.clear()
		if "_achievements" in achievement_manager:
			achievement_manager._achievements.clear()
		if achievement_manager.has_method("_save"):
			achievement_manager._save()
	
	# Also delete the file
	if FileAccess.file_exists(SaveManagerScript.ACHIEVEMENTS_PATH):
		DirAccess.remove_absolute(SaveManagerScript.ACHIEVEMENTS_PATH)
	
	print("[DEBUG] Achievements reset!")

func _on_reset_all_data() -> void:
	var results := SaveManagerScript.delete_all_saves()
	
	for path in results:
		if results[path]:
			print("[DEBUG] Deleted: %s" % path)
		else:
			print("[DEBUG] Failed to delete: %s" % path)
	
	if GameState:
		GameState.set_pristine_cores(0)
		GameState.stages_cleared.clear()
	
	var achievement_manager := get_node_or_null("/root/AchievementManager")
	if achievement_manager:
		if "_character_progress" in achievement_manager:
			achievement_manager._character_progress.clear()
		if "_achievements" in achievement_manager:
			achievement_manager._achievements.clear()
	
	print("[DEBUG] ========================================")
	print("[DEBUG] ALL DATA RESET! Restart game to apply.")
	print("[DEBUG] ========================================")
