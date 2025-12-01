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

const MAX_PARTICLES := 60
const SPAWN_INTERVAL := 0.08

# Particle type configurations
var _particle_config := {}

func _ready() -> void:
	_rng.randomize()
	z_index = 50  # Above most things, below UI
	# Don't use top_level - particles should be in world space
	set_process(true)
	
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
		"density": 1.2
	}
	
	# Sakura grove particles - cherry blossom petals
	_particle_config[&"sakura_grove"] = {
		"types": [
			{
				"color": Color(1.0, 0.75, 0.85, 0.9),
				"size_range": Vector2(12, 20),
				"speed_range": Vector2(25, 50),
				"drift_range": Vector2(40, 80),
				"lifetime_range": Vector2(6, 12),
				"shape": "petal",
				"glow": false
			},
			{
				"color": Color(1.0, 0.85, 0.9, 0.85),
				"size_range": Vector2(10, 16),
				"speed_range": Vector2(30, 60),
				"drift_range": Vector2(35, 70),
				"lifetime_range": Vector2(5, 10),
				"shape": "petal",
				"glow": false
			}
		],
		"density": 2.5
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
				"pulse_speed": 3.0
			}
		],
		"density": 0.8,
		"density_night": 0.6
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
		"density": 1.5
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
	var particles_to_spawn := int(MAX_PARTICLES * 0.8)  # Fill to 80%
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
	
	# Get camera for spawn area reference only
	if _camera == null:
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
		
		while _spawn_timer >= spawn_rate and _particles.size() < MAX_PARTICLES:
			_spawn_timer -= spawn_rate
			_spawn_particle(config)
	
	# Update particles
	_update_particles(delta)
	
	queue_redraw()

func _spawn_particle(config: Dictionary) -> void:
	var types: Array = config.get("types_night", config.get("types", [])) if _is_night else config.get("types", [])
	if types.is_empty():
		return
	
	var type_config: Dictionary = types[_rng.randi() % types.size()]
	
	# Spawn in world space around camera
	var view_size := _get_view_size()
	var camera_pos := _camera.global_position if _camera else Vector2.ZERO
	var spawn_pos := Vector2(
		camera_pos.x + _rng.randf_range(-view_size.x * 0.7, view_size.x * 0.7),
		camera_pos.y + _rng.randf_range(-view_size.y * 0.8, -view_size.y * 0.4)  # Start above view
	)
	
	var size_range: Vector2 = type_config.get("size_range", Vector2(2, 4))
	var speed_range: Vector2 = type_config.get("speed_range", Vector2(20, 50))
	var drift_range: Vector2 = type_config.get("drift_range", Vector2(10, 30))
	var lifetime_range: Vector2 = type_config.get("lifetime_range", Vector2(4, 8))
	
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
		"lifetime": _rng.randf_range(lifetime_range.x, lifetime_range.y),
		"age": 0.0,
		"phase": _rng.randf() * TAU,
		"drift_phase": _rng.randf() * TAU,
		"alpha": 1.0
	}
	_particles.append(particle)

func _update_particles(delta: float) -> void:
	var view_size := _get_view_size()
	var camera_pos := _camera.global_position if _camera else Vector2.ZERO
	var i := 0
	while i < _particles.size():
		var p: Dictionary = _particles[i]
		p["age"] += delta
		
		# Remove if too old or too far below camera view
		var particle_pos: Vector2 = p["position"]
		var dist_from_camera := (particle_pos - camera_pos).length()
		if p["age"] >= p["lifetime"] or dist_from_camera > view_size.length() * 0.8:
			_particles.remove_at(i)
			continue
		
		# Update position with gentle drift
		p["drift_phase"] += delta * 2.0
		var drift := sin(p["drift_phase"]) * 20.0
		p["position"] += p["velocity"] * delta
		p["position"].x += drift * delta
		
		# Rotation
		p["rotation"] += p["rotation_speed"] * delta
		
		# Fade in/out
		var life_ratio: float = p["age"] / p["lifetime"]
		if life_ratio < 0.1:
			p["alpha"] = life_ratio / 0.1
		elif life_ratio > 0.7:
			p["alpha"] = (1.0 - life_ratio) / 0.3
		else:
			p["alpha"] = 1.0
		
		# Pulse for glowing particles (fireflies)
		if p["glow"] and p["pulse_speed"] > 0:
			var pulse := sin(p["age"] * p["pulse_speed"] + p["phase"])
			p["alpha"] *= 0.4 + pulse * 0.6
		
		_particles[i] = p
		i += 1

func _get_view_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(1920, 1080)
	var size := viewport.get_visible_rect().size
	if _camera:
		size *= _camera.zoom
	return size

func _draw() -> void:
	for p in _particles:
		var color: Color = p["color"]
		color.a *= p["alpha"]
		
		# Convert world position to local for drawing
		var pos: Vector2 = p["position"] - global_position
		var size: float = p["size"]
		
		match p["shape"]:
			"circle":
				if p["glow"]:
					# Outer glow
					var glow_color := Color(color.r, color.g, color.b, color.a * 0.3)
					draw_circle(pos, size * 3, glow_color)
					draw_circle(pos, size * 2, Color(color.r, color.g, color.b, color.a * 0.5))
				draw_circle(pos, size, color)
			
			"petal":
				_draw_petal(pos, size, p["rotation"], color)
			
			"dust":
				# Irregular dust shape
				var points := PackedVector2Array()
				for j in range(5):
					var angle: float = p["rotation"] + TAU * float(j) / 5.0
					var dist := size * _rng.randf_range(0.6, 1.0)
					points.append(pos + Vector2(cos(angle), sin(angle)) * dist)
				draw_polygon(points, [color, color, color, color, color])
			
			"firefly":
				# Glowing firefly
				var glow_size := size * (2.0 + sin(p["age"] * p["pulse_speed"]) * 0.5)
				var glow_color := Color(color.r, color.g, color.b, color.a * 0.2)
				draw_circle(pos, glow_size * 2, glow_color)
				draw_circle(pos, glow_size, Color(color.r, color.g, color.b, color.a * 0.4))
				draw_circle(pos, size, color)
				# Bright core
				draw_circle(pos, size * 0.5, Color(1.0, 1.0, 0.9, color.a))

func _draw_petal(pos: Vector2, size: float, petal_rotation: float, color: Color) -> void:
	# Draw a simple petal shape
	var points := PackedVector2Array()
	var num_points := 8
	for i in range(num_points):
		var t := float(i) / float(num_points - 1)
		var angle := petal_rotation + (t - 0.5) * PI * 0.6
		var dist := size * sin(t * PI)  # Bulge in middle
		points.append(pos + Vector2(cos(angle), sin(angle)) * dist)
	
	if points.size() >= 3:
		var colors := PackedColorArray()
		for i in range(points.size()):
			colors.append(color)
		draw_polygon(points, colors)
