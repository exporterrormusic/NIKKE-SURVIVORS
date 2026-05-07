extends StaticBody2D
class_name SwayableBush

## Swayable bush obstacle that blocks bullets and movement like boulders
## Optimized: Combined detector, visibility-based processing

# Cached ShopMenu reference to avoid load() in hot collision paths
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

var _sprite: Sprite2D = null
var _collision_shape: CollisionShape2D = null
var _bump_intensity: float = 0.0
var _bump_decay_rate: float = 5.0

# Boulder-compatible size property for Bullet.gd collision check
var boulder_size: float = 60.0

var _rng := RandomNumberGenerator.new()
var _time_offset: float = 0.0
var _sway_amount: float = 0.12
var _sway_speed: float = 0.8
var _last_projectile_bump_time: float = 0.0
const PROJECTILE_BUMP_COOLDOWN: float = 0.3

# Cached player reference for visibility check
var _cached_player: Node2D = null
const VISIBILITY_DISTANCE_SQ: float = 1200.0 * 1200.0 # Only process within 1200px of player


func _ready() -> void:
	add_to_group("boulders")
	_rng.randomize()
	_time_offset = _rng.randf() * 10.0
	_sway_amount = _rng.randf_range(0.08, 0.15)
	_sway_speed = _rng.randf_range(0.6, 1.0)
	
	call_deferred("_setup_bush")


func _setup_bush() -> void:
	# Find sprite child
	for child in get_children():
		if child is Sprite2D:
			_sprite = child
			break
	
	# Find collision shape and set boulder_size
	for child in get_children():
		if child is CollisionShape2D:
			_collision_shape = child
			if _collision_shape.shape is CircleShape2D:
				boulder_size = _collision_shape.shape.radius * 2.0
			break
	
	if not _sprite:
		return
	
	# Set collision layers exactly like boulders
	collision_layer = 0b0000_0000_0000_0100 # Layer 3
	collision_mask = 0b0000_0000_0000_0111 # Layers 1, 2, 3
	
	# Create SINGLE combined detector (bullet + player detection)
	_create_combined_detector()


func _create_combined_detector() -> void:
	"""Create single Area2D for both bullet AND player detection (optimized)."""
	var detector := Area2D.new()
	detector.name = "CombinedDetector"
	detector.collision_layer = 0
	# Detect projectiles (layer 3/bit 2 = 4) AND player (layer 1/bit 0 = 1)
	detector.collision_mask = 5 # 4 + 1 = 5
	detector.monitoring = true
	detector.monitorable = false
	
	var detector_shape := CollisionShape2D.new()
	var detector_circle := CircleShape2D.new()
	
	if _collision_shape and _collision_shape.shape is CircleShape2D:
		detector_circle.radius = _collision_shape.shape.radius * 1.5
	else:
		detector_circle.radius = 50.0
	
	detector_shape.shape = detector_circle
	detector.add_child(detector_shape)
	add_child(detector)
	
	# Connect both signals to combined handlers
	detector.area_entered.connect(_on_area_entered)
	detector.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if not _sprite:
		return
	
	# OPTIMIZATION: Only process visible bushes (near player)
	if not _cached_player or not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("player")
	
	if _cached_player:
		var dist_sq := global_position.distance_squared_to(_cached_player.global_position)
		if dist_sq > VISIBILITY_DISTANCE_SQ:
			return # Skip processing for distant bushes
	
	var time := Time.get_ticks_msec() / 1000.0
	
	# Base wind sway
	var wind_sway := sin(time * _sway_speed + _time_offset) * _sway_amount
	wind_sway += sin(time * _sway_speed * 2.1 + _time_offset * 1.5) * _sway_amount * 0.3
	
	# Bump shake
	var bump_sway := 0.0
	if _bump_intensity > 0.01:
		bump_sway = sin(time * 22.0) * _bump_intensity * 0.25
		bump_sway += sin(time * 35.0) * _bump_intensity * 0.12
		_bump_intensity = maxf(0.0, _bump_intensity - delta * _bump_decay_rate)
	
	var total_skew := wind_sway + bump_sway
	
	# Apply skew transform
	_sprite.transform = Transform2D(_sprite.rotation, _sprite.scale, total_skew, _sprite.position)


func _on_body_entered(body: Node2D) -> void:
	"""Handle both player bump AND bullet body collision."""
	# Check if it's the player (for bump effect)
	if body.is_in_group("player"):
		trigger_bump(1.0)
		return
	
	# Otherwise treat as bullet body
	_handle_bullet_body(body)


func _on_area_entered(area: Area2D) -> void:
	"""Handle bullet area collision."""
	_handle_bullet_area(area)


func _handle_bullet_area(area: Area2D) -> void:
	"""Destroy bullets that hit this bush. Sniper bullets pierce through."""
	
	# Check if this is a PLAYER projectile
	var is_player_projectile := false
	if "owner_node" in area:
		var owner = area.owner_node
		if owner and owner.is_in_group("player"):
			is_player_projectile = true
	
	if not is_player_projectile:
		var area_name := area.name.to_lower()
		if "bullet" in area_name or "pellet" in area_name or "rocket" in area_name or "missile" in area_name or "minigun" in area_name:
			if "boss" not in area_name and "enemy" not in area_name:
				is_player_projectile = true
	
	if is_player_projectile:
		trigger_bump(0.7, true)
	
	# Sniper bullets pierce through
	if area.name.contains("Sniper") or area.name.contains("SnowWhite"):
		return
	
	# Check for Chrono-Intangibility upgrade
	var player = get_tree().get_first_node_in_group("player")
	var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
	var in_squad = false
	if player and player.has_method("is_character_in_squad"):
		in_squad = player.is_character_in_squad("wells") or player.is_character_in_squad("Wells")
	
	if has_upgrade and in_squad:
		return
	
	if area.is_in_group("bullets") or area.is_in_group("projectiles") or area.is_in_group("player_projectiles") or area.is_in_group("enemy_projectiles"):
		area.queue_free()
	elif area.has_method("_retire"):
		area._retire()
	elif area.name.contains("Bullet") or area.name.contains("Laser") or area.name.contains("Pellet") or area.name.contains("Rocket"):
		area.queue_free()


func _handle_bullet_body(body: Node2D) -> void:
	"""Destroy bullet bodies that hit this bush. Sniper bullets pierce through."""
	
	var is_player_projectile := false
	if "owner_node" in body:
		var owner = body.owner_node
		if owner and owner.is_in_group("player"):
			is_player_projectile = true
	
	if not is_player_projectile:
		var body_name := body.name.to_lower()
		if "bullet" in body_name or "pellet" in body_name or "rocket" in body_name or "missile" in body_name:
			if "boss" not in body_name and "enemy" not in body_name:
				is_player_projectile = true
	
	if is_player_projectile:
		trigger_bump(0.7, true)
	
	if body.name.contains("Sniper") or body.name.contains("SnowWhite"):
		return
	
	var player = get_tree().get_first_node_in_group("player")
	var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
	var in_squad = false
	if player and player.has_method("is_character_in_squad"):
		in_squad = player.is_character_in_squad("wells") or player.is_character_in_squad("Wells")
	
	if has_upgrade and in_squad:
		return
	
	if body.is_in_group("bullets") or body.is_in_group("projectiles") or body.is_in_group("player_projectiles"):
		body.queue_free()
	elif body.has_method("_retire"):
		body._retire()
	elif body.name.contains("Bullet") or body.name.contains("Pellet") or body.name.contains("Rocket"):
		body.queue_free()


func trigger_bump(intensity: float = 1.0, from_projectile: bool = false) -> void:
	"""Trigger a bump shake animation."""
	if from_projectile:
		var current_time := Time.get_ticks_msec() / 1000.0
		if current_time - _last_projectile_bump_time < PROJECTILE_BUMP_COOLDOWN:
			return
		_last_projectile_bump_time = current_time
	
	_bump_intensity = clampf(_bump_intensity + intensity, 0.0, 1.0)
