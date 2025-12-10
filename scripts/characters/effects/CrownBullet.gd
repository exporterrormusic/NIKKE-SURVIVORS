extends Area2D
class_name CrownBullet

## Crown's regal gold minigun bullet - uses shader for swirling golden sphere effect

var velocity: Vector2 = Vector2.ZERO
var owner_node: Node = null
var base_damage: int = 2
var lifespan: float = 3.0
var _age: float = 0.0
var start_position: Vector2 = Vector2.ZERO
var _start_position_set: bool = false

# Max range for Crown's minigun (same as standard minigun)
const MAX_RANGE := 1100.0

# Critical hit settings
const BASE_CRIT_CHANCE := 0.15
const CRIT_MULTIPLIER := 2.0

func _ready() -> void:
	# Set up collision
	collision_layer = 4  # Projectile layer
	collision_mask = 6   # Enemy layer (2) + Hitbox layer (4)
	
	# Connect hit detection
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Assign to effects layer to prevent night darkening (deferred so node is in tree)
	call_deferred("_assign_to_effects_layer")
	
	# Create the visual
	_create_visual()
	
	z_index = 50

	# Connect to environment modulate changes so we can redraw with compensation
	if not Engine.is_editor_hint():
		var tree = get_tree()
		if tree:
			var env = tree.get_first_node_in_group("environment_controller")
			if env and env.has_signal("modulate_changed"):
				env.modulate_changed.connect(Callable(self, "_on_environment_modulate_changed"))

func _assign_to_effects_layer() -> void:
	"""Deferred call to assign to effects layer after node is in tree"""
	# Use helper which ensures correct CanvasLayer settings (follow_viewport)
	VisualLayerHelper.reparent_to_effects_layer(self, 900)


func _create_visual() -> void:
	# Create collision shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 6.0
	collision.shape = shape
	add_child(collision)

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifespan:
		queue_free()
		return
	
	# Capture start position on first frame
	if not _start_position_set:
		start_position = global_position
		_start_position_set = true
	
	# Move bullet
	position += velocity * delta
	
	# Check max range
	if MAX_RANGE > 0.0:
		var traveled := global_position.distance_to(start_position)
		if traveled >= MAX_RANGE:
			queue_free()
			return
	
	# Check boulder collision (reparenting to EffectsLayer breaks Area2D overlap)
	if _check_boulder_collision():
		queue_free()
		return
	
	# Redraw for shader animation
	queue_redraw()

func _check_boulder_collision() -> bool:
	"""Manual boulder collision check since bullets are in EffectsLayer (different scene tree branch)."""
	var boulders := get_tree().get_nodes_in_group("boulders")
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_to(boulder_pos) < boulder_radius:
			return true
	return false


func _draw() -> void:
	# Draw the golden sphere with layered glow
	var size := 28.0  # Size to match other bullets
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Apply ambient/vignette compensation so the drawn circles remain bright at night
	var vp := get_viewport()
	var base_color := Color(1.0, 0.95, 0.7, 1.0)
	var comp_color := BasicProjectileVisual._apply_compensation(base_color, global_position, vp) if BasicProjectileVisual else base_color

	# Outer glow - bright gold bloom (compensated)
	draw_circle(Vector2.ZERO, size * 0.8, Color(comp_color.r, comp_color.g, comp_color.b, 0.3))
	draw_circle(Vector2.ZERO, size * 0.6, Color(comp_color.r, comp_color.g, comp_color.b, 0.5))

	# Core - bright golden (compensated)
	draw_circle(Vector2.ZERO, size * 0.4, Color(comp_color.r, comp_color.g, comp_color.b, 0.8))
	draw_circle(Vector2.ZERO, size * 0.25, Color(comp_color.r, comp_color.g, comp_color.b, 1.0))

	# Bright center (keep white)
	draw_circle(Vector2.ZERO, size * 0.12, Color(1.0, 1.0, 1.0, 1.0))
	
	# Draw swirling golden particles
	var time := _age * 3.0
	for i in range(6):
		var angle := time + float(i) * TAU / 6.0
		var radius := size * 0.35 * (0.7 + 0.3 * sin(time * 2.0 + float(i)))
		var pos := Vector2(cos(angle), sin(angle)) * radius
		var particle_size := 3.5 + 2.0 * sin(time * 4.0 + float(i) * 1.5)
		draw_circle(pos, particle_size, Color(1.0, 0.95, 0.6, 0.8))

func _on_body_entered(body: Node2D) -> void:
	_hit_target(body)

func _on_area_entered(area: Area2D) -> void:
	_hit_target(area)

func _hit_target(target: Node) -> void:
	# Skip if target is the owner
	if target == owner_node:
		return
	
	# Skip if not an enemy
	if not target.is_in_group("enemies"):
		return
	
	# Skip charmed enemies
	if target.is_in_group("charmed_allies"):
		return
	
	# Roll for critical hit - base chance + shop bonus (capped at 100%)
	var crit_chance := BASE_CRIT_CHANCE
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_crit_chance"):
		crit_chance += player.get_crit_chance()
	crit_chance = minf(crit_chance, 1.0)  # Cap at 100%
	var is_crit := randf() < crit_chance
	var damage := base_damage
	if is_crit:
		damage = int(base_damage * CRIT_MULTIPLIER)
	
	# Apply damage
	if target.has_method("take_damage"):
		var hit_direction := velocity.normalized()
		target.take_damage(damage, is_crit, hit_direction)
	
	# Destroy bullet after hitting
	queue_free()
