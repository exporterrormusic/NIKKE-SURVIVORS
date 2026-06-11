extends StaticBody2D
class_name ProceduralBoulder

## Procedurally generated boulder obstacle that blocks bullets and movement

# Cached ShopMenu reference to avoid load() in hot collision paths
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

@export var boulder_size: float = 240.0  # Tripled from 80.0
@export var variation_seed: int = 0

var _visual: Polygon2D = null
var _collision_shape: CollisionShape2D = null

# Static shared material for batching
static var _shared_mat: ShaderMaterial = null

func _ready():
	add_to_group("boulders")
	_create_boulder()

func _create_boulder():
	"""Create boulder visuals and collision using procedural generation."""
	var rng = RandomNumberGenerator.new()
	rng.seed = variation_seed if variation_seed != 0 else randi()
	
	# Create visual polygon
	_visual = Polygon2D.new()
	_visual.z_index = 0  # Same as player - Y-sorting will handle depth
	_visual.y_sort_enabled = true
	add_child(_visual)
	
	# Generate irregular boulder shape
	var points: PackedVector2Array = []
	var num_points = rng.randi_range(8, 12)  # Irregular shape
	var base_radius = boulder_size * 0.5
	
	for i in range(num_points):
		var angle = (float(i) / num_points) * TAU
		# Randomize radius for each point
		var radius_variation = rng.randf_range(0.7, 1.0)
		var radius = base_radius * radius_variation
		var point = Vector2(cos(angle), sin(angle)) * radius
		points.append(point)
	
	_visual.polygon = points
	
	# Optimization: Use Shared Material for Batching
	if not _shared_mat:
		_shared_mat = ShaderMaterial.new()
		var shader = load("res://resources/shaders/boulder.gdshader")
		_shared_mat.shader = shader
		# Set uniforms once for all boulders
		_shared_mat.set_shader_parameter("rock_base_color", Vector3(0.65, 0.67, 0.7))
		_shared_mat.set_shader_parameter("rock_highlight", Vector3(0.9, 0.92, 0.95))
		_shared_mat.set_shader_parameter("rock_shadow", Vector3(0.4, 0.42, 0.45))
	
	_visual.material = _shared_mat
	
	# Pass random seed via Modulate (Vertex Color) to preserve batching
	# The shader reads v_seed = COLOR.r
	_visual.modulate = Color(rng.randf(), 1.0, 1.0, 1.0)
	
	# Use simple circle collision shape to avoid concave polygon issues
	_collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = base_radius * 0.95  # Slightly smaller than visual for smooth movement
	_collision_shape.shape = circle
	add_child(_collision_shape)
	
	# Add Area2D for bullet detection (Area2D bullets don't collide with StaticBody2D)
	var bullet_detector := Area2D.new()
	bullet_detector.name = "BulletDetector"
	bullet_detector.collision_layer = 0  # No layer - just for detection
	bullet_detector.collision_mask = 4   # Projectiles are on layer 3 (bit 2 = value 4)
	bullet_detector.monitoring = true
	bullet_detector.monitorable = false
	
	var detector_shape := CollisionShape2D.new()
	var detector_circle := CircleShape2D.new()
	detector_circle.radius = base_radius * 0.95
	detector_shape.shape = detector_circle
	bullet_detector.add_child(detector_shape)
	add_child(bullet_detector)
	
	# Connect to destroy bullets on contact
	bullet_detector.area_entered.connect(_on_bullet_entered)
	bullet_detector.body_entered.connect(_on_bullet_body_entered)
	
	# Set collision layers - this is critical for proper physics
	# Layer 3 (bit 2): Environment/obstacles  
	# Mask: Player (layer 1/bit 0), Enemies (layer 3/bit 2), Projectiles (layer 2/bit 1)
	collision_layer = 0b0000_0000_0000_0100  # Layer 3 (bit 2 = value 4)
	collision_mask = 0b0000_0000_0000_0111   # Layers 1, 2, 3 (bits 0,1,2 = value 7)

func _on_bullet_entered(area: Area2D) -> void:
	"""Destroy bullets that hit this boulder. Sniper bullets pierce through."""
	# Sniper bullets pierce through boulders
	if area is SnowWhiteBullet or area.name.contains("Sniper") or area.name.contains("SnowWhite"):
		return
	
	# Check for Chrono-Intangibility upgrade (playing Wells)
	# Check for Chrono-Intangibility upgrade (playing Wells)
	var player = get_tree().get_first_node_in_group("player")
	var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
	var playing_wells = false
	if player and player.has_method("is_playing_character"):
		playing_wells = player.is_playing_character("wells")
	
	if has_upgrade and playing_wells:
		return # Bullet phases through
	
	if area.is_in_group("bullets") or area.is_in_group("projectiles") or area.is_in_group("player_projectiles") or area.is_in_group("enemy_projectiles"):
		area.queue_free()
	elif area.has_method("_retire"):
		area._retire()
	elif area.name.contains("Bullet") or area.name.contains("Laser") or area.name.contains("Pellet"):
		area.queue_free()

func _on_bullet_body_entered(body: Node2D) -> void:
	"""Destroy bullet bodies that hit this boulder. Sniper bullets pierce through."""
	# Sniper bullets pierce through boulders
	if body is SnowWhiteBullet or body.name.contains("Sniper") or body.name.contains("SnowWhite"):
		return
	
	# Check for Chrono-Intangibility upgrade (playing Wells)
	# Check for Chrono-Intangibility upgrade (playing Wells)
	var player = get_tree().get_first_node_in_group("player")
	var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
	var playing_wells = false
	if player and player.has_method("is_playing_character"):
		playing_wells = player.is_playing_character("wells")
	
	if has_upgrade and playing_wells:
		return # Bullet phases through
	
	if body.is_in_group("bullets") or body.is_in_group("projectiles") or body.is_in_group("player_projectiles"):
		body.queue_free()
	elif body.has_method("_retire"):
		body._retire()
	elif body.name.contains("Bullet") or body.name.contains("Pellet"):
		body.queue_free()


func set_boulder_seed(new_seed: int):
	"""Set the variation seed for this boulder."""
	variation_seed = new_seed
	if is_node_ready():
		# Recreate with new seed
		if _visual:
			_visual.queue_free()
		if _collision_shape:
			_collision_shape.queue_free()
		_create_boulder()
