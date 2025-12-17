extends Node2D
class_name LevelUpGlow

## WoW-style golden glow effect for level up
## Spawns around the player with rising golden particles and an expanding ring

const EFFECT_DURATION := 2.0
const RING_EXPAND_DURATION := 0.4
const PARTICLE_COUNT := 8 # Reduced from 12
const RING_SEGMENTS := 16 # Reduced from 32

# Golden color palette
const GOLD_CORE := Color(1.0, 0.9, 0.4, 1.0)
const GOLD_BRIGHT := Color(1.0, 0.95, 0.6, 1.0)
const GOLD_OUTER := Color(1.0, 0.8, 0.2, 0.8)
const GOLD_GLOW := Color(1.0, 0.85, 0.3, 0.4)

var _time: float = 0.0
var _particles: Array = []  # Array of particle data dictionaries
var _ring_radius: float = 0.0
var _ring_alpha: float = 1.0
var _player: Node2D = null

func _ready() -> void:
	# Top level so we don't inherit player transforms after spawning
	top_level = true
	z_index = 100
	
	# Set up unshaded material so it shows through lighting
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Initialize particles
	_spawn_particles()

func _spawn_particles() -> void:
	_particles.clear()
	for i in range(PARTICLE_COUNT):
		var angle := randf() * TAU
		var dist := randf_range(20.0, 60.0)
		var start_pos := Vector2(cos(angle), sin(angle)) * dist
		var rise_speed := randf_range(80.0, 150.0)
		var drift := randf_range(-30.0, 30.0)
		var size := randf_range(3.0, 8.0)
		var delay := randf() * 0.5  # Staggered start
		var lifetime := randf_range(1.0, 1.8)
		
		_particles.append({
			"pos": start_pos,
			"start_pos": start_pos,
			"rise_speed": rise_speed,
			"drift": drift,
			"size": size,
			"delay": delay,
			"lifetime": lifetime,
			"alpha": 0.0
		})

func _process(delta: float) -> void:
	_time += delta
	
	# Follow player position if set
	if is_instance_valid(_player):
		global_position = _player.global_position
	
	# Update ring expansion
	var ring_t := minf(_time / RING_EXPAND_DURATION, 1.0)
	_ring_radius = lerpf(30.0, 120.0, ease(ring_t, -2.0))  # Ease out
	_ring_alpha = lerpf(0.8, 0.0, ring_t)
	
	# Update particles
	for p in _particles:
		var local_time: float = _time - float(p.delay)
		if local_time < 0:
			p.alpha = 0.0
			continue
		
		var life_ratio: float = local_time / float(p.lifetime)
		if life_ratio > 1.0:
			p.alpha = 0.0
			continue
		
		# Move upward with slight drift
		p.pos = p.start_pos + Vector2(p.drift * local_time, -p.rise_speed * local_time)
		
		# Fade in quickly, then fade out
		if life_ratio < 0.1:
			p.alpha = life_ratio / 0.1
		elif life_ratio > 0.7:
			p.alpha = (1.0 - life_ratio) / 0.3
		else:
			p.alpha = 1.0
		
		# Shrink slightly as they rise
		p.size = lerpf(p.size, p.size * 0.5, life_ratio)
	
	# Throttle redraw to every other frame for performance
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()
	
	# Auto-remove when done
	if _time >= EFFECT_DURATION:
		queue_free()

func _draw() -> void:
	# Draw expanding ring first (behind particles)
	if _ring_alpha > 0.01:
		_draw_glow_ring()
	
	# Draw central glow
	_draw_central_glow()
	
	# Draw particles
	for p in _particles:
		if p.alpha > 0.01:
			_draw_particle(p)
	
	# Draw column of light effect
	_draw_light_column()

func _draw_glow_ring() -> void:
	# Draw an expanding ring with glow
	var ring_color := Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, _ring_alpha * 0.6)
	var glow_color := Color(GOLD_GLOW.r, GOLD_GLOW.g, GOLD_GLOW.b, _ring_alpha * 0.3)
	
	# Outer glow
	draw_arc(Vector2.ZERO, _ring_radius + 8.0, 0, TAU, RING_SEGMENTS, glow_color, 12.0)
	# Main ring
	draw_arc(Vector2.ZERO, _ring_radius, 0, TAU, RING_SEGMENTS, ring_color, 4.0)
	# Inner bright line
	var inner_color := Color(GOLD_CORE.r, GOLD_CORE.g, GOLD_CORE.b, _ring_alpha * 0.8)
	draw_arc(Vector2.ZERO, _ring_radius - 2.0, 0, TAU, RING_SEGMENTS, inner_color, 2.0)

func _draw_central_glow() -> void:
	# Pulsing glow at center
	var pulse := sin(_time * 6.0) * 0.2 + 0.8
	var fade := 1.0 - (_time / EFFECT_DURATION)
	fade = maxf(0.0, fade)
	
	# Multiple overlapping circles for soft glow
	var glow_alpha := 0.3 * pulse * fade
	draw_circle(Vector2.ZERO, 60.0, Color(GOLD_GLOW.r, GOLD_GLOW.g, GOLD_GLOW.b, glow_alpha * 0.4))
	draw_circle(Vector2.ZERO, 30.0, Color(GOLD_OUTER.r, GOLD_OUTER.g, GOLD_OUTER.b, glow_alpha * 0.7))

func _draw_particle(p: Dictionary) -> void:
	var pos: Vector2 = p.pos
	var size: float = p.size
	var alpha: float = p.alpha
	
	# Glow behind particle
	var glow_size := size * 2.5
	draw_circle(pos, glow_size, Color(GOLD_GLOW.r, GOLD_GLOW.g, GOLD_GLOW.b, alpha * 0.3))
	
	# Combined core and bright center
	draw_circle(pos, size * 0.8, Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, alpha))

func _draw_light_column() -> void:
	# Draw vertical column of light (fades quickly)
	var column_fade := 1.0 - (_time / 0.6)
	column_fade = maxf(0.0, column_fade)
	if column_fade < 0.01:
		return
	
	# Draw as a series of horizontal lines with gradient
	var column_width := 40.0
	var column_height := 200.0
	
	for i in range(10): # Reduced from 20
		var y := -column_height * (float(i) / 10.0) # Adjusted for loop size
		var width_factor := 1.0 - (float(i) / 10.0) * 0.7
		var alpha := column_fade * (1.0 - float(i) / 10.0) * 0.4
		var half_width := column_width * 0.5 * width_factor
		
		draw_line(
			Vector2(-half_width, y),
			Vector2(half_width, y),
			Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, alpha),
			3.0
		)

## Call this to attach to a player
func attach_to_player(player: Node2D) -> void:
	_player = player
	if is_instance_valid(player):
		global_position = player.global_position

## Static helper to spawn the effect
static func spawn_at(parent: Node, player: Node2D) -> LevelUpGlow:
	var effect := LevelUpGlow.new()
	parent.add_child(effect)
	effect.attach_to_player(player)
	return effect
