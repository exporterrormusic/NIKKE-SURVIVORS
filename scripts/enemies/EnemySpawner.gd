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

# Enemy Pooling
var _enemy_pool: Dictionary = {}

func return_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy): return
	
	enemy.visible = false
	enemy.set_process(false)
	enemy.set_physics_process(false)
	
	# Defer removal to avoid physics locks if called during physics frame
	var do_return = func():
		if is_instance_valid(enemy):
			if enemy.get_parent():
				enemy.get_parent().remove_child(enemy)
			
			if not _enemy_pool.has("modular"):
				_enemy_pool["modular"] = []
			_enemy_pool["modular"].append(enemy)

	do_return.call_deferred()

func _get_from_pool() -> Node2D:
	if _enemy_pool.has("modular") and not _enemy_pool["modular"].is_empty():
		var enemy = _enemy_pool["modular"].pop_back()
		if is_instance_valid(enemy):
			# Start hidden to prevent 1-frame flash at old position
			enemy.visible = false
			if enemy.has_method("reset"):
				enemy.reset()
			return enemy
	return null

# Effect scripts
const TankEffectsScript = preload("res://scripts/enemies/effects/TankEffects.gd")
const EliteEffectsScript = preload("res://scripts/enemies/effects/EliteEffects.gd")
const BossEffectsScript = preload("res://scripts/enemies/effects/BossEffects.gd")

# Spawn settings
@export var spawn_radius: float = 800.0 # Distance from player to spawn
@export var spawn_variance: float = 100.0 # Random offset

# Map bounds (will be set from Level)
var _map_bounds: Rect2 = Rect2(-2000, -2000, 4000, 4000)

var _player: Node2D = null
var _enemy_container: Node2D = null
var _rng := RandomNumberGenerator.new()
var _horde_angle: float = 0.0 # Direction for horde spawns
var _current_night_boost: float = 0.0
var _elite_only_mode: bool = false # Stage 2: All spawns upgraded (basic→elite, elite→boss)

# Screen effects (tank vignette, boss darken)
var _screen_effects: CanvasLayer = null
var _boss_health_bar: CanvasLayer = null

func set_elite_only_mode(enabled: bool) -> void:
	_elite_only_mode = enabled

func set_map_bounds(bounds: Rect2) -> void:
	_map_bounds = bounds

# Tier configuration (now centralized in EnemyTierConfig.gd)
const EnemyTierConfigClass = preload("res://scripts/enemies/EnemyTierConfig.gd")

# Health multiplier from wave system (doubles each wave)
var _health_multiplier: float = 1.0

# Cached autoload reference (avoid repeated get_node_or_null in hot paths)
var _game_manager: Node = null

func _ready() -> void:
	add_to_group("enemy_spawners")
	_rng.randomize()
	_game_manager = get_node_or_null("/root/GameManager")
	_setup_screen_effects()

## Calculate ATK multiplier based on difficulty
## At difficulty 1 = 1.0x, at difficulty 2 = 1.25x, at difficulty 3 = 1.5x, etc.
func _get_atk_multiplier() -> float:
	var diff_mult = _game_manager.difficulty_multiplier if _game_manager else 1.0
	return 1.0 + 0.25 * (diff_mult - 1)

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
		
		# Connect to global boss spawn events (e.g. Future Marian)
		if EventBus.has_signal("boss_spawned"):
			EventBus.boss_spawned.connect(_on_global_boss_spawned)

func _on_global_boss_spawned(boss: Node) -> void:
	if not _boss_health_bar or not is_instance_valid(boss):
		return
		
	var boss_name = "BOSS"
	if boss.has_meta("display_name"):
		boss_name = boss.get_meta("display_name")
	elif boss.has_method("get_boss_name"):
		boss_name = boss.get_boss_name()
		
	var is_super = false
	if boss.has_meta("is_super_boss"):
		is_super = boss.get_meta("is_super_boss")
		
	_boss_health_bar.show_boss(boss, boss_name, is_super)

func set_health_multiplier(mult: float) -> void:
	_health_multiplier = mult

func initialize(player: Node2D, enemy_container: Node2D) -> void:
	_player = player
	_enemy_container = enemy_container

func set_night_boost(boost: float) -> void:
	_current_night_boost = boost

func spawn_enemy(enemy_type: String, pattern: String) -> Node2D:
	if not _player or not _enemy_container:
		return null
	
	# print("[EnemySpawner] spawn_enemy called: type=", enemy_type, " pattern=", pattern)
	var enemy := _create_enemy(enemy_type, pattern == "elite")
	if not enemy:
		return null
	
	# print("[EnemySpawner] Enemy created successfully, is_elite=", pattern == "elite")
	
	# Position based on pattern
	var spawn_pos := _get_spawn_position(pattern)
	enemy.global_position = spawn_pos
	enemy.visible = true # Ensure pooled enemies are visible
	
	# Parenting Check (Pooling Safety)
	if enemy.get_parent() == _enemy_container:
		# Already in container, just ensure it's not queued for deletion?
		pass
	else:
		if enemy.get_parent():
			enemy.reparent(_enemy_container)
		else:
			_enemy_container.add_child(enemy)
	
	# Signal Check (Pooling Safety)
	if not enemy.tree_exiting.is_connected(_on_enemy_tree_exiting):
		enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
	
	emit_signal("enemy_spawned", enemy)
	
	return enemy

## Spawn an enemy at a specific world position (for HUNT mode)
func spawn_at_position(enemy_type: String, world_position: Vector2) -> Node2D:
	if not _enemy_container:
		return null
	
	var enemy := _create_enemy(enemy_type, false)
	if not enemy:
		return null
	
	enemy.global_position = world_position
	
	# Reveal enemy now that position is set (prevents flash)
	enemy.visible = true
	
	# Parenting
	if enemy.get_parent() == _enemy_container:
		pass
	else:
		if enemy.get_parent():
			enemy.reparent(_enemy_container)
		else:
			_enemy_container.add_child(enemy)
	
	# Signal Check
	if not enemy.tree_exiting.is_connected(_on_enemy_tree_exiting):
		enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
	
	emit_signal("enemy_spawned", enemy)
	return enemy

func _on_enemy_tree_exiting(enemy: Node2D) -> void:
	emit_signal("enemy_died", enemy)

func _create_enemy(enemy_type: String, is_elite: bool = false) -> Node2D:
	var enemy: Node2D
	
	# REPLACEMENT: All requests use the new Modular System
	if enemy_type in ["basic", "modular_rapture", "tank", "shielder", "exploder", "boss", "super_boss", "elite", "ranged"]:
		# Check pool first
		enemy = _get_from_pool()
		if not enemy:
			enemy = ModularEnemyScene.instantiate()
			
		# Normalize type to 'basic' so downstream configuration (stats/elite modifiers) applies correctly
		# WAIT: If type is 'tank', we want it to stay 'tank' so _apply_tank_stats runs!
		# If type is 'boss', stay 'boss'.
		# Only normalize 'modular_rapture' to 'basic'.
		if enemy_type == "modular_rapture":
			enemy_type = "basic"
	else:
		# Fallback to modular enemy for unknown types, treating as basic
		enemy = _get_from_pool()
		if not enemy:
			enemy = ModularEnemyScene.instantiate()
		enemy_type = "basic"

	if not enemy:
		return null
	
	# Elite-only mode (Stage 2): upgrade all enemy types
	# basic → tank, tank → elite, elite → boss, boss → super_boss
	var actual_type := enemy_type
	var force_elite := is_elite
	
	# Random tank variant selection (shielder or exploder instead of tank)
	# 70% tank, 15% shielder, 15% exploder
	if actual_type == "tank":
		var roll := randf()
		if roll < 0.15:
			actual_type = "shielder"
		elif roll < 0.30:
			actual_type = "exploder"
		# else stays as "tank"
		# else stays as "tank"
	
	if _elite_only_mode:
		match enemy_type:
			"basic", "ranged":
				# Basic becomes tank in Stage 2
				actual_type = "tank"
			"tank", "shielder", "exploder":
				# Tank variants become elite in Stage 2
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
		
		"shielder":
			_apply_shielder_stats(enemy)
		
		"exploder":
			_apply_exploder_stats(enemy)
		
		"boss":
			_apply_boss_stats(enemy)
			force_elite = false # Don't double-apply elite
		
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
	_apply_tier_stats(enemy, "basic")

func _apply_tank_stats(enemy: Node2D) -> void:
	_apply_tier_stats(enemy, "tank")

func _apply_shielder_stats(enemy: Node2D) -> void:
	_apply_tier_stats(enemy, "shielder")
	
	# Create and attach shield effect
	var shield = ShielderShield.new()
	shield.name = "ShielderShield"
	enemy.add_child(shield)
	shield.initialize(enemy, enemy.max_hp, 1.0)
	shield.draw_hp_bar = false # Use unified ModularEnemy UI

	
	# Apply blue HP bar color
	if enemy.has_node("ProgressBar"):
		var hp_bar = enemy.get_node("ProgressBar")
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.6, 1.0) # Blue
		hp_bar.add_theme_stylebox_override("fill", style)

func _apply_exploder_stats(enemy: Node2D) -> void:
	_apply_tier_stats(enemy, "exploder")
	
	# Create and attach exploder behavior
	var behavior = ExploderBehavior.new()
	behavior.name = "ExploderBehavior"
	enemy.add_child(behavior)
	behavior.initialize(enemy, int(enemy.max_hp * 2.0)) # Damage = 2x Max HP
	
	# Apply red HP bar color
	if enemy.has_node("ProgressBar"):
		var hp_bar = enemy.get_node("ProgressBar")
		var style = StyleBoxFlat.new()
		style.bg_color = Color(1.0, 0.2, 0.2) # Red
		hp_bar.add_theme_stylebox_override("fill", style)

func _apply_outline_glow(enemy: Node2D, glow_color: Color, enhance_core: bool = false, enable_outline: bool = false) -> void:
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
		var shader_mat := ShaderCache.create_enemy_glow_material(glow_color, enhance_core, scale_factor, enable_outline)
		sprite.material = shader_mat


## Unified tier stats application using EnemyTierConfig data
## Replaces duplicate code in _apply_basic_stats, _apply_tank_stats, etc.
func _apply_tier_stats(enemy: Node2D, tier_name: String) -> void:
	var tier: Dictionary = EnemyTierConfigClass.get_tier(tier_name)
	var difficulty_mult: float = _game_manager.difficulty_multiplier if _game_manager else 1.0
	var atk_mult: float = _get_atk_multiplier()
	
	# Apply scale
	if tier.scale > 1.0:
		enemy.scale = Vector2.ONE * tier.scale
	
	# Apply HP (base * tier_mult * wave_mult * difficulty_mult)
	# FIX: Always start from clean base (stats) to prevent compounding multipliers in pool
	var base_hp = 1
	if "stats" in enemy and enemy.stats and "max_hp" in enemy.stats:
		base_hp = enemy.stats.max_hp
	elif tier.get("base_hp", 0) > 0:
		base_hp = tier.base_hp
		
	var new_max = int(base_hp * tier.hp_mult * _health_multiplier * difficulty_mult)
	if new_max <= 0:
		push_warning("[EnemySpawner] Calc max_hp <= 0 for tier %s" % tier_name)
		new_max = 1
	enemy.max_hp = new_max
	enemy.hp = enemy.max_hp

	# FORCE HP OVERRIDE for N01 in Goddess Fall mode
	if tier_name == "super_boss" and _game_manager and _game_manager.goddess_fall_mode:
		enemy.max_hp = 9999
		enemy.hp = 9999
	
	# Apply speed
	var speed_mult: float = tier.speed_mult
	# Only apply Goddess Fall speed modifier in that mode
	if _game_manager and _game_manager.goddess_fall_mode:
		speed_mult *= EnemyTierConfigClass.GODDESS_FALL_SPEED_MULT
	enemy.speed = int(enemy.speed * speed_mult)
	
	# Apply damage
	if tier.damage_mult > 1.0:
		enemy.base_damage = int(tier.damage_mult * atk_mult)
	else:
		enemy.base_damage = int(enemy.base_damage * atk_mult)
	
	# Enable shooting if specified
	if tier.get("can_shoot", false) and enemy.has_method("set_can_shoot"):
		enemy.set_can_shoot(true)
	
	# Add to groups
	for group_name in tier.get("groups", []):
		enemy.add_to_group(group_name)
	
	# Set tier metadata
	enemy.set_meta("enemy_tier", tier_name)
	
	# Apply glow
	var enable_outline: bool = tier.get("enable_outline", true) # Default to true
	# Force disable outline for exploders (override)
	if tier_name == "exploder":
		enable_outline = false
		
	_apply_outline_glow(enemy, tier.glow_color, tier.glow_enhanced, enable_outline)
	
	# Handle core drops
	var core_chance: float = tier.get("core_drop_chance", 0.0)
	# Elite core drop chance (20%) is now baseline
	if tier_name == "elite":
		core_chance = EnemyTierConfigClass.GODDESS_FALL_ELITE_CORE_CHANCE
	
	# Cheat: Otter -> Always drop pristine core
	if CheatManager.is_cheat_active("pristine_drops"):
		core_chance = 1.0
		
	if core_chance > 0.0 and randf() < core_chance:
		enemy.set_meta("pristine_core_drop", difficulty_mult)
	
	# Add boss AI if needed
	var needs_boss_ai: bool = tier.get("has_boss_ai", false)
	# Tank Boss AI and Elite Enhanced AI are now baseline
	if tier_name == "tank":
		needs_boss_ai = EnemyTierConfigClass.GODDESS_FALL_TANK_BOSS_AI
	
	if needs_boss_ai:
		var boss_ai = load("res://scripts/enemies/BossAI.gd")
		if boss_ai:
			var ai_node := Node.new()
			ai_node.set_script(boss_ai)
			ai_node.name = "BossAI"
			# Set metadata based on tier
			if tier_name == "tank":
				ai_node.set_meta("tank_mode", true)
			elif tier_name == "elite":
				ai_node.set_meta("elite_enhanced", true)
			enemy.add_child(ai_node)
	
	# Add visual effects based on tier
	var effects_script_path: String = tier.get("effects_script", "")
	if effects_script_path != "":
		var effects_script = load(effects_script_path)
		if effects_script:
			var fx := Node2D.new()
			fx.set_script(effects_script)
			fx.name = "%sEffects" % tier_name.capitalize().replace("_", "")
			enemy.add_child(fx)
	
	# Special features (Aura / Enrage) are now baseline
	if tier.get("has_aura", false):
		_setup_super_boss_aura(enemy)
	if tier_name in ["boss", "super_boss"]:
		_setup_boss_enrage_timer(enemy)
	
	# Show boss health bar if applicable
	var health_bar_name: String = tier.get("health_bar_name", "")
	if health_bar_name != "" and _boss_health_bar and _boss_health_bar.has_method("show_boss"):
		var is_super: bool = tier_name == "super_boss"
		_boss_health_bar.show_boss(enemy, health_bar_name, is_super)


func _apply_boss_stats(enemy: Node2D) -> void:
	_apply_tier_stats(enemy, "boss")

func _apply_super_boss_stats(enemy: Node2D) -> void:
	_apply_tier_stats(enemy, "super_boss")
	# Setup shield AFTER groups are assigned (can't do this in _ready as groups aren't set yet)
	if enemy.has_method("setup_super_boss_shield"):
		enemy.setup_super_boss_shield()

func _apply_elite_modifier(enemy: Node2D) -> void:
	_apply_tier_stats(enemy, "elite")

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
	var min_offscreen_dist := half_screen.length() + 100.0 # 100px buffer
	
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
			var spread := _rng.randf_range(-0.4, 0.4) # ~45 degree spread
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
	# Check if boss already has an enrage timer (prevent duplicates)
	if boss.get_node_or_null("EnrageTimer"):
		print("[EnemySpawner] WARNING: Boss already has EnrageTimer, skipping duplicate")
		return
	
	var timer := Timer.new()
	timer.name = "EnrageTimer"
	timer.one_shot = true
	timer.wait_time = 60.0
	timer.autostart = true # Use autostart so timer starts when added to tree
	timer.timeout.connect(_on_boss_enrage_timeout.bind(boss))
	boss.add_child(timer)
	# Timer will auto-start when boss enters tree (no need to call start() here)
	
	print("[EnemySpawner] Boss enrage timer set: %.1f seconds" % timer.wait_time)
	
	# Add visual warning timer display
	boss.set_meta("enrage_timer", timer)
	boss.set_meta("enrage_start_time", Time.get_ticks_msec())

func _on_boss_enrage_timeout(boss: Node2D) -> void:
	if not is_instance_valid(boss):
		return
	
	var is_super_boss := boss.is_in_group("super_boss")
	
	# Mark that player is being killed by enrage (no core drop)
	if _game_manager:
		_game_manager.set_meta("killed_by_enrage", true)
	
	# Create screen-wide explosion effect
	_create_enrage_explosion(boss.global_position, is_super_boss)
	
	# Deal damage to player
	if _player:
		if is_super_boss:
			# Super boss: 100% max HP, ignores everything - guaranteed kill
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

func spawn_rapture_queen() -> Node2D:
	var scene = load("res://scenes/enemies/bosses/RaptureQueenN01.tscn")
	if not scene:
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
	
	# FORCE HP OVERRIDE for Goddess Fall (Critical Fix)
	if _game_manager and _game_manager.goddess_fall_mode:
		queen.max_hp = 999
		queen.hp = 999
	
	# Set boss-tier damage (super_boss = 8.0 multiplier)
	queen.base_damage = int(8 * _get_atk_multiplier())
	
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
		_boss_health_bar.show_boss(queen, "RAPTURE QUEEN N01", true) # Red bar for super boss
		
	# Emit signal so Level can trigger weather
	emit_signal("rapture_queen_spawned")
	
	return queen
