extends Area2D
class_name RosePetal
## Small rose petal projectile shot from Scarlet's sword when "Rose's Core" upgrade is purchased
## Travels a short distance and deals full slash damage

var velocity := Vector2.ZERO
var lifetime: float = 0.0
var max_lifetime: float = 0.6  # Longer travel time for more range
var owner_node: Node = null

var base_damage := 10
var _has_hit := false

# Visual - sharp flowing petals
var _rotation_speed: float = 0.0
var _color: Color = Color(1.0, 0.2, 0.45, 0.95)  # Vivid rose pink
var _glow_color: Color = Color(1.0, 0.5, 0.7, 0.6)  # Soft pink glow
var _size: float = 22.0  # Much larger for visibility
var _trail_positions: Array = []  # For motion trail
var _max_trail: int = 6

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Enemies are on layer 2
	monitoring = true
	monitorable = false
	
	var shape := CircleShape2D.new()
	shape.radius = _size * 0.6  # Hitbox slightly smaller than visual
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	
	body_entered.connect(_on_body_entered)
	
	# Consistent rotation to keep petal pointing in travel direction with slight spin
	_rotation_speed = randf_range(3.0, 6.0) * (1 if randf() > 0.5 else -1)
	
	# Z-index for visibility
	z_index = 50
	
	queue_redraw()

func _process(delta: float) -> void:
	# Track trail positions
	_trail_positions.push_front(global_position)
	if _trail_positions.size() > _max_trail:
		_trail_positions.pop_back()
	
	global_position += velocity * delta
	rotation += _rotation_speed * delta
	
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()
		return
	
	# Fade out near end of life
	var alpha_mult := 1.0
	if lifetime > max_lifetime * 0.7:
		alpha_mult = 1.0 - ((lifetime - max_lifetime * 0.7) / (max_lifetime * 0.3))
	_color.a = 0.95 * alpha_mult
	_glow_color.a = 0.6 * alpha_mult
	
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if _has_hit:
		return
	if body == owner_node:
		return
	if owner_node and body.name == "Player":
		return
	if body.is_in_group("charmed_allies"):
		return
	if not body.has_method("take_damage"):
		return
	
	_has_hit = true
	
	# Roll for critical hit
	var crit_chance := 0.15
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_crit_chance"):
		crit_chance += player.get_crit_chance()
	crit_chance = minf(crit_chance, 1.0)
	var is_crit := randf() < crit_chance
	var damage := base_damage
	if is_crit:
		damage = int(base_damage * 2.0)
	
	var hit_direction = velocity.normalized()
	body.take_damage(damage, is_crit, hit_direction)
	
	queue_free()

func _draw() -> void:
	# Draw motion trail first (behind petal)
	for i in range(_trail_positions.size()):
		var trail_alpha := (1.0 - float(i) / _max_trail) * _color.a * 0.5
		var trail_size := _size * (1.0 - float(i) / _max_trail * 0.6)
		var local_pos: Vector2 = _trail_positions[i] - global_position
		_draw_sharp_petal(local_pos, trail_size * 0.7, Color(_color.r, _color.g, _color.b, trail_alpha))
	
	# Draw outer glow
	var glow_points := _get_petal_points(_size * 1.4)
	draw_colored_polygon(glow_points, _glow_color)
	
	# Draw main sharp petal shape
	_draw_sharp_petal(Vector2.ZERO, _size, _color)
	
	# Bright highlight streak along center
	var highlight_color := Color(1.0, 0.85, 0.9, _color.a)
	var streak_length := _size * 0.7
	draw_line(Vector2(-streak_length * 0.3, 0), Vector2(streak_length * 0.5, 0), highlight_color, 3.0)
	
	# Sparkle at tip
	var sparkle_pos := Vector2(_size * 0.6, 0)
	draw_circle(sparkle_pos, 3.0, Color(1.0, 1.0, 1.0, _color.a))

func _draw_sharp_petal(pos: Vector2, size: float, color: Color) -> void:
	var points := _get_petal_points(size)
	# Offset points by position
	var offset_points: PackedVector2Array = []
	for p in points:
		offset_points.append(p + pos)
	draw_colored_polygon(offset_points, color)

func _get_petal_points(size: float) -> PackedVector2Array:
	# Sharp, elongated petal shape - pointed at front, curved at back
	var points: PackedVector2Array = []
	
	# Front sharp tip
	points.append(Vector2(size, 0))
	
	# Upper curve (flowing backward)
	points.append(Vector2(size * 0.5, -size * 0.25))
	points.append(Vector2(size * 0.1, -size * 0.4))
	points.append(Vector2(-size * 0.3, -size * 0.35))
	points.append(Vector2(-size * 0.6, -size * 0.2))
	
	# Back curve
	points.append(Vector2(-size * 0.7, 0))
	
	# Lower curve (flowing backward, mirror of upper)
	points.append(Vector2(-size * 0.6, size * 0.2))
	points.append(Vector2(-size * 0.3, size * 0.35))
	points.append(Vector2(size * 0.1, size * 0.4))
	points.append(Vector2(size * 0.5, size * 0.25))
	
	return points
