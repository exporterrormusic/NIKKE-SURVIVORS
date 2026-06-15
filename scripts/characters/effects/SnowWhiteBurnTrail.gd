extends Node2D
class_name SnowWhiteBurnTrail
## Shader-based burning trail left by Snow White's bullets
## Uses a single polygon with shader for excellent performance

const BurnDOTScript = preload("res://scripts/effects/BurnDOT.gd")

@export var trail_width: float = 24.0 # Half-width of the trail
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

# "Burning" talent (flat DoT) and "Inferno" talent (slow). The trail itself is
# the "Afterburn" feature; these two are upgrades layered on top, configured by
# the bullet that spawns the trail.
const BURN_SOURCE_ID := "snow_white_burning"
const AFTERBURN_HIT_SOURCE := "snow_white_afterburn"
const BURN_DURATION := 5.0
const BURN_MULTS := [2.0, 5.0, 10.0]   # total burn damage = mult x bullet_damage over BURN_DURATION
const INFERNO_SLOWS := [0.15, 0.30, 0.50] # slow fraction per rank
const INFERNO_REFRESH := 0.4 # slow lingers this long after leaving the fire

# Set by the SnowWhiteBullet that creates this trail (from talent levels)
var burning_level: int = 0
var inferno_level: int = 0
var bullet_damage: int = 0

const MAX_POINTS := 150

var _cached_env: Node = null # Cached environment controller

func _ready() -> void:
	z_index = 8
	
	# Cache environment controller for performance (avoid tree lookup every _draw)
	_cached_env = get_tree().get_first_node_in_group("environment_controller")
	
	# Register mask proxy
	if GrassMaskManager.instance:
		_mask_proxy = TrailMaskProxy.new()
		_mask_proxy.z_index = 0
		GrassMaskManager.instance.add_eraser(_mask_proxy)

func _exit_tree() -> void:
	if _mask_proxy and is_instance_valid(_mask_proxy):
		_mask_proxy.queue_free()

func add_point(global_pos: Vector2) -> void:
	# Prevent adding points too close to the last one (prevents degenerate polygons/triangulation crashes)
	if not _points.is_empty():
		var last_pt = _points[_points.size() - 1]
		# Minimum 8px distance squared (64) to ensure valid geometry
		if global_pos.distance_squared_to(last_pt) < 64.0:
			return

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
	
	# Get environment modulate for compensation (use cached env for performance)
	var modulate_color = _cached_env.current_modulate if _cached_env and "current_modulate" in _cached_env else Color.WHITE
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
	_draw_trail_layer(lengths, total_length, 1.0, Color(0.2, 0.5, 1.0, 0.4 * flicker) * inverse) # Outer blue
	_draw_trail_layer(lengths, total_length, 0.65, Color(0.4, 0.8, 1.0, 0.7 * flicker) * inverse) # Mid cyan
	_draw_trail_layer(lengths, total_length, 0.3, Color(0.9, 1.0, 1.0, 0.9) * inverse) # Core white

	# Update Grass Mask Proxy
	if _mask_proxy and is_instance_valid(_mask_proxy):
		_mask_proxy.points = _points.duplicate()
		_mask_proxy.widths.clear()
		# Pre-calculate widths for the proxy to draw
		for i in range(_points.size()):
			var u := lengths[i] / total_length
			var back_taper := _smoothstep(0.0, 0.12, u)
			var front_taper := _smoothstep(1.0, 0.95, u)
			_mask_proxy.widths.append(trail_width * back_taper * front_taper)
		_mask_proxy.queue_redraw()

var _mask_proxy: Node2D = null

class TrailMaskProxy extends Node2D:
	var points: PackedVector2Array = []
	var widths: PackedFloat32Array = []
	
	func _draw() -> void:
		if points.size() < 2: return
		
		# Draw solid white shape matching the trail
		var top_pts := PackedVector2Array()
		var bottom_pts := PackedVector2Array()
		
		for i in range(points.size()):
			var pos := points[i]
			# Viewport camera matches Main camera. So Global Coords work directly.
			# We'll keep Proxy at (0,0).
			
			var perp := Vector2.UP
			if i < points.size() - 1:
				var dir := (points[i + 1] - points[i]).normalized()
				perp = Vector2(-dir.y, dir.x)
			elif i > 0:
				var dir := (points[i] - points[i - 1]).normalized()
				perp = Vector2(-dir.y, dir.x)
			
			var w = widths[i]
			top_pts.append(pos - perp * w)
			bottom_pts.append(pos + perp * w)
			
		# Build single polygon instead of many quads (performance fix)
		var polygon := PackedVector2Array()
		for pt in top_pts:
			polygon.append(pt)
		for i in range(bottom_pts.size() - 1, -1, -1):
			polygon.append(bottom_pts[i])
		draw_colored_polygon(polygon, Color.WHITE)

func _draw_trail_layer(lengths: PackedFloat32Array, total_length: float, width_mult: float, color: Color) -> void:
	if _points.size() < 2:
		return
	
	# Build ONE continuous polygon strip instead of many separate quads
	# This reduces draw calls from O(n) to O(1) per layer
	var top_pts := PackedVector2Array()
	var bottom_pts := PackedVector2Array()
	
	for i in range(_points.size()):
		var pos := to_local(_points[i])
		var u := lengths[i] / total_length
		
		# Calculate perpendicular
		var perp := Vector2.UP
		if i < _points.size() - 1:
			var dir := (_points[i + 1] - _points[i]).normalized()
			perp = Vector2(-dir.y, dir.x)
		elif i > 0:
			var dir := (_points[i] - _points[i - 1]).normalized()
			perp = Vector2(-dir.y, dir.x)
		
		# Taper
		var back_taper := _smoothstep(0.0, 0.12, u)
		var front_taper := _smoothstep(1.0, 0.95, u)
		var taper := back_taper * front_taper
		var alpha := _get_point_alpha(i)
		var w := trail_width * width_mult * taper
		
		if alpha <= 0.0 or w < 0.5:
			continue
		
		top_pts.append(pos - perp * w)
		bottom_pts.append(pos + perp * w)
	
	if top_pts.size() < 2:
		return
	
	# Build single closed polygon: top points forward, bottom points reversed
	var polygon := PackedVector2Array()
	for pt in top_pts:
		polygon.append(pt)
	for i in range(bottom_pts.size() - 1, -1, -1):
		polygon.append(bottom_pts[i])
	
	# Skip degenerate strips (duplicate/collinear points) that cannot be triangulated
	if Geometry2D.triangulate_polygon(polygon).is_empty():
		return

	# Single draw call for entire layer
	draw_colored_polygon(polygon, color)

func _check_enemies() -> void:
	# Performance: Use cached enemy list instead of get_nodes_in_group
	var enemies := TargetCache.get_enemies()
	if enemies.is_empty() or _points.is_empty():
		return
	
	# Performance: Pre-calculate active point bounding box for early-out test
	var active_min := Vector2(INF, INF)
	var active_max := Vector2(-INF, -INF)
	var active_points := PackedVector2Array()
	
	for i in range(_points.size()):
		var alpha := _get_point_alpha(i)
		if alpha > 0:
			var pt := _points[i]
			active_points.append(pt)
			active_min.x = minf(active_min.x, pt.x)
			active_min.y = minf(active_min.y, pt.y)
			active_max.x = maxf(active_max.x, pt.x)
			active_max.y = maxf(active_max.y, pt.y)
	
	if active_points.is_empty():
		return
	
	# Expand bounds by trail width
	var margin := trail_width * 2.0
	active_min -= Vector2(margin, margin)
	active_max += Vector2(margin, margin)
	
	var threshold_sq := (trail_width * 2.0) * (trail_width * 2.0)
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_pos: Vector2 = (enemy as Node2D).global_position
		
		# Early-out: skip if enemy is outside bounding box
		if enemy_pos.x < active_min.x or enemy_pos.x > active_max.x:
			continue
		if enemy_pos.y < active_min.y or enemy_pos.y > active_max.y:
			continue
		
		# Check distance to active points only
		for pt in active_points:
			if enemy_pos.distance_squared_to(pt) < threshold_sq:
				_process_enemy(enemy)
				break # Only damage once per tick

func _process_enemy(body: Node2D) -> void:
	if not is_instance_valid(body):
		return
	if not body.is_in_group("enemies"):
		return
	if body.is_in_group("charmed_allies"):
		return

	# Inferno: slow enemies standing in the fire (never bosses).
	if inferno_level > 0 and not body.is_in_group("bosses") and not body.is_in_group("super_boss"):
		if body.has_method("apply_slow"):
			var slow_pct: float = INFERNO_SLOWS[mini(inferno_level, INFERNO_SLOWS.size()) - 1]
			body.apply_slow(1.0 - slow_pct, INFERNO_REFRESH)

	# Burning: flat damage-over-time scaled off the bullet's damage. Refreshes
	# duration while the enemy stays in the fire (ticks never starve because the
	# DoT's tick timer is independent of its duration timer).
	if burning_level > 0:
		var existing_dot: Node = null
		for child in body.get_children():
			if child.get_script() == BurnDOTScript and child._source_id == BURN_SOURCE_ID:
				existing_dot = child
				break

		if existing_dot:
			existing_dot.refresh()
		else:
			var mult: float = BURN_MULTS[mini(burning_level, BURN_MULTS.size()) - 1]
			var dot = BurnDOTScript.new()
			dot.use_flat = true
			dot.flat_total = mult * float(maxi(bullet_damage, 1))
			dot.duration = BURN_DURATION
			dot.damage_source = BURN_SOURCE_ID
			body.add_child(dot)
			dot.setup(body, BURN_SOURCE_ID, BURN_DURATION)

	# Bare Afterburn always chips enemies standing in the fire (the "injury").
	if body.has_method("take_damage"):
		body.take_damage(damage_per_tick, false, Vector2.ZERO, false, AFTERBURN_HIT_SOURCE)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
