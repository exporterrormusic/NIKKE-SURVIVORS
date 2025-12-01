extends Node2D
class_name CharacterSwapEffect

## Visual effect for character swap - flash + particles

const FLASH_DURATION := 0.18
const PARTICLE_COUNT := 16
const PARTICLE_SPEED := 280.0
const PARTICLE_LIFETIME := 0.35

# Character colors for themed particles
const CHARACTER_COLORS := {
	0: Color(1.0, 0.3, 0.3),   # Scarlet - Red
	1: Color(0.7, 0.85, 1.0),  # Snow White - Ice Blue
	2: Color(1.0, 0.8, 0.3)    # Rapunzel - Golden
}

var _particles: Array = []
var _flash_alpha := 1.0
var _elapsed := 0.0
var _character_color: Color = Color.WHITE
var _is_active := false

func trigger(character_index: int, at_position: Vector2) -> void:
	global_position = at_position
	_character_color = CHARACTER_COLORS.get(character_index, Color.WHITE)
	_flash_alpha = 1.0
	_elapsed = 0.0
	_is_active = true
	
	# Spawn particles in a ring
	_particles.clear()
	for i in range(PARTICLE_COUNT):
		var angle := (TAU / PARTICLE_COUNT) * i + randf() * 0.3
		var speed := PARTICLE_SPEED * randf_range(0.8, 1.2)
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2.from_angle(angle) * speed,
			"size": randf_range(4.0, 8.0),
			"alpha": 1.0,
			"lifetime": PARTICLE_LIFETIME * randf_range(0.8, 1.2)
		})
	
	queue_redraw()

func _process(delta: float) -> void:
	if not _is_active:
		return
	
	_elapsed += delta
	
	# Fade flash
	_flash_alpha = max(0.0, 1.0 - (_elapsed / FLASH_DURATION))
	
	# Update particles
	var all_dead := true
	for i in range(_particles.size()):
		var p: Dictionary = _particles[i]
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.90  # Drag
		var life_ratio: float = _elapsed / float(p["lifetime"])
		p["alpha"] = max(0.0, 1.0 - life_ratio)
		if p["alpha"] > 0:
			all_dead = false
		_particles[i] = p
	
	queue_redraw()
	
	if all_dead and _flash_alpha <= 0:
		_is_active = false

func _draw() -> void:
	if not _is_active:
		return
	
	# Draw flash ring - larger to cover sprite
	if _flash_alpha > 0:
		var flash_color := Color(_character_color.r * 1.5, _character_color.g * 1.5, _character_color.b * 1.5, _flash_alpha * 0.7)
		var ring_radius := 55.0 + (1.0 - _flash_alpha) * 35.0
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 32, flash_color, 6.0)
		
		# Secondary inner ring for more impact
		var inner_ring_color := Color(_character_color.r * 1.3, _character_color.g * 1.3, _character_color.b * 1.3, _flash_alpha * 0.5)
		var inner_ring_radius := 35.0 + (1.0 - _flash_alpha) * 20.0
		draw_arc(Vector2.ZERO, inner_ring_radius, 0, TAU, 24, inner_ring_color, 3.0)
		
		# Inner bright flash - larger
		var inner_color := Color(1.0, 1.0, 1.0, _flash_alpha * 0.85)
		draw_circle(Vector2.ZERO, 28.0 * _flash_alpha, inner_color)
	
	# Draw particles
	for p in _particles:
		if p["alpha"] <= 0:
			continue
		var col := Color(_character_color.r * 1.4, _character_color.g * 1.4, _character_color.b * 1.4, p["alpha"])
		draw_circle(p["pos"], p["size"], col)
		# Bright core
		var core_col := Color(1.5, 1.5, 1.5, p["alpha"] * 0.8)
		draw_circle(p["pos"], p["size"] * 0.4, core_col)
