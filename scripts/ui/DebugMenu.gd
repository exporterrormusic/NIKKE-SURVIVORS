extends CanvasLayer
class_name DebugMenu

## Debug menu accessible via F5 key
## Provides toggles and buttons for testing/debugging

const SaveManagerScript = preload("res://scripts/systems/SaveManager.gd")
# UITheme loaded lazily in _setup_ui to avoid blocking startup
var UI = null

var _panel: PanelContainer
var _vbox: VBoxContainer
var _is_visible: bool = false

# Toggle states
var _invincibility_enabled: bool = false
var _infinite_burst_enabled: bool = false

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
	
	# Main panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(300, 400)
	_panel.position = Vector2(-150, -200)
	
	var style := StyleBoxFlat.new()
	style.bg_color = UI.DEBUG_PANEL_BG
	style.border_color = UI.DEBUG_PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	
	# Scrollable container
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 380)
	_panel.add_child(scroll)
	
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_vbox)
	
	# Title
	var title := Label.new()
	title.text = "DEBUG MENU (F4)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UI.DEBUG_TITLE)
	title.add_theme_font_size_override("font_size", 20)
	_vbox.add_child(title)
	
	_add_separator()
	
	# === TOGGLES SECTION ===
	_add_section_label("TOGGLES")
	
	_add_toggle_button("Player Invincibility", _on_toggle_invincibility)
	_add_toggle_button("Infinite Burst", _on_toggle_infinite_burst)
	
	_add_separator()
	
	# === PLAYER SECTION ===
	_add_section_label("PLAYER")
	
	_add_button("Fill Burst Gauge", _on_fill_burst)
	_add_button("Force Level Up", _on_force_level_up)
	_add_button("Add 1000 XP", _on_add_xp)
	_add_button("Full Heal", _on_full_heal)
	
	_add_separator()
	
	# === SPAWN SECTION ===
	_add_section_label("SPAWN ENEMIES")
	
	_add_button("Spawn Tank", _on_spawn_tank)
	_add_button("Spawn Elite", _on_spawn_elite)
	_add_button("Spawn Boss", _on_spawn_boss)
	_add_button("Spawn 10 Basic", _on_spawn_basic_wave)
	
	_add_separator()
	
	# === PROGRESS SECTION ===
	_add_section_label("PROGRESS")
	
	_add_button("Unlock All Stages", _on_unlock_all_stages)
	_add_button("+1 Pristine Core", _on_add_pristine_core)
	_add_button("+10 Pristine Cores", _on_add_pristine_cores_10)
	_add_button("Reset Shop Data", _on_reset_shop)
	
	_add_separator()
	
	# === DANGER ZONE ===
	_add_section_label("⚠️ DANGER ZONE")
	_add_danger_button("RESET ALL DATA", _on_reset_all_data)
	
	_add_separator()
	
	# Close button
	var close_btn := Button.new()
	close_btn.text = "CLOSE (F4 / ESC)"
	close_btn.pressed.connect(_toggle_menu)
	_style_button(close_btn, UI.DEBUG_BTN_CLOSE)
	_vbox.add_child(close_btn)

func _add_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UI.DEBUG_SECTION_LABEL)
	label.add_theme_font_size_override("font_size", 14)
	_vbox.add_child(label)

func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	_vbox.add_child(sep)

func _add_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	_style_button(btn, UI.DEBUG_BTN_NORMAL)
	_vbox.add_child(btn)
	return btn

func _add_toggle_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text + " [OFF]"
	btn.pressed.connect(func(): callback.call(btn))
	_style_button(btn, UI.DEBUG_BTN_TOGGLE)
	btn.set_meta("base_text", text)
	_vbox.add_child(btn)
	return btn

func _add_danger_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	_style_button(btn, UI.DEBUG_BTN_DANGER)
	_vbox.add_child(btn)
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
		btn.text = base_text + " [ON]"
		var style := btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		style.bg_color = UI.DEBUG_TOGGLE_ON
		btn.add_theme_stylebox_override("normal", style)
	else:
		btn.text = base_text + " [OFF]"
		var style := btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		style.bg_color = UI.DEBUG_TOGGLE_OFF
		btn.add_theme_stylebox_override("normal", style)

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
		# Try to find Level node directly
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
	
	print("[DEBUG] Infinite Burst: ", _infinite_burst_enabled)

# === PLAYER CALLBACKS ===

func _on_fill_burst() -> void:
	if _player and "burst_current" in _player and "burst_max" in _player:
		_player.burst_current = _player.burst_max
		if _player.has_node("PlayerHud"):
			_player.get_node("PlayerHud").update_burst(_player.burst_current, _player.burst_max, true)
		if "overhead_hud" in _player and _player.overhead_hud:
			_player.overhead_hud.update_burst(_player.burst_current, _player.burst_max)
		print("[DEBUG] Burst gauge filled")

func _on_force_level_up() -> void:
	if _player and _player.has_method("add_xp"):
		# Get XP needed to level up
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

# === SPAWN CALLBACKS ===

func _on_spawn_tank() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		_enemy_spawner.spawn_enemy("tank", "ring")
		print("[DEBUG] Spawned Tank")

func _on_spawn_elite() -> void:
	if _enemy_spawner and _enemy_spawner.has_method("spawn_enemy"):
		_enemy_spawner.spawn_enemy("basic", "elite")  # Use pattern="elite" to apply elite modifier
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

func _on_add_pristine_core() -> void:
	if GameState and GameState.has_method("add_pristine_cores"):
		GameState.add_pristine_cores(1)
		print("[DEBUG] Added 1 Pristine Core. Total: %d" % GameState.get_pristine_cores())

func _on_add_pristine_cores_10() -> void:
	if GameState and GameState.has_method("add_pristine_cores"):
		GameState.add_pristine_cores(10)
		print("[DEBUG] Added 10 Pristine Cores. Total: %d" % GameState.get_pristine_cores())

func _on_reset_shop() -> void:
	# Reset cores to 0 and lock all non-default characters
	if GameState:
		GameState.set_pristine_cores(0)
	
	var config := ConfigFile.new()
	config.set_value("currency", "pristine_cores", 0)
	config.set_value("characters", "unlocked", CharacterRegistry.DEFAULT_UNLOCKED.duplicate())
	config.set_value("upgrades", "data", {})
	config.save(SaveManagerScript.SHOP_PATH)
	
	print("[DEBUG] Shop data reset!")

func _on_reset_all_data() -> void:
	# Use SaveManager to get all save paths and delete them
	var results := SaveManagerScript.delete_all_saves()
	
	# Log results
	for path in results:
		if results[path]:
			print("[DEBUG] Deleted: %s" % path)
		else:
			print("[DEBUG] Failed to delete: %s" % path)
	
	# Reset in-memory state
	if GameState:
		GameState.set_pristine_cores(0)
		GameState.stages_cleared.clear()
	
	# Reset achievement progress in memory
	var achievement_manager := get_node_or_null("/root/AchievementManager")
	if achievement_manager:
		if "_character_progress" in achievement_manager:
			achievement_manager._character_progress.clear()
		if "_achievements" in achievement_manager:
			achievement_manager._achievements.clear()
	
	print("[DEBUG] ========================================")
	print("[DEBUG] ALL DATA RESET! Restart game to apply.")
	print("[DEBUG] ========================================")
