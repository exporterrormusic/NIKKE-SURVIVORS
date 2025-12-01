extends Node2D

# Spark particle for turret destruction effect

var _velocity := Vector2.ZERO
var _lifetime := 0.0
var _max_lifetime := 0.5
var _size := 3.0
var _color := Color(0.9, 0.92, 0.95, 1.0)
var _is_smoke := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	
	# 30% chance to be smoke instead of spark
	_is_smoke = _rng.randf() < 0.3
	
	if _is_smoke:
		_velocity = Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-60, -20))
		_max_lifetime = _rng.randf_range(0.6, 1.0)
		_size = _rng.randf_range(8, 15)
		_color = Color(0.4, 0.42, 0.45, 0.6)
	else:
		# Spark with random direction
		var angle := _rng.randf() * TAU
		var speed := _rng.randf_range(80, 200)
		_velocity = Vector2(cos(angle), sin(angle)) * speed
		_max_lifetime = _rng.randf_range(0.3, 0.6)
		_size = _rng.randf_range(2, 5)
		# Metallic spark colors
		var spark_colors := [
			Color(1.0, 0.95, 0.8, 1.0),   # Warm white
			Color(0.95, 0.9, 0.85, 1.0),  # Off-white
			Color(1.0, 0.8, 0.4, 1.0),    # Orange spark
		]
		_color = spark_colors[_rng.randi() % spark_colors.size()]

func _process(delta: float) -> void:
	_lifetime += delta
	
	if _lifetime >= _max_lifetime:
		queue_free()
		return
	
	# Apply gravity to sparks, upward drift to smoke
	if _is_smoke:
		_velocity.y -= 20 * delta  # Float up
		_velocity *= 0.98  # Air resistance
	else:
		_velocity.y += 300 * delta  # Gravity
	
	position += _velocity * delta
	queue_redraw()

func _draw() -> void:
	var progress := _lifetime / _max_lifetime
	var alpha := 1.0 - progress
	
	if _is_smoke:
		# Smoke puff expands and fades
		var smoke_size := _size * (1.0 + progress * 1.5)
		var smoke_color := Color(_color.r, _color.g, _color.b, _color.a * alpha)
		draw_circle(Vector2.ZERO, smoke_size, smoke_color)
	else:
		# Spark shrinks and fades
		var spark_size := _size * (1.0 - progress * 0.5)
		var spark_color := Color(_color.r, _color.g, _color.b, alpha)
		draw_circle(Vector2.ZERO, spark_size, spark_color)
		
		# Motion trail
		var trail_length := _velocity.normalized() * -spark_size * 2
		var trail_color := Color(spark_color.r, spark_color.g, spark_color.b, alpha * 0.5)
		draw_line(Vector2.ZERO, trail_length, trail_color, spark_size * 0.7)
