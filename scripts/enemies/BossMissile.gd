extends Area2D
class_name BossMissile

## Red missile fired by boss - targets a fixed location near player
## Shows a red ground indicator where it will land
## Launch animation: shoots out from boss, arcs up, then curves toward target

# Missile settings
const INITIAL_SPEED := 80.0      # Faster start (was 50)
const MAX_SPEED := 700.0         # Faster max speed (was 500)
const ACCELERATION := 280.0      # Faster acceleration (was 180)
const LIFETIME := 6.0            # Shorter lifetime (was 8)
const AOE_RADIUS := 120.0        # Explosion radius (slightly smaller)
const AOE_DAMAGE := 2            # Damage dealt by explosion
const MISSILE_SCALE := 0.65      # Slightly smaller than player missiles
const TARGET_OFFSET_RANGE := 200.0  # Distance from player center to target (increased for spread)
const INDICATOR_RADIUS := 80.0   # Visual radius of ground indicator
const SPREAD_ARC := PI * 1.2     # Total arc width for spreading missiles (about 216 degrees)

# Launch phase settings (submarine-style launch)
const BASE_LAUNCH_PHASE_DURATION := 0.4   # Time spent in initial launch phase
const LAUNCH_SPEED := 350.0               # Speed during launch phase
const LAUNCH_ARC_HEIGHT := 80.0           # How high the arc goes
const BASE_TURN_PHASE_DURATION := 0.35    # Time spent turning toward target

# Actual phase durations (reduced by 30% in Goddess Fall)
var _launch_phase_duration := BASE_LAUNCH_PHASE_DURATION
var _turn_phase_duration := BASE_TURN_PHASE_DURATION

# Launch phase state
enum MissilePhase { LAUNCH, TURN, CRUISE }
var _phase: int = MissilePhase.LAUNCH
var _phase_timer: float = 0.0
var _launch_direction := Vector2.UP  # Initial launch direction (away from boss)
var _boss_position := Vector2.ZERO   # Where the boss was when missile spawned

# State
var _player: Node2D = null
var _velocity := Vector2.ZERO
var _current_speed := INITIAL_SPEED
var _direction := Vector2.RIGHT
var _lifetime_timer := LIFETIME
var _target_position := Vector2.ZERO  # Fixed target position
var _launch_delay := 0.0
var _launched := false
var _ground_indicator: Node2D = null  # Visual indicator for impact zone

# Rocket visual settings (matching ExplosiveProjectile style)
var _body_length := 74.0 * MISSILE_SCALE
var _body_width := 20.0 * MISSILE_SCALE
var _exhaust_length := 42.0 * MISSILE_SCALE

# Trail settings (reduced for performance)
var _trail_points: Array = []
var _trail_ages: Array = []
const TRAIL_WIDTH := 16.0 * MISSILE_SCALE
const TRAIL_MAX_POINTS := 4  # Reduced from 6
const TRAIL_SPACING := 50.0 * MISSILE_SCALE  # Increased spacing

# Smoke settings (reduced for performance)
var _smoke_puffs: Array = []
var _smoke_timer := 0.0
const SMOKE_SPAWN_INTERVAL := 0.18  # Reduced spawn rate
const SMOKE_INITIAL_RADIUS := 8.0 * MISSILE_SCALE
const SMOKE_GROWTH_RATE := 22.0
const SMOKE_FADE_SPEED := 0.9  # Faster fade
const MAX_SMOKE_PUFFS := 4  # Reduced from 8

# Animation state
var _exhaust_time := 0.0
var _flicker_seed := 0.0
var _wobble_offset := 0.0
var _thrust_pulse := 0.0
var _age := 0.0
var _trail_distance := 0.0

# Colors (red/orange for enemy)
var _trail_color := Color(1.0, 0.1, 0.1, 0.8) # Red trail
var _smoke_color := Color(0.5, 0.5, 0.5, 0.85)

# Glow sprite
var _glow_sprite: Sprite2D = null

# Static cached textures (shared across all missiles)
static var _cached_glow_texture: Texture2D = null

# Redraw throttle
var _redraw_frame: int = 0

# Damage (can be scaled by Goddess Fall)
var damage: int = AOE_DAMAGE

func initialize(player: Node2D, delay: float = 0.0, spread_index: int = 0, total_missiles: int = 1, scaled_damage: int = AOE_DAMAGE) -> void:
	_player = player
	_launch_delay = delay
	damage = scaled_damage
	
	# Goddess Fall: 30% faster charge/launch times
	if GameState and GameState.goddess_fall_mode:
		_launch_phase_duration = BASE_LAUNCH_PHASE_DURATION * 0.7
		_turn_phase_duration = BASE_TURN_PHASE_DURATION * 0.7
	
	# Store boss position for launch animation
	_boss_position = global_position
	
	# Calculate fixed target position near player
	# Spread missiles in an arc toward the player so they don't overlap
	if player and is_instance_valid(player):
		# Base direction from missile spawn to player
		var base_dir := (player.global_position - global_position).normalized()
		var base_angle := base_dir.angle()
		
		# Launch direction is AWAY from player (opposite of target direction)
		# Add some upward bias and random spread for variety
		var launch_angle := base_angle + PI + randf_range(-0.4, 0.4)  # Opposite + random
		_launch_direction = Vector2.from_angle(launch_angle)
		
		# Calculate spread angle for this missile
		# Distribute missiles evenly across the arc, with slight randomness
		var spread_offset := 0.0
		if total_missiles > 1:
			# Spread from -SPREAD_ARC/2 to +SPREAD_ARC/2
			var t := float(spread_index) / float(total_missiles - 1)  # 0 to 1
			spread_offset = (t - 0.5) * SPREAD_ARC
			# Add small random jitter
			spread_offset += randf_range(-0.15, 0.15)
		else:
			# Single missile gets random offset within smaller arc
			spread_offset = randf_range(-SPREAD_ARC * 0.25, SPREAD_ARC * 0.25)
		
		var target_angle := base_angle + spread_offset
		var distance := randf_range(TARGET_OFFSET_RANGE * 0.5, TARGET_OFFSET_RANGE * 1.5)
		var offset := Vector2.from_angle(target_angle) * distance
		_target_position = player.global_position + offset
		_direction = (_target_position - global_position).normalized()
		
		# Create ground indicator at target position
		_create_ground_indicator()
	
	# Ensure we have a valid direction
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT
	if _launch_direction == Vector2.ZERO:
		_launch_direction = -_direction  # Default: opposite of target

func _create_ground_indicator() -> void:
	_ground_indicator = Node2D.new()
	_ground_indicator.global_position = _target_position
	_ground_indicator.set_script(preload("res://scripts/enemies/BossMissileIndicator.gd"))
	if _ground_indicator.has_method("initialize"):
		_ground_indicator.initialize(INDICATOR_RADIUS)
	
	# Add to parent so it persists after missile is freed
	call_deferred("_add_indicator_to_scene")

func _ready() -> void:
	# Make missile unshaded but MIX blend for solid dark look
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# PHYSICS SETUP for Scarlet Slash detection
	collision_layer = 4 # Layer 3 (Enemy Projectiles)
	collision_mask = 0  # We handle player calc manually
	add_to_group("enemy_projectiles")
	
	# Add collision shape
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 20.0
	shape.shape = circle
	add_child(shape)
	
	_flicker_seed = randf_range(0.0, TAU)
	_velocity = _direction * _current_speed
	_trail_points.append(global_position)
	_trail_ages.append(0.0)
	# Start behind boss sprite so missiles appear to shoot out from inside
	z_index = -1
	_ensure_glow_sprite()
	queue_redraw()

func _ensure_glow_sprite() -> void:
	if _glow_sprite:
		return
	# Use static cached texture for all missiles
	if _cached_glow_texture == null:
		_cached_glow_texture = _create_radial_glow_texture()
	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = _cached_glow_texture
	_glow_sprite.centered = true
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX # Darker glow for day visibility
	glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow_sprite.material = glow_material
	_glow_sprite.visible = true
	_glow_sprite.modulate = Color(0.5, 0.0, 0.0, 0.6) # Deep dark red glow
	_glow_sprite.scale = Vector2.ONE * 0.8 * MISSILE_SCALE
	add_child(_glow_sprite)

func _create_radial_glow_texture(size: int = 128) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var max_distance := center.length()
	for y in size:
		for x in size:
			var pos := Vector2(x + 0.5, y + 0.5)
			var distance := pos.distance_to(center)
			var normalized := clampf(distance / max_distance, 0.0, 1.0)
			var falloff := pow(1.0 - normalized, 2.4)
			var alpha := clampf(falloff, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	# Handle launch delay
	if _launch_delay > 0:
		_launch_delay -= delta
		return
	
	if not _launched:
		_launched = true
		_phase = MissilePhase.LAUNCH
		_phase_timer = 0.0
		_current_speed = LAUNCH_SPEED
		_velocity = _launch_direction * _current_speed
	
	_age += delta
	_phase_timer += delta
	
	# Wobble and thrust pulse animations
	_wobble_offset = sin(_age * 25.0) * 0.03 + sin(_age * 40.0) * 0.015
	_thrust_pulse = 0.8 + sin(_age * 35.0) * 0.2 + sin(_age * 55.0) * 0.1
	
	# Update lifetime
	_lifetime_timer -= delta
	if _lifetime_timer <= 0:
		_explode()
		return
	
	# Phase-based movement
	var step := Vector2.ZERO
	
	match _phase:
		MissilePhase.LAUNCH:
			# Shoot out away from boss with slight arc
			var launch_progress: float = _phase_timer / _launch_phase_duration
			_current_speed = LAUNCH_SPEED * (1.0 + launch_progress * 0.5)  # Accelerate slightly
			
			# Add slight upward arc (perpendicular to launch direction)
			var arc_offset := sin(launch_progress * PI) * LAUNCH_ARC_HEIGHT * delta
			var perp := Vector2(-_launch_direction.y, _launch_direction.x)
			
			_velocity = _launch_direction * _current_speed
			step = _velocity * delta + perp * arc_offset
			
			if _phase_timer >= _launch_phase_duration:
				_phase = MissilePhase.TURN
				_phase_timer = 0.0
		
		MissilePhase.TURN:
			# Smoothly turn from launch direction toward target
			var turn_progress: float = _phase_timer / _turn_phase_duration
			turn_progress = _ease_out_cubic(turn_progress)  # Smooth easing
			
			# Recalculate target direction (in case player moved slightly)
			var target_dir := (_target_position - global_position).normalized()
			
			# Interpolate between launch direction and target direction
			var current_angle := _launch_direction.angle()
			var target_angle := target_dir.angle()
			var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
			var interpolated_angle: float = current_angle + angle_diff * turn_progress
			
			var move_dir := Vector2.from_angle(interpolated_angle)
			_current_speed = lerpf(LAUNCH_SPEED, INITIAL_SPEED * 2.0, turn_progress)
			_velocity = move_dir * _current_speed
			step = _velocity * delta
			
			if _phase_timer >= _turn_phase_duration:
				_phase = MissilePhase.CRUISE
				_current_speed = INITIAL_SPEED
		
		MissilePhase.CRUISE:
			# Normal cruise toward target (original behavior)
			_current_speed = minf(_current_speed + ACCELERATION * delta, MAX_SPEED)
			_velocity = _direction * _current_speed
			step = _velocity * delta
			
			# Check if we've reached or passed the target
			var dist_to_target := global_position.distance_to(_target_position)
			if dist_to_target < 30.0 or _has_passed_target():
				_explode()
				return
	
	global_position += step
	
	# Update visual rotation to match velocity direction
	if _velocity.length() > 0:
		_direction = _velocity.normalized()
	
	# Update trail
	_update_trail(step.length())
	_advance_trail_ages(delta)
	
	# Update smoke
	_update_smoke(delta)
	
	# Update exhaust animation
	_exhaust_time += delta
	
	# Update glow position
	_update_glow_visual()
	
	# Throttle redraws - only redraw every 2nd frame for performance
	_redraw_frame += 1
	if _redraw_frame % 2 == 0:
		queue_redraw()
	
	# Check collision with player (direct hit)
	if _player and is_instance_valid(_player):
		var dist := global_position.distance_to(_player.global_position)
		if dist < 25.0:
			_explode()

func _update_trail(distance_moved: float) -> void:
	_trail_distance += distance_moved
	if _trail_distance >= TRAIL_SPACING:
		_trail_distance = 0.0
		_trail_points.insert(0, global_position)
		_trail_ages.insert(0, 0.0)
		while _trail_points.size() > TRAIL_MAX_POINTS:
			_trail_points.pop_back()
			_trail_ages.pop_back()

func _advance_trail_ages(delta: float) -> void:
	for i in range(_trail_ages.size()):
		_trail_ages[i] += delta

func _update_smoke(delta: float) -> void:
	_smoke_timer += delta
	if _smoke_timer >= SMOKE_SPAWN_INTERVAL and _smoke_puffs.size() < MAX_SMOKE_PUFFS:
		_smoke_timer = 0.0
		var dir := _velocity.normalized() if _velocity.length() > 0 else Vector2.RIGHT
		var spawn_pos := global_position - dir * (_body_length * 0.5)
		spawn_pos += Vector2(randf_range(-5, 5), randf_range(-5, 5)) * MISSILE_SCALE
		_smoke_puffs.append({
			"position": spawn_pos,
			"radius": SMOKE_INITIAL_RADIUS,
			"alpha": _smoke_color.a,
			"color": _smoke_color
		})
	
	# Update existing smoke
	var i := 0
	while i < _smoke_puffs.size():
		var puff: Dictionary = _smoke_puffs[i]
		puff["radius"] += SMOKE_GROWTH_RATE * delta
		puff["alpha"] *= pow(SMOKE_FADE_SPEED, delta * 60.0)
		if puff["alpha"] < 0.01:
			_smoke_puffs.remove_at(i)
			continue
		_smoke_puffs[i] = puff
		i += 1

func _update_glow_visual() -> void:
	if _glow_sprite == null:
		return
	var dir := _velocity.normalized() if _velocity.length() > 0 else Vector2.RIGHT
	var offset := -dir * _exhaust_length * 0.5
	_glow_sprite.position = offset
	_glow_sprite.rotation = dir.angle()
	var pulse := 0.6 + _thrust_pulse * 0.3
	_glow_sprite.modulate.a = pulse

func _draw() -> void:
	# Draw trail first (behind everything)
	_draw_trail()
	
	# Draw smoke
	_draw_smoke()
	
	# Draw rocket body and exhaust
	_draw_rocket()

func _draw_trail() -> void:
	if _trail_points.is_empty():
		return
	# Simplified trail - fewer circles, less layering
	var count := mini(_trail_points.size(), TRAIL_MAX_POINTS)
	for i in range(count):
		var t := float(i) / maxf(1.0, float(count - 1))
		var fade := 1.0 - t * 0.8
		if fade < 0.15:
			continue
		var local: Vector2 = _trail_points[i] - global_position
		var radius := TRAIL_WIDTH * (1.0 - t * 0.5)
		var color := Color(_trail_color.r, _trail_color.g, _trail_color.b, _trail_color.a * fade)
		draw_circle(local, radius, color)

func _draw_smoke() -> void:
	# Simplified smoke - single circle per puff
	for puff_variant in _smoke_puffs:
		if not (puff_variant is Dictionary):
			continue
		var puff := puff_variant as Dictionary
		var radius: float = float(puff.get("radius", SMOKE_INITIAL_RADIUS))
		var alpha: float = clampf(float(puff.get("alpha", _smoke_color.a)), 0.0, 1.0)
		if alpha <= 0.05 or radius <= 1.0:
			continue
		var puff_color: Color = puff.get("color", _smoke_color)
		var color := Color(puff_color.r, puff_color.g, puff_color.b, alpha * 0.7)
		var local := (puff.get("position", global_position) as Vector2) - global_position
		draw_circle(local, radius, color)

func _draw_rocket() -> void:
	var dir := _velocity.normalized() if _velocity.length() > 0 else Vector2.RIGHT
	
	# Apply wobble
	dir = dir.rotated(_wobble_offset)
	var perp := Vector2(-dir.y, dir.x)
	
	# Draw exhaust first (behind body)
	_draw_rocket_exhaust(dir, perp)
	
	# Draw body
	_draw_rocket_body(dir, perp)

func _draw_rocket_exhaust(dir: Vector2, perp: Vector2) -> void:
	var tail := -dir * (_body_length * 0.5 - _body_width * 0.12)
	var flicker := 1.0 + 0.3 * sin(_exhaust_time * 18.0 + _flicker_seed)
	flicker *= _thrust_pulse
	
	var outer_length := _exhaust_length * 1.15 * flicker
	var outer_width := _body_width * 1.4 * (0.9 + _thrust_pulse * 0.15)
	var outer_tip := tail - dir * outer_length
	var outer_left := tail + perp * outer_width
	var outer_right := tail - perp * outer_width
	var outer_color := Color(0.6, 0.0, 0.0, 0.9)  # Deep dark red for outer
	draw_polygon(
		PackedVector2Array([outer_tip, outer_right, tail, outer_left]),
		PackedColorArray([outer_color, outer_color, outer_color, outer_color])
	)
	
	var inner_length := outer_length * 0.62
	var inner_width := outer_width * 0.55
	var inner_tip := tail - dir * inner_length
	var inner_left := tail + perp * inner_width
	var inner_right := tail - perp * inner_width
	var inner_color := Color(0.8, 0.1, 0.0, 0.95)  # Dark red for inner
	draw_polygon(
		PackedVector2Array([inner_tip, inner_right, tail, inner_left]),
		PackedColorArray([inner_color, inner_color, inner_color, inner_color])
	)
	
	var core_length := inner_length * 0.55
	var core_width := inner_width * 0.45
	var core_tip := tail - dir * core_length
	var core_left := tail + perp * core_width
	var core_right := tail - perp * core_width
	var core_color := Color(0.4, 0.0, 0.0, 1.0)  # Very dark core
	draw_polygon(
		PackedVector2Array([core_tip, core_right, tail, core_left]),
		PackedColorArray([core_color, core_color, core_color, core_color])
	)
	
	# Exhaust glow
	var glow_radius: float = max(_body_width * 0.85, inner_width * 0.9)
	var glow_color := Color(outer_color.r, outer_color.g, outer_color.b, outer_color.a * 0.5)
	draw_circle(tail, glow_radius, glow_color)

func _draw_rocket_body(dir: Vector2, perp: Vector2) -> void:
	var half_length := _body_length * 0.5
	var segment_count := 4
	var segment_span := _body_length / float(segment_count)
	var segment_half_width := _body_width * 0.5
	
	for segment_index in range(segment_count):
		var start_offset := -half_length + segment_span * float(segment_index)
		var end_offset := start_offset + segment_span * 0.9
		var start_vec := dir * start_offset
		var end_vec := dir * end_offset
		var intensity: float = float(segment_index) / max(1.0, float(segment_count - 1))
		
		# Red/dark body color for enemy missile
		var segment_color := Color(0.55 + 0.2 * intensity, 0.2 + 0.1 * intensity, 0.2 + 0.08 * intensity, 1.0)
		
		var body_points := PackedVector2Array([
			end_vec + perp * segment_half_width,
			end_vec - perp * segment_half_width,
			start_vec - perp * segment_half_width,
			start_vec + perp * segment_half_width
		])
		draw_polygon(body_points, PackedColorArray([segment_color, segment_color, segment_color, segment_color]))
	
	# Nose cone (pointy front)
	var nose_length := _body_width * 0.8
	var nose_tip := dir * (half_length + nose_length)
	var nose_base_left := dir * half_length + perp * segment_half_width
	var nose_base_right := dir * half_length - perp * segment_half_width
	var nose_color := Color(0.85, 0.3, 0.2, 1.0)  # Brighter red nose
	draw_polygon(
		PackedVector2Array([nose_tip, nose_base_right, nose_base_left]),
		PackedColorArray([nose_color, nose_color, nose_color])
	)
	
	# Fins at back
	var fin_length := _body_width * 0.6
	var fin_width := _body_width * 0.4
	var fin_base := -dir * half_length
	for side in [-1.0, 1.0]:
		var fin_outer: Vector2 = fin_base + perp * (segment_half_width + fin_width) * side
		var fin_tip: Vector2 = fin_base - dir * fin_length + perp * segment_half_width * side * 0.5
		var fin_inner: Vector2 = fin_base + perp * segment_half_width * side
		var fin_color := Color(0.5, 0.18, 0.15, 1.0)  # Dark red fins
		draw_polygon(
			PackedVector2Array([fin_outer, fin_tip, fin_inner]),
			PackedColorArray([fin_color, fin_color, fin_color])
		)

func _add_indicator_to_scene() -> void:
	if _ground_indicator and get_parent():
		get_parent().add_child(_ground_indicator)

func _has_passed_target() -> bool:
	# Check if missile has flown past the target
	var to_target := _target_position - global_position
	return _direction.dot(to_target) < 0

func _explode() -> void:
	# Remove ground indicator
	if _ground_indicator and is_instance_valid(_ground_indicator):
		_ground_indicator.queue_free()
	
	# Create AOE explosion effect
	var explosion := Node2D.new()
	explosion.set_script(preload("res://scripts/enemies/BossMissileExplosion.gd"))
	explosion.global_position = global_position
	if explosion.has_method("initialize"):
		explosion.initialize(AOE_RADIUS, damage, _player)
	
	if get_parent():
		get_parent().add_child(explosion)
	
	queue_free()

## Smooth cubic easing function for turn phase
func _ease_out_cubic(t: float) -> float:
	var x := 1.0 - t
	return 1.0 - x * x * x
