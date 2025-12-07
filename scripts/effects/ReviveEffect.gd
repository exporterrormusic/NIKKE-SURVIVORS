extends Node2D
class_name ReviveEffect

## Blue magical revive effect for Cecil's "Three Wishes..." upgrade
## Shows a blue burst with rising fairy-like particles

const EFFECT_DURATION := 1.5
const RING_EXPAND_DURATION := 0.3
const PARTICLE_COUNT := 16

# Blue fairy color palette
const BLUE_CORE := Color(0.4, 0.8, 1.0, 1.0)
const BLUE_BRIGHT := Color(0.6, 0.9, 1.0, 1.0)
const BLUE_OUTER := Color(0.2, 0.6, 1.0, 0.8)
const BLUE_GLOW := Color(0.3, 0.7, 1.0, 0.4)

var _time: float = 0.0
var _particles: Array = []
var _ring_radius: float = 0.0
var _ring_alpha: float = 1.0

func _ready() -> void:
	top_level = true
	z_index = 100
	
	# Unshaded material
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Initialize particles
	_spawn_particles()

func _spawn_particles() -> void:
	_particles.clear()
	for i in range(PARTICLE_COUNT):
		var angle := randf() * TAU
		var dist := randf_range(10.0, 40.0)
		var start_pos := Vector2(cos(angle), sin(angle)) * dist
		var rise_speed := randf_range(60.0, 120.0)
		var drift := randf_range(-20.0, 20.0)
		var size := randf_range(4.0, 10.0)
		var delay := randf() * 0.3
		var lifetime := randf_range(0.8, 1.3)
		
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
	
	# Update ring expansion
	if _time < RING_EXPAND_DURATION:
		var t := _time / RING_EXPAND_DURATION
		_ring_radius = lerpf(0.0, 80.0, t)
		_ring_alpha = 1.0 - t * 0.5
	else:
		var fade_t := (_time - RING_EXPAND_DURATION) / 0.3
		_ring_alpha = max(0.0, 0.5 - fade_t * 0.5)
	
	# Update particles
	for p in _particles:
		var particle_time: float = _time - p.delay
		if particle_time < 0.0:
			p.alpha = 0.0
			continue
		
		var life_ratio: float = particle_time / p.lifetime
		if life_ratio > 1.0:
			p.alpha = 0.0
			continue
		
		# Movement
		p.pos = p.start_pos + Vector2(p.drift * particle_time, -p.rise_speed * particle_time)
		
		# Fade in then out
		if life_ratio < 0.2:
			p.alpha = life_ratio / 0.2
		else:
			p.alpha = 1.0 - (life_ratio - 0.2) / 0.8
	
	queue_redraw()
	
	# Clean up
	if _time >= EFFECT_DURATION:
		queue_free()

func _draw() -> void:
	# Draw expanding ring
	if _ring_alpha > 0.0:
		var ring_color := BLUE_OUTER
		ring_color.a = _ring_alpha * 0.6
		draw_arc(Vector2.ZERO, _ring_radius, 0.0, TAU, 48, ring_color, 3.0, true)
		
		# Inner glow ring
		var inner_color := BLUE_BRIGHT
		inner_color.a = _ring_alpha * 0.4
		draw_arc(Vector2.ZERO, _ring_radius * 0.7, 0.0, TAU, 32, inner_color, 2.0, true)
	
	# Draw center flash
	if _time < 0.2:
		var flash_alpha := 1.0 - _time / 0.2
		var flash_color := BLUE_CORE
		flash_color.a = flash_alpha
		draw_circle(Vector2.ZERO, 30.0 * (1.0 + _time * 2.0), flash_color)
	
	# Draw particles (fairy sparkles)
	for p in _particles:
		if p.alpha <= 0.0:
			continue
		
		# Star shape for magical effect
		var color := BLUE_BRIGHT
		color.a = p.alpha
		var size: float = p.size
		
		# Draw 4-point star
		var points := PackedVector2Array()
		for j in range(4):
			var angle := j * TAU / 4.0
			points.append(p.pos + Vector2(cos(angle), sin(angle)) * size)
			points.append(p.pos + Vector2(cos(angle + TAU/8.0), sin(angle + TAU/8.0)) * size * 0.3)
		points.append(points[0])
		draw_polyline(points, color, 2.0, true)
		
		# Center dot
		var core_color := BLUE_CORE
		core_color.a = p.alpha
		draw_circle(p.pos, size * 0.3, core_color)
