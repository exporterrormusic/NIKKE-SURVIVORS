extends Area2D

## Enemy Laser Projectile
## DESIGN: Visual and hitbox are EXACTLY the same size - pixel perfect
## The beam visual IS the hitbox, no separate calculations

# Configuration
@export var speed := 500.0
@export var damage := 10
@export var max_range := 600.0
@export var lifetime := 1.5

# THE beam size - this single value defines BOTH visual and hitbox
# Everything scales from this (original was 110x48)
const BEAM_SIZE := Vector2(110.0, 48.0) # Width x Height of beam

# Visual colors
const BEAM_COLOR := Color(0.9, 0.1, 0.1, 1.0) # Red
const GLOW_COLOR := Color(1.0, 0.3, 0.1, 0.6) # Orange-red glow
const HITBOX_ACTIVATION_DELAY := 0.5 # Seconds before hitbox becomes active

# State
var _direction := Vector2.RIGHT
var _is_retired := false
var _age := 0.0
var _distance_travelled := 0.0
var _hit_targets := {}
var _collision_poly: CollisionPolygon2D = null
var _beam_visual: ColorRect = null
var _rng := RandomNumberGenerator.new()
var _hitbox_active := false # Delayed hitbox activation

# Owner info for damage log
var owner_name := "Enemy"

# Cached
static var _cached_gm: Node = null

func _ready() -> void:
	z_as_relative = false
	z_index = 900
	_rng.randomize()
	
	# Collision layers
	collision_layer = 4 # Enemy projectile
	collision_mask = 1 | 2 | 8 # Player, enemies (charmed), allies
	monitoring = true
	monitorable = true
	add_to_group("enemy_projectiles")
	
	# Start with collision DISABLED - will activate after delay
	monitoring = false
	monitorable = false
	
	# Create the beam - ONE size for everything
	_create_beam()
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Move to effects layer for night glow
	# Move to effects layer for night glow
	call_deferred("_move_to_effects_layer")

func _create_beam() -> void:
	# COLLISION SHAPE - Tapered Polygon to match shader visual
	# The shader creates a "needle" or "wedge" shape that is thin at the start (left)
	# and thick at the end (right). A rectangle hitbox hits players with empty corners.
	if _collision_poly: _collision_poly.queue_free()
	
	_collision_poly = CollisionPolygon2D.new()
	# Define trapezoid points (local space, starting from (0,0) going Right)
	# Tail (Left): Thin (20% height)
	# Head (Right): Girthy (85% height - leaving some glow margin)
	var half_h = BEAM_SIZE.y * 0.5
	var tail_h = half_h * 0.25
	var head_h = half_h * 0.85
	
	var points = PackedVector2Array([
		Vector2(0, -tail_h), # Top-Left
		Vector2(BEAM_SIZE.x, -head_h), # Top-Right
		Vector2(BEAM_SIZE.x, head_h), # Bottom-Right
		Vector2(0, tail_h) # Bottom-Left
	])
	_collision_poly.polygon = points
	add_child(_collision_poly)
	
	# VISUAL - exact same size container, but shader handles the internal shape
	_beam_visual = ColorRect.new()
	_beam_visual.size = BEAM_SIZE
	_beam_visual.position = Vector2(0, -BEAM_SIZE.y * 0.5) # Center vertically
	_beam_visual.z_index = 900
	
	# Apply shader for nice appearance
	var shader = load("res://resources/shaders/laser_bolt.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_beam_visual.material = mat
	else:
		_beam_visual.color = BEAM_COLOR
	
	add_child(_beam_visual)

func _move_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 900

func set_direction(dir: Vector2) -> void:
	_direction = dir.normalized() if dir.length() > 0 else Vector2.RIGHT
	rotation = _direction.angle()

func _physics_process(delta: float) -> void:
	if _is_retired:
		return
	
	# Time scale for bullet time
	if not _cached_gm:
		_cached_gm = get_node_or_null("/root/GameManager")
	var time_scale: float = _cached_gm.enemy_time_scale if _cached_gm else 1.0
	var dt := delta * time_scale
	
	# Move
	var displacement := _direction * speed * dt
	global_position += displacement
	_distance_travelled += displacement.length()
	_age += dt
	
	# Delayed hitbox activation - prevents instant kills when spawning near player
	if not _hitbox_active and _age >= HITBOX_ACTIVATION_DELAY:
		_hitbox_active = true
		monitoring = true
		monitorable = true
	
	# Animate shader
	if _beam_visual and _beam_visual.material is ShaderMaterial:
		var mat := _beam_visual.material as ShaderMaterial
		mat.set_shader_parameter("time", _age)
		mat.set_shader_parameter("flicker_seed", _rng.randf())
	
	# Boulder collision check
	if _check_boulder_collision():
		_retire()
		return
	
	# Lifetime/range check
	if _age >= lifetime or _distance_travelled >= max_range:
		_retire()

func _check_boulder_collision() -> bool:
	for boulder in get_tree().get_nodes_in_group("boulders"):
		if not is_instance_valid(boulder):
			continue
		var radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_squared_to(boulder.global_position) < radius * radius:
			return true
	return false

func _retire() -> void:
	if _is_retired:
		return
	_is_retired = true
	
	# Immediately disable collision
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if _collision_poly:
		_collision_poly.set_deferred("disabled", true)
	
	# Return to pool
	ProjectileCache.return_to_pool(self)

func reset() -> void:
	"""Reset for pooling."""
	_is_retired = false
	_age = 0.0
	_distance_travelled = 0.0
	_hit_targets.clear()
	owner_name = "Enemy"
	_hitbox_active = false
	
	# Reset transforms
	scale = Vector2.ONE
	modulate = Color.WHITE
	
	# Re-enable collision
	if _collision_poly:
		_collision_poly.disabled = false
		# Polygon points are static relative to BEAM_SIZE constants, no need to resize shape
	
	# Reset visual
	if _beam_visual:
		_beam_visual.size = BEAM_SIZE
		_beam_visual.position = Vector2(0, -BEAM_SIZE.y * 0.5)
	
	# Re-enable processing
	set_process(true)
	set_physics_process(true)
	monitoring = true
	monitorable = true
	
	call_deferred("_move_to_effects_layer")

# Signal handlers
func _on_body_entered(body: Node) -> void:
	_apply_damage(body)

func _on_area_entered(area: Area2D) -> void:
	_apply_damage(area)

func _apply_damage(target: Node) -> void:
	if _is_retired or not is_instance_valid(target):
		return
	
	var id := target.get_instance_id()
	if _hit_targets.has(id):
		return
	_hit_targets[id] = true
	
	# Charmed laser logic
	var from_charmed: bool = has_meta("from_charmed") and get_meta("from_charmed")
	
	if from_charmed:
		if target.is_in_group("charmed_allies") or target.is_in_group("player"):
			return
		if target.is_in_group("enemies") and target.has_method("take_damage"):
			target.take_damage(damage, false, Vector2.ZERO, false, "charmed_enemy")
			_retire()
			return
	else:
		# Normal enemy laser - only damages player/allies, NOT enemies (including charmed ones)
		# Skip ALL enemies (charmed allies are still enemies functionally)
		if target.is_in_group("enemies"):
			return
		# Also skip charmed_allies explicitly (in case they're not in enemies group)
		if target.is_in_group("charmed_allies"):
			return
	
	# Apply damage
	if target.has_method("take_damage"):
		target.take_damage(damage, false, Vector2.ZERO, false, owner_name + ":Laser")
		_retire()
	elif target.has_method("apply_damage"):
		target.apply_damage(damage)
		_retire()
