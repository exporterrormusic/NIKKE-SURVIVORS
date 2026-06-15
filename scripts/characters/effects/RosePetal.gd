extends Area2D
class_name RosePetal
## Small rose petal projectile shot from Scarlet's sword when "Rose's Core" upgrade is purchased
## Travels a short distance and deals full slash damage

# Cached ShopMenu reference to avoid load() in hot paths
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

var velocity := Vector2.ZERO
var lifetime: float = 0.0
var max_lifetime: float = 0.6 # Longer travel time for more range
var owner_node: Node = null

var base_damage := 10
var _has_hit := false

# Visual - sharp flowing petals
var _rotation_speed: float = 0.0
var _color: Color = Color(1.0, 0.2, 0.45, 0.95) # Vivid rose pink
var _glow_color: Color = Color(1.0, 0.5, 0.7, 0.6) # Soft pink glow
var _size: float = 22.0 # Much larger for visibility
var _trail_positions: Array = [] # For motion trail
var _max_trail: int = 6

func _ready() -> void:
	add_to_group("player_projectiles")
	add_to_group("projectiles") # Also needed for Wells' Chrono-Intangibility boulder detection
	collision_layer = 4 # Layer 3 (Projectiles)
	collision_mask = 7 # 1(World) + 2(Enemies) + 4(Shields/Hitboxes)
	monitoring = true
	monitorable = true # Must be monitorable for Shield to detect it too
	
	var shape := CircleShape2D.new()
	shape.radius = _size * 1.2 # Generous hitbox (was 0.6) so the aimed target is reliably hit
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_body_entered) # Support hitting Area2D shields
	
	# Consistent rotation to keep petal pointing in travel direction with slight spin
	_rotation_speed = randf_range(3.0, 6.0) * (1 if randf() > 0.5 else -1)
	
	# Z-index for visibility
	z_index = 50
	
	# Make petal unshaded (glows in dark)
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	queue_redraw()

func _physics_process(delta: float) -> void:
	# Track trail positions
	_trail_positions.push_front(global_position)
	if _trail_positions.size() > _max_trail:
		_trail_positions.pop_back()
	
	var frame_movement = velocity * delta
	var current_pos = global_position
	var next_pos = current_pos + frame_movement
	
	# Raycast check to prevent tunneling
	var space_state = get_world_2d().direct_space_state
	# Mask 7 = World(1) + Enemy(2) + Shield/Hitbox(4)
	var query = PhysicsRayQueryParameters2D.create(current_pos, next_pos, 7, [self])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		# Check if this is a boulder we should phase through BEFORE setting position
		var collider = result.collider
		if collider is StaticBody2D and collider.is_in_group("boulders"):
			var player_ref = get_tree().get_first_node_in_group("player")
			if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and player_ref and player_ref.has_method("is_playing_character") and player_ref.is_playing_character("wells"):
				# Phase through boulder - continue to next_pos, don't stop at collision point
				global_position = next_pos
				# Skip the rest of the collision handling
			else:
				# Not phasing - normal collision handling
				global_position = result.position
				_on_body_entered(collider)
				return
		else:
			# Not a boulder - normal collision handling
			global_position = result.position
			_on_body_entered(collider)
			return
	
	global_position = next_pos
	rotation += _rotation_speed * delta
	
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()
		return
	
	# Check boulder collision
	if _check_boulder_collision():
		queue_free()
		return
	
	# Fade out near end of life
	var alpha_mult := 1.0
	if lifetime > max_lifetime * 0.7:
		alpha_mult = 1.0 - ((lifetime - max_lifetime * 0.7) / (max_lifetime * 0.3))
	_color.a = 0.95 * alpha_mult
	_glow_color.a = 0.6 * alpha_mult
	
	queue_redraw()

func _check_boulder_collision() -> bool:
	"""Manual boulder collision check since petals don't reparent but still need check."""
	# Skip if Chrono-Intangibility upgrade is active AND playing Wells
	var player = get_tree().get_first_node_in_group("player")
	if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and player and player.has_method("is_playing_character") and player.is_playing_character("wells"):
		return false
		
	var boulders := get_tree().get_nodes_in_group("boulders")
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		# Use 5% larger radius to match collision shape edge cases
		if global_position.distance_to(boulder_pos) < boulder_radius * 1.05:
			return true
	return false


func _on_body_entered(body: Node2D) -> void:
	if _has_hit:
		return
	if body == owner_node:
		return
	if owner_node and body.name == "Player":
		return
	if body.is_in_group("charmed_allies"):
		return
		
	# 1. Check for Shield Hit (Area2D child of ShielderShield) via explicit detection
	# (This handles the case where we hit the shield area directly)
	var shield_root = null
	if body is Area2D:
		shield_root = body.get_parent()
	elif body.has_method("take_shield_damage"):
		shield_root = body
		
	if shield_root and shield_root.has_method("take_shield_damage"):
		# Shield hit!
		shield_root.take_shield_damage(base_damage, "projectile")
		if shield_root.has_method("is_active") and shield_root.is_active():
			# Shield absorbed it (still active)
			queue_free()
			return
		else:
			# Shield BROKE from this hit
			# We must still destroy the petal because it spent its energy breaking the shield
			queue_free()
			return

	if not body.has_method("take_damage"):
		return
		
	# Check if this "damageable" body is actually a boulder (destructible terrain)
	if body.is_in_group("boulders") or (body.get_parent() and body.get_parent().is_in_group("boulders")):
		var check_player = get_tree().get_first_node_in_group("player")
		if ShopMenu.has_character_upgrade("wells", "chrono_intangibility") and check_player and check_player.has_method("is_playing_character") and check_player.is_playing_character("wells"):
			return # Ignore boulder hitting
			
	# Backup spatial check for boulders in body_entered if group check failed
	var boulders = get_tree().get_nodes_in_group("boulders")
	for b in boulders:
		if is_instance_valid(b):
			var b_rad = 150.0
			if "boulder_size" in b: b_rad = b.boulder_size * 0.5
			if global_position.distance_squared_to(b.global_position) < (b_rad * 1.2) ** 2:
				# It is inside a boulder radius, treat as boulder
				var check_player = get_tree().get_first_node_in_group("player")
				if ShopMenu.has_character_upgrade("wells", "chrono_intangibility") and check_player and check_player.has_method("is_playing_character") and check_player.is_playing_character("wells"):
					return
	
	_has_hit = true
	
	# Roll for critical hit
	var crit_chance := 0.05  # HoloCure clone: 5% base crit
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_crit_chance"):
		crit_chance += player.get_crit_chance()
	crit_chance = minf(crit_chance, 1.0)
	var is_crit := randf() < crit_chance
	var damage := base_damage
	if is_crit:
		damage = int(base_damage * 1.5)  # HoloCure clone: 1.5x on crit
	
	var hit_direction = velocity.normalized()
	# Pass source="projectile" so ModularEnemy registers burst hit
	body.take_damage(damage, is_crit, hit_direction, false, "projectile")
	
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
