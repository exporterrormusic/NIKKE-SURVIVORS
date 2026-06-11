# Extracted from scripts/characters/KiloController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0
const GLOW_COLOR := Color(1.0, 0.82, 0.2, 1.0)  # Golden color
const GLOW_RADIUS := 55.0

# Sparkle system - small and numerous
var _sparkles: Array = []
const MAX_SPARKLES := 35
const SPARKLE_SPAWN_RATE := 0.03
var _sparkle_timer: float = 0.0

class Sparkle:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var size: float
	var rotation: float
	var rot_speed: float

func _ready() -> void:
	z_index = 50  # Above player sprite for sparkles
	# Store reference to player before potential reparenting
	set_meta("owner_player", get_parent())
	# Assign to effects layer to avoid night darkening
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_parent = get_parent()
			if saved_parent:
				saved_parent.remove_child(self)
			effects.add_child(self)
			z_as_relative = false
			z_index = 500  # Very high to stay above everything

func _process(delta: float) -> void:
	# Track player position if reparented to effects layer
	if has_meta("owner_player"):
		var player = get_meta("owner_player")
		if is_instance_valid(player):
			global_position = player.global_position
	
	_time += delta
	_sparkle_timer += delta
	
	# Spawn new sparkles
	if _sparkle_timer >= SPARKLE_SPAWN_RATE and _sparkles.size() < MAX_SPARKLES:
		_sparkle_timer = 0.0
		_spawn_sparkle()
	
	# Update sparkles
	var to_remove := []
	for i in range(_sparkles.size()):
		var s = _sparkles[i]
		s.life -= delta
		if s.life <= 0:
			to_remove.append(i)
		else:
			s.pos += s.vel * delta
			s.vel.y -= 60.0 * delta  # Float upward gently
			s.rotation += s.rot_speed * delta
	
	for i in range(to_remove.size() - 1, -1, -1):
		_sparkles.remove_at(to_remove[i])
	
	queue_redraw()

func _spawn_sparkle() -> void:
	var s = Sparkle.new()
	# Spawn across wider area around character
	s.pos = Vector2(randf_range(-60.0, 60.0), randf_range(-70.0, 50.0))
	s.vel = Vector2(randf_range(-30, 30), randf_range(-50, -15))
	s.life = randf_range(0.4, 0.8)
	s.max_life = s.life
	s.size = randf_range(3.0, 6.0)  # Smaller, cuter sparkles
	s.rotation = randf() * TAU
	s.rot_speed = randf_range(-5.0, 5.0)
	_sparkles.append(s)

func _draw() -> void:
	# Smooth pulsing glow
	var pulse := 1.0 + sin(_time * 3.5) * 0.12
	var alpha_base := 0.7 + sin(_time * 2.0) * 0.15
	
	# Draw glow layers (behind at z_index, but we draw first)
	var layers := 8
	for i in range(layers):
		var t := float(i) / float(layers - 1)
		var radius := GLOW_RADIUS * pulse * (0.3 + t * 0.7)
		var layer_alpha := alpha_base * pow(1.0 - t, 2.0) * 0.5
		
		var r := lerpf(1.0, GLOW_COLOR.r, t * 0.4)
		var g := lerpf(0.95, GLOW_COLOR.g, t * 0.6)
		var b := lerpf(0.6, GLOW_COLOR.b, t * 0.8)
		
		draw_circle(Vector2.ZERO, radius, Color(r, g, b, layer_alpha))
	
	# Draw sparkles - brighter
	for s in _sparkles:
		var life_ratio: float = s.life / s.max_life
		var sparkle_alpha: float = life_ratio  # Full brightness
		var sparkle_size: float = s.size * (0.6 + life_ratio * 0.4)
		
		# Draw 4-pointed star
		_draw_sparkle(s.pos, sparkle_size, s.rotation, sparkle_alpha)

func _draw_sparkle(pos: Vector2, size: float, rot: float, alpha: float) -> void:
	# Soft outer glow
	draw_circle(pos, size * 0.6, Color(1.0, 0.9, 0.5, alpha * 0.4))
	
	# Core - bright white-gold
	draw_circle(pos, size * 0.35, Color(1.0, 1.0, 0.9, alpha))
	
	# 4-pointed star rays - delicate
	var ray_length := size * 1.5
	var ray_width := size * 0.2
	for i in range(4):
		var angle := rot + i * PI * 0.5
		var dir := Vector2(cos(angle), sin(angle))
		var tip := pos + dir * ray_length
		# Soft glow
		draw_line(pos, tip, Color(1.0, 0.9, 0.5, alpha * 0.4), ray_width * 1.5)
		# Bright core
		draw_line(pos, tip, Color(1.0, 0.98, 0.85, alpha), ray_width)
