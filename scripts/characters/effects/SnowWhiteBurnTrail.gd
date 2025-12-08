extends Node2D
class_name SnowWhiteBurnTrail
## Shader-based burning trail left by Snow White's bullets
## Uses a single polygon with shader for excellent performance

const BurnDOTScript = preload("res://scripts/effects/BurnDOT.gd")

@export var trail_width: float = 24.0  # Half-width of the trail
@export var segment_lifetime: float = 1.5
@export var fade_duration: float = 0.5
@export var damage_per_tick: int = 2
@export var tick_interval: float = 0.25

var is_friendly: bool = true
var _is_finalized: bool = false

# Trail data
var _points: PackedVector2Array = []
var _point_times: PackedFloat64Array = []
var _current_time: float = 0.0

# Collision
var _tick_elapsed: float = 0.0

const DOT_SOURCE_ID := "snow_white_burn"
const DOT_DURATION := 10.0
const DOT_DAMAGE_PERCENT := 0.03
const DOT_BOSS_DAMAGE_PERCENT := 0.01

const MAX_POINTS := 150

func _ready() -> void:
	z_index = 8

func add_point(global_pos: Vector2) -> void:
	# Limit points for performance
	if _points.size() >= MAX_POINTS:
		_points.remove_at(0)
		_point_times.remove_at(0)
	
	_points.append(global_pos)
	_point_times.append(_current_time)
	queue_redraw()

func finalize() -> void:
	_is_finalized = true

func _get_point_alpha(index: int) -> float:
	if index < 0 or index >= _point_times.size():
		return 0.0
	var age: float = _current_time - _point_times[index]
	if age < segment_lifetime:
		return 1.0
	elif age < segment_lifetime + fade_duration:
		return 1.0 - ((age - segment_lifetime) / fade_duration)
	return 0.0

func _process(delta: float) -> void:
	_current_time += delta
	
	# Remove fully faded points from the front
	var total_life := segment_lifetime + fade_duration
	while _point_times.size() > 0:
		var age: float = _current_time - _point_times[0]
		if age >= total_life:
			_points.remove_at(0)
			_point_times.remove_at(0)
		else:
			break
	
	# Check if trail is done
	if _is_finalized and _points.size() == 0:
		queue_free()
		return
	
	# Redraw periodically
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()
	
	# Damage tick
	_tick_elapsed += delta
	if _tick_elapsed >= tick_interval:
		_tick_elapsed = 0.0
		_check_enemies()

func _draw() -> void:
	if _points.size() < 2:
		return
	
	# Get environment modulate for compensation
	var env = get_tree().root.find_child("Environment", true, false)
	var modulate_color = env.current_modulate if env and "current_modulate" in env else Color.WHITE
	var inverse = Color(
		1.0 / max(modulate_color.r, 0.001),
		1.0 / max(modulate_color.g, 0.001),
		1.0 / max(modulate_color.b, 0.001),
		1.0 / max(modulate_color.a, 0.001)
	)
	
	# Calculate lengths for tapering
	var total_length := 0.0
	var lengths := PackedFloat32Array()
	lengths.append(0.0)
	for i in range(1, _points.size()):
		total_length += _points[i].distance_to(_points[i - 1])
		lengths.append(total_length)
	
	if total_length < 1.0:
		return
	
	# Animated flicker
	var flicker := 0.85 + 0.15 * sin(_current_time * 12.0)
	
	# Draw as connected segments using a single polyline with antialiasing
	# Build the trail polygon manually for the icy fire effect
	
	# We'll draw 3 layers: outer glow, mid, and core
	_draw_trail_layer(lengths, total_length, 1.0, Color(0.2, 0.5, 1.0, 0.4 * flicker) * inverse)   # Outer blue
	_draw_trail_layer(lengths, total_length, 0.65, Color(0.4, 0.8, 1.0, 0.7 * flicker) * inverse)  # Mid cyan  
	_draw_trail_layer(lengths, total_length, 0.3, Color(0.9, 1.0, 1.0, 0.9) * inverse)              # Core white

func _draw_trail_layer(lengths: PackedFloat32Array, total_length: float, width_mult: float, color: Color) -> void:
	if _points.size() < 2:
		return
	
	var top_pts := PackedVector2Array()
	var bottom_pts := PackedVector2Array()
	
	for i in range(_points.size()):
		var pos := to_local(_points[i])
		var u := lengths[i] / total_length  # 0 at back, 1 at front
		
		# Calculate perpendicular
		var perp := Vector2.UP
		if i < _points.size() - 1:
			var dir := (_points[i + 1] - _points[i]).normalized()
			perp = Vector2(-dir.y, dir.x)
		elif i > 0:
			var dir := (_points[i] - _points[i - 1]).normalized()
			perp = Vector2(-dir.y, dir.x)
		
		# Taper at back (triangle tip) and slight taper at front
		var back_taper := _smoothstep(0.0, 0.12, u)
		var front_taper := _smoothstep(1.0, 0.95, u)
		var taper := back_taper * front_taper
		
		# Get alpha for this point
		var alpha := _get_point_alpha(i)
		
		# Final width
		var w := trail_width * width_mult * taper
		
		# Skip if invisible
		if alpha <= 0.0 or w < 0.5:
			continue
		
		top_pts.append(pos - perp * w)
		bottom_pts.append(pos + perp * w)
	
	if top_pts.size() < 2:
		return
	
	# Build closed polygon
	var polygon := PackedVector2Array()
	for pt in top_pts:
		polygon.append(pt)
	for i in range(bottom_pts.size() - 1, -1, -1):
		polygon.append(bottom_pts[i])
	
	draw_colored_polygon(polygon, color)

func _check_enemies() -> void:
	var tree := get_tree()
	if not tree:
		return
	
	var enemies := tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		# Check if enemy is near any active trail point
		var enemy_pos: Vector2 = (enemy as Node2D).global_position
		for i in range(_points.size()):
			var alpha := _get_point_alpha(i)
			if alpha <= 0:
				continue
			var dist := enemy_pos.distance_to(_points[i])
			if dist < trail_width * 2.0:
				_process_enemy(enemy)
				break

func _process_enemy(body: Node2D) -> void:
	if not is_instance_valid(body):
		return
	if not body.is_in_group("enemies"):
		return
	if body.is_in_group("charmed_allies"):
		return
	
	# Look for existing burn DOT
	var existing_dot: Node = null
	for child in body.get_children():
		if child.get_script() == BurnDOTScript and child._source_id == DOT_SOURCE_ID:
			existing_dot = child
			break
	
	if existing_dot:
		existing_dot.refresh()
	else:
		var dot = BurnDOTScript.new()
		dot.damage_percent = DOT_DAMAGE_PERCENT
		dot.boss_damage_percent = DOT_BOSS_DAMAGE_PERCENT
		dot.duration = DOT_DURATION
		body.add_child(dot)
		dot.setup(body, DOT_SOURCE_ID)
	
	if body.has_method("take_damage"):
		body.take_damage(damage_per_tick, false, Vector2.ZERO)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
