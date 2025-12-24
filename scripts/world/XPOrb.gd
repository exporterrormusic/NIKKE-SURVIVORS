extends Node2D

# Mystical Soul Orb - Enhanced XP pickup with visual effects

var speed = 1000
var player
var xp_bar # Reference to the actual ProgressBar node
var xp_value: int = 1 # XP granted when collected (set by enemy spawner)

# Visual effect properties
const PRIMARY_COLOR := Color(0.2, 0.6, 1.0, 1.0) # Bright blue
const SECONDARY_COLOR := Color(0.4, 0.8, 1.0, 1.0) # Light blue accent
const GLOW_COLOR := Color(0.1, 0.5, 1.0, 0.6) # Blue outer glow
const SPARKLE_COLOR := Color(0.9, 0.95, 1.0, 0.9) # White-blue sparkles

var _age := 0.0
var _bob_offset := 0.0
var _base_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _sprite: Sprite2D = null
var _glow_sprite: Sprite2D = null
var _inner_glow: Sprite2D = null
var _glow_texture: Texture2D = null
var _rng := RandomNumberGenerator.new()

# Trail particles (REMOVED for performance)
# const MAX_TRAIL_PARTICLES := 8

# Pulse animation (now 2.25x original speed)
const PULSE_SPEED := 9.0
const BOB_SPEED := 6.75
const BOB_AMPLITUDE := 3.0
const ROTATION_SPEED := 3.375

func _ready():
	_rng.randomize()
	_bob_offset = _rng.randf() * TAU # Random phase so orbs don't sync
	# Find player in the scene tree
	player = TargetCache.get_player()
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

func initialize(xp_amount: int, spawn_pos: Vector2) -> void:
	"""Initialize orb with XP value and position (called by enemy spawner)."""
	xp_value = xp_amount
	global_position = spawn_pos
	_base_position = spawn_pos
	_last_position = spawn_pos

func _exit_tree() -> void:
	# Clean up any trail particles still in the scene
	# for p in _trail_particles:
	# 	if is_instance_valid(p.get("node")):
	# 		p["node"].queue_free()
	# _trail_particles.clear()
	pass

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
	_inner_glow.modulate = Color(0.85, 0.9, 1.0, 0.9) # Bright white-blue center
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
		ProjectileCache.return_to_pool(self)
		return
	
	# Check if player is still valid (prevents error when player is freed)
	if not is_instance_valid(player) or not "xp" in player:
		ProjectileCache.return_to_pool(self)
		return
	
	_age += delta
	# PERFORMANCE: Only update visuals every 4th frame (was 2nd)
	# Use instance id to interlace updates so not all orbs update on same frame
	if (Engine.get_process_frames() + get_instance_id()) % 4 == 0:
		_update_visuals(delta * 4.0) # Compensate delta for skipped frames
	# _update_trail(delta) # Disabled for performance
	
	_last_position = global_position
	
	# PERFORMANCE: Throttled update
	var current_frame := Engine.get_process_frames()
	if (current_frame + get_instance_id()) % 2 == 0:
		var target_pos_world = TargetCache.get_xp_target_pos()
		if target_pos_world == Vector2.ZERO:
			ProjectileCache.return_to_pool(self)
			return
			
		var dir = (target_pos_world - global_position).normalized()
		
		# Calculate arc path that pushes toward screen edges
		var to_target: Vector2 = target_pos_world - global_position
		var distance_to_target: float = to_target.length()
		var perp := Vector2(-dir.y, dir.x) # Perpendicular to movement
		
		# Determine which side of screen the orb is on and push outward
		var camera_pos = TargetCache.get_player().global_position if TargetCache.get_player() else global_position
		var side_bias := 1.0 if global_position.x > camera_pos.x else -1.0
		
		# Arc strength peaks in the middle of the journey, fades near start/end
		var journey_progress := 1.0 - clampf(distance_to_target / 400.0, 0.0, 1.0)
		var arc_strength := sin(journey_progress * PI) * 120.0 # Strong outward arc
		
		# Apply arc force pushing toward screen edge
		var arc_offset: Vector2 = perp * side_bias * arc_strength * delta * 2.0 # Mult by 2 because update is half-rate
		
		position += dir * speed * delta * 2.0
		position += arc_offset
		
		# Add bobbing motion perpendicular to movement
		var bob := sin(_age * BOB_SPEED + _bob_offset) * BOB_AMPLITUDE
		position += perp * bob * delta * 20
		
		if distance_to_target < 30:
			_spawn_collection_burst()
			if player:
				player.add_xp(xp_value)
			ProjectileCache.return_to_pool(self)
		_spawn_collection_burst()
		if player:
			player.add_xp(xp_value)
		ProjectileCache.return_to_pool(self)

func _update_visuals(_delta: float) -> void:
	# SIMPLIFIED for performance - just basic pulsing, no color shifts or rotations
	var pulse := sin(_age * PULSE_SPEED) * 0.5 + 0.5
	
	# Outer glow simple pulse only
	if _glow_sprite:
		_glow_sprite.scale = Vector2.ONE * (1.3 + pulse * 0.3)
		_glow_sprite.modulate.a = 0.5 + pulse * 0.2
	
	# Inner glow simple pulse
	if _inner_glow:
		_inner_glow.scale = Vector2.ONE * (0.5 + pulse * 0.15)
	
	# Main sprite - no animation for performance
	# (Removed rotation and color shifting)

# Trail Logic Removed for Performance
func _update_trail(_delta: float) -> void:
	pass

func _spawn_trail_particle() -> void:
	pass

# Collection burst uses ShaderCache for shared material

func _spawn_collection_burst() -> void:
	# DISABLED for performance - spawning 4 Sprite2Ds per orb caused lag with many orbs
	pass

func _spawn_collection_burst_disabled() -> void:
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

	# Fallback - should use TextureCache instead
	return TextureCache.get_glow_texture_32()

func reset() -> void:
	_age = 0.0
	_rng.randomize()
	_bob_offset = _rng.randf() * TAU
	_base_position = position
	_last_position = global_position
	
	# Ensure player reference is valid
	if not player or not is_instance_valid(player):
		player = TargetCache.get_player()
		
	# Ensure xp_bar reference is valid
	if not xp_bar or not is_instance_valid(xp_bar):
		if player and "xp_ui" in player:
			var xp_ui = player.xp_ui
			if xp_ui:
				xp_bar = xp_ui.get_node_or_null("ProgressBar")
	
	# Reset visuals
	modulate = Color.WHITE
	scale = Vector2.ONE
	rotation = 0.0
	if _glow_sprite:
		_glow_sprite.scale = Vector2(1.5, 1.5)
		_glow_sprite.rotation = 0.0
	if _inner_glow:
		_inner_glow.scale = Vector2(0.6, 0.6)
		_inner_glow.rotation = 0.0