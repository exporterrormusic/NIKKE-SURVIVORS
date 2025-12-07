extends Area2D

# Mystical Soul Orb - Enhanced XP pickup with visual effects

var speed = 1000
var player
var xp_bar  # Reference to the actual ProgressBar node

# Visual effect properties
const PRIMARY_COLOR := Color(0.2, 0.6, 1.0, 1.0)      # Bright blue
const SECONDARY_COLOR := Color(0.4, 0.8, 1.0, 1.0)     # Light blue accent
const GLOW_COLOR := Color(0.1, 0.5, 1.0, 0.6)          # Blue outer glow
const SPARKLE_COLOR := Color(0.9, 0.95, 1.0, 0.9)      # White-blue sparkles

var _age := 0.0
var _bob_offset := 0.0
var _base_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _sprite: Sprite2D = null
var _glow_sprite: Sprite2D = null
var _inner_glow: Sprite2D = null
var _glow_texture: Texture2D = null
var _rng := RandomNumberGenerator.new()

# Trail particles
var _trail_particles: Array = []
const MAX_TRAIL_PARTICLES := 8

# Pulse animation (now 2.25x original speed)
const PULSE_SPEED := 9.0
const BOB_SPEED := 6.75
const BOB_AMPLITUDE := 3.0
const ROTATION_SPEED := 3.375

func _ready():
	_rng.randomize()
	_bob_offset = _rng.randf() * TAU  # Random phase so orbs don't sync
	# Find player in the scene tree
	player = get_tree().get_first_node_in_group("player")
	if not player:
		var level = get_tree().current_scene
		if level and level.has_node("Player"):
			player = level.get_node("Player")
	# Get xp_bar from the XPUI node
	if player and "xp_ui" in player:
		var xp_ui = player.xp_ui
		if xp_ui:
			xp_bar = xp_ui.get_node_or_null("ProgressBar")
	_sprite = $Sprite2D if has_node("Sprite2D") else null
	_base_position = position
	_last_position = global_position
	
	# Use cached texture for performance
	_glow_texture = TextureCache.get_glow_texture_32()
	_create_glow_layers()

func _exit_tree() -> void:
	# Clean up any trail particles still in the scene
	for p in _trail_particles:
		if is_instance_valid(p.get("node")):
			p["node"].queue_free()
	_trail_particles.clear()

func _create_glow_layers() -> void:
	# Get shared additive material (cached, not created per orb)
	var additive_mat := ShaderCache.get_additive_material()
	
	# Outer glow (large, soft)
	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = _glow_texture
	_glow_sprite.centered = true
	_glow_sprite.modulate = GLOW_COLOR
	_glow_sprite.scale = Vector2(1.5, 1.5)
	_glow_sprite.z_index = -1
	_glow_sprite.material = additive_mat
	add_child(_glow_sprite)
	
	# Inner glow (bright white/blue core)
	_inner_glow = Sprite2D.new()
	_inner_glow.texture = _glow_texture
	_inner_glow.centered = true
	_inner_glow.modulate = Color(0.85, 0.9, 1.0, 0.9)  # Bright white-blue center
	_inner_glow.scale = Vector2(0.6, 0.6)
	_inner_glow.z_index = 1
	_inner_glow.material = additive_mat
	add_child(_inner_glow)
	
	# Tint the main sprite
	if _sprite:
		_sprite.modulate = PRIMARY_COLOR
		_sprite.z_index = 2

func _physics_process(delta):
	if not xp_bar:
		queue_free()
		return
	
	_age += delta
	_update_visuals(delta)
	_update_trail(delta)
	
	var progress = float(player.xp) / player.xp_to_next
	var bar_rect = xp_bar.get_global_rect()
	var target_x = bar_rect.position.x + progress * bar_rect.size.x
	var target_pos_screen = Vector2(target_x, bar_rect.get_center().y)
	
	# Convert screen position to world position
	var camera = get_viewport().get_camera_2d()
	var viewport_size = get_viewport_rect().size
	var screen_center = viewport_size / 2
	var offset = (target_pos_screen - screen_center) * camera.zoom
	var target_pos_world = camera.global_position + offset
	
	_last_position = global_position
	
	var dir = (target_pos_world - global_position).normalized()
	
	# Calculate arc path that pushes toward screen edges
	var to_target: Vector2 = target_pos_world - global_position
	var distance_to_target: float = to_target.length()
	var perp := Vector2(-dir.y, dir.x)  # Perpendicular to movement
	
	# Determine which side of screen the orb is on and push outward
	var orb_screen_pos: Vector2 = global_position - camera.global_position + screen_center
	var side_bias := 1.0 if orb_screen_pos.x > screen_center.x else -1.0
	
	# Arc strength peaks in the middle of the journey, fades near start/end
	var journey_progress := 1.0 - clampf(distance_to_target / 400.0, 0.0, 1.0)
	var arc_strength := sin(journey_progress * PI) * 120.0  # Strong outward arc
	
	# Apply arc force pushing toward screen edge
	var arc_offset: Vector2 = perp * side_bias * arc_strength * delta
	
	position += dir * speed * delta
	position += arc_offset
	
	# Add bobbing motion perpendicular to movement
	var bob := sin(_age * BOB_SPEED + _bob_offset) * BOB_AMPLITUDE
	position += perp * bob * delta * 10
	
	if global_position.distance_to(target_pos_world) < 20:
		_spawn_collection_burst()
		if player:
			player.add_xp(1)
		queue_free()

func _update_visuals(delta: float) -> void:
	var pulse := sin(_age * PULSE_SPEED) * 0.5 + 0.5
	var fast_pulse := sin(_age * PULSE_SPEED * 2.5) * 0.3 + 0.7
	
	# Outer glow pulses
	if _glow_sprite:
		var glow_scale := 1.3 + pulse * 0.4
		_glow_sprite.scale = Vector2.ONE * glow_scale
		_glow_sprite.modulate.a = 0.4 + pulse * 0.3
		_glow_sprite.rotation += delta * ROTATION_SPEED * 0.5
	
	# Inner glow counter-rotates and pulses faster
	if _inner_glow:
		var inner_scale := 0.5 + fast_pulse * 0.2
		_inner_glow.scale = Vector2.ONE * inner_scale
		_inner_glow.modulate.a = 0.7 + fast_pulse * 0.3
		_inner_glow.rotation -= delta * ROTATION_SPEED
		
		# Color shift between bright white and warm white-blue
		var color_t := sin(_age * 4.5) * 0.5 + 0.5
		var base_white := Color(0.9, 0.95, 1.0, 1.0)
		var warm_white := Color(0.7, 0.8, 1.0, 1.0)
		var shifted_color := base_white.lerp(warm_white, color_t * 0.5)
		_inner_glow.modulate = Color(shifted_color.r, shifted_color.g, shifted_color.b, 0.7 + fast_pulse * 0.3)
	
	# Main sprite subtle effects
	if _sprite:
		_sprite.rotation += delta * ROTATION_SPEED * 0.3
		var sprite_scale := 1.0 + fast_pulse * 0.1
		_sprite.scale = Vector2.ONE * sprite_scale
		
		# Color shift
		var color_t := sin(_age * 2.25) * 0.5 + 0.5
		_sprite.modulate = PRIMARY_COLOR.lerp(SECONDARY_COLOR, color_t * 0.3)

func _update_trail(delta: float) -> void:
	var velocity := global_position - _last_position
	var speed_factor: float = velocity.length() / (speed * delta) if delta > 0 else 0.0
	
	# Only spawn trail when moving fast
	if speed_factor > 0.3 and _rng.randf() < 0.4:
		_spawn_trail_particle()
	
	# Update existing trail particles
	var i := 0
	while i < _trail_particles.size():
		var p: Dictionary = _trail_particles[i]
		p["age"] += delta
		p["alpha"] = maxf(0, 1.0 - p["age"] / p["lifetime"])
		
		if p["age"] >= p["lifetime"]:
			if is_instance_valid(p["node"]):
				p["node"].queue_free()
			_trail_particles.remove_at(i)
		else:
			if is_instance_valid(p["node"]):
				p["node"].modulate.a = p["alpha"] * 0.7
				p["node"].scale = Vector2.ONE * (0.3 + p["alpha"] * 0.3)
			i += 1

func _spawn_trail_particle() -> void:
	if _trail_particles.size() >= MAX_TRAIL_PARTICLES:
		return
	
	var particle := Sprite2D.new()
	particle.texture = _glow_texture
	particle.centered = true
	particle.global_position = global_position + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))
	particle.scale = Vector2(0.4, 0.4)
	
	var spark_color := SPARKLE_COLOR if _rng.randf() > 0.5 else PRIMARY_COLOR
	particle.modulate = spark_color
	
	# Use shared additive material
	particle.material = ShaderCache.get_additive_material()
	
	get_parent().add_child(particle)
	
	_trail_particles.append({
		"node": particle,
		"age": 0.0,
		"lifetime": _rng.randf_range(0.2, 0.4),
		"alpha": 1.0
	})

# Collection burst uses ShaderCache for shared material

func _spawn_collection_burst() -> void:
	# Use shared additive material from ShaderCache
	var additive_mat := ShaderCache.get_additive_material()
	
	# Spawn fewer sparkles for performance (4 instead of 8)
	var burst_count := 4
	for i in range(burst_count):
		var angle := (TAU / burst_count) * i + _rng.randf_range(-0.2, 0.2)
		
		var spark := Sprite2D.new()
		spark.texture = _glow_texture
		spark.centered = true
		spark.global_position = global_position
		spark.scale = Vector2(0.5, 0.5)
		spark.modulate = SPARKLE_COLOR if i % 2 == 0 else PRIMARY_COLOR
		spark.material = additive_mat
		
		get_parent().add_child(spark)
		
		# Animate with tween - ensure cleanup happens
		var tween := spark.create_tween()
		tween.set_parallel(true)
		
		var end_pos := global_position + Vector2(cos(angle), sin(angle)) * _rng.randf_range(20, 35)
		tween.tween_property(spark, "global_position", end_pos, 0.25).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "modulate:a", 0.0, 0.25).set_ease(Tween.EASE_IN)
		tween.tween_property(spark, "scale", Vector2(0.1, 0.1), 0.25)
		
		# Use a safer cleanup method - free after delay even if tween fails
		tween.chain().tween_callback(func(): 
			if is_instance_valid(spark):
				spark.queue_free()
		)

func _create_radial_glow_texture(_size: int) -> Texture2D:
	# Fallback - should use TextureCache instead
	return TextureCache.get_glow_texture_32()