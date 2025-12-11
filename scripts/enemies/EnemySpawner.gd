extends Node2D
class_name EnemySpawner

## Handles enemy spawning patterns and enemy type creation

signal enemy_spawned(enemy: Node2D)
signal enemy_died(enemy: Node2D)
signal rapture_queen_spawned()

# Enemy scenes
# Enemy scenes
# const BasicEnemyScene = preload("res://scenes/characters/Enemy.tscn") # REMOVED: Legacy
const ModularEnemyScene = preload("res://scenes/enemies/ModularRapture.tscn")

# Effect scripts
const TankEffectsScript = preload("res://scripts/enemies/effects/TankEffects.gd")
const EliteEffectsScript = preload("res://scripts/enemies/effects/EliteEffects.gd")
const BossEffectsScript = preload("res://scripts/enemies/effects/BossEffects.gd")

# Spawn settings
@export var spawn_radius: float = 800.0  # Distance from player to spawn
@export var spawn_variance: float = 100.0  # Random offset

# Map bounds (will be set from Level)
var _map_bounds: Rect2 = Rect2(-2000, -2000, 4000, 4000)

var _player: Node2D = null
var _enemy_container: Node2D = null
var _rng := RandomNumberGenerator.new()
var _horde_angle: float = 0.0  # Direction for horde spawns
var _current_night_boost: float = 0.0
var _elite_only_mode: bool = false  # Stage 2: All spawns upgraded (basic→elite, elite→boss)

# Screen effects (tank vignette, boss darken)
var _screen_effects: CanvasLayer = null
var _boss_health_bar: CanvasLayer = null

func set_elite_only_mode(enabled: bool) -> void:
	_elite_only_mode = enabled
	print("[EnemySpawner] Elite-only mode: ", enabled)

func set_map_bounds(bounds: Rect2) -> void:
	_map_bounds = bounds

# Elite visual settings - 5x size, gold glow, has boss abilities
# Elite visual settings - 5x size, gold glow, has boss abilities
const ELITE_SCALE := 3.25
const ELITE_HP_MULT := 10.0
const ELITE_DAMAGE_MULT := 3.0
const ELITE_SPEED_MULT := 0.8
const ELITE_GLOW_COLOR := Color(0.8, 0.1, 0.1, 1.0)  # Red glow (Swapped from Tank)

# Tank settings - 2x size, red glow
const TANK_SCALE := 2.0
const TANK_HP_MULT := 5.0
const TANK_SPEED_MULT := 1.0
const TANK_DAMAGE_MULT := 2.0
const TANK_GLOW_COLOR := Color(1.0, 0.85, 0.2, 1.0)  # Yellow glow (Swapped from Elite)

# Boss settings - 4.5x size, purple glow
const BOSS_SCALE := 4.5
const BOSS_HP_MULT := 50.0
const BOSS_SPEED_MULT := 0.5  # 0.5x normal speed
const BOSS_DAMAGE_MULT := 5.0
const BOSS_GLOW_COLOR := Color(0.7, 0.2, 1.0, 1.0)  # Purple glow

# Super Boss settings (Stage 2) - 5.5x size, red-purple glow
const SUPER_BOSS_SCALE := 5.5
const SUPER_BOSS_HP_MULT := 100.0
const SUPER_BOSS_SPEED_MULT := 0.4
const SUPER_BOSS_DAMAGE_MULT := 8.0
const SUPER_BOSS_GLOW_COLOR := Color(1.0, 0.2, 0.5, 1.0)  # Red-purple glow

# Health multiplier from wave system (doubles each wave)
var _health_multiplier: float = 1.0

func _ready() -> void:
	_rng.randomize()
	_setup_screen_effects()

## Calculate ATK multiplier based on difficulty
## At difficulty 1 = 1.0x, at difficulty 2 = 1.25x, at difficulty 3 = 1.5x, etc.
func _get_atk_multiplier() -> float:
	return 1.0 + 0.25 * (GameState.difficulty_multiplier - 1)

func _setup_screen_effects() -> void:
	# Create screen effects overlay for tank vignette and boss darken
	var ScreenEffectsScript = load("res://scripts/enemies/effects/EnemyScreenEffects.gd")
	if ScreenEffectsScript:
		_screen_effects = ScreenEffectsScript.new()
		_screen_effects.name = "EnemyScreenEffects"
		add_child(_screen_effects)
	
	# Create boss health bar
	var BossHPScript = load("res://scripts/enemies/effects/BossHealthBar.gd")
	if BossHPScript:
		_boss_health_bar = BossHPScript.new()
		_boss_health_bar.name = "BossHealthBar"
		add_child(_boss_health_bar)

func set_health_multiplier(mult: float) -> void:
	_health_multiplier = mult

func initialize(player: Node2D, enemy_container: Node2D) -> void:
	_player = player
	_enemy_container = enemy_container

func set_night_boost(boost: float) -> void:
	_current_night_boost = boost

func spawn_enemy(enemy_type: String, pattern: String) -> Node2D:
	if not _player or not _enemy_container:
		print("[EnemySpawner] FAILED: No player or enemy_container!")
		return null
	
	# print("[EnemySpawner] spawn_enemy called: type=", enemy_type, " pattern=", pattern)
	var enemy := _create_enemy(enemy_type, pattern == "elite")
	if not enemy:
		print("[EnemySpawner] FAILED: _create_enemy returned null!")
		return null
	
	# print("[EnemySpawner] Enemy created successfully, is_elite=", pattern == "elite")
	
	# Position based on pattern
	var spawn_pos := _get_spawn_position(pattern)
	enemy.global_position = spawn_pos
	
	_enemy_container.add_child(enemy)
	
	# Connect to enemy's tree_exiting to emit enemy_died signal
	enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
	
	emit_signal("enemy_spawned", enemy)
	
	return enemy

func _on_enemy_tree_exiting(enemy: Node2D) -> void:
	emit_signal("enemy_died", enemy)

func _create_enemy(enemy_type: String, is_elite: bool = false) -> Node2D:
	var enemy: Node2D
	
	# REPLACEMENT: All requests use the new Modular System
	if enemy_type in ["basic", "modular_rapture", "tank", "boss", "super_boss", "elite", "ranged"]:
		enemy = ModularEnemyScene.instantiate()
		# Normalize type to 'basic' so downstream configuration (stats/elite modifiers) applies correctly
		# WAIT: If type is 'tank', we want it to stay 'tank' so _apply_tank_stats runs!
		# If type is 'boss', stay 'boss'.
		# Only normalize 'modular_rapture' to 'basic'.
		if enemy_type == "modular_rapture":
			enemy_type = "basic"
	else:
		# Fallback to modular enemy for unknown types, treating as basic
		print("[EnemySpawner] Warning: Unknown enemy type '%s', defaulting to Modular Basic" % enemy_type)
		enemy = ModularEnemyScene.instantiate()
		enemy_type = "basic"

	if not enemy:
		return null
	
	# Elite-only mode (Stage 2): upgrade all enemy types
	# basic → tank, tank → elite, elite → boss, boss → super_boss
	var actual_type := enemy_type
	var force_elite := is_elite
	
	if _elite_only_mode:
		match enemy_type:
			"basic", "ranged":
				# Basic becomes tank in Stage 2
				actual_type = "tank"
			"tank":
				# Tank becomes elite in Stage 2
				force_elite = true
			"elite":
				# Elite becomes boss in Stage 2
				actual_type = "boss"
				force_elite = false
			"boss":
				# Boss becomes super boss in Stage 2
				actual_type = "super_boss"
		
		# If it was already elite (from pattern), upgrade to boss
		if is_elite and enemy_type not in ["elite", "boss", "super_boss"]:
			actual_type = "boss"
			force_elite = false
	
	# Apply type modifications (each applies health multiplier internally)
	match actual_type:
		"basic", "ranged":
			_apply_basic_stats(enemy)
		
		"tank":
			_apply_tank_stats(enemy)
		
		"boss":
			_apply_boss_stats(enemy)
			force_elite = false  # Don't double-apply elite
		
		"super_boss":
			_apply_super_boss_stats(enemy)
			force_elite = false
	
	# Apply elite modifier on top
	if force_elite:
		_apply_elite_modifier(enemy)
	
	# Apply night glow if needed
	if _current_night_boost > 0.0:
		call_deferred("_apply_night_boost", enemy, _current_night_boost)
	
	return enemy

func _apply_basic_stats(enemy: Node2D) -> void:
	# Apply wave health multiplier and difficulty multiplier
	var difficulty_mult: int = GameState.difficulty_multiplier
	var new_max = int(enemy.max_hp * _health_multiplier * difficulty_mult)
	if new_max <= 0:
		print("[EnemySpawner] CRITICAL: Calc max_hp <= 0! base=", enemy.max_hp, " mult=", _health_multiplier, " diff=", difficulty_mult)
	enemy.max_hp = new_max
	enemy.hp = enemy.max_hp
	# Apply Goddess Fall ATK multiplier
	enemy.base_damage = int(enemy.base_damage * _get_atk_multiplier())
	# Goddess Fall: 30% speed boost
	if GameState.goddess_fall_mode:
		enemy.speed = int(enemy.speed * 1.3)
	# Enable shooting
	if enemy.has_method("set_can_shoot"):
		enemy.set_can_shoot(true)
	
	# Ensure basic enemies get the universal shader (for night glow support)
	_apply_outline_glow(enemy, Color.TRANSPARENT, false)

func _apply_tank_stats(enemy: Node2D) -> void:
	var difficulty_mult: int = GameState.difficulty_multiplier
	var atk_mult: float = _get_atk_multiplier()
	enemy.scale = Vector2.ONE * TANK_SCALE
	enemy.max_hp = int(enemy.max_hp * TANK_HP_MULT * _health_multiplier * difficulty_mult)
	enemy.hp = enemy.max_hp
	# Goddess Fall: 30% speed boost on top of tank speed
	var speed_mult := TANK_SPEED_MULT
	if GameState.goddess_fall_mode:
		speed_mult *= 1.3
	enemy.speed = int(enemy.speed * speed_mult)
	enemy.base_damage = int(TANK_DAMAGE_MULT * atk_mult)
	# Tanks can shoot missiles AND melee
	if enemy.has_method("set_can_shoot"):
		enemy.set_can_shoot(true)
	enemy.add_to_group("tank")
	enemy.set_meta("enemy_tier", "tank")  # Track tier for frostburn reduction
	# Red outline glow (respects sprite alpha) with enhanced core
	_apply_outline_glow(enemy, TANK_GLOW_COLOR, true)
	
	# Goddess Fall mode: Tanks get missile ability like elites/bosses
	if GameState.goddess_fall_mode:
		var boss_ai = load("res://scripts/enemies/BossAI.gd")
		if boss_ai:
			var ai_node := Node.new()
			ai_node.set_script(boss_ai)
			ai_node.name = "BossAI"
			ai_node.set_meta("tank_mode", true)  # Limited abilities for tanks
			enemy.add_child(ai_node)
	
	# Add tank visual effects (ground cracks, stomp particles, proximity vignette)
	var tank_fx := Node2D.new()
	tank_fx.set_script(TankEffectsScript)
	tank_fx.name = "TankEffects"
	enemy.add_child(tank_fx)

func _apply_outline_glow(enemy: Node2D, glow_color: Color, enhance_core: bool = false) -> void:
	# Apply universal shader to sprite
	var sprite = null
	
	# 1. Try common properties
	if "visuals" in enemy and enemy.visuals is CanvasItem:
		sprite = enemy.visuals
	
	# 2. Try root nodes
	if not sprite:
		sprite = enemy.get_node_or_null("AnimatedSprite2D")
	if not sprite:
		sprite = enemy.get_node_or_null("Sprite2D")
		
	# 3. Try "Visuals" container (common in bosses)
	if not sprite:
		var visual_container = enemy.get_node_or_null("Visuals")
		if visual_container:
			# Look for sprite inside
			sprite = visual_container.get_node_or_null("AnimatedSprite2D")
			if not sprite:
				sprite = visual_container.get_node_or_null("Sprite2D")
				
	if sprite:
		# Use ShaderCache for optimized material creation (avoids load() per enemy)
		var scale_factor: float = max(enemy.scale.x, enemy.scale.y)
		var shader_mat := ShaderCache.create_enemy_glow_material(glow_color, enhance_core, scale_factor)
		sprite.material = shader_mat

# Deprecated: _get_outline_shader() replaced by universal resource load

	# Create outline shader that respects sprite alpha and can enhance red core


func _apply_boss_stats(enemy: Node2D) -> void:
	var difficulty_mult: int = GameState.difficulty_multiplier
	var atk_mult: float = _get_atk_multiplier()
	# print("[EnemySpawner] Applying BOSS stats: scale=", BOSS_SCALE, " hp_mult=", BOSS_HP_MULT, " health_mult=", _health_multiplier, " difficulty=", difficulty_mult)
	enemy.scale = Vector2.ONE * BOSS_SCALE
	enemy.max_hp = int(enemy.max_hp * BOSS_HP_MULT * _health_multiplier * difficulty_mult)
	enemy.hp = enemy.max_hp
	enemy.speed = int(enemy.speed * BOSS_SPEED_MULT)
	# Goddess Fall: 30% speed boost on top of boss speed
	if GameState.goddess_fall_mode:
		enemy.speed = int(enemy.speed * 1.3)
	enemy.base_damage = int(BOSS_DAMAGE_MULT * atk_mult)
	# print("[EnemySpawner] Boss HP set to: ", enemy.max_hp, " speed=", enemy.speed, " scale=", enemy.scale)
	enemy.add_to_group("boss")
	enemy.set_meta("enemy_tier", "boss")
	# Bosses have 1/3 chance of dropping pristine cores, multiplied by difficulty
	if randf() < 0.333:
		enemy.set_meta("pristine_core_drop", difficulty_mult)
	# Purple outline glow (respects sprite alpha) with enhanced core
	_apply_outline_glow(enemy, BOSS_GLOW_COLOR, true)
	
	# Add boss attack controller
	var boss_ai = load("res://scripts/enemies/BossAI.gd")
	if boss_ai:
		var ai_node := Node.new()
		ai_node.set_script(boss_ai)
		ai_node.name = "BossAI"
		enemy.add_child(ai_node)
	
	# Add boss visual effects (dark aura, particle vortex, glowing core, screen darken)
	var boss_fx := Node2D.new()
	boss_fx.set_script(BossEffectsScript)
	boss_fx.name = "BossEffects"
	enemy.add_child(boss_fx)
	
	# Goddess Fall mode: Boss enrage timer (60 seconds to kill or player dies)
	if GameState.goddess_fall_mode:
		_setup_boss_enrage_timer(enemy)
	
	# Show boss health bar
	if _boss_health_bar and _boss_health_bar.has_method("show_boss"):
		_boss_health_bar.show_boss(enemy, "RAPTURE TITAN")

func _apply_super_boss_stats(enemy: Node2D) -> void:
	var difficulty_mult: int = GameState.difficulty_multiplier
	var atk_mult: float = _get_atk_multiplier()
	# print("[EnemySpawner] Applying SUPER BOSS stats: scale=", SUPER_BOSS_SCALE, " hp_mult=", SUPER_BOSS_HP_MULT, " difficulty=", difficulty_mult)
	enemy.scale = Vector2.ONE * SUPER_BOSS_SCALE
	enemy.max_hp = int(enemy.max_hp * SUPER_BOSS_HP_MULT * _health_multiplier * difficulty_mult)
	enemy.hp = enemy.max_hp
	enemy.speed = int(enemy.speed * SUPER_BOSS_SPEED_MULT)
	# Goddess Fall: 30% speed boost on top of super boss speed
	if GameState.goddess_fall_mode:
		enemy.speed = int(enemy.speed * 1.3)
	enemy.base_damage = int(SUPER_BOSS_DAMAGE_MULT * atk_mult)
	# print("[EnemySpawner] Super Boss HP set to: ", enemy.max_hp, " speed=", enemy.speed, " scale=", enemy.scale)
	enemy.add_to_group("boss")
	enemy.add_to_group("super_boss")
	enemy.set_meta("enemy_tier", "super_boss")
	enemy.set_meta("pristine_core_drop", difficulty_mult)  # Super bosses guaranteed cores * difficulty
	# Red-purple outline glow
	_apply_outline_glow(enemy, SUPER_BOSS_GLOW_COLOR, true)
	
	# Add boss attack controller
	var boss_ai = load("res://scripts/enemies/BossAI.gd")
	if boss_ai:
		var ai_node := Node.new()
		ai_node.set_script(boss_ai)
		ai_node.name = "BossAI"
		enemy.add_child(ai_node)
	
	# Add boss visual effects
	var boss_fx := Node2D.new()
	boss_fx.set_script(BossEffectsScript)
	boss_fx.name = "BossEffects"
	enemy.add_child(boss_fx)
	
	# Goddess Fall mode: Super boss gets empowerment aura
	if GameState.goddess_fall_mode:
		_setup_super_boss_aura(enemy)
		_setup_boss_enrage_timer(enemy)
	
	# Show boss health bar
	if _boss_health_bar and _boss_health_bar.has_method("show_boss"):
		_boss_health_bar.show_boss(enemy, "RAPTURE OVERLORD")

func _apply_elite_modifier(enemy: Node2D) -> void:
	var difficulty_mult: int = GameState.difficulty_multiplier
	var atk_mult: float = _get_atk_multiplier()
	# print("[EnemySpawner] Applying ELITE modifier on top of existing HP: ", enemy.max_hp, " difficulty=", difficulty_mult)
	enemy.scale = Vector2.ONE * ELITE_SCALE  # Fixed 5x scale, not multiplicative
	enemy.max_hp = int(enemy.max_hp * ELITE_HP_MULT * _health_multiplier * difficulty_mult)
	enemy.hp = enemy.max_hp
	enemy.speed = int(enemy.speed * ELITE_SPEED_MULT)
	enemy.base_damage = int(ELITE_DAMAGE_MULT * atk_mult)
	# print("[EnemySpawner] Elite HP now: ", enemy.max_hp)
	enemy.add_to_group("elite")
	enemy.set_meta("enemy_tier", "elite")  # Track tier for frostburn reduction
	# In Goddess Fall mode, elites have 1/5 chance to drop cores
	if GameState.goddess_fall_mode and randf() < 0.2:
		enemy.set_meta("pristine_core_drop", difficulty_mult)
	# Goddess Fall: 30% speed boost on top of elite speed
	if GameState.goddess_fall_mode:
		enemy.speed = int(enemy.speed * 1.3)
	# Gold outline glow (respects sprite alpha) with enhanced core
	_apply_outline_glow(enemy, ELITE_GLOW_COLOR, true)
	
	# Add boss attack controller (missiles + beam) to elites
	# In Goddess Fall mode, elites also get laser and rocket abilities
	var boss_ai = load("res://scripts/enemies/BossAI.gd")
	if boss_ai:
		var ai_node := Node.new()
		ai_node.set_script(boss_ai)
		ai_node.name = "BossAI"
		if GameState.goddess_fall_mode:
			ai_node.set_meta("elite_enhanced", true)  # Full abilities in Goddess Fall
		enemy.add_child(ai_node)
	
	# Add elite visual effects (golden aura, spark trail, glowing core)
	var elite_fx := Node2D.new()
	elite_fx.set_script(EliteEffectsScript)
	elite_fx.name = "EliteEffects"
	enemy.add_child(elite_fx)

func _apply_tint(enemy: Node2D, tint: Color) -> void:
	var sprite = enemy.get_node_or_null("AnimatedSprite2D")
	if not sprite:
		sprite = enemy.get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = tint

func _apply_glow(enemy: Node2D, glow_color: Color, intensity: float) -> void:
	# Add a PointLight2D for glow effect
	var light := PointLight2D.new()
	light.name = "EliteGlow"
	light.color = glow_color
	light.energy = intensity
	light.texture_scale = 0.5 * enemy.scale.x
	# Create a simple gradient texture
	var gradient := GradientTexture2D.new()
	gradient.width = 128
	gradient.height = 128
	gradient.fill = GradientTexture2D.FILL_RADIAL
	gradient.fill_from = Vector2(0.5, 0.5)
	gradient.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color.WHITE)
	grad.set_color(1, Color.TRANSPARENT)
	gradient.gradient = grad
	light.texture = gradient
	enemy.add_child(light)

func _apply_night_boost(enemy: Node2D, boost: float) -> void:
	var sprite = enemy.get_node_or_null("AnimatedSprite2D")
	if not sprite:
		sprite = enemy.get_node_or_null("Sprite2D")
	if sprite and sprite.material is ShaderMaterial:
		sprite.material.set_shader_parameter("night_boost", boost)

func _get_spawn_position(pattern: String) -> Vector2:
	var player_pos := _player.global_position
	
	# Get viewport size to ensure we spawn off-screen
	var viewport := get_viewport()
	var viewport_size := viewport.get_visible_rect().size if viewport else Vector2(1920, 1080)
	var camera := viewport.get_camera_2d() if viewport else null
	var zoom := camera.zoom if camera else Vector2.ONE
	
	# Calculate minimum distance to be off-screen (half diagonal + buffer)
	var half_screen := viewport_size / (2.0 * zoom)
	var min_offscreen_dist := half_screen.length() + 100.0  # 100px buffer
	
	# Use the larger of spawn_radius or minimum off-screen distance
	var actual_radius := maxf(spawn_radius, min_offscreen_dist)
	
	var spawn_pos: Vector2
	
	match pattern:
		"ring":
			# Random position around player in a ring
			var angle := _rng.randf() * TAU
			var distance := actual_radius + _rng.randf_range(0, spawn_variance)
			spawn_pos = player_pos + Vector2.from_angle(angle) * distance
		
		"horde":
			# All from one direction (with slight spread)
			var spread := _rng.randf_range(-0.4, 0.4)  # ~45 degree spread
			var distance := actual_radius + _rng.randf_range(0, spawn_variance)
			spawn_pos = player_pos + Vector2.from_angle(_horde_angle + spread) * distance
		
		"elite", "center":
			# Spawn at edge of screen, facing player
			var angle := _rng.randf() * TAU
			spawn_pos = player_pos + Vector2.from_angle(angle) * actual_radius
		
		_:
			# Default ring pattern
			var angle := _rng.randf() * TAU
			spawn_pos = player_pos + Vector2.from_angle(angle) * actual_radius
	
	# Clamp to map bounds with padding
	var padding := 50.0
	spawn_pos.x = clampf(spawn_pos.x, _map_bounds.position.x + padding, _map_bounds.end.x - padding)
	spawn_pos.y = clampf(spawn_pos.y, _map_bounds.position.y + padding, _map_bounds.end.y - padding)
	
	# If clamping pushed us on-screen, try to find a valid off-screen position
	var to_player := player_pos - spawn_pos
	var dist_to_player := to_player.length()
	if dist_to_player < min_offscreen_dist:
		# We're too close (probably clamped at map edge near player)
		# Try spawning from the opposite direction
		for _attempt in range(8):
			var test_angle := _rng.randf() * TAU
			var test_pos := player_pos + Vector2.from_angle(test_angle) * actual_radius
			test_pos.x = clampf(test_pos.x, _map_bounds.position.x + padding, _map_bounds.end.x - padding)
			test_pos.y = clampf(test_pos.y, _map_bounds.position.y + padding, _map_bounds.end.y - padding)
			if test_pos.distance_to(player_pos) >= min_offscreen_dist * 0.8:
				spawn_pos = test_pos
				break
	
	# Check if spawn position overlaps a boulder - retry if so
	spawn_pos = _avoid_boulder_overlap(spawn_pos, player_pos, actual_radius, padding)
	
	return spawn_pos

func _avoid_boulder_overlap(spawn_pos: Vector2, player_pos: Vector2, spawn_radius_val: float, padding: float) -> Vector2:
	"""Ensure spawn position doesn't overlap any boulder. Retries up to 8 times."""
	var boulders := get_tree().get_nodes_in_group("boulders")
	if boulders.is_empty():
		return spawn_pos
	
	for _attempt in range(8):
		var overlaps_boulder := false
		for boulder in boulders:
			if not is_instance_valid(boulder):
				continue
			var boulder_pos: Vector2 = boulder.global_position
			var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
			# Add extra margin for enemy size
			if spawn_pos.distance_to(boulder_pos) < (boulder_radius + 50.0):
				overlaps_boulder = true
				break
		
		if not overlaps_boulder:
			return spawn_pos
		
		# Try a new random position
		var test_angle := _rng.randf() * TAU
		spawn_pos = player_pos + Vector2.from_angle(test_angle) * spawn_radius_val
		spawn_pos.x = clampf(spawn_pos.x, _map_bounds.position.x + padding, _map_bounds.end.x - padding)
		spawn_pos.y = clampf(spawn_pos.y, _map_bounds.position.y + padding, _map_bounds.end.y - padding)
	
	return spawn_pos


func start_horde_from_direction(direction: Vector2) -> void:
	"""Set the direction for horde spawns."""
	_horde_angle = direction.angle()

func start_random_horde_direction() -> void:
	"""Pick a random direction for the next horde."""
	_horde_angle = _rng.randf() * TAU

func get_enemy_count() -> int:
	if not _enemy_container:
		return 0
	return _enemy_container.get_child_count()


# === GODDESS FALL MODE FUNCTIONS ===

## Setup boss enrage timer - boss explodes after 60 seconds if not killed, killing the player
func _setup_boss_enrage_timer(boss: Node2D) -> void:
	var timer := Timer.new()
	timer.name = "EnrageTimer"
	timer.one_shot = true
	timer.wait_time = 60.0
	timer.autostart = true  # Use autostart so timer starts when added to tree
	timer.timeout.connect(_on_boss_enrage_timeout.bind(boss))
	boss.add_child(timer)
	# Timer will auto-start when boss enters tree (no need to call start() here)
	
	# Add visual warning timer display
	boss.set_meta("enrage_timer", timer)
	boss.set_meta("enrage_start_time", Time.get_ticks_msec())
	print("[EnemySpawner] Boss enrage timer started - 60 seconds to kill!")

func _on_boss_enrage_timeout(boss: Node2D) -> void:
	if not is_instance_valid(boss):
		return
	
	var is_super_boss := boss.is_in_group("super_boss")
	print("[EnemySpawner] BOSS ENRAGED! Creating massive explosion!")
	
	# Mark that player is being killed by enrage (no core drop)
	if GameState:
		GameState.set_meta("killed_by_enrage", true)
	
	# Create screen-wide explosion effect
	_create_enrage_explosion(boss.global_position, is_super_boss)
	
	# Deal damage to player
	if _player:
		if is_super_boss:
			# Super boss: 100% max HP, ignores everything - guaranteed kill
			print("[EnemySpawner] Super boss enrage - guaranteed kill!")
			if _player.has_method("die"):
				_player.die()
			elif _player.has_method("take_damage"):
				# Force death by setting HP to 0 directly
				if "current_hp" in _player:
					_player.current_hp = 0
				_player.take_damage(99999)
		else:
			# Regular boss: 90% of max HP
			var damage: int = int(_player.max_hp * 0.9)
			print("[EnemySpawner] Boss enrage - dealing %d damage (90%% of %d max HP)" % [damage, _player.max_hp])
			if _player.has_method("take_damage"):
				_player.take_damage(damage)
	
	# Kill the boss in the explosion
	if boss.has_method("take_damage"):
		boss.take_damage(boss.max_hp * 10)

func _create_enrage_explosion(center: Vector2, is_super_boss: bool) -> void:
	# Create a massive screen-wide explosion effect
	var explosion := Node2D.new()
	explosion.name = "EnrageExplosion"
	explosion.global_position = center
	explosion.z_index = 100
	
	# Add to level so it persists
	var level := get_tree().current_scene
	if level:
		level.add_child(explosion)
	else:
		add_child(explosion)
	
	# Create the visual effect
	var effect_script := GDScript.new()
	effect_script.source_code = _get_enrage_explosion_script(is_super_boss)
	effect_script.reload()
	explosion.set_script(effect_script)

func _get_enrage_explosion_script(is_super_boss: bool) -> String:
	var color_str := "Color(1.0, 0.1, 0.0)" if not is_super_boss else "Color(0.8, 0.0, 0.2)"
	var core_color := "Color(1.0, 0.5, 0.2)" if not is_super_boss else "Color(1.0, 0.2, 0.4)"
	return '''
extends Node2D

var _time := 0.0
var _max_radius := 2000.0
var _duration := 1.5
var _flash_alpha := 1.0

func _ready() -> void:
	# Screen flash
	var flash := ColorRect.new()
	flash.name = "Flash"
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = ''' + color_str + '''
	flash.color.a = 0.8
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	canvas.add_child(flash)
	
	# Camera shake
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(1.0)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	
	# Fade out flash
	var flash_node := get_node_or_null("CanvasLayer/Flash")
	if flash_node:
		var fade_t := clampf(_time / _duration, 0.0, 1.0)
		flash_node.color.a = 0.8 * (1.0 - fade_t)
	
	if _time >= _duration:
		queue_free()

func _draw() -> void:
	var t := clampf(_time / _duration, 0.0, 1.0)
	var radius := _max_radius * ease(t, 0.3)
	var alpha := 1.0 - t
	
	# Expanding ring
	var ring_color := ''' + color_str + '''
	ring_color.a = alpha * 0.8
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, ring_color, 30.0 * (1.0 - t) + 5.0)
	
	# Inner glow
	var core_color := ''' + core_color + '''
	core_color.a = alpha * 0.6
	for i in range(5):
		var r := radius * (0.2 + i * 0.15) * (1.0 - t * 0.5)
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, core_color, 20.0 * (1.0 - t))
'''

## Setup super boss empowerment aura - buffs nearby enemies
func _setup_super_boss_aura(boss: Node2D) -> void:
	var aura_node := Node2D.new()
	aura_node.name = "EmpowermentAura"
	aura_node.set_script(load("res://scripts/enemies/effects/SuperBossAura.gd"))
	boss.add_child(aura_node)
	print("[EnemySpawner] Super boss empowerment aura active!")

func spawn_rapture_queen() -> Node2D:
	var scene = load("res://scenes/enemies/bosses/RaptureQueenN01.tscn")
	if not scene:
		print("[EnemySpawner] FAILED: Could not load Rapture Queen scene!")
		return null
		
	var queen = scene.instantiate()
	if not queen: return null
	
	var spawn_pos := Vector2.ZERO
	if _player:
		# Spawn fixed distance above player (ensure visibility - was -900, now -400 to be on-screen)
		var offset = Vector2(0, -400)
		spawn_pos = _player.global_position + offset
		
		# Clamp to map bounds if available
		if _map_bounds != Rect2():
			spawn_pos.x = clamp(spawn_pos.x, _map_bounds.position.x + 300, _map_bounds.end.x - 300)
			spawn_pos.y = clamp(spawn_pos.y, _map_bounds.position.y + 300, _map_bounds.end.y - 300)
	
	queen.global_position = spawn_pos
	
	# Apply Boss Glow (Crucial for visibility in Night mode)
	# Using Purple/Pink glow for Rapture Queen
	var queen_glow = Color(1.0, 0.2, 0.6, 1.0)
	_apply_outline_glow(queen, queen_glow, true) # Enable core enhancement
	
	# Register with container
	# Register with container - safely using call_deferred
	if _enemy_container:
		_enemy_container.call_deferred("add_child", queen)
	else:
		_player.get_parent().call_deferred("add_child", queen) # Fallback to level
		
	# Setup Boss Bar
	if _boss_health_bar and _boss_health_bar.has_method("show_boss"):
		_boss_health_bar.show_boss(queen, "RAPTURE QUEEN N01")
		
	# Emit signal so Level can trigger weather
	emit_signal("rapture_queen_spawned")
	print("[EnemySpawner] Rapture Queen N01 Spawned at: ", queen.global_position)
	
	return queen
