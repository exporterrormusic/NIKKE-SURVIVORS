extends Node2D
class_name IntelGroundEffect
## Sci-fi tech ground effect for INTEL box locations.
## Creates a circular tech pattern on the ground to visually distinguish INTEL sites.

# Visual styling
const PATTERN_RADIUS := 500.0
const PRIMARY_COLOR := Color(0.0, 0.7, 0.9, 0.4)     # Cyan
const SECONDARY_COLOR := Color(0.0, 0.5, 0.7, 0.25)  # Darker cyan
const GRID_COLOR := Color(0.0, 0.8, 1.0, 0.15)       # Grid lines
const GLOW_COLOR := Color(0.0, 0.9, 1.0, 0.2)        # Outer glow

const RING_COUNT := 6
const GRID_DIVISIONS := 12
const HEX_COUNT := 18
const ROTATION_SPEED := 0.1
const PULSE_SPEED := 2.0

var _time := 0.0

func _ready() -> void:
	z_index = -10  # Below everything
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var pulse := sin(_time * PULSE_SPEED) * 0.5 + 0.5
	
	# Draw outer glow
	_draw_outer_glow(pulse)
	
	# Draw concentric rings
	_draw_rings(pulse)
	
	# Draw radial grid lines
	_draw_radial_grid()
	
	# Draw hexagonal patterns
	_draw_hex_patterns(pulse)
	
	# Draw circuit-like patterns
	_draw_circuits()
	
	# Draw scanning line
	_draw_scan_line()

func _draw_outer_glow(pulse: float) -> void:
	# Soft gradient glow at edge
	for i in range(10):
		var t := float(i) / 10.0
		var radius := PATTERN_RADIUS * (0.9 + t * 0.1)
		var alpha := 0.1 * (1.0 - t) * (0.7 + pulse * 0.3)
		var color := GLOW_COLOR
		color.a = alpha
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, color, 8.0)

func _draw_rings(pulse: float) -> void:
	# Draw concentric tech rings
	for i in range(RING_COUNT):
		var t := float(i) / float(RING_COUNT)
		var radius := PATTERN_RADIUS * (0.2 + t * 0.8)
		
		# Alternate ring styles
		var color: Color
		var width: float
		if i % 2 == 0:
			color = PRIMARY_COLOR
			color.a = 0.3 + pulse * 0.15
			width = 2.0
		else:
			color = SECONDARY_COLOR
			color.a = 0.2 + pulse * 0.1
			width = 1.0
		
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, color, width)
		
		# Add tick marks on some rings
		if i >= 2 and i % 2 == 0:
			_draw_ring_ticks(radius, 24)

func _draw_ring_ticks(radius: float, count: int) -> void:
	var tick_length := 8.0
	var color := PRIMARY_COLOR
	color.a = 0.3
	
	for i in range(count):
		var angle := (float(i) / count) * TAU
		var dir := Vector2.from_angle(angle)
		var start := dir * (radius - tick_length / 2)
		var end := dir * (radius + tick_length / 2)
		draw_line(start, end, color, 1.0)

func _draw_radial_grid() -> void:
	# Draw radial lines from center
	for i in range(GRID_DIVISIONS):
		var angle := (float(i) / GRID_DIVISIONS) * TAU
		var dir := Vector2.from_angle(angle)
		var start := dir * (PATTERN_RADIUS * 0.1)
		var end := dir * PATTERN_RADIUS
		
		# Dashed line effect
		var dash_count := 8
		for j in range(dash_count):
			var t1 := float(j) / dash_count
			var t2 := float(j + 0.6) / dash_count
			var p1 := start.lerp(end, t1)
			var p2 := start.lerp(end, t2)
			draw_line(p1, p2, GRID_COLOR, 1.0)

func _draw_hex_patterns(pulse: float) -> void:
	# Draw hexagon shapes at various positions
	var hex_radius := 25.0
	
	for i in range(HEX_COUNT):
		var angle := (float(i) / HEX_COUNT) * TAU + _time * ROTATION_SPEED
		var dist := PATTERN_RADIUS * (0.4 + float(i % 3) * 0.2)
		var pos := Vector2.from_angle(angle) * dist
		
		# Calculate individual pulse offset
		var hex_pulse := sin(_time * 3.0 + i * 0.5) * 0.3 + 0.7
		
		var color := PRIMARY_COLOR
		color.a = 0.2 * hex_pulse
		
		_draw_hexagon(pos, hex_radius * hex_pulse, color)

func _draw_hexagon(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := (float(i) / 6.0) * TAU - PI / 6.0
		points.append(center + Vector2.from_angle(angle) * radius)
	
	# Draw outline
	for i in range(6):
		draw_line(points[i], points[(i + 1) % 6], color, 1.5)

func _draw_circuits() -> void:
	# Draw circuit-like patterns in quadrants
	var color := SECONDARY_COLOR
	color.a = 0.25
	
	# Simple circuit patterns
	for quadrant in range(4):
		var base_angle := quadrant * PI / 2.0 + PI / 4.0
		var base_pos := Vector2.from_angle(base_angle) * PATTERN_RADIUS * 0.6
		
		# Draw a few connected lines
		var offsets := [
			Vector2(0, 0),
			Vector2(30, 0),
			Vector2(30, 20),
			Vector2(60, 20),
		]
		
		# Rotate offsets by quadrant
		var rot := base_angle - PI / 4.0
		for i in range(offsets.size() - 1):
			var p1: Vector2 = base_pos + offsets[i].rotated(rot)
			var p2: Vector2 = base_pos + offsets[i + 1].rotated(rot)
			draw_line(p1, p2, color, 1.5)
		
		# Draw nodes at corners
		for offset in offsets:
			var pos: Vector2 = base_pos + offset.rotated(rot)
			draw_circle(pos, 3.0, color)

func _draw_scan_line() -> void:
	# Rotating scan line effect
	var scan_angle := _time * 0.5
	var dir := Vector2.from_angle(scan_angle)
	
	# Draw scan line as gradient
	var line_start := Vector2.ZERO
	var line_end := dir * PATTERN_RADIUS
	
	# Multiple lines for gradient effect
	for i in range(20):
		var offset_angle := scan_angle - (float(i) / 20.0) * 0.3
		var offset_dir := Vector2.from_angle(offset_angle)
		var alpha := 0.15 * (1.0 - float(i) / 20.0)
		var color := GLOW_COLOR
		color.a = alpha
		draw_line(line_start, offset_dir * PATTERN_RADIUS, color, 2.0)
