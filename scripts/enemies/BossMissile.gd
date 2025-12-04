extends Node2D
class_name BossMissile

## Red tracking missile fired by boss - uses same rocket visuals as Rapunzel's missiles
## Has poor tracking - aims near the player but generally misses

# Missile settings
const INITIAL_SPEED := 50.0      # Slow start
const MAX_SPEED := 500.0         # Slightly slower than player missiles
const ACCELERATION := 180.0      # Speed increase per second
const TURN_SPEED := 1.8          # Reduced turn speed for poor tracking
const LIFETIME := 8.0            # Max lifetime before self-destruct
const TRACKING_DURATION := 2.5   # How long missile tracks player
const AOE_RADIUS := 120.0        # Explosion radius (slightly smaller)
const AOE_DAMAGE := 2            # Damage dealt by explosion
const MISSILE_SCALE := 0.65      # Slightly smaller than player missiles

# Inaccuracy settings - missile aims near player, not at them
const AIM_OFFSET_RANGE := 150.0  # Random offset from player position
const AIM_UPDATE_INTERVAL := 0.5 # How often to recalculate aim offset

# State
var _player: Node2D = null
var _velocity := Vector2.ZERO
var _current_speed := INITIAL_SPEED
var _direction := Vector2.RIGHT
var _lifetime_timer := LIFETIME
var _tracking_timer := TRACKING_DURATION
var _launch_delay := 0.0
var _launched := false
var _aim_offset := Vector2.ZERO  # Random offset for poor aiming
var _aim_update_timer := 0.0

# Rocket visual settings (matching ExplosiveProjectile style)
var _body_length := 74.0 * MISSILE_SCALE
var _body_width := 20.0 * MISSILE_SCALE
var _exhaust_length := 42.0 * MISSILE_SCALE

# Trail settings
var _trail_points: Array = []
var _trail_ages: Array = []
const TRAIL_WIDTH := 18.0 * MISSILE_SCALE
const TRAIL_MAX_POINTS := 12
const TRAIL_SPACING := 28.0 * MISSILE_SCALE

# Smoke settings
var _smoke_puffs: Array = []
var _smoke_timer := 0.0
const SMOKE_SPAWN_INTERVAL := 0.05
const SMOKE_INITIAL_RADIUS := 10.0 * MISSILE_SCALE
const SMOKE_GROWTH_RATE := 28.0
const SMOKE_FADE_SPEED := 0.9

# Animation state
var _exhaust_time := 0.0
var _flicker_seed := 0.0
var _wobble_offset := 0.0
var _thrust_pulse := 0.0
var _age := 0.0
var _trail_distance := 0.0

# Colors (red/orange for enemy)
var _trail_color := Color(1.0, 0.4, 0.2, 0.8)
var _trail_core_color := Color(1.0, 0.7, 0.5, 0.9)
var _trail_glow_color := Color(1.0, 0.3, 0.1, 0.6)
var _smoke_color := Color(0.5, 0.5, 0.5, 0.85)

# Glow sprite
var _glow_sprite: Sprite2D = null
var _glow_texture: Texture2D = null

func initialize(player: Node2D, delay: float = 0.0) -> void:
	_player = player
	_launch_delay = delay
	
	# Calculate initial direction toward player with offset
	_update_aim_offset()
	if player and is_instance_valid(player):
		var target_pos := player.global_position + _aim_offset
		_direction = (target_pos - global_position).normalized()
	
	# Ensure we have a valid direction
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT

func _update_aim_offset() -> void:
	# Random offset so missile aims near player, not directly at them
	var angle := randf() * TAU
	var distance := randf_range(AIM_OFFSET_RANGE * 0.5, AIM_OFFSET_RANGE)
	_aim_offset = Vector2.from_angle(angle) * distance
	_aim_update_timer = AIM_UPDATE_INTERVAL

func _ready() -> void:
	_flicker_seed = randf_range(0.0, TAU)
	_velocity = _direction * _current_speed
	_trail_points.append(global_position)
	_trail_ages.append(0.0)
	_ensure_glow_sprite()
	queue_redraw()

func _ensure_glow_sprite() -> void:
	if _glow_sprite:
		return
	if _glow_texture == null:
		_glow_texture = _create_radial_glow_texture()
	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = _glow_texture
	_glow_sprite.centered = true
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_sprite.material = glow_material
	_glow_sprite.visible = true
	_glow_sprite.modulate = Color(1.0, 0.4, 0.15, 0.7)
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
		_velocity = _direction * _current_speed
	
	_age += delta
	
	# Wobble and thrust pulse animations
	_wobble_offset = sin(_age * 25.0) * 0.03 + sin(_age * 40.0) * 0.015
	_thrust_pulse = 0.8 + sin(_age * 35.0) * 0.2 + sin(_age * 55.0) * 0.1
	
	# Update lifetime
	_lifetime_timer -= delta
	if _lifetime_timer <= 0:
		_explode()
		return
	
	# Update aim offset periodically for varied inaccuracy
	_aim_update_timer -= delta
	if _aim_update_timer <= 0:
		_update_aim_offset()
	
	# Track player during tracking phase (with offset for poor aiming)
	if _tracking_timer > 0 and _player and is_instance_valid(_player):
		_tracking_timer -= delta
		var target_pos := _player.global_position + _aim_offset
		var to_target := (target_pos - global_position).normalized()
		var target_angle := to_target.angle()
		var current_angle := _direction.angle()
		var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
		var turn := clampf(angle_diff, -TURN_SPEED * delta, TURN_SPEED * delta)
		_direction = Vector2.from_angle(current_angle + turn)
	
	# Accelerate
	_current_speed = minf(_current_speed + ACCELERATION * delta, MAX_SPEED)
	
	# Move
	_velocity = _direction * _current_speed
	var step := _velocity * delta
	global_position += step
	
	# Update trail
	_update_trail(step.length())
	_advance_trail_ages(delta)
	
	# Update smoke
	_update_smoke(delta)
	
	# Update exhaust animation
	_exhaust_time += delta
	
	# Update glow position
	_update_glow_visual()
	
	queue_redraw()
	
	# Check collision with player
	if _player and is_instance_valid(_player):
		var dist := global_position.distance_to(_player.global_position)
		if dist < 25.0:  # Direct hit (smaller hitbox)
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
	if _smoke_timer >= SMOKE_SPAWN_INTERVAL:
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
	var total_points := _trail_points.size() + 1
	if total_points <= 1:
		return
	for idx in range(total_points):
		var array_index := total_points - 1 - idx
		var point: Vector2
		var age: float = 0.0
		if array_index == _trail_points.size():
			point = global_position
		else:
			point = _trail_points[array_index]
			if array_index < _trail_ages.size():
				age = _trail_ages[array_index]
		var t: float = float(idx) / max(1.0, float(total_points - 1))
		var fade: float = clampf(1.0 - t * 0.9, 0.0, 1.0) * clampf(1.0 - age * 0.7, 0.0, 1.0)
		if fade <= 0.01:
			continue
		var local := point - global_position
		var main_radius: float = lerpf(TRAIL_WIDTH, TRAIL_WIDTH * 0.2, t)
		if main_radius <= 0.5:
			continue
		var outer_color := Color(_trail_color.r, _trail_color.g, _trail_color.b, _trail_color.a * fade)
		var core_color := Color(_trail_core_color.r, _trail_core_color.g, _trail_core_color.b, _trail_core_color.a * fade * 0.9)
		var glow_color := Color(_trail_glow_color.r, _trail_glow_color.g, _trail_glow_color.b, _trail_glow_color.a * fade * 0.6)
		draw_circle(local, main_radius * 1.5, glow_color)
		draw_circle(local, main_radius, outer_color)
		draw_circle(local, main_radius * 0.45, core_color)

func _draw_smoke() -> void:
	for puff_variant in _smoke_puffs:
		if not (puff_variant is Dictionary):
			continue
		var puff := puff_variant as Dictionary
		var radius: float = float(puff.get("radius", SMOKE_INITIAL_RADIUS))
		var alpha: float = clampf(float(puff.get("alpha", _smoke_color.a)), 0.0, 1.0)
		if alpha <= 0.01 or radius <= 0.5:
			continue
		var puff_color: Color = puff.get("color", _smoke_color)
		var outer := Color(puff_color.r, puff_color.g, puff_color.b, alpha * 0.35)
		var core := Color(puff_color.r * 0.9, puff_color.g * 0.9, puff_color.b * 0.9, alpha)
		var local := (puff.get("position", global_position) as Vector2) - global_position
		draw_circle(local, radius * 1.6, outer)
		draw_circle(local, radius, core)

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
	var outer_color := Color(1.0, 0.35, 0.1, 0.85)  # Red-orange for enemy
	draw_polygon(
		PackedVector2Array([outer_tip, outer_right, tail, outer_left]),
		PackedColorArray([outer_color, outer_color, outer_color, outer_color])
	)
	
	var inner_length := outer_length * 0.62
	var inner_width := outer_width * 0.55
	var inner_tip := tail - dir * inner_length
	var inner_left := tail + perp * inner_width
	var inner_right := tail - perp * inner_width
	var inner_color := Color(1.0, 0.65, 0.3, 0.92)  # Orange-yellow
	draw_polygon(
		PackedVector2Array([inner_tip, inner_right, tail, inner_left]),
		PackedColorArray([inner_color, inner_color, inner_color, inner_color])
	)
	
	var core_length := inner_length * 0.55
	var core_width := inner_width * 0.45
	var core_tip := tail - dir * core_length
	var core_left := tail + perp * core_width
	var core_right := tail - perp * core_width
	var core_color := Color(1.0, 0.95, 0.75, 0.95)  # Hot white-yellow
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

func _explode() -> void:
	# Create AOE explosion effect
	var explosion := Node2D.new()
	explosion.set_script(preload("res://scripts/enemies/BossMissileExplosion.gd"))
	explosion.global_position = global_position
	if explosion.has_method("initialize"):
		explosion.initialize(AOE_RADIUS, AOE_DAMAGE, _player)
	
	if get_parent():
		get_parent().add_child(explosion)
	
	queue_free()
