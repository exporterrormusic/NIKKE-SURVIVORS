extends Area2D
class_name PristineCoreOrb

## Large red glowing orb dropped by bosses/elites or as wave rewards.
## Physically drops, waits for player, then flies to the core counter.

var speed := 900.0 # Faster flight to UI
var cores_value := 1 # How many cores this orb is worth

# Visual effect properties
const PRIMARY_COLOR := Color(1.0, 0.2, 0.15, 1.0) # Intense red
const SECONDARY_COLOR := Color(1.0, 0.4, 0.2, 1.0) # Orange-red accent
const GLOW_COLOR := Color(1.0, 0.15, 0.1, 0.7) # Red outer glow
const CORE_COLOR := Color(1.0, 0.7, 0.5, 1.0) # Hot white-orange core

const UISounds := preload("res://scripts/ui/UISoundManager.gd")


# State Machine
enum State {SPAWNING, IDLE, COLLECTING}
var _state: State = State.SPAWNING

var _age := 0.0
var _idle_time := 0.0
var _vis_timer := 0.0

var _spawn_position := Vector2.ZERO
var _visuals_root: Node2D = null
var _glow_sprite: Sprite2D = null
var _inner_glow: Sprite2D = null
var _core_sprite: Sprite2D = null
var _glow_texture: Texture2D = null
var _rng := RandomNumberGenerator.new()

# Trail particles
var _trail_particles: Array = []
const MAX_TRAIL_PARTICLES := 12

# Animation
const PULSE_SPEED := 4.0
const ROTATION_SPEED := 2.0
const BOB_SPEED := 3.0
const BOB_HEIGHT := 8.0 # Subtle bobbing (was 64 - way too much)

# Spawning Physics
var _velocity := Vector2.ZERO
const GRAVITY := 900.0
const FRICTION := 4.0
const BOUNCE := 0.6

func _ready() -> void:
	add_to_group("drops")
	_rng.randomize()
	_spawn_position = global_position
	
	# Initial "Pop" velocity
	var angle = _rng.randf_range(-PI / 1.2, -PI / 3.5) # Upward cone
	var speed = _rng.randf_range(300.0, 500.0)
	_velocity = Vector2.from_angle(angle) * speed
	
	# Use cached texture for glow
	_glow_texture = TextureCache.get_glow_texture_32()
	_create_visuals()
	
	# Set up collision for Player Pickup
	# Layer 5 (Items)
	collision_layer = 16
	# Detect Layer 2 (Player)
	collision_mask = 2
	
	body_entered.connect(_on_body_entered)
	
	# Ensure Monitorable for detection
	monitoring = true
	monitorable = false
	
	# Create Collision Shape
	var shape = CircleShape2D.new()
	shape.radius = 256.0 # Large pickup radius
	
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)

func _create_visuals() -> void:
	_visuals_root = Node2D.new()
	add_child(_visuals_root)
	
	# 1. Subtle Glow (Behind)
	var glow = Sprite2D.new()
	glow.texture = _glow_texture
	glow.modulate = Color(1.0, 0.3, 0.15, 0.85) # Intense visible glow
	glow.scale = Vector2(8.0, 8.0) # Larger glow for strong visibility
	
	# Make glow unshaded too
	var glow_mat = CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = glow_mat
	
	_visuals_root.add_child(glow)
	_glow_sprite = glow # Keep ref for pulsing
	
	# 2. Main Icon (Procedural Drawing)
	# We create a specific Node2D to handle the drawing
	var icon_drawer = Node2D.new()
	icon_drawer.script = _get_icon_drawer_script()
	icon_drawer.scale = Vector2(4.0, 4.0) # Matches previous relative scale, but radius reduced in script
	
	# Make icon unshaded to glow at night
	var icon_mat = CanvasItemMaterial.new()
	icon_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	icon_drawer.material = icon_mat
	
	_visuals_root.add_child(icon_drawer)
	
func _get_icon_drawer_script() -> GDScript:
	var script := preload("res://scripts/effects/visuals/PristineCoreIconDrawer.gd")
	return script

func _on_body_entered(body: Node2D) -> void:
	if _state == State.COLLECTING:
		return
		
	# Check if body is player (defensive check, mask should handle it)
	if body.is_in_group("player"):
		_start_collection()

func _physics_process(delta: float) -> void:
	_age += delta
	_vis_timer += delta
	_update_visuals(delta)
	_update_trail(delta)

	match _state:
		State.SPAWNING:
			_process_spawning(delta)
		State.IDLE:
			_process_idle(delta)
		State.COLLECTING:
			_process_collecting(delta)

func _process_spawning(delta: float) -> void:
	# Apply gravity
	_velocity.y += GRAVITY * delta
	
	# Move
	global_position += _velocity * delta
	
	# Apply heavy drag to simulate landing
	_velocity = _velocity.move_toward(Vector2.ZERO, FRICTION * 400.0 * delta)
	
	if _velocity.length_squared() < 100.0:
		_state = State.IDLE
		_spawn_position = global_position # Update anchor for bobbing

func _process_idle(delta: float) -> void:
	_idle_time += delta
	
	# Bobbing animation
	var bob_offset = sin(_idle_time * BOB_SPEED) * BOB_HEIGHT
	if _visuals_root:
		_visuals_root.position.y = bob_offset

func _start_collection() -> void:
	_state = State.COLLECTING
	UISounds.play_confirm()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func _process_collecting(delta: float) -> void:
	# Fly toward the core counter in the bottom-right
	var camera := get_viewport().get_camera_2d()
	if not camera:
		_finalize_collection()
		return
	
	var viewport_size := get_viewport_rect().size
	var screen_center := viewport_size / 2.0
	
	# Target: bottom-right corner where counter is (screen space -> world space)
	var target_screen := Vector2(viewport_size.x - 120, viewport_size.y - 50)
	var offset := (target_screen - screen_center) * camera.zoom
	var target_world := camera.global_position + offset
	
	var to_target := target_world - global_position
	var dist := to_target.length()
	var dir := to_target.normalized() if dist > 0 else Vector2.ZERO
	
	# Accelerate
	speed += 2000.0 * delta
	global_position += dir * speed * delta
	
	# Shrink visuals as it enters UI
	if dist < 300.0:
		var shrink_t = dist / 300.0
		scale = Vector2.ONE * shrink_t
	
	# Check if reached target
	if dist < 50.0:
		_finalize_collection()

func _finalize_collection() -> void:
	# Add cores to game state
	if GameManager:
		if GameManager.has_method("add_pristine_cores"):
			GameManager.add_pristine_cores(cores_value)
	
	# Find and flash the core counter
	var level := get_tree().current_scene
	if level:
		var counter_layer := level.get_node_or_null("CoreCounterLayer")
		if counter_layer:
			var counter := counter_layer.get_node_or_null("CoreCounter")
			if counter:
				var styled := counter.get_node_or_null("StyledContainer")
				if styled and styled.has_method("flash_collected"):
					styled.flash_collected()
				if styled and styled.has_method("update_count"):
					if GameManager:
						styled.update_count(GameManager.get_pristine_cores())
	queue_free()

func _spawn_collection_burst() -> void:
	pass

func _update_visuals(_delta: float) -> void:
	var pulse := sin(_vis_timer * PULSE_SPEED) * 0.5 + 0.5
	
	# Strong pulsing glow
	if _glow_sprite:
		var glow_scale := 7.0 + pulse * 2.0 # Bold pulsing glow
		_glow_sprite.scale = Vector2.ONE * glow_scale
		_glow_sprite.modulate.a = 0.7 + pulse * 0.3

func _update_trail(delta: float) -> void:
	# "Red Vapor" Effect: Always spawn rising smoke/vapor
	# Frequency matches frame rate for smooth looking vapor, or slightly throttled
	var spawn_rate = 0.05 # Spawn every 50ms
	if _state == State.COLLECTING: spawn_rate = 0.01 # Fast trail when collecting
	
	# Random spawn chance per frame relative to delta to control rate
	# Or just accumulate timer? Let's use simple probability for now
	if randf() < (delta / spawn_rate):
		var particle := {
			"pos": global_position + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-8, 8)) + (_visuals_root.position if _visuals_root else Vector2.ZERO),
			"vel": Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-70, -40)), # Rising up
			"life": 1.2,
			"max_life": 1.2,
			"size": _rng.randf_range(1.0, 2.0), # Larger and more visible
			"rotation": _rng.randf() * TAU,
			"rot_speed": _rng.randf_range(-2.0, 2.0),
			"node": null
		}
		
		var sprite := Sprite2D.new()
		sprite.texture = _glow_texture
		sprite.modulate = Color(1.0, 0.25, 0.2, 0.5) # Brighter red vapor
		sprite.scale = Vector2.ONE * particle["size"]
		sprite.global_position = particle["pos"]
		sprite.rotation = particle["rotation"]
		sprite.z_index = -1
		
		# Allow vapor to glow at night too?
		var mat = CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite.material = mat
		
		get_parent().add_child(sprite)
		particle["node"] = sprite
		
		_trail_particles.append(particle)
	
	# Spawn fire particles (brighter, faster rising sparks)
	if randf() < (delta / 0.08): # Fire sparks every ~80ms
		var fire_particle := {
			"pos": global_position + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-4, 4)) + (_visuals_root.position if _visuals_root else Vector2.ZERO),
			"vel": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-100, -60)), # Fast rising
			"life": 0.6,
			"max_life": 0.6,
			"size": _rng.randf_range(0.6, 1.2),
			"rotation": _rng.randf() * TAU,
			"rot_speed": _rng.randf_range(-4.0, 4.0),
			"node": null
		}
		
		var fire_sprite := Sprite2D.new()
		fire_sprite.texture = _glow_texture
		fire_sprite.modulate = Color(1.0, 0.7, 0.2, 0.8) # Orange-yellow fire
		fire_sprite.scale = Vector2.ONE * fire_particle["size"]
		fire_sprite.global_position = fire_particle["pos"]
		fire_sprite.rotation = fire_particle["rotation"]
		fire_sprite.z_index = 0 # Above vapor
		
		# Additive blend for fire glow
		var fire_mat = CanvasItemMaterial.new()
		fire_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		fire_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		fire_sprite.material = fire_mat
		
		get_parent().add_child(fire_sprite)
		fire_particle["node"] = fire_sprite
		
		_trail_particles.append(fire_particle)
		
	# Update existing particles
	var i := 0
	while i < _trail_particles.size():
		var p = _trail_particles[i]
		p["life"] -= delta
		if p["life"] <= 0 or not is_instance_valid(p["node"]):
			if is_instance_valid(p["node"]):
				p["node"].queue_free()
			_trail_particles.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta
			p["rotation"] += p["rot_speed"] * delta
			
			var t: float = p["life"] / p["max_life"]
			var node: Sprite2D = p["node"]
			node.global_position = p["pos"]
			node.rotation = p["rotation"]
			node.modulate.a = t * 0.4 # Fade out
			node.scale = Vector2.ONE * p["size"] * (0.5 + t * 0.5) # Shrink slightly
			i += 1

func _exit_tree() -> void:
	for p in _trail_particles:
		if is_instance_valid(p.get("node")):
			p["node"].queue_free()
	_trail_particles.clear()
