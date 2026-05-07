extends Node2D
class_name AmbientParticleSystem

# Biome-themed ambient floating particles
# - Snow: white snowflakes drifting
# - Sakura: pink petals floating gently
# - Grasslands: floating seeds/pollen, fireflies at night
# - Dunes: dust motes, sand particles

var _rng := RandomNumberGenerator.new()
var _particles: Array = []
var _age := 0.0
var _biome_id: StringName = &""
var _is_night := false
var _camera: Camera2D = null
var _spawn_timer := 0.0
var _ambient_compensation: float = 1.0

const MAX_PARTICLES := 280 # Increased for richer atmosphere
const SPAWN_INTERVAL := 0.08

# Particle type configurations
var _particle_config := {}

func _ready() -> void:
	_rng.randomize()
	z_index = 50 # Above most things, below UI
	# Don't use top_level - particles should be in world space
	set_process(true)
	
	var environment_controller = get_tree().root.find_child("EnvironmentController", true, false)
	if environment_controller and environment_controller is EnvironmentController:
		environment_controller.modulate_changed.connect(_on_modulate_changed)
	
	_setup_particle_configs()

func _setup_particle_configs() -> void:
	# Snowfield particles
	_particle_config[&"snowfield"] = {
		"types": [
			{
				"color": Color(1.0, 1.0, 1.0, 0.7),
				"size_range": Vector2(2, 5),
				"speed_range": Vector2(20, 60),
				"drift_range": Vector2(15, 40),
				"lifetime_range": Vector2(4, 8),
				"shape": "circle",
				"glow": false
			}
		],
		"density": 1.8 # Increased for more atmospheric snow
	}
	
	# Sakura grove particles - cherry blossom petals
	_particle_config[&"sakura_grove"] = {
		"types": [
			{
				"color": Color(1.0, 0.85, 0.88, 0.75), # Soft blush pink (desaturated)
				"size_range": Vector2(10, 16),
				"speed_range": Vector2(25, 50),
				"drift_range": Vector2(40, 80),
				"lifetime_range": Vector2(6, 12),
				"shape": "petal",
				"glow": false
			},
			{
				"color": Color(0.98, 0.88, 0.90, 0.7), # Pale peach-pink
				"size_range": Vector2(8, 14),
				"speed_range": Vector2(30, 60),
				"drift_range": Vector2(35, 70),
				"lifetime_range": Vector2(5, 10),
				"shape": "petal",
				"glow": false
			},
			{
				"color": Color(1.0, 0.92, 0.94, 0.65), # Almost white with hint of pink
				"size_range": Vector2(6, 11),
				"speed_range": Vector2(20, 45),
				"drift_range": Vector2(30, 65),
				"lifetime_range": Vector2(5, 10),
				"shape": "petal",
				"glow": false
			}
		],
		"density": 3.0, # Increased for denser petal coverage
		"types_night": [
			{
				"color": Color(1.0, 0.9, 0.4, 0.9),
				"size_range": Vector2(3, 6),
				"speed_range": Vector2(10, 30),
				"drift_range": Vector2(15, 40),
				"lifetime_range": Vector2(4, 8),
				"shape": "firefly",
				"glow": true,
				"pulse_speed": 1.5,
				"move_angle": - 90.0 # Float UP
			}
		],
		"density_night": 1.2 # Increased firefly density
	}
	
	# Grasslands - pollen/seeds during day, fireflies at night
	_particle_config[&"grasslands"] = {
		"types": [
			{
				"color": Color(1.0, 1.0, 0.8, 0.5),
				"size_range": Vector2(1.5, 3),
				"speed_range": Vector2(5, 20),
				"drift_range": Vector2(10, 30),
				"lifetime_range": Vector2(6, 12),
				"shape": "circle",
				"glow": false
			}
		],
		"types_night": [
			{
				"color": Color(0.8, 1.0, 0.5, 0.9),
				"size_range": Vector2(2, 4),
				"speed_range": Vector2(8, 25),
				"drift_range": Vector2(20, 50),
				"lifetime_range": Vector2(3, 6),
				"shape": "firefly",
				"glow": true,
				"pulse_speed": 1.5
			}
		],
		"density": 1.2, # Increased pollen density
		"density_night": 1.0 # More fireflies
	}
	
	# Dunes - dust and sand
	_particle_config[&"dunes"] = {
		"types": [
			{
				"color": Color(0.9, 0.8, 0.6, 0.4),
				"size_range": Vector2(1, 3),
				"speed_range": Vector2(30, 80),
				"drift_range": Vector2(5, 15),
				"lifetime_range": Vector2(3, 6),
				"shape": "circle",
				"glow": false
			},
			{
				"color": Color(0.95, 0.85, 0.7, 0.3),
				"size_range": Vector2(2, 5),
				"speed_range": Vector2(40, 100),
				"drift_range": Vector2(8, 20),
				"lifetime_range": Vector2(2, 5),
				"shape": "dust",
				"glow": false
			}
		],
		"density": 2.2 # Increased dust density
	}
	
	# Rain Forest - rain particles
	_particle_config[&"rain_forest"] = {
		"types": [
			{
				"color": Color(0.9, 0.95, 1.0, 0.8),
				"size_range": Vector2(3, 6), # Larger for visibility
				"speed_range": Vector2(800, 1200), # Even faster
				"drift_range": Vector2(50, 150), # More sideways drift
				"lifetime_range": Vector2(1, 2), # Shorter lifetime
				"shape": "rain_streak",
				"glow": false
			}
		],
		"density": 120.0 # Reduced from 600 for performance
	}

func configure(biome_id: StringName, is_night: bool) -> void:
	_biome_id = biome_id
	_is_night = is_night
	_particles.clear()
	
	# Pre-fill the screen with particles so it doesn't start empty
	_prefill_particles()

func _prefill_particles() -> void:
	# Get camera early if possible
	if _camera == null:
		var viewport := get_viewport()
		if viewport:
			_camera = viewport.get_camera_2d()
	
	var config = _particle_config.get(_biome_id, null)
	if not config:
		return
	
	var types: Array = config.get("types_night", config.get("types", [])) if _is_night else config.get("types", [])
	if types.is_empty():
		return
	
	var view_size := _get_view_size()
	var camera_pos := _camera.global_position if _camera else Vector2.ZERO
	
	# Spawn particles distributed across the screen with varied ages
	var particles_to_spawn := int(MAX_PARTICLES * 0.8) # Fill to 80%
	for i in range(particles_to_spawn):
		var type_config: Dictionary = types[_rng.randi() % types.size()]
		
		var size_range: Vector2 = type_config.get("size_range", Vector2(2, 4))
		var speed_range: Vector2 = type_config.get("speed_range", Vector2(20, 50))
		var drift_range: Vector2 = type_config.get("drift_range", Vector2(10, 30))
		var lifetime_range: Vector2 = type_config.get("lifetime_range", Vector2(4, 8))
		
		# Spawn across the ENTIRE view area, not just above
		var spawn_pos := Vector2(
			camera_pos.x + _rng.randf_range(-view_size.x * 0.7, view_size.x * 0.7),
			camera_pos.y + _rng.randf_range(-view_size.y * 0.6, view_size.y * 0.6)
		)
		
		var lifetime := _rng.randf_range(lifetime_range.x, lifetime_range.y)
		# Start with random age so particles are at different stages
		var starting_age := _rng.randf_range(0.0, lifetime * 0.7)
		
		var particle := {
			"position": spawn_pos,
			"velocity": Vector2(_rng.randf_range(-drift_range.x, drift_range.y), _rng.randf_range(speed_range.x, speed_range.y)),
			"size": _rng.randf_range(size_range.x, size_range.y),
			"color": type_config.get("color", Color.WHITE),
			"shape": type_config.get("shape", "circle"),
			"glow": type_config.get("glow", false),
			"pulse_speed": type_config.get("pulse_speed", 0.0),
			"rotation": _rng.randf() * TAU,
			"rotation_speed": _rng.randf_range(-2, 2),
			"lifetime": lifetime,
			"age": starting_age,
			"phase": _rng.randf() * TAU,
			"drift_phase": _rng.randf() * TAU,
			"alpha": 1.0
		}
		_particles.append(particle)

func _process(delta: float) -> void:
	_age += delta
	
	# Always fetch active camera to ensure we follow player after camera switches
	var viewport := get_viewport()
	if viewport:
		_camera = viewport.get_camera_2d()
	
	# DON'T follow camera - stay at origin, particles use world positions
	
	# Spawn particles
	_spawn_timer += delta
	var config = _particle_config.get(_biome_id, null)
	if config:
		var density: float = config.get("density_night", config.get("density", 1.0)) if _is_night else config.get("density", 1.0)
		var spawn_rate := SPAWN_INTERVAL / density
		
		# Prevent infinite accumulation if max particles reached
		if _spawn_timer > spawn_rate * 2.0:
			_spawn_timer = spawn_rate * 2.0
		
		while _spawn_timer >= spawn_rate and _particles.size() < MAX_PARTICLES:
			_spawn_timer -= spawn_rate
			_spawn_particle(config)
	
	# Update particles
	_update_particles(delta)
	
	# Only redraw if we have particles (reduces overhead in menus/empty scenes)
	if _particles.size() > 0:
		queue_redraw()

func _spawn_particle(config: Dictionary) -> void:
	var types: Array = config.get("types_night", config.get("types", [])) if _is_night else config.get("types", [])
	if types.is_empty():
		return
	
	var type_config: Dictionary = types[_rng.randi() % types.size()]
	
	# Spawn in world space around camera
	var view_size := _get_view_size()
	var camera_pos := _camera.global_position if _camera else Vector2.ZERO
	
	# Default: Start above view (falling)
	var spawn_y_min_factor = -0.8
	var spawn_y_max_factor = -0.4
	
	# Custom spawn area for rising particles
	var move_angle = type_config.get("move_angle", 75.0)
	if move_angle < 0: # Rising (e.g. -90 for up)
		spawn_y_min_factor = 0.4
		spawn_y_max_factor = 0.8
	
	var spawn_pos := Vector2(
		camera_pos.x + _rng.randf_range(-view_size.x * 0.7, view_size.x * 0.7),
		camera_pos.y + _rng.randf_range(view_size.y * spawn_y_min_factor, view_size.y * spawn_y_max_factor)
	)
	
	var size_range: Vector2 = type_config.get("size_range", Vector2(2, 4))
	var speed_range: Vector2 = type_config.get("speed_range", Vector2(20, 50))
	var drift_range: Vector2 = type_config.get("drift_range", Vector2(10, 30))
	var lifetime_range: Vector2 = type_config.get("lifetime_range", Vector2(4, 8))
	
	var config_angle = type_config.get("move_angle", 90.0) # Default to straight down
	
	var particle := {
		"position": spawn_pos,
		"velocity": _get_velocity_from_angle(speed_range, drift_range, config_angle),
		"size": _rng.randf_range(size_range.x, size_range.y),
		"color": type_config.get("color", Color.WHITE),
		"shape": type_config.get("shape", "circle"),
		"glow": type_config.get("glow", false),
		"pulse_speed": type_config.get("pulse_speed", 0.0),
		"rotation": _rng.randf() * TAU,
		"rotation_speed": _rng.randf_range(-2, 2),
		"lifetime": _rng.randf_range(lifetime_range.x, lifetime_range.y),
		"age": 0.0,
		"phase": _rng.randf() * TAU,
		"drift_phase": _rng.randf() * TAU,
		"alpha": 1.0,
		"opacity_mult": 0.6 if type_config.get("shape") == "firefly" else 1.0
	}
	_particles.append(particle)

func _get_velocity_from_angle(speed_range: Vector2, drift_range: Vector2, angle_deg: float) -> Vector2:
	var base_angle := deg_to_rad(angle_deg)
	var angle_variation := deg_to_rad(15.0) # More variation
	var angle := base_angle + _rng.randf_range(-angle_variation, angle_variation)
	
	var speed := _rng.randf_range(speed_range.x, speed_range.y)
	var direction := Vector2(cos(angle), sin(angle))
	
	# Add some instability
	if drift_range.length() > 0:
		var drift_strength = _rng.randf_range(0.0, drift_range.x * 0.01)
		direction.x += drift_strength * (_rng.randf() * 2.0 - 1.0)
	
	return direction * speed

func _update_particles(delta: float) -> void:
	# Always fetch active camera to prevent stale reference
	var viewport := get_viewport()
	if viewport:
		_camera = viewport.get_camera_2d()
	
	var view_size := _get_view_size()
	var camera_pos := _camera.global_position if _camera else Vector2.ZERO
	# Slightly larger than view for wrap-around
	var screen_rect := Rect2(camera_pos - view_size * 0.7, view_size * 1.4)
	
	# WRAP-AROUND LOGIC
	# Use world bounds if available, otherwise fallback to camera view
	var bounds: Rect2 = _get_active_bounds(screen_rect)

	for i in range(_particles.size() - 1, -1, -1):
		var p: Dictionary = _particles[i]
		p["age"] += delta
		p["lifetime"] -= delta
		
		# Movement
		p["position"] += p["velocity"] * delta
		
		# Add drift/wobble
		p["drift_phase"] += delta * 2.0
		p["phase"] += delta * p["rotation_speed"]
		
		# Apply wobble to position without changing base velocity
		# This gives "floating" feel
		var wobble_x = sin(p["drift_phase"]) * 10.0 * delta
		p["position"].x += wobble_x
		
		if not bounds.has_point(p["position"]):
			if p["age"] > 1.0:
				_wrap_particle(p, bounds)
		
		# Remove dead
		if p["lifetime"] <= 0:
			_particles.remove_at(i)
			continue
		
		# Fade in/out
		var life_ratio: float = p["age"] / p["lifetime"]
		if life_ratio < 0.1:
			p["alpha"] = life_ratio / 0.1
		elif life_ratio > 0.7:
			p["alpha"] = (1.0 - life_ratio) / 0.3
		else:
			p["alpha"] = 1.0
		
		# Apply firefly opacity reduction (pre-calculated)
		p["alpha"] *= p.get("opacity_mult", 1.0)
		
		# Pulse for glowing particles
		if p["glow"] and p["pulse_speed"] > 0:
			var pulse := sin(p["age"] * p["pulse_speed"] + p["phase"])
			# Avoid full invisibility (0.2 to 1.0 range)
			p["alpha"] *= 0.6 + pulse * 0.4
			
		_particles[i] = p

func _wrap_particle(p: Dictionary, rect: Rect2) -> void:
	# If particle leaves one side, wrap to the opposite
	# Add small buffer to prevent popping
	var buffer = 50.0
	
	if p["position"].x < rect.position.x - buffer:
		p["position"].x = rect.end.x + buffer
	elif p["position"].x > rect.end.x + buffer:
		p["position"].x = rect.position.x - buffer
		
	if p["position"].y < rect.position.y - buffer:
		p["position"].y = rect.end.y + buffer
	elif p["position"].y > rect.end.y + buffer:
		p["position"].y = rect.position.y - buffer

var _cached_environment_controller: Node = null

func _get_active_bounds(view_rect: Rect2) -> Rect2:
	if not is_instance_valid(_cached_environment_controller):
		_cached_environment_controller = get_tree().root.find_child("EnvironmentController", true, false)
	
	if _cached_environment_controller and _cached_environment_controller.has_method("get_world_bounds"):
		var world_bounds: Rect2 = _cached_environment_controller.get_world_bounds()
		if world_bounds.size != Vector2.ZERO:
			# Pad bounds slightly to allow particles to drift in/out smoothly
			return world_bounds.grow(100.0)
	return view_rect

func _get_view_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(1920, 1080)
	var size := viewport.get_visible_rect().size
	if _camera and _camera.zoom.x > 0 and _camera.zoom.y > 0:
		# DIVIDE by zoom - when zoomed OUT (zoom < 1), visible world area is LARGER
		# E.g., zoom = 0.5 means we can see 2x the world area
		size /= _camera.zoom
	return size

func _draw() -> void:
	for p in _particles:
		var color: Color = p["color"]
		# Basic color math
		color.r *= _ambient_compensation
		color.g *= _ambient_compensation
		color.b *= _ambient_compensation
		
		# Clamp brightness without expensive maxf checks every framing if we can avoid it, 
		# but for HDR fireflies we probably need it. Simplified:
		if color.r > 1.0 or color.g > 1.0 or color.b > 1.0:
			var max_c := maxf(color.r, maxf(color.g, color.b))
			color = color / max_c # Normalize
			
		color.a *= p["alpha"]
		
		# Convert world position to local for drawing
		var pos: Vector2 = p["position"] - global_position
		var size: float = p["size"]
		
		match p["shape"]:
			"circle":
				draw_circle(pos, size, color)
			
			"petal":
				_draw_petal(pos, size, p["rotation"], color)
			
			"dust":
				# Simplified dust: just a small square/diamond
				var p1 = pos + Vector2(0, -size)
				var p2 = pos + Vector2(size, 0)
				var p3 = pos + Vector2(0, size)
				var p4 = pos + Vector2(-size, 0)
				draw_colored_polygon([p1, p2, p3, p4], color)
			
			"firefly":
				# Optimized firefly: 2 circles max
				# Glow
				var glow_alpha = color.a * 0.3
				draw_circle(pos, size * 2.5, Color(color.r, color.g, color.b, glow_alpha))
				# Core (bright)
				draw_circle(pos, size * 0.8, Color(2.0, 2.0, 1.5, color.a))
			
			"rain_streak":
				# Draw a short line in the direction of movement
				var velocity: Vector2 = p["velocity"]
				var length := size * 4.0 # Shorter streaks
				var direction := velocity.normalized()
				var start_pos := pos - direction * length * 0.5
				var end_pos := pos + direction * length * 0.5
				draw_line(start_pos, end_pos, color, size)

func _draw_petal(pos: Vector2, size: float, petal_rotation: float, color: Color) -> void:
	# Studio Ghibli-style cherry blossom petal
	# Soft, rounded teardrop shape - no heart notch for natural look
	# Single polygon call for performance
	var cos_r = cos(petal_rotation)
	var sin_r = sin(petal_rotation)
	
	# Helper to rotate a point around origin
	var rotate_point = func(x: float, y: float) -> Vector2:
		return Vector2(x * cos_r - y * sin_r, x * sin_r + y * cos_r)
	
	# Build petal shape: soft rounded teardrop (like real cherry blossom)
	# Points go clockwise from bottom tip
	var points: PackedVector2Array = PackedVector2Array()
	
	# Scale factors for soft petal proportions
	var length := size * 1.0 # Vertical length
	var width := size * 0.5 # Narrower for elegance
	
	# Bottom tip (slightly rounded, not sharp)
	points.append(pos + rotate_point.call(0.0, length))
	
	# Right side - gentle curve for organic feel
	points.append(pos + rotate_point.call(width * 0.25, length * 0.7))
	points.append(pos + rotate_point.call(width * 0.55, length * 0.4))
	points.append(pos + rotate_point.call(width * 0.7, length * 0.05))
	points.append(pos + rotate_point.call(width * 0.55, -length * 0.2))
	
	# Rounded top (smooth curve across, no notch)
	points.append(pos + rotate_point.call(width * 0.25, -length * 0.32))
	points.append(pos + rotate_point.call(0.0, -length * 0.35)) # Top center
	points.append(pos + rotate_point.call(-width * 0.25, -length * 0.32))
	
	# Left side - mirror of right
	points.append(pos + rotate_point.call(-width * 0.55, -length * 0.2))
	points.append(pos + rotate_point.call(-width * 0.7, length * 0.05))
	points.append(pos + rotate_point.call(-width * 0.55, length * 0.4))
	points.append(pos + rotate_point.call(-width * 0.25, length * 0.7))
	
	# Draw main petal body
	draw_colored_polygon(points, color)

func _on_modulate_changed(color: Color) -> void:
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	var clamped_luminance := clampf(luminance, 0.2, 1.25)
	_ambient_compensation = clampf(1.0 / clamped_luminance, 1.0, 4.0)
