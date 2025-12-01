extends Node2D
class_name BossMissile

## Red tracking missile fired by boss - slow start, fast finish, AOE on impact

# Missile settings
const INITIAL_SPEED := 50.0      # Slow start
const MAX_SPEED := 600.0         # Fast max speed
const ACCELERATION := 200.0      # Speed increase per second
const TURN_SPEED := 2.5          # Radians per second for tracking
const LIFETIME := 8.0            # Max lifetime before self-destruct
const TRACKING_DURATION := 3.0   # How long missile tracks player
const AOE_RADIUS := 150.0        # Explosion radius
const AOE_DAMAGE := 2            # Damage dealt by explosion
const MISSILE_SIZE := Vector2(24, 12)  # Visual size

# State
var _player: Node2D = null
var _velocity := Vector2.ZERO
var _current_speed := INITIAL_SPEED
var _direction := Vector2.RIGHT
var _lifetime_timer := LIFETIME
var _tracking_timer := TRACKING_DURATION
var _launch_delay := 0.0
var _launched := false

# Visuals
var _sprite: Sprite2D = null
var _trail: Line2D = null
var _trail_points: Array[Vector2] = []
const MAX_TRAIL_POINTS := 20

func initialize(player: Node2D, delay: float = 0.0) -> void:
	_player = player
	_launch_delay = delay
	
	# Calculate initial direction toward player
	if player and is_instance_valid(player):
		_direction = (player.global_position - global_position).normalized()
	
	# Ensure we have a valid direction
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT

func _ready() -> void:
	_create_visuals()

func _create_visuals() -> void:
	# Main missile sprite (red elongated shape)
	_sprite = Sprite2D.new()
	_sprite.name = "MissileSprite"
	
	# Create procedural missile texture
	var img := Image.create(int(MISSILE_SIZE.x), int(MISSILE_SIZE.y), false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	
	# Draw missile body (pointed oval)
	var center := MISSILE_SIZE / 2.0
	for x in range(int(MISSILE_SIZE.x)):
		for y in range(int(MISSILE_SIZE.y)):
			var px := float(x) - center.x
			var py := float(y) - center.y
			# Elongated ellipse
			var dist := sqrt((px / (center.x * 0.9)) ** 2 + (py / (center.y * 0.8)) ** 2)
			if dist < 1.0:
				# Gradient from white core to red edge
				var t := dist
				var color := Color(1.0, 0.2 + 0.3 * (1.0 - t), 0.1, 1.0)
				# Brighter at front
				if px > 0:
					color = color.lightened(0.2 * (px / center.x))
				img.set_pixel(x, y, color)
	
	var tex := ImageTexture.create_from_image(img)
	_sprite.texture = tex
	add_child(_sprite)
	
	# Glowing effect
	var glow := PointLight2D.new()
	glow.name = "MissileGlow"
	glow.color = Color(1.0, 0.3, 0.1, 1.0)
	glow.energy = 1.5
	glow.texture_scale = 0.3
	# Create radial gradient
	var grad_tex := GradientTexture2D.new()
	grad_tex.width = 64
	grad_tex.height = 64
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color.WHITE)
	grad.set_color(1, Color.TRANSPARENT)
	grad_tex.gradient = grad
	glow.texture = grad_tex
	add_child(glow)
	
	# Trail effect
	_trail = Line2D.new()
	_trail.name = "MissileTrail"
	_trail.width = 8.0
	_trail.default_color = Color(1.0, 0.4, 0.1, 0.8)
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	# Gradient from full opacity to transparent
	var trail_grad := Gradient.new()
	trail_grad.set_color(0, Color(1.0, 0.4, 0.1, 0.8))
	trail_grad.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	_trail.gradient = trail_grad
	# Add to parent so trail stays in world space
	call_deferred("_add_trail_to_parent")

func _add_trail_to_parent() -> void:
	if get_parent():
		get_parent().add_child(_trail)

func _process(delta: float) -> void:
	# Handle launch delay
	if _launch_delay > 0:
		_launch_delay -= delta
		# Wobble slightly while waiting
		if _sprite:
			_sprite.rotation = sin(Time.get_ticks_msec() * 0.01) * 0.2
		return
	
	if not _launched:
		_launched = true
	
	# Update lifetime
	_lifetime_timer -= delta
	if _lifetime_timer <= 0:
		_explode()
		return
	
	# Track player during tracking phase
	if _tracking_timer > 0 and _player and is_instance_valid(_player):
		_tracking_timer -= delta
		var to_player := (_player.global_position - global_position).normalized()
		var target_angle := to_player.angle()
		var current_angle := _direction.angle()
		var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
		var turn := clampf(angle_diff, -TURN_SPEED * delta, TURN_SPEED * delta)
		_direction = Vector2.from_angle(current_angle + turn)
	
	# Accelerate
	_current_speed = minf(_current_speed + ACCELERATION * delta, MAX_SPEED)
	
	# Move
	_velocity = _direction * _current_speed
	global_position += _velocity * delta
	
	# Rotate sprite to face direction
	if _sprite:
		_sprite.rotation = _direction.angle()
	
	# Update trail
	_update_trail()
	
	# Check collision with player
	if _player and is_instance_valid(_player):
		var dist := global_position.distance_to(_player.global_position)
		if dist < 30.0:  # Direct hit
			_explode()

func _update_trail() -> void:
	if not _trail or not is_instance_valid(_trail):
		return
	
	# Add current position to trail
	_trail_points.insert(0, global_position)
	
	# Limit trail length
	while _trail_points.size() > MAX_TRAIL_POINTS:
		_trail_points.pop_back()
	
	# Update trail line
	_trail.clear_points()
	for point in _trail_points:
		_trail.add_point(point)

func _explode() -> void:
	# Create AOE explosion effect
	var explosion := Node2D.new()
	explosion.set_script(preload("res://scripts/BossMissileExplosion.gd"))
	explosion.global_position = global_position
	if explosion.has_method("initialize"):
		explosion.initialize(AOE_RADIUS, AOE_DAMAGE, _player)
	
	if get_parent():
		get_parent().add_child(explosion)
	
	# Clean up trail
	if _trail and is_instance_valid(_trail):
		_trail.queue_free()
	
	queue_free()

func _exit_tree() -> void:
	# Clean up trail if we're removed unexpectedly
	if _trail and is_instance_valid(_trail):
		_trail.queue_free()
