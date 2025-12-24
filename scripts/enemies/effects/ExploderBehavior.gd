extends Node2D
class_name ExploderBehavior

## Suicide bomber behavior for Exploder enemy type
## 10-second countdown once visible or near player. Timer-based only, no HP drain.
## Red fiery burning effect on sprite and HP bar area.

var owner_enemy: Node2D = null
var explosion_damage: int = 20
var explosion_radius: float = 150.0

# Behavior settings
const DETONATION_RANGE := 100.0
const FUSE_DURATION := 10.0
const FINAL_COUNTDOWN := 1.0

# State
enum State {WAITING, BURNING, COUNTDOWN, EXPLODING}
var _state: State = State.WAITING
var _fuse_timer: float = 0.0
var _countdown_timer: float = 0.0
var _strobe_time: float = 0.0

# Visual
var _warning_radius: float = 0.0
var _strobe_intensity: float = 0.0
var _distance_to_player: float = 1000.0
var _sparkle_particles: Array = []
var _original_modulate: Color = Color.WHITE


func initialize(enemy: Node2D, damage: int) -> void:
	owner_enemy = enemy
	explosion_damage = damage
	enemy.add_to_group("exploder")
	
	# Store original modulate
	var sprite = _get_sprite()
	if sprite:
		_original_modulate = sprite.modulate


func _ready() -> void:
	z_index = 100


func _get_sprite() -> CanvasItem:
	if not owner_enemy:
		return null
	var sprite = owner_enemy.get_node_or_null("AnimatedSprite2D")
	if not sprite:
		sprite = owner_enemy.get("visuals")
	return sprite


func _process(delta: float) -> void:
	if not owner_enemy or not is_instance_valid(owner_enemy):
		queue_free()
		return
	
	# Fix: Check for enemy death (prevents red circle from lingering after kill)
	var hc = owner_enemy.get("health_component")
	if is_instance_valid(hc) and hc.has_method("is_dead") and hc.is_dead():
		if _state != State.EXPLODING:
			queue_free()
			return

	global_position = owner_enemy.global_position
	
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		_distance_to_player = global_position.distance_to(player.global_position)
	
	# Strobe effect - faster as fuse burns
	var flicker_speed = 5.0
	if _state != State.WAITING:
		var burn_progress = _fuse_timer / FUSE_DURATION
		flicker_speed = 5.0 + burn_progress * 20.0
	_strobe_time += delta * flicker_speed
	_strobe_intensity = (sin(_strobe_time) + 1.0) * 0.5
	
	# Apply red tint to sprite
	_apply_full_red_tint()
	
	# Update sparkle particles
	_update_sparkles(delta)
	
	match _state:
		State.WAITING:
			_process_waiting(delta)
		State.BURNING:
			_process_burning(delta)
		State.COUNTDOWN:
			_process_countdown(delta)
		State.EXPLODING:
			pass
	
	queue_redraw()


func _process_waiting(_delta: float) -> void:
	var should_trigger = false
	
	if _distance_to_player <= DETONATION_RANGE:
		should_trigger = true
	
	if _is_on_screen():
		should_trigger = true
	
	if should_trigger:
		_start_fuse()


func _start_fuse() -> void:
	_state = State.BURNING
	_fuse_timer = 0.0


func _process_burning(delta: float) -> void:
	_fuse_timer += delta
	
	# Trigger when: fuse burns out OR player enters explosion radius
	if _fuse_timer >= FUSE_DURATION or _distance_to_player <= explosion_radius:
		_state = State.COUNTDOWN
		_countdown_timer = FINAL_COUNTDOWN
		_warning_radius = 0.0


func _process_countdown(delta: float) -> void:
	_countdown_timer -= delta
	
	var progress = 1.0 - (_countdown_timer / FINAL_COUNTDOWN)
	_warning_radius = explosion_radius * progress
	
	_strobe_time += delta * 40.0
	
	if _countdown_timer <= 0:
		_state = State.EXPLODING
		_explode()


func _is_on_screen() -> bool:
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return true
	
	var screen_size = get_viewport_rect().size
	var camera_pos = camera.global_position
	var zoom = camera.zoom if camera.zoom.x > 0 else Vector2.ONE
	var half_screen = screen_size / 2.0 / zoom
	
	var dist_x = abs(global_position.x - camera_pos.x)
	var dist_y = abs(global_position.y - camera_pos.y)
	
	return dist_x < half_screen.x + 50 and dist_y < half_screen.y + 50


func _explode() -> void:
	# Add subtle screen shake for impact
	CombatJuice.add_trauma(0.4)
	
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		var dist = global_position.distance_to(player.global_position)
		if dist <= explosion_radius:
			if player.has_method("take_damage"):
				player.take_damage(explosion_damage, false, Vector2.ZERO, false, "Exploder:Explosion")
	
	# Trigger normal death animation by calling the death handler
	if owner_enemy and is_instance_valid(owner_enemy):
		# Kill the enemy properly - triggers death effect and XP drops
		if owner_enemy.has_method("_on_death"):
			# Call _on_death directly to bypass take_damage and FloatingText generation
			# We pass 0 overkill for standard explosion death
			owner_enemy._on_death(0)
		elif owner_enemy.has_method("die"):
			owner_enemy.die()
		else:
			owner_enemy.queue_free()
	
	await get_tree().create_timer(0.2).timeout
	queue_free()


func _apply_full_red_tint() -> void:
	var sprite = _get_sprite()
	if not sprite:
		return
	
	var target_color = Color.WHITE
	
	if _state == State.WAITING:
		# User request: Start with NO red tint or effect.
		target_color = Color.WHITE
		
	elif _state == State.BURNING:
		# User request: Don't start red shader until 5 seconds before exploding
		if _fuse_timer < 5.0:
			target_color = Color.WHITE
		else:
			# Interpolate from White -> Red between 5s and 10s
			var delay = 5.0
			var active_duration = FUSE_DURATION - delay # 5.0s
			var burn_progress = (_fuse_timer - delay) / active_duration
			
			# Start: White (1,1,1) -> End: Red (1, 0.2, 0.2)
			# Add strobe pulsing on top that gets stronger
			var gb_base = 1.0 - (burn_progress * 0.8) # Drops to 0.2
			
			# Strobe gets intense
			var pulse_strength = 0.1 + burn_progress * 0.2
			var gb_pulse = _strobe_intensity * pulse_strength
			
			var gb_final = clampf(gb_base - gb_pulse, 0.0, 1.0)
			target_color = Color(1.0, gb_final, gb_final)
		
	elif _state == State.COUNTDOWN:
		# Full Red / Flashing to Black or White for urgency?
		# Let's do Red to Dark Red strobe
		var gb = 0.0
		# Strobe intensity 0..1. 
		# When 1 (bright) -> Pure Red (1,0,0)
		# When 0 (dark) -> Dark Red (0.5, 0, 0)? Or just keep Pure Red?
		# User said "fully tinted red".
		target_color = Color(1.0, 0.0, 0.0)
		
		# Optional: Flash white at the very end?
		if _countdown_timer < 0.2:
			target_color = Color(10, 10, 10) # HDR White flash
	
	# Apply
	# Use shader parameter 'sprite_tint' introduced in universal_sprite_shader.gdshader
	# This avoids issues with modulate being ignored or causing darkness depending on shader logic
	if sprite.material is ShaderMaterial:
		sprite.material.set_shader_parameter("sprite_tint", target_color)
	else:
		# Fallback if no shader material (shouldn't happen on enemies usually)
		sprite.modulate = target_color


func _update_sparkles(delta: float) -> void:
	# Update existing particles
	var alive: Array = []
	for p in _sparkle_particles:
		p["life"] -= delta
		if p["life"] > 0:
			p["pos"] += p["vel"] * delta
			p["vel"].y += 100 * delta
			alive.append(p)
	_sparkle_particles = alive
	
	# Spawn particles when burning
	if _state in [State.BURNING, State.COUNTDOWN]:
		var burn_progress = _fuse_timer / FUSE_DURATION if _state == State.BURNING else 1.0
		var spawn_chance = 0.5 + burn_progress * 0.4
		
		if randf() < spawn_chance:
			# Spawn around the entire enemy sprite area
			var spawn_radius = 30.0 * owner_enemy.scale.x
			var angle = randf() * TAU
			var dist = randf_range(5, spawn_radius)
			var spawn_pos = Vector2(cos(angle), sin(angle)) * dist
			
			_sparkle_particles.append({
				"pos": spawn_pos,
				"vel": Vector2(randf_range(-20, 20), randf_range(-50, -20)),
				"life": randf_range(0.3, 0.6),
				"size": randf_range(2.0, 4.0),
				"color": Color(1.0, randf_range(0.1, 0.3), 0.0, 1.0) # Deep red
			})


func _draw() -> void:
	# Final countdown warning circle
	if _state == State.COUNTDOWN:
		var warning_alpha = 0.5 + _strobe_intensity * 0.4
		draw_arc(Vector2.ZERO, _warning_radius, 0, TAU, 48, Color(1.0, 0.2, 0.2, warning_alpha), 4.0)
		draw_circle(Vector2.ZERO, _warning_radius, Color(1.0, 0.2, 0.2, 0.2 + _strobe_intensity * 0.1))
		draw_arc(Vector2.ZERO, explosion_radius, 0, TAU, 48, Color(1.0, 0.2, 0.2, 0.3), 2.0)
	
	# Burning indicator ring - REMOVED per user request (was causing visual clutter/confusion)
	# elif _state == State.BURNING:
	# 	var burn_progress = _fuse_timer / FUSE_DURATION
	# 	var ring_alpha = 0.3 + burn_progress * 0.4 + _strobe_intensity * 0.2
	# 	var ring_size = 25.0 + burn_progress * 15.0
	# 	draw_arc(Vector2.ZERO, ring_size, 0, TAU, 24, Color(1.0, 0.2, 0.1, ring_alpha), 3.0)
	
	# Draw sparkle particles (fire effect)
	for p in _sparkle_particles:
		var alpha = p["life"] * 2.0
		var color = p["color"]
		color.a = alpha
		draw_circle(p["pos"], p["size"], color)
	
	# Draw burning overlay on HP bar area when active
	if _state in [State.BURNING, State.COUNTDOWN] and owner_enemy and is_instance_valid(owner_enemy):
		_draw_hp_bar_fire_overlay()


func _draw_hp_bar_fire_overlay() -> void:
	"""Draw fiery overlay over the HP bar area."""
	# HP bar default size is 50x8. 
	# DRAWING LOGIC NOTE: 
	# This Node2D inherits the Enemy's scale. 
	# Drawing at e.g. (10,10) will result in visual position (10*scale, 10*scale).
	# ModularEnemy HP bar is at offset (-25, -47) * scale.
	# So we draw at (-25, -47) LOCAL to match global (-25, -47) * scale.
	
	var bar_offset = Vector2(-25, -47)
	var bar_pos = bar_offset
	var bar_width = 50.0
	var bar_height = 8.0
	
	# Burning overlay rectangle (red glow covering the bar)
	var burn_progress = _fuse_timer / FUSE_DURATION if _state == State.BURNING else 1.0
	var overlay_alpha = 0.4 + burn_progress * 0.4 + _strobe_intensity * 0.2
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(1.0, 0.1, 0.05, overlay_alpha))
	
	# Fiery border
	var border_intensity = 0.6 + _strobe_intensity * 0.4
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(1.0, 0.4, 0.1, border_intensity), false, 2.0)
	
	# Timer Radial Square (Right of HP bar)
	if _state == State.BURNING:
		var remaining = 1.0 - burn_progress
		var square_size = 12.0
		var square_pos = Vector2(bar_pos.x + bar_width + 4, bar_pos.y + (bar_height - square_size) / 2)
		var center = square_pos + Vector2(square_size, square_size) / 2
		var radius = square_size / 2
		
		# Background (Black)
		draw_rect(Rect2(square_pos, Vector2(square_size, square_size)), Color.BLACK)
		
		# Radial Fill (Red, fills clockwise as time runs out ... or empties?)
		# User said: "goes from black and as the countdown spins it turns red."
		# So it starts black, and FILLS with red.
		# remaining goes 1.0 -> 0.0. burn_progress goes 0.0 -> 1.0.
		# Angle: -90 degrees (up) to start.
		
		var start_angle = - PI / 2
		var end_angle = start_angle + (burn_progress * TAU)
		
		# Create polygon for radial fill
		var points = PackedVector2Array([center])
		var segments = 16
		for i in range(segments + 1):
			var t = float(i) / segments
			var current_angle = lerpf(start_angle, end_angle, t)
			if burn_progress > 0: # Avoid drawing if 0
				points.append(center + Vector2(cos(current_angle), sin(current_angle)) * radius)
		
		if points.size() > 2:
			draw_colored_polygon(points, Color(1.0, 0.2, 0.2, 1.0))
		
		# Border
		draw_rect(Rect2(square_pos, Vector2(square_size, square_size)), Color(1.0, 1.0, 1.0, 0.5), false, 1.0)
