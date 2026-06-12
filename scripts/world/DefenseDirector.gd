extends Node
class_name DefenseDirector
## Defense mode director - Defend your ARK from endless waves.
## Square map with ARK at top center, enemies spawn from left, right, and bottom.

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal base_damaged(new_health: int, max_health: int)
signal base_destroyed()
signal defense_complete(waves_survived: int)

# Map configuration (square map)
const MAP_SIZE := 4000.0
const ARK_DEPTH := 400.0  # How tall the ARK is
const ARK_WIDTH := MAP_SIZE / 3  # 1/3 of map width (~1333)
const ARK_Y := -MAP_SIZE / 2 + ARK_DEPTH / 2  # Touch top edge (center of ARK)
const PLAYER_SPAWN_Y := 0.0  # Player spawns at center
const MIN_SPAWN_Y := -500.0  # Enemies never spawn above this Y (well below ARK)

# Spawn locations
const SPAWN_MARGIN := 200.0
const SPAWN_LEFT_X := -MAP_SIZE / 2 + SPAWN_MARGIN
const SPAWN_RIGHT_X := MAP_SIZE / 2 - SPAWN_MARGIN
const SPAWN_BOTTOM_Y := MAP_SIZE / 2 - SPAWN_MARGIN

# Wave configuration
const WAVE_DURATION := 25.0
const SPAWN_INTERVAL := 0.3
const PRE_SPAWN_COUNT := 12
const N01_START_WAVE := 15
const N01_REPEAT_WAVES := 5

# Wave script (mirrors WaveDirector but endless)
var WAVE_SCRIPT := {
	1:  { "rate": 2.5, "max": 40, "types": ["basic"], "boss": false },
	2:  { "rate": 2.7, "max": 45, "types": ["basic", "tank"], "boss": false },
	3:  { "rate": 2.9, "max": 50, "types": ["basic", "tank", "exploder"], "boss": false },
	4:  { "rate": 3.1, "max": 55, "types": ["basic", "tank", "exploder", "shielder"], "boss": false },
	5:  { "rate": 3.5, "max": 55, "types": ["basic", "tank", "exploder", "shielder"], "boss": true, "boss_count": 1 },
	6:  { "rate": 3.0, "max": 50, "types": ["basic", "tank", "exploder", "shielder"], "boss": false },
	7:  { "rate": 3.8, "max": 65, "types": ["basic", "tank", "exploder", "shielder", "elite"], "boss": true, "boss_count": 2 },
	8:  { "rate": 3.7, "max": 65, "types": ["basic", "tank", "exploder", "shielder", "elite"], "boss": false },
	9:  { "rate": 4.0, "max": 70, "types": ["basic", "tank", "exploder", "shielder", "elite"], "boss": true, "boss_count": 1 },
	10: { "rate": 4.5, "max": 75, "types": ["basic", "tank", "exploder", "shielder", "elite"], "boss": true, "boss_count": 1, "super_boss": true },
	11: { "rate": 5.0, "max": 80, "types": ["basic", "tank", "exploder", "shielder", "elite"], "boss": true, "boss_count": 3, "super_boss": true },
}

# Spawn weights
var SPAWN_WEIGHTS := {
	"basic": 30,
	"tank": 10,
	"exploder": 3,
	"shielder": 2,
	"elite": 1
}

# State
var _current_wave: int = 0
var _wave_timer: float = 0.0
var _spawn_timer: float = 0.0
var _active: bool = false
var _enemies_spawned_this_wave: int = 0
var _wave_config: Dictionary = {}

# References
var _player: Node2D = null
var _enemy_spawner: Node2D = null
var _base: Node2D = null
var _defense_ui: Node = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func start() -> void:
	_active = true
	_current_wave = 0
	_wave_timer = 3.0
	_spawn_timer = 0.0
	
	# Find references
	_player = get_tree().get_first_node_in_group("player")
	_enemy_spawner = get_tree().get_first_node_in_group("enemy_spawners")
	
	# Set player spawn position (below ARK)
	if _player:
		_player.global_position = Vector2(0, PLAYER_SPAWN_Y)
	
	# Create ARK
	_spawn_ark()
	
	# Setup defense UI
	_setup_defense_ui()
	
	# Pre-spawn enemies at edges
	_pre_spawn_edge_enemies()
	
	print("[DefenseDirector] Defense mode started! Protect your ARK!")

func stop() -> void:
	_active = false

func _process(delta: float) -> void:
	if not _active:
		return
	
	# Wave timing
	_wave_timer -= delta
	if _wave_timer <= 0:
		_start_next_wave()
		_wave_timer = WAVE_DURATION
	
	# Spawn timing
	if not _wave_config.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0:
			_spawn_wave_enemy()
			_spawn_timer = SPAWN_INTERVAL

func _spawn_ark() -> void:
	var BaseScript = load("res://scripts/world/DefenseBase.gd")
	if BaseScript:
		_base = Node2D.new()
		_base.set_script(BaseScript)
		_base.name = "DefenseArk"
		_base.global_position = Vector2(0, ARK_Y)
		_base.add_to_group("defense_base")
		
		if _base.has_method("initialize"):
			_base.initialize(ARK_WIDTH, ARK_DEPTH)
		
		_base.damaged.connect(_on_base_damaged)
		_base.destroyed.connect(_on_base_destroyed)
		
		get_parent().add_child(_base)
		print("[DefenseDirector] ARK spawned at top center")

func _setup_defense_ui() -> void:
	_defense_ui = CanvasLayer.new()
	_defense_ui.layer = 10
	_defense_ui.name = "DefenseUI"
	get_parent().add_child(_defense_ui)
	
	# Wave counter panel (top-left)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 20
	panel.offset_top = 50
	panel.offset_right = 200
	panel.offset_bottom = 130
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.9)
	style.border_color = Color(0.9, 0.4, 0.2, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", style)
	_defense_ui.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 8
	vbox.offset_right = -12
	vbox.offset_bottom = -8
	panel.add_child(vbox)
	
	var title := Label.new()
	title.text = "WAVE"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.4, 0.2, 1.0))
	vbox.add_child(title)
	
	var wave_label := Label.new()
	wave_label.name = "WaveLabel"
	wave_label.text = "0"
	wave_label.add_theme_font_size_override("font_size", 36)
	wave_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(wave_label)
	
	# === ARK HP BAR (top-center) ===
	var ark_hp_container := Control.new()
	ark_hp_container.name = "ArkHPContainer"
	ark_hp_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ark_hp_container.offset_left = -200
	ark_hp_container.offset_top = 20
	ark_hp_container.offset_right = 200
	ark_hp_container.offset_bottom = 70
	_defense_ui.add_child(ark_hp_container)
	
	# Label "ARK HP"
	var hp_title := Label.new()
	hp_title.name = "ArkHPTitle"
	hp_title.text = "ARK HP"
	hp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hp_title.offset_bottom = 20
	hp_title.add_theme_font_size_override("font_size", 16)
	hp_title.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0, 1.0))
	ark_hp_container.add_child(hp_title)
	
	# HP Bar background
	var bar_bg := ColorRect.new()
	bar_bg.name = "ArkHPBarBG"
	bar_bg.color = Color(0.1, 0.1, 0.15, 0.9)
	bar_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar_bg.offset_top = 22
	bar_bg.offset_left = 10
	bar_bg.offset_right = -10
	bar_bg.offset_bottom = 48
	ark_hp_container.add_child(bar_bg)
	
	# HP Bar fill
	var bar_fill := ColorRect.new()
	bar_fill.name = "ArkHPBarFill"
	bar_fill.color = Color(0.2, 0.8, 0.3, 1.0)
	bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar_fill.offset_top = 2
	bar_fill.offset_left = 2
	bar_fill.offset_right = -2
	bar_fill.offset_bottom = -2
	bar_bg.add_child(bar_fill)
	
	# HP Text
	var hp_text := Label.new()
	hp_text.name = "ArkHPText"
	hp_text.text = "9999 / 9999"
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_text.add_theme_font_size_override("font_size", 14)
	hp_text.add_theme_color_override("font_color", Color.WHITE)
	bar_bg.add_child(hp_text)

func _update_wave_ui() -> void:
	if _defense_ui:
		var panel = _defense_ui.get_child(0) if _defense_ui.get_child_count() > 0 else null
		if panel:
			var wave_label = panel.get_node_or_null("VBoxContainer/WaveLabel")
			if wave_label:
				wave_label.text = str(_current_wave)

func _pre_spawn_edge_enemies() -> void:
	if not _enemy_spawner:
		return
	
	# Spawn enemies at various positions in lower portion of map
	for i in range(PRE_SPAWN_COUNT):
		var spawn_pos := _get_random_spawn_position()
		# Ensure spawn is in safe zone (never near ARK)
		spawn_pos.y = maxf(spawn_pos.y, MIN_SPAWN_Y)
		# Move slightly inward from edge for pre-spawn
		spawn_pos.x *= 0.8
		spawn_pos.y = lerpf(spawn_pos.y, 0, 0.3)  # Closer to center
		_spawn_enemy_at("basic", spawn_pos)
	
	print("[DefenseDirector] Pre-spawned %d enemies" % PRE_SPAWN_COUNT)

func _start_next_wave() -> void:
	_current_wave += 1
	_enemies_spawned_this_wave = 0
	
	# Get wave config (cycle through waves 1-11, then repeat 11 with scaling)
	var wave_index := _current_wave
	if wave_index > 11:
		wave_index = 11
	
	_wave_config = WAVE_SCRIPT.get(wave_index, WAVE_SCRIPT[11]).duplicate()
	
	# Scale difficulty for waves beyond 11
	if _current_wave > 11:
		var scale := 1.0 + (_current_wave - 11) * 0.15
		_wave_config["rate"] = _wave_config["rate"] * scale
		_wave_config["max"] = int(_wave_config["max"] * scale)
	
	emit_signal("wave_started", _current_wave)
	_update_wave_ui()
	
	# Spawn bosses at wave start
	_spawn_wave_bosses()
	
	# Check for N01 spawn
	if _current_wave >= N01_START_WAVE:
		if _current_wave == N01_START_WAVE or (_current_wave - N01_START_WAVE) % N01_REPEAT_WAVES == 0:
			_spawn_n01()
	
	print("[DefenseDirector] Wave %d started! Rate: %.1f, Max: %d" % [_current_wave, _wave_config["rate"], _wave_config["max"]])

func _spawn_wave_bosses() -> void:
	if not _enemy_spawner:
		return
	
	# Spawn regular bosses
	if _wave_config.get("boss", false):
		var boss_count: int = _wave_config.get("boss_count", 1)
		for i in range(boss_count):
			var spawn_pos := _get_random_spawn_position()
			_spawn_enemy_at("boss", spawn_pos)
	
	# Spawn super bosses
	if _wave_config.get("super_boss", false):
		var spawn_pos := _get_random_spawn_position()
		_spawn_enemy_at("super_boss", spawn_pos)

func _spawn_n01() -> void:
	if not _enemy_spawner or not _enemy_spawner.has_method("spawn_rapture_queen"):
		return
	
	var spawn_pos := Vector2(0, SPAWN_BOTTOM_Y)
	var queen = _enemy_spawner.spawn_rapture_queen()
	if queen:
		queen.global_position = spawn_pos
		print("[DefenseDirector] N01 spawned at wave %d!" % _current_wave)

func _spawn_wave_enemy() -> void:
	if not _enemy_spawner or _wave_config.is_empty():
		return
	
	var available_types: Array = _wave_config.get("types", ["basic"])
	if available_types.is_empty():
		return
	
	# Weighted random selection
	var enemy_type := _select_weighted_enemy(available_types)
	
	# Spawn from random edge (left, right, or bottom)
	var spawn_pos := _get_random_spawn_position()
	
	_spawn_enemy_at(enemy_type, spawn_pos)
	_enemies_spawned_this_wave += 1

func _get_random_spawn_position() -> Vector2:
	# Random edge: 0=left, 1=right, 2=bottom
	var edge := _rng.randi() % 3
	var spawn_pos := Vector2.ZERO
	
	match edge:
		0:  # Left edge
			spawn_pos.x = SPAWN_LEFT_X
			spawn_pos.y = _rng.randf_range(MIN_SPAWN_Y, MAP_SIZE / 2 - SPAWN_MARGIN)
		1:  # Right edge
			spawn_pos.x = SPAWN_RIGHT_X
			spawn_pos.y = _rng.randf_range(MIN_SPAWN_Y, MAP_SIZE / 2 - SPAWN_MARGIN)
		2:  # Bottom edge
			spawn_pos.x = _rng.randf_range(-MAP_SIZE / 2 + SPAWN_MARGIN, MAP_SIZE / 2 - SPAWN_MARGIN)
			spawn_pos.y = SPAWN_BOTTOM_Y
	
	return spawn_pos

func _select_weighted_enemy(available_types: Array) -> String:
	var total_weight := 0
	for type in available_types:
		total_weight += SPAWN_WEIGHTS.get(type, 1)
	
	var roll := _rng.randi() % total_weight
	var cumulative := 0
	
	for type in available_types:
		cumulative += SPAWN_WEIGHTS.get(type, 1)
		if roll < cumulative:
			return type
	
	return "basic"

func _spawn_enemy_at(enemy_type: String, pos: Vector2) -> void:
	if not _enemy_spawner:
		return
	
	var enemy: Node2D = null
	
	if _enemy_spawner.has_method("spawn_at_position"):
		enemy = _enemy_spawner.spawn_at_position(enemy_type, pos)
	elif _enemy_spawner.has_method("spawn_enemy"):
		enemy = _enemy_spawner.spawn_enemy(enemy_type, "center")
		if enemy:
			enemy.global_position = pos
	
	# Set enemy to target the ARK
	if enemy and _base:
		_set_enemy_ark_target(enemy)

func _set_enemy_ark_target(enemy: Node2D) -> void:
	enemy.add_to_group("defense_enemies")
	enemy.set_meta("defense_base_position", Vector2(0, ARK_Y + ARK_DEPTH / 2))
	enemy.set_meta("defense_mode", true)

func _on_base_damaged(new_health: int, max_health_val: int) -> void:
	emit_signal("base_damaged", new_health, max_health_val)
	_update_ark_hp_ui(new_health, max_health_val)

func _update_ark_hp_ui(current_hp: int, max_hp: int) -> void:
	if not _defense_ui:
		return
	
	var container = _defense_ui.get_node_or_null("ArkHPContainer")
	if not container:
		return
	
	var bar_bg = container.get_node_or_null("ArkHPBarBG")
	if not bar_bg:
		return
	
	var bar_fill = bar_bg.get_node_or_null("ArkHPBarFill")
	var hp_text = bar_bg.get_node_or_null("ArkHPText")
	
	var ratio := float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	
	if bar_fill:
		bar_fill.anchor_right = ratio
		bar_fill.offset_right = -2
		
		if ratio > 0.6:
			bar_fill.color = Color(0.2, 0.8, 0.3, 1.0)
		elif ratio > 0.3:
			bar_fill.color = Color(0.9, 0.8, 0.2, 1.0)
		else:
			bar_fill.color = Color(0.9, 0.2, 0.2, 1.0)
	
	if hp_text:
		hp_text.text = "%d / %d" % [current_hp, max_hp]

func _on_base_destroyed() -> void:
	_active = false
	emit_signal("base_destroyed")
	emit_signal("defense_complete", _current_wave)
	print("[DefenseDirector] ARK destroyed! Survived %d waves" % _current_wave)

# === PUBLIC API ===

func get_current_wave() -> int:
	return _current_wave

func get_base() -> Node2D:
	return _base

func get_ark_position() -> Vector2:
	return Vector2(0, ARK_Y)
