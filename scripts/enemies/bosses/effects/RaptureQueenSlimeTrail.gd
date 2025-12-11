extends Node2D

## Slime Trail Manager for Rapture Queen N01
## Leaves permanent slime trail polygons wherever the boss moves
## Visual: Dark purple/black liquid, similar to burn zones but slime-themed
## Now with damage zones that hurt players!

var _trail_segments: Array[PackedVector2Array] = []
var _time: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _boss: Node2D = null
var _spawn_distance := 30.0  # Spawn new segment every 30 pixels
var _trail_width := 120.0  # Width of slime trail (INCREASED 50% from 80 to 120)
var _segment_counter := 0  # For wave offset

# Slime colors - dark purple/black liquid
const SLIME_COLOR_BASE := Color(0.08, 0.0, 0.12, 0.85)  # Dark purple-black
const SLIME_COLOR_EDGE := Color(0.15, 0.0, 0.2, 0.7)    # Lighter purple edge
const SLIME_HIGHLIGHT := Color(0.2, 0.05, 0.25, 0.5)    # Purple sheen

# Damage settings (same as burn zones)
const DAMAGE_RATE_PERCENT := 0.25  # 25% max HP per second

func setup(boss: Node2D) -> void:
	_boss = boss
	if _boss:
		_last_position = _boss.global_position

func _ready() -> void:
	z_index = -5  # Below boss but above ground

func _process(delta: float) -> void:
	_time += delta
	
	if not _boss or not is_instance_valid(_boss):
		return
	
	var current_pos = _boss.global_position
	var distance = current_pos.distance_to(_last_position)
	
	# Spawn new trail segment if moved enough
	if distance >= _spawn_distance:
		_spawn_trail_segment(_last_position, current_pos)
		_last_position = current_pos
	
	queue_redraw()

func _spawn_trail_segment(from_pos: Vector2, to_pos: Vector2) -> void:
	# Create a wavy rectangular polygon for the trail segment
	var direction = (to_pos - from_pos).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)
	
	var half_width = _trail_width / 2.0
	
	# Create wavy edges instead of straight - more points for wave effect
	var points = PackedVector2Array()
	var num_edge_points = 5  # Points along each side for wave
	
	# Top edge (wavy)
	for i in range(num_edge_points):
		var t = float(i) / float(num_edge_points - 1)
		var pos = from_pos.lerp(to_pos, t)
		# Add wave using noise
		var wave_offset = sin(_segment_counter * 0.5 + t * PI * 2.0) * 15.0
		points.append(pos + perpendicular * (half_width + wave_offset))
	
	# Bottom edge (wavy, reversed)
	for i in range(num_edge_points - 1, -1, -1):
		var t = float(i) / float(num_edge_points - 1)
		var pos = from_pos.lerp(to_pos, t)
		# Add wave using noise (opposite phase)
		var wave_offset = sin(_segment_counter * 0.5 + t * PI * 2.0 + PI) * 15.0
		points.append(pos - perpendicular * (half_width + wave_offset))
	
	# Store segment
	_trail_segments.append(points)
	_segment_counter += 1
	
	# Create damage area for this segment
	_create_damage_area(points)

func _create_damage_area(points: PackedVector2Array) -> void:
	var area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2  # Player is on layer 2
	area.monitorable = false
	area.monitoring = true
	area.set_script(_get_damage_script())
	add_child(area)
	
	var col = CollisionPolygon2D.new()
	col.polygon = points
	area.add_child(col)

func _get_damage_script() -> GDScript:
	var script = GDScript.new()
	script.source_code = """
extends Area2D

var damage_rate_percent := 0.25
var _damage_accum: Dictionary = {}

func _physics_process(delta: float) -> void:
	var bodies = get_overlapping_bodies()
	
	for body in bodies:
		# Only damage player
		if not body.is_in_group("player"):
			continue
			
		if body.has_method("take_damage"):
			# Calculate DPS
			var max_hp = 100.0
			if "max_hp" in body: 
				max_hp = float(body.max_hp)
			
			var dps = max_hp * damage_rate_percent
			var frame_damage = dps * delta
			
			# Accumulate
			var bid = body.get_instance_id()
			if not _damage_accum.has(bid):
				_damage_accum[bid] = 0.0
			
			_damage_accum[bid] += frame_damage
			
			# Apply full integer chunks
			if _damage_accum[bid] >= 1.0:
				var dmg_to_apply = int(_damage_accum[bid])
				_damage_accum[bid] -= dmg_to_apply
				body.take_damage(dmg_to_apply)
"""
	script.reload()
	return script

func _draw() -> void:
	# Draw each trail segment using global coordinates
	for segment in _trail_segments:
		# Base slime color - solid fill
		draw_colored_polygon(segment, SLIME_COLOR_BASE)
		
		# Add animated bubbles/glow effect
		if segment.size() >= 3:
			var center = Vector2.ZERO
			for point in segment:
				center += point
			center /= segment.size()
			
			# Pulsing slime effect
			var pulse = 0.5 + 0.5 * sin(_time * 2.0 + center.x * 0.1)
			var bubble_color = SLIME_HIGHLIGHT
			bubble_color.a *= pulse
			
			# Draw some bubbles
			for i in range(3):
				var offset = Vector2(
					sin(_time * 1.5 + i * 2.0 + center.x * 0.05) * 20.0,
					cos(_time * 1.3 + i * 1.5 + center.y * 0.05) * 20.0
				)
				var bubble_pos = center + offset
				draw_circle(bubble_pos, 8.0, bubble_color)
				draw_circle(bubble_pos, 4.0, Color(bubble_color.r, bubble_color.g, bubble_color.b, bubble_color.a * 1.5))

func clear_trails() -> void:
	_trail_segments.clear()
	# Clear damage areas
	for child in get_children():
		if child is Area2D:
			child.queue_free()
	queue_redraw()

