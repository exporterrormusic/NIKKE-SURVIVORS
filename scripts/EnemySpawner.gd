extends Node2D
class_name EnemySpawner

## Handles enemy spawning patterns and enemy type creation

signal enemy_spawned(enemy: Node2D)
signal enemy_died(enemy: Node2D)

# Enemy scenes
const BasicEnemyScene = preload("res://scenes/characters/Enemy.tscn")

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

func set_map_bounds(bounds: Rect2) -> void:
	_map_bounds = bounds

# Elite visual settings - 5x size, gold glow, has boss abilities
const ELITE_SCALE := 2.5
const ELITE_HP_MULT := 10.0
const ELITE_DAMAGE_MULT := 2.0
const ELITE_SPEED_MULT := 0.8
const ELITE_GLOW_COLOR := Color(1.0, 0.85, 0.2, 1.0)  # Gold glow

# Tank settings - 1.5x size, red glow
const TANK_SCALE := 1.5
const TANK_HP_MULT := 8.0
const TANK_SPEED_MULT := 0.5
const TANK_DAMAGE_MULT := 2.0
const TANK_GLOW_COLOR := Color(1.0, 0.2, 0.1, 1.0)  # Red glow

# Boss settings - 4.5x size, purple glow
const BOSS_SCALE := 4.5
const BOSS_HP_MULT := 60.0
const BOSS_SPEED_MULT := 1.5  # 1.5x normal speed
const BOSS_DAMAGE_MULT := 5.0
const BOSS_GLOW_COLOR := Color(0.7, 0.2, 1.0, 1.0)  # Purple glow

# Health multiplier from wave system (doubles each wave)
var _health_multiplier: float = 1.0

func _ready() -> void:
	_rng.randomize()

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
	
	var enemy := _create_enemy(enemy_type, pattern == "elite")
	if not enemy:
		return null
	
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
	var enemy: Node2D = BasicEnemyScene.instantiate()
	if not enemy:
		return null
	
	# Apply type modifications (each applies health multiplier internally)
	match enemy_type:
		"basic", "ranged":
			_apply_basic_stats(enemy)
		
		"tank":
			_apply_tank_stats(enemy)
		
		"boss":
			_apply_boss_stats(enemy)
			is_elite = false  # Don't double-apply elite
	
	# Apply elite modifier on top
	if is_elite:
		_apply_elite_modifier(enemy)
	
	# Apply night glow if needed
	if _current_night_boost > 0.0:
		call_deferred("_apply_night_boost", enemy, _current_night_boost)
	
	return enemy

func _apply_basic_stats(enemy: Node2D) -> void:
	# Apply wave health multiplier - basic enemies can shoot and melee
	enemy.max_hp = int(enemy.max_hp * _health_multiplier)
	enemy.hp = enemy.max_hp
	# Enable shooting
	if enemy.has_method("set_can_shoot"):
		enemy.set_can_shoot(true)

func _apply_tank_stats(enemy: Node2D) -> void:
	enemy.scale = Vector2.ONE * TANK_SCALE
	enemy.max_hp = int(enemy.max_hp * TANK_HP_MULT * _health_multiplier)
	enemy.hp = enemy.max_hp
	enemy.speed = int(enemy.speed * TANK_SPEED_MULT)
	# Tanks can shoot missiles AND melee
	if enemy.has_method("set_can_shoot"):
		enemy.set_can_shoot(true)
	enemy.add_to_group("tank")
	enemy.set_meta("enemy_tier", "tank")  # Track tier for frostburn reduction
	# Red outline glow (respects sprite alpha)
	_apply_outline_glow(enemy, TANK_GLOW_COLOR)

func _apply_outline_glow(enemy: Node2D, glow_color: Color) -> void:
	# Apply outline shader to sprite that respects alpha
	var sprite = enemy.get_node_or_null("AnimatedSprite2D")
	if not sprite:
		sprite = enemy.get_node_or_null("Sprite2D")
	if sprite:
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = _get_outline_shader()
		shader_mat.set_shader_parameter("outline_color", glow_color)
		shader_mat.set_shader_parameter("outline_width", 2.0)
		sprite.material = shader_mat

func _get_outline_shader() -> Shader:
	# Create outline shader that respects sprite alpha
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 2.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	
	if (col.a > 0.1) {
		COLOR = col;
	} else {
		// Check neighboring pixels for outline
		vec2 size = TEXTURE_PIXEL_SIZE * outline_width;
		float outline = 0.0;
		
		// Sample in 8 directions
		outline += texture(TEXTURE, UV + vec2(-size.x, 0)).a;
		outline += texture(TEXTURE, UV + vec2(size.x, 0)).a;
		outline += texture(TEXTURE, UV + vec2(0, -size.y)).a;
		outline += texture(TEXTURE, UV + vec2(0, size.y)).a;
		outline += texture(TEXTURE, UV + vec2(-size.x, -size.y)).a;
		outline += texture(TEXTURE, UV + vec2(size.x, -size.y)).a;
		outline += texture(TEXTURE, UV + vec2(-size.x, size.y)).a;
		outline += texture(TEXTURE, UV + vec2(size.x, size.y)).a;
		
		if (outline > 0.0) {
			COLOR = outline_color;
		} else {
			COLOR = col;
		}
	}
}
"""
	return shader

func _apply_boss_stats(enemy: Node2D) -> void:
	print("[EnemySpawner] Applying BOSS stats: scale=", BOSS_SCALE, " hp_mult=", BOSS_HP_MULT, " health_mult=", _health_multiplier)
	enemy.scale = Vector2.ONE * BOSS_SCALE
	enemy.max_hp = int(enemy.max_hp * BOSS_HP_MULT * _health_multiplier)
	enemy.hp = enemy.max_hp
	enemy.speed = int(enemy.speed * BOSS_SPEED_MULT)
	print("[EnemySpawner] Boss HP set to: ", enemy.max_hp, " speed=", enemy.speed, " scale=", enemy.scale)
	enemy.add_to_group("boss")
	enemy.set_meta("enemy_tier", "boss")  # Track tier for frostburn reduction
	# Purple outline glow (respects sprite alpha)
	_apply_outline_glow(enemy, BOSS_GLOW_COLOR)
	
	# Add boss attack controller
	var boss_ai = load("res://scripts/BossAI.gd")
	if boss_ai:
		var ai_node := Node.new()
		ai_node.set_script(boss_ai)
		ai_node.name = "BossAI"
		enemy.add_child(ai_node)

func _apply_elite_modifier(enemy: Node2D) -> void:
	print("[EnemySpawner] Applying ELITE modifier on top of existing HP: ", enemy.max_hp)
	enemy.scale = Vector2.ONE * ELITE_SCALE  # Fixed 5x scale, not multiplicative
	enemy.max_hp = int(enemy.max_hp * ELITE_HP_MULT * _health_multiplier)
	enemy.hp = enemy.max_hp
	enemy.speed = int(enemy.speed * ELITE_SPEED_MULT)
	print("[EnemySpawner] Elite HP now: ", enemy.max_hp)
	enemy.add_to_group("elite")
	enemy.set_meta("enemy_tier", "elite")  # Track tier for frostburn reduction
	# Gold outline glow (respects sprite alpha)
	_apply_outline_glow(enemy, ELITE_GLOW_COLOR)
	
	# Add boss attack controller (missiles + beam) to elites
	var boss_ai = load("res://scripts/BossAI.gd")
	if boss_ai:
		var ai_node := Node.new()
		ai_node.set_script(boss_ai)
		ai_node.name = "BossAI"
		enemy.add_child(ai_node)

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
