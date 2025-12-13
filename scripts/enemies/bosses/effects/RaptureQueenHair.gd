extends Node2D

## Procedural Thick Hair for Rapture Queen
## Uses colored polygons to simulate large volumes of flowing silky hair

# Configuration
const HAIR_COLOR := Color(0.05, 0.05, 0.08, 1.0) # Deep black
const HIGHLIGHT_COLOR := Color(0.2, 0.2, 0.3, 0.3) # Subtle sheen
const CLUMP_COUNT := 12 # Fewer, thicker clumps
const SEGMENTS := 12
const MAX_LENGTH := 250.0 # Longer
const MIN_LENGTH := 180.0
const BASE_WIDTH := 60.0 # Much thicker base
const TIP_WIDTH := 2.0 # Thicker tip to avoid zero-width duplication errors

# Animation
var _time: float = 0.0
var _velocity_smooth: Vector2 = Vector2.ZERO
var _parent_velocity: Vector2 = Vector2.ZERO

# Hair Clump Data
# Array of dicts: { angle, length, phase_offset, width_scale }
var _clumps: Array = []

func _ready() -> void:
	# Initialize hair clumps
	for i in range(CLUMP_COUNT):
		# Distribute angles symmetrically flowing UP/BACK (-PI/2)
		# Angles from -210 deg to -330 deg (spanning the top/back)
		var t = float(i) / float(CLUMP_COUNT - 1)
		var angle_deg = lerp(150.0, 390.0, t) # Wraps around top
		# Adjust to Radians
		var angle_rad = deg_to_rad(angle_deg)
		
		var clump = {
			"angle": angle_rad,
			"length": randf_range(MIN_LENGTH, MAX_LENGTH),
			"phase": randf() * TAU,
			"width_scale": randf_range(0.9, 1.3)
		}
		_clumps.append(clump)
		
	# Behind the face
	# z_index = -1 # REMOVED: Managed by RaptureQueenVisuals.gd

func _process(delta: float) -> void:
	_time += delta
	
	# Get parent velocity for flow
	_parent_velocity = Vector2.ZERO
	var parent = get_parent() # Visuals
	if parent and "velocity" in parent: # Access script var
		_parent_velocity = parent._velocity
	elif parent:
		var grandparent = parent.get_parent()
		if grandparent and "velocity" in grandparent:
			_parent_velocity = grandparent.velocity
			
	# Smooth velocity for hair lag
	_velocity_smooth = _velocity_smooth.lerp(_parent_velocity, delta * 2.0)
	
	queue_redraw()

func _draw() -> void:
	# Draw all clumps
	for clump in _clumps:
		_draw_clump(clump)

func _draw_clump(clump: Dictionary) -> void:
	var root_pos = Vector2(cos(clump.angle), sin(clump.angle)) * 20.0 # Offset from center head
	
	var points_left = PackedVector2Array()
	var points_right = PackedVector2Array()
	
	var flow_dir = -_velocity_smooth.normalized()
	var flow_strength = clamped_map(_velocity_smooth.length(), 0, 200, 0, 1.0)
	
	for i in range(SEGMENTS + 1):
		var t = float(i) / float(SEGMENTS)
		
		# Base direction: outward from angle
		var base_dir = Vector2(cos(clump.angle), sin(clump.angle))
		
		# Waving (idle)
		var wave_angle = sin(_time * 2.0 + clump.phase + t * 4.0) * 0.3 * (1.0 - flow_strength)
		var wave_dir = base_dir.rotated(wave_angle)
		
		# Flow (movement) - blend towards flow_dir based on flow_strength and segment depth
		var current_dir = wave_dir.lerp(flow_dir, flow_strength * t * 0.8)
		if flow_strength > 0.1:
			current_dir = current_dir.normalized()
		
		# Position of spine point
		var spine_point = root_pos + current_dir * (clump.length * t)
		
		# Width at this segment
		var width = lerp(BASE_WIDTH, TIP_WIDTH, pow(t, 0.5)) * clump.width_scale
		
		# Normal for width expansion
		var normal = current_dir.orthogonal().normalized()
		
		points_left.append(spine_point + normal * width * 0.5)
		points_right.append(spine_point - normal * width * 0.5)
	
	# Draw Quads for each segment
	# This avoids "Invalid polygon data" errors from self-intersecting complex polygons
	# and is much faster than decomposition. Since color is solid, overlap doesn't matter.
	for j in range(points_left.size() - 1):
		var p1 = points_left[j]
		var p2 = points_left[j+1]
		var p3 = points_right[j+1]
		var p4 = points_right[j]
		
		# Draw as two triangles to be absolutely robust against "bowtie" quads
		# Triangles cannot fail triangulation
		draw_colored_polygon(PackedVector2Array([p1, p2, p4]), HAIR_COLOR)
		draw_colored_polygon(PackedVector2Array([p2, p3, p4]), HAIR_COLOR)
	
	# Optional: Draw highlight line on top
	# draw_polyline(points_left, HIGHLIGHT_COLOR, 2.0)
	
	# Draw highlight (thinner strip)
	# draw_polyline(points_left, HIGHLIGHT_COLOR, 2.0) # Optional highlighting

func clamped_map(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	var t = (value - in_min) / (in_max - in_min)
	t = clamp(t, 0.0, 1.0)
	return out_min + t * (out_max - out_min)
