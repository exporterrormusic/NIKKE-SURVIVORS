extends StaticBody2D
class_name SnowyBoulder

## Snow-covered boulder obstacle that blocks bullets and movement
## Uses a texture instead of procedural generation
## Emits snow puff particles when hit by projectiles

const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

# Texture paths - place your snowy boulder texture here
const SNOWY_BOULDER_TEXTURES: Array[String] = [
	"res://assets/textures/decorations/boulder1.png",
	"res://assets/textures/decorations/boulder2.png",
	"res://assets/textures/decorations/boulder3.png",
]

@export var boulder_size: float = 240.0
@export var variation_seed: int = 0

var _sprite: Sprite2D = null
var _collision_shape: CollisionShape2D = null
var _snow_particles: GPUParticles2D = null
var _rng: RandomNumberGenerator = null

# Cooldown for particle effect
var _last_hit_time: float = 0.0
const HIT_COOLDOWN: float = 0.15 # Minimum time between snow puffs


func _ready() -> void:
	add_to_group("boulders")
	_rng = RandomNumberGenerator.new()
	_rng.seed = variation_seed if variation_seed != 0 else randi()
	_create_boulder()
	_setup_snow_particles()


func _create_boulder() -> void:
	"""Create boulder visuals and collision using texture."""
	# Create sprite for visual
	_sprite = Sprite2D.new()
	_sprite.z_index = 0
	add_child(_sprite)
	
	# Try to load a texture, use fallback if not found
	var texture: Texture2D = null
	var texture_index = _rng.randi() % SNOWY_BOULDER_TEXTURES.size()
	
	for i in range(SNOWY_BOULDER_TEXTURES.size()):
		var try_index = (texture_index + i) % SNOWY_BOULDER_TEXTURES.size()
		var path = SNOWY_BOULDER_TEXTURES[try_index]
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
			if texture:
				break
	
	if texture:
		_sprite.texture = texture
		# Scale to match desired boulder_size
		var tex_size = texture.get_size()
		var scale_factor = boulder_size / max(tex_size.x, tex_size.y)
		_sprite.scale = Vector2(scale_factor, scale_factor)
	else:
		# Fallback: create a simple white circle placeholder
		_create_fallback_visual()
	
	# No random rotation - keep "up" facing "up" for 2.5D perspective
	_sprite.rotation = 0.0
	
	# Random flip for more variety
	if _rng.randf() > 0.5:
		_sprite.flip_h = true
	
	# Collision shape
	_collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = boulder_size * 0.45 # Slightly smaller than visual
	_collision_shape.shape = circle
	add_child(_collision_shape)
	
	# Bullet detector Area2D
	var bullet_detector := Area2D.new()
	bullet_detector.name = "BulletDetector"
	bullet_detector.collision_layer = 0
	bullet_detector.collision_mask = 4 # Projectiles layer
	bullet_detector.monitoring = true
	bullet_detector.monitorable = false
	
	var detector_shape := CollisionShape2D.new()
	var detector_circle := CircleShape2D.new()
	# Make detector larger to catch fast bullets before they hit the hard collider
	detector_circle.radius = boulder_size * 0.65
	detector_shape.shape = detector_circle
	bullet_detector.add_child(detector_shape)
	add_child(bullet_detector)
	
	bullet_detector.area_entered.connect(_on_bullet_entered)
	bullet_detector.body_entered.connect(_on_bullet_body_entered)
	
	# Set collision layers
	collision_layer = 0b0000_0000_0000_0100 # Layer 3
	collision_mask = 0b0000_0000_0000_0111 # Layers 1, 2, 3


func _create_fallback_visual() -> void:
	"""Create a simple circle visual when no texture is available."""
	# Generate a simple white circle texture procedurally
	var gradient = GradientTexture2D.new()
	gradient.width = 64
	gradient.height = 64
	gradient.fill = GradientTexture2D.FILL_RADIAL
	gradient.fill_from = Vector2(0.5, 0.5)
	gradient.fill_to = Vector2(0.5, 0.0)
	
	var grad = Gradient.new()
	grad.remove_point(0)
	grad.remove_point(0)
	grad.add_point(0.0, Color.WHITE)
	grad.add_point(0.95, Color.WHITE)
	grad.add_point(1.0, Color(1, 1, 1, 0)) # Transparent edge
	gradient.gradient = grad
	
	_sprite.texture = gradient
	_sprite.scale = Vector2(boulder_size / 64.0, boulder_size / 64.0)


func _setup_snow_particles() -> void:
	"""Create GPU particle system for snow puff effect when hit."""
	_snow_particles = GPUParticles2D.new()
	_snow_particles.name = "SnowPuff"
	_snow_particles.emitting = false
	_snow_particles.one_shot = true
	_snow_particles.explosiveness = 1.0
	_snow_particles.amount = 64 # Denser cloud for "puffy" look
	_snow_particles.lifetime = 0.8
	_snow_particles.local_coords = true # Move with boulder if it moved, but mainly so we can rotate the emitter
	_snow_particles.z_index = 10
	
	# Create reliable round texture via Image
	# 16x16 white circle
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0)) # Transparent
	
	var center = Vector2(8, 8)
	var radius = 7.0
	for y in range(16):
		for x in range(16):
			var dist = center.distance_to(Vector2(x, y))
			if dist <= radius:
				var alpha = 1.0
				if dist > radius - 1.0: # Antialias edge
					alpha = 1.0 - (dist - (radius - 1.0))
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
				
	_snow_particles.texture = ImageTexture.create_from_image(img)
	
	add_child(_snow_particles)
	
	# Create particle material
	var particle_mat = ParticleProcessMaterial.new()
	
	# Emission shape - Large sphere to cover the "opposite half"
	particle_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_mat.emission_sphere_radius = boulder_size * 0.4 # Cover almost half the boulder
	
	# Direction - Forward
	particle_mat.direction = Vector3(1, 0, 0)
	particle_mat.spread = 60.0
	
	# Velocity
	particle_mat.initial_velocity_min = 60.0
	particle_mat.initial_velocity_max = 120.0
	
	# Gravity - reduced gravity for fluffier snow
	particle_mat.gravity = Vector3(0, 100, 0)
	
	# Scale - Tiny flakes
	# Texture is 16px. Scale 0.3 = 4.8px. Scale 0.6 = 9.6px.
	particle_mat.scale_min = 0.3
	particle_mat.scale_max = 0.6
	
	# Fade out
	var alpha_curve = Curve.new()
	alpha_curve.add_point(Vector2(0.0, 1.0))
	alpha_curve.add_point(Vector2(0.3, 1.0))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	var alpha_curve_tex = CurveTexture.new()
	alpha_curve_tex.curve = alpha_curve
	particle_mat.alpha_curve = alpha_curve_tex
	
	# Scale over lifetime - grow slightly then shrink
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.2, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.3))
	var scale_curve_tex = CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	particle_mat.scale_curve = scale_curve_tex
	
	# Color - Pure white
	particle_mat.color = Color.WHITE
	
	_snow_particles.process_material = particle_mat
	
	# Use simple quad for snow flakes (or load a texture if available)
	# For now, just use the default quad mesh


func trigger_snow_puff(hit_pos: Vector2 = Vector2.ZERO) -> void:
	"""Trigger the snow puff particle effect from a specific position."""
	if not _snow_particles:
		return
	
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_hit_time < HIT_COOLDOWN:
		return
	_last_hit_time = current_time
	
	# Calculate direction from center to hit position
	# If hit_pos is ZERO (fallback), just use Up
	var local_hit_pos = to_local(hit_pos)
	
	if hit_pos != Vector2.ZERO:
		# Spawn at CENTER
		# User request: "spawn on the center, with it falling away to the opposite half"
		_snow_particles.position = Vector2.ZERO - local_hit_pos.normalized() * (boulder_size * 0.1) # Start slightly towards impact, fly through
		
		# Better interpretation: "spawn on center... falling away to opposite half"
		# Just spawn at center.
		_snow_particles.position = Vector2.ZERO
		
		# Look OPPOSITE to the hit position (Fly AWAY from impact)
		# vector from hit_pos -> center is -local_hit_pos
		# fly_dir = -local_hit_pos
		var fly_dir = - local_hit_pos
		_snow_particles.look_at(to_global(fly_dir))
	else:
		_snow_particles.position = Vector2.ZERO
		_snow_particles.rotation = - PI / 2 # Up
	
	_snow_particles.restart()
	_snow_particles.emitting = true


func _on_bullet_entered(area: Area2D) -> void:
	"""Handle bullet collision - emit snow puff and block/destroy bullet."""
	# Check if player-owned for snow puff effect
	var is_player_projectile := false
	if "owner_node" in area:
		var projectile_owner = area.owner_node
		if projectile_owner and projectile_owner.is_in_group("player"):
			is_player_projectile = true
	
	if not is_player_projectile:
		var area_name := area.name.to_lower()
		if "bullet" in area_name or "pellet" in area_name or "rocket" in area_name:
			if "boss" not in area_name and "enemy" not in area_name:
				is_player_projectile = true
	
	if is_player_projectile:
		trigger_snow_puff(area.global_position)
	
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
	
	# Destroy the bullet
	if area.is_in_group("bullets") or area.is_in_group("projectiles") or area.is_in_group("player_projectiles") or area.is_in_group("enemy_projectiles"):
		area.queue_free()
	elif area.has_method("_retire"):
		area._retire()
	elif area.name.contains("Bullet") or area.name.contains("Laser") or area.name.contains("Pellet") or area.name.contains("Rocket"):
		area.queue_free()


func _on_bullet_body_entered(body: Node2D) -> void:
	"""Handle bullet body collision."""
	var is_player_projectile := false
	if "owner_node" in body:
		var projectile_owner = body.owner_node
		if projectile_owner and projectile_owner.is_in_group("player"):
			is_player_projectile = true
	
	if not is_player_projectile:
		var body_name := body.name.to_lower()
		if "bullet" in body_name or "pellet" in body_name or "rocket" in body_name:
			if "boss" not in body_name and "enemy" not in body_name:
				is_player_projectile = true
	
	if is_player_projectile:
		trigger_snow_puff(body.global_position)
	
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


func set_boulder_seed(new_seed: int) -> void:
	"""Set the variation seed for this boulder."""
	variation_seed = new_seed
	if is_node_ready():
		if _sprite:
			_sprite.queue_free()
		if _collision_shape:
			_collision_shape.queue_free()
		_rng.seed = new_seed
		_create_boulder()
