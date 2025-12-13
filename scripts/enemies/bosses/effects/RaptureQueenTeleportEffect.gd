extends Node2D

## Teleport visual effect for Rapture Queen N01
## Creates flowing black liquid particle effects for dissolve and reform animations

enum Phase { DISSOLVE, REFORM }

# Configuration
const PARTICLE_COUNT := 120  # Optimized from 250
const DISSOLVE_DURATION := 0.4
const REFORM_DURATION := 0.3
const PARTICLE_LIFETIME := 0.8

# State
var _phase: Phase = Phase.DISSOLVE
var _time: float = 0.0
var _particles: Array = []
var _source_position: Vector2 = Vector2.ZERO
var _boss_scale: float = 1.0
var _finished: bool = false

# Visual settings
const LIQUID_COLORS := [
	Color(0.05, 0.0, 0.05, 0.9),      # Deep black
	Color(0.1, 0.0, 0.15, 0.85),      # Dark purple
	Color(0.15, 0.0, 0.1, 0.8),       # Deep red-black
	Color(0.08, 0.0, 0.12, 0.75),     # Medium purple-black
]

# Particle data structure
class LiquidParticle:
	var position: Vector2
	var velocity: Vector2
	var lifetime: float
	var max_lifetime: float
	var size: float
	var color: Color
	var spawn_offset: Vector2  # Original offset from boss center
	
	func _init(pos: Vector2, vel: Vector2, life: float, sz: float, col: Color, offset: Vector2):
		position = pos
		velocity = vel
		lifetime = 0.0
		max_lifetime = life
		size = sz
		color = col
		spawn_offset = offset

func _ready() -> void:
	z_index = 100  # Above boss
	
	# Unshaded additive material for glow
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

func setup_dissolve(pos: Vector2, boss_scale: float = 1.0) -> void:
	_phase = Phase.DISSOLVE
	_source_position = pos
	global_position = pos
	_boss_scale = boss_scale
	_spawn_particles_from_source()

func setup_reform(pos: Vector2, boss_scale: float = 1.0) -> void:
	_phase = Phase.REFORM
	_source_position = pos
	global_position = pos
	_boss_scale = boss_scale
	_spawn_particles_for_reform()

func _spawn_particles_from_source() -> void:
	# Spawn particles from boss body that flow downward
	for i in range(PARTICLE_COUNT):
		# Random offset from center (boss body area) - SCALED
		var angle = randf() * TAU
		var radius = randf_range(30.0, 120.0) * _boss_scale  # Boss body radius SCALED
		var offset = Vector2(cos(angle), sin(angle)) * radius
		
		# Velocity: mostly downward with some spread - FASTER
		var vel = Vector2(
			randf_range(-50.0, 50.0),  # Horizontal spread
			randf_range(100.0, 200.0)   # Downward speed INCREASED
		)
		
		# Random properties - LARGER PARTICLES
		var lifetime = randf_range(0.5, PARTICLE_LIFETIME)
		var size = randf_range(5.0, 15.0) * _boss_scale  # LARGER and SCALED
		var color = LIQUID_COLORS[randi() % LIQUID_COLORS.size()]
		
		var particle = LiquidParticle.new(offset, vel, lifetime, size, color, offset)
		_particles.append(particle)

func _spawn_particles_for_reform() -> void:
	# Spawn particles below that flow upward to reform boss
	for i in range(PARTICLE_COUNT):
		# Start below and around the target position - SCALED
		var angle = randf() * TAU
		var radius = randf_range(30.0, 120.0) * _boss_scale
		var offset = Vector2(cos(angle), sin(angle)) * radius
		var start_offset = offset + Vector2(0, randf_range(150.0, 300.0) * _boss_scale)  # Below target SCALED
		
		# Velocity: upward and inward - FASTER
		var to_center = -offset.normalized()
		var vel = Vector2(
			to_center.x * randf_range(70.0, 130.0),
			-randf_range(150.0, 220.0)  # Upward speed INCREASED
		)
		
		# Random properties - LARGER PARTICLES
		var lifetime = randf_range(0.5, PARTICLE_LIFETIME)
		var size = randf_range(5.0, 15.0) * _boss_scale  # LARGER and SCALED
		var color = LIQUID_COLORS[randi() % LIQUID_COLORS.size()]
		
		var particle = LiquidParticle.new(start_offset, vel, lifetime, size, color, offset)
		_particles.append(particle)

func _process(delta: float) -> void:
	_time += delta
	
	# Update particles
	for particle in _particles:
		particle.lifetime += delta
		
		if particle.lifetime <= particle.max_lifetime:
			# Physics
			particle.velocity.y += 200.0 * delta if _phase == Phase.DISSOLVE else -150.0 * delta  # Gravity/anti-gravity
			particle.position += particle.velocity * delta
			
			# Add swirl/turbulence
			var swirl_strength = 50.0
			var swirl_angle = _time * 3.0 + particle.position.x * 0.1
			particle.velocity.x += sin(swirl_angle) * swirl_strength * delta
	
	queue_redraw()
	
	# Check if effect is done
	var all_dead = true
	for particle in _particles:
		if particle.lifetime < particle.max_lifetime:
			all_dead = false
			break
	
	if all_dead and not _finished:
		_finished = true
		queue_free()

func _draw() -> void:
	for particle in _particles:
		if particle.lifetime > particle.max_lifetime:
			continue
		
		# Fade in quickly, fade out slowly
		var life_percent = particle.lifetime / particle.max_lifetime
		var alpha_mult = 1.0
		if life_percent < 0.1:
			alpha_mult = life_percent / 0.1  # Fade in
		elif life_percent > 0.7:
			alpha_mult = (1.0 - life_percent) / 0.3  # Fade out
		
		var color = particle.color
		color.a *= alpha_mult
		
		# Optimized Draw: Reduced from 4 overlapping circles to 2
		var pos = particle.position
		var size = particle.size
		
		# Single Soft Glow (combined outer/mid)
		draw_circle(pos, size * 2.0, Color(color.r, color.g, color.b, color.a * 0.2))
		
		# Core with highlight
		draw_circle(pos, size, color)

func is_finished() -> bool:
	return _finished
