extends Node2D
class_name PlayerMovementEffects

# Movement visual effects for the player
# - Dust particles when running/moving fast
# - Speed lines when dashing

var _player: CharacterBody2D = null
var _rng := RandomNumberGenerator.new()

# Dust particles
var _dust_particles: Array = []
var _dust_spawn_timer := 0.0
const DUST_SPAWN_INTERVAL := 0.06
const MAX_DUST_PARTICLES := 20
const DUST_BASE_COLOR := Color(0.7, 0.65, 0.55, 0.6)  # Sandy/dirt color
const DUST_LIGHT_COLOR := Color(0.85, 0.8, 0.7, 0.4)  # Lighter accent

# Speed lines (dash effect)
var _speed_lines: Array = []
var _speed_line_timer := 0.0
const SPEED_LINE_SPAWN_INTERVAL := 0.03
const MAX_SPEED_LINES := 12
const SPEED_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const SPEED_LINE_LENGTH := 40.0

# Footstep impact
var _footstep_timer := 0.0
const FOOTSTEP_INTERVAL := 0.15

func _ready() -> void:
	_rng.randomize()
	_player = get_parent() as CharacterBody2D
	z_index = -1  # Draw behind player
	set_process(true)

func _process(delta: float) -> void:
	if not _player:
		return
	
	var player_velocity: Vector2 = _player.velocity
	var player_speed: float = player_velocity.length()
	var is_dashing: bool = _player.dashing if "dashing" in _player else false
	var is_running: bool = _player.running if "running" in _player else false
	
	# Spawn dust when moving
	if player_speed > 100:
		_dust_spawn_timer += delta
		var spawn_rate := DUST_SPAWN_INTERVAL
		if is_running:
			spawn_rate *= 0.7  # More dust when running
		if is_dashing:
			spawn_rate *= 0.5  # Even more when dashing
		
		while _dust_spawn_timer >= spawn_rate:
			_dust_spawn_timer -= spawn_rate
			_spawn_dust_particle(player_velocity)
	
	# Spawn speed lines when dashing
	if is_dashing:
		_speed_line_timer += delta
		while _speed_line_timer >= SPEED_LINE_SPAWN_INTERVAL:
			_speed_line_timer -= SPEED_LINE_SPAWN_INTERVAL
			_spawn_speed_line(player_velocity)
	
	# Footstep impacts when running
	if is_running and player_speed > 200:
		_footstep_timer += delta
		if _footstep_timer >= FOOTSTEP_INTERVAL:
			_footstep_timer = 0.0
			_spawn_footstep_impact(player_velocity)
	
	# Update particles
	_update_dust_particles(delta)
	_update_speed_lines(delta)
	
	queue_redraw()

func _spawn_dust_particle(velocity: Vector2) -> void:
	if _dust_particles.size() >= MAX_DUST_PARTICLES:
		return
	
	var move_dir := velocity.normalized()
	# Spawn dust at feet level (offset Y significantly down from sprite center)
	var feet_offset := Vector2(0, 45)
	var spawn_offset := -move_dir * 10.0 + Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-5, 5)) + feet_offset
	
	var particle := {
		"position": _player.global_position + spawn_offset,
		"velocity": Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-30, -5)),
		"radius": _rng.randf_range(3.0, 6.0),
		"alpha": _rng.randf_range(0.4, 0.7),
		"lifetime": _rng.randf_range(0.3, 0.6),
		"age": 0.0,
		"color": DUST_BASE_COLOR if _rng.randf() > 0.3 else DUST_LIGHT_COLOR
	}
	_dust_particles.append(particle)

func _update_dust_particles(delta: float) -> void:
	var i := 0
	while i < _dust_particles.size():
		var p: Dictionary = _dust_particles[i]
		p["age"] += delta
		
		var life_ratio: float = float(p["age"]) / float(p["lifetime"])
		if life_ratio >= 1.0:
			_dust_particles.remove_at(i)
			continue
		
		# Update position (drift upward and slow down)
		p["position"] += p["velocity"] * delta
		p["velocity"] *= 0.95  # Slow down
		p["velocity"].y -= 30.0 * delta  # Rise slightly
		
		# Grow and fade
		p["radius"] += 8.0 * delta
		p["alpha"] = (1.0 - life_ratio) * p["color"].a
		
		_dust_particles[i] = p
		i += 1

func _spawn_speed_line(velocity: Vector2) -> void:
	if _speed_lines.size() >= MAX_SPEED_LINES:
		return
	
	var move_dir := velocity.normalized()
	var perp := Vector2(-move_dir.y, move_dir.x)
	
	# Spawn lines around the player, offset perpendicular to movement
	var side_offset := perp * _rng.randf_range(-30, 30)
	var back_offset := -move_dir * _rng.randf_range(10, 40)
	
	var line := {
		"start": _player.global_position + side_offset + back_offset,
		"direction": -move_dir,
		"length": SPEED_LINE_LENGTH * _rng.randf_range(0.6, 1.2),
		"width": _rng.randf_range(1.5, 3.0),
		"alpha": _rng.randf_range(0.5, 0.9),
		"lifetime": 0.15,
		"age": 0.0
	}
	_speed_lines.append(line)

func _update_speed_lines(delta: float) -> void:
	var i := 0
	while i < _speed_lines.size():
		var line: Dictionary = _speed_lines[i]
		line["age"] += delta
		
		var life_ratio: float = float(line["age"]) / float(line["lifetime"])
		if life_ratio >= 1.0:
			_speed_lines.remove_at(i)
			continue
		
		# Fade out
		line["alpha"] = (1.0 - life_ratio) * 0.8
		
		_speed_lines[i] = line
		i += 1

func _spawn_footstep_impact(velocity: Vector2) -> void:
	# Small burst of dust at feet
	var move_dir := velocity.normalized()
	for j in range(3):
		if _dust_particles.size() >= MAX_DUST_PARTICLES:
			break
		
		var angle := _rng.randf_range(-PI * 0.6, PI * 0.6)
		var impact_dir := (-move_dir).rotated(angle)
		
		var particle := {
			"position": _player.global_position + Vector2(0, 8),  # At feet level
			"velocity": impact_dir * _rng.randf_range(30, 60) + Vector2(0, -20),
			"radius": _rng.randf_range(2.0, 4.0),
			"alpha": _rng.randf_range(0.5, 0.8),
			"lifetime": _rng.randf_range(0.2, 0.35),
			"age": 0.0,
			"color": DUST_BASE_COLOR
		}
		_dust_particles.append(particle)

func _draw() -> void:
	# Draw dust particles
	for p in _dust_particles:
		var local_pos: Vector2 = p["position"] - _player.global_position
		var color: Color = p["color"]
		color.a = p["alpha"]
		
		# Draw soft dust puff (outer + inner)
		var outer_color := Color(color.r, color.g, color.b, color.a * 0.4)
		draw_circle(local_pos, p["radius"] * 1.5, outer_color)
		draw_circle(local_pos, p["radius"], color)
	
	# Draw speed lines
	for line in _speed_lines:
		var local_start: Vector2 = line["start"] - _player.global_position
		var local_end: Vector2 = local_start + line["direction"] * line["length"]
		
		var color := SPEED_LINE_COLOR
		color.a = line["alpha"]
		
		# Draw line with gradient (thick to thin)
		draw_line(local_start, local_end, color, line["width"])
		
		# Bright tip
		var tip_color := Color(1.0, 1.0, 1.0, line["alpha"] * 1.2)
		draw_circle(local_start, line["width"] * 0.6, tip_color)
