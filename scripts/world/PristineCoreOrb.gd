extends Area2D
class_name PristineCoreOrb

## Large red glowing orb dropped by bosses/elites that flies to the core counter

var speed := 800.0
var cores_value := 1  # How many cores this orb is worth

# Visual effect properties
const PRIMARY_COLOR := Color(1.0, 0.2, 0.15, 1.0)       # Intense red
const SECONDARY_COLOR := Color(1.0, 0.4, 0.2, 1.0)      # Orange-red accent
const GLOW_COLOR := Color(1.0, 0.15, 0.1, 0.7)          # Red outer glow
const CORE_COLOR := Color(1.0, 0.7, 0.5, 1.0)           # Hot white-orange core

var _age := 0.0
var _spawn_position := Vector2.ZERO
var _glow_sprite: Sprite2D = null
var _inner_glow: Sprite2D = null
var _core_sprite: Sprite2D = null
var _glow_texture: Texture2D = null
var _rng := RandomNumberGenerator.new()
var _collected := false

# Trail particles
var _trail_particles: Array = []
const MAX_TRAIL_PARTICLES := 12

# Animation
const PULSE_SPEED := 8.0
const ROTATION_SPEED := 4.0
const ORB_SIZE := 48.0  # Large orb

# Initial burst movement before flying to counter
var _burst_timer := 0.0
const BURST_DURATION := 0.3
var _burst_direction := Vector2.ZERO

func _ready() -> void:
	_rng.randomize()
	_spawn_position = global_position
	
	# Random burst direction (upward bias)
	_burst_direction = Vector2(
		_rng.randf_range(-0.5, 0.5),
		_rng.randf_range(-1.0, -0.3)
	).normalized()
	
	# Use cached texture for glow
	_glow_texture = TextureCache.get_glow_texture_32()
	_create_visuals()
	
	# Set up collision
	collision_layer = 0
	collision_mask = 0  # No collision needed, purely visual

func _create_visuals() -> void:
	var additive_mat := ShaderCache.get_additive_material()
	
	# Outer glow (large, intense red)
	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = _glow_texture
	_glow_sprite.centered = true
	_glow_sprite.modulate = GLOW_COLOR
	_glow_sprite.scale = Vector2(3.0, 3.0)  # Large glow
	_glow_sprite.z_index = -1
	_glow_sprite.material = additive_mat
	add_child(_glow_sprite)
	
	# Middle glow layer
	var mid_glow := Sprite2D.new()
	mid_glow.texture = _glow_texture
	mid_glow.centered = true
	mid_glow.modulate = Color(1.0, 0.3, 0.15, 0.8)
	mid_glow.scale = Vector2(1.8, 1.8)
	mid_glow.z_index = 0
	mid_glow.material = additive_mat
	add_child(mid_glow)
	
	# Inner glow (bright white-orange core)
	_inner_glow = Sprite2D.new()
	_inner_glow.texture = _glow_texture
	_inner_glow.centered = true
	_inner_glow.modulate = CORE_COLOR
	_inner_glow.scale = Vector2(1.0, 1.0)
	_inner_glow.z_index = 1
	_inner_glow.material = additive_mat
	add_child(_inner_glow)
	
	# Hot white center
	_core_sprite = Sprite2D.new()
	_core_sprite.texture = _glow_texture
	_core_sprite.centered = true
	_core_sprite.modulate = Color(1.0, 0.95, 0.9, 1.0)
	_core_sprite.scale = Vector2(0.5, 0.5)
	_core_sprite.z_index = 2
	_core_sprite.material = additive_mat
	add_child(_core_sprite)

func _physics_process(delta: float) -> void:
	if _collected:
		return
	
	_age += delta
	_update_visuals(delta)
	_update_trail(delta)
	
	# Initial burst outward
	if _burst_timer < BURST_DURATION:
		_burst_timer += delta
		var burst_speed := 400.0 * (1.0 - _burst_timer / BURST_DURATION)
		global_position += _burst_direction * burst_speed * delta
		return
	
	# Fly toward the core counter in the bottom-right
	var camera := get_viewport().get_camera_2d()
	if not camera:
		queue_free()
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
	
	# Arc toward edge of screen for visual flair
	var perp := Vector2(-dir.y, dir.x)
	var orb_screen_pos := global_position - camera.global_position + screen_center
	var side_bias := 1.0 if orb_screen_pos.x > screen_center.x else -1.0
	var journey_progress := 1.0 - clampf(dist / 600.0, 0.0, 1.0)
	var arc_strength := sin(journey_progress * PI) * 100.0
	var arc_offset := perp * side_bias * arc_strength * delta
	
	# Accelerate as it gets closer
	var speed_mult := 1.0 + journey_progress * 1.5
	global_position += dir * speed * speed_mult * delta
	global_position += arc_offset
	
	# Check if reached target
	if dist < 50:
		_collect()

func _collect() -> void:
	if _collected:
		return
	_collected = true
	
	# Add cores to game state
	if GameState:
		GameState.add_pristine_cores(cores_value)
	
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
					styled.update_count(GameState.get_pristine_cores())
	
	# Spawn collection burst effect
	_spawn_collection_burst()
	
	queue_free()

func _spawn_collection_burst() -> void:
	# Spawn particles radiating outward
	for i in range(12):
		var particle := Sprite2D.new()
		particle.texture = _glow_texture
		particle.modulate = PRIMARY_COLOR
		particle.scale = Vector2(0.4, 0.4)
		particle.global_position = global_position
		particle.z_index = 100
		
		var angle := float(i) / 12.0 * TAU
		var vel := Vector2.from_angle(angle) * 300.0
		
		get_parent().add_child(particle)
		
		# Animate particle
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "global_position", particle.global_position + vel * 0.3, 0.3)
		tween.tween_property(particle, "modulate:a", 0.0, 0.3)
		tween.tween_property(particle, "scale", Vector2.ZERO, 0.3)
		tween.chain().tween_callback(particle.queue_free)

func _update_visuals(delta: float) -> void:
	var pulse := sin(_age * PULSE_SPEED) * 0.5 + 0.5
	var fast_pulse := sin(_age * PULSE_SPEED * 2.0) * 0.3 + 0.7
	
	# Outer glow pulses intensely
	if _glow_sprite:
		var glow_scale := 2.5 + pulse * 0.8
		_glow_sprite.scale = Vector2.ONE * glow_scale
		_glow_sprite.modulate.a = 0.5 + pulse * 0.4
		_glow_sprite.rotation += delta * ROTATION_SPEED * 0.3
	
	# Inner glow counter-rotates
	if _inner_glow:
		var inner_scale := 0.9 + fast_pulse * 0.3
		_inner_glow.scale = Vector2.ONE * inner_scale
		_inner_glow.modulate.a = 0.8 + fast_pulse * 0.2
		_inner_glow.rotation -= delta * ROTATION_SPEED
		
		# Color shift between red and orange
		var color_t := sin(_age * 5.0) * 0.5 + 0.5
		_inner_glow.modulate = CORE_COLOR.lerp(SECONDARY_COLOR, color_t * 0.4)
	
	# Core pulses white-hot
	if _core_sprite:
		var core_scale := 0.4 + fast_pulse * 0.15
		_core_sprite.scale = Vector2.ONE * core_scale
		_core_sprite.rotation += delta * ROTATION_SPEED * 2.0

func _update_trail(delta: float) -> void:
	# Spawn trail particles
	if _age > 0.05 and randf() < 0.6:
		var particle := {
			"pos": global_position + Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8)),
			"vel": Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-30, 10)),
			"life": 0.4,
			"max_life": 0.4,
			"size": _rng.randf_range(0.3, 0.6),
			"node": null
		}
		
		var sprite := Sprite2D.new()
		sprite.texture = _glow_texture
		sprite.modulate = PRIMARY_COLOR
		sprite.scale = Vector2.ONE * particle["size"]
		sprite.global_position = particle["pos"]
		sprite.z_index = -2
		sprite.material = ShaderCache.get_additive_material()
		get_parent().add_child(sprite)
		particle["node"] = sprite
		
		_trail_particles.append(particle)
		if _trail_particles.size() > MAX_TRAIL_PARTICLES:
			var old = _trail_particles.pop_front()
			if is_instance_valid(old["node"]):
				old["node"].queue_free()
	
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
			var t: float = p["life"] / p["max_life"]
			var node: Sprite2D = p["node"]
			node.global_position = p["pos"]
			node.modulate.a = t * 0.8
			node.scale = Vector2.ONE * p["size"] * t
			i += 1

func _exit_tree() -> void:
	for p in _trail_particles:
		if is_instance_valid(p.get("node")):
			p["node"].queue_free()
	_trail_particles.clear()
