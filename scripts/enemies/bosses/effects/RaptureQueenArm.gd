extends Node2D

## Procedural Tentacle Arm for Rapture Queen
## Writhes around using multi-segment sine waves and drips black oil

const COLOR := Color(0.05, 0.05, 0.08, 1.0) # Black oil
const OUTLINE_COLOR := Color(0.2, 0.2, 0.25, 0.5) # Slight grey outline
const SEGMENTS := 14
const TOTAL_LENGTH := 250.0 # Longer
const BASE_WIDTH := 24.0 # Thicker
const TIP_WIDTH := 0.0
const WRITHE_SPEED := 1.5
const WRITHE_MAGNITUDE := 40.0

var _segments: PackedVector2Array = []
var _target_positions: PackedVector2Array = []
var _time_offset: float = 0.0
var _angle_offset: float = 0.0
var _time: float = 0.0

# Drips
var _drips: Array = [] # {pos, velocity, life}
const GRAVITY := 200.0

func _ready() -> void:
	_time_offset = randf() * 100.0
	# Initialize segments straight out
	for i in range(SEGMENTS):
		_segments.append(Vector2(i * (TOTAL_LENGTH / SEGMENTS), 0))

func setup(angle: float) -> void:
	_angle_offset = angle
	rotation = angle

func _process(delta: float) -> void:
	_time += delta
	
	# Update Procedural Animation (Writhing)
	var segment_length = TOTAL_LENGTH / SEGMENTS
	var current_pos = Vector2.ZERO
	var points = PackedVector2Array([Vector2.ZERO])
	
	for i in range(1, SEGMENTS):
		# Calculate angle for this segment
		# Base angle is 0 (relative to arm rotation)
		# Add sine waves for organic motion
		var seg_factor = float(i) / float(SEGMENTS)
		var wave1 = sin(_time * WRITHE_SPEED + _time_offset + seg_factor * 3.0)
		var wave2 = cos(_time * WRITHE_SPEED * 0.7 + _time_offset * 1.5 + seg_factor * 2.0)
		
		var local_angle = (wave1 + wave2) * 0.5 * (WRITHE_MAGNITUDE * deg_to_rad(1.0)) * seg_factor
		
		# Direction vector
		var dir = Vector2(cos(local_angle), sin(local_angle))
		current_pos += dir * segment_length
		points.append(current_pos)
	
	_segments = points
	
	# Handle drips
	if randf() < 0.05: # Chance to spawn drip
		_spawn_drip()
	
	_update_drips(delta)
	
	queue_redraw()

func _spawn_drip() -> void:
	# Pick random segment (weighted towards end)
	var idx = randi() % SEGMENTS
	if idx < 2: return # Don't drip from base
	
	var pos_local = _segments[idx]
	var pos_global = to_global(pos_local)
	
	_drips.append({
		"pos": pos_local, # Keep local for drawing, but apply gravity relative to rotation? simpler to simulate local
		"vel": Vector2(0, 50).rotated(-rotation), # Gravity down in local space
		"life": 1.0,
		"size": randf_range(2.0, 5.0)
	})

func _update_drips(delta: float) -> void:
	var active_drips = []
	var down_vec = Vector2(0, 1).rotated(-rotation) * GRAVITY * delta
	
	for drip in _drips:
		drip.life -= delta
		drip.vel += down_vec
		drip.pos += drip.vel * delta
		
		if drip.life > 0:
			active_drips.append(drip)
	
	_drips = active_drips

func _draw() -> void:
	if _segments.size() < 2: return
	
	# Draw smooth tentacle
	# Generate polygon strip
	var poly_left = PackedVector2Array()
	var poly_right = PackedVector2Array()
	
	for i in range(_segments.size()):
		var t = float(i) / float(_segments.size() - 1)
		var pos = _segments[i]
		
		# Direction to next point (or from prev)
		var dir = Vector2.RIGHT
		if i < _segments.size() - 1:
			dir = (_segments[i+1] - pos).normalized()
		elif i > 0:
			dir = (pos - _segments[i-1]).normalized()
		
		var normal = dir.orthogonal()
		var width = lerp(BASE_WIDTH, TIP_WIDTH, t)
		
		poly_left.append(pos + normal * width * 0.5)
		poly_right.append(pos - normal * width * 0.5)
	
	poly_right.reverse()
	var full_poly = poly_left + poly_right
	
	# Draw outline
	draw_polyline(full_poly, OUTLINE_COLOR, 2.0)
	# Draw fill
	draw_colored_polygon(full_poly, COLOR)
	
	# Draw drips
	for drip in _drips:
		draw_circle(drip.pos, drip.size * drip.life, COLOR)

func get_current_points() -> PackedVector2Array:
	return _segments
