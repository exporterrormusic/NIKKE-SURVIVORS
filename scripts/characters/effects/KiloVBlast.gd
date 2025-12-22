extends Node2D
class_name KiloVBlast

# New V-Blast implementation using reliable Line2D nodes
# Ensures visibility at night with Unshaded material

@export var blast_color: Color = Color(1.0, 0.28, 0.08, 1.0)
@export var blast_range: float = 180.0
@export var blast_angle: float = 45.0
@export var duration: float = 1.0 # Increased from 0.6
@export var blast_damage: int = 4
@export var is_burst: bool = false
@export var knockback_force: float = 0.0

var _left_line: Line2D
var _right_line: Line2D
var _fill_poly: Polygon2D
var _tween: Tween
var _hit_enemies: Array = [] # Track enemies hit to avoid double damage
var owner_node: Node = null

func _ready() -> void:
	# Guaranteed visibility settings
	z_index = 500
	var mat = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	_setup_visuals()
	_animate()
	
	# Deal damage immediately in the cone
	call_deferred("_deal_cone_damage")

func setup(forward_dir: Vector2, pos: Vector2, color_override: Color, p_damage: int, p_range: float, p_owner: Node, p_is_burst: bool) -> void:
	global_position = pos
	blast_damage = p_damage
	blast_range = p_range # Apply size upgrade
	owner_node = p_owner
	is_burst = p_is_burst
	
	if color_override != Color.BLACK:
		blast_color = color_override
	
	# Calculate arm vectors
	var half_angle = deg_to_rad(blast_angle * 0.5)
	var left_dir = forward_dir.rotated(-half_angle) * blast_range
	var right_dir = forward_dir.rotated(half_angle) * blast_range
	
	# Store vector info for damage calculation
	set_meta("blast_vectors", {
		"forward": forward_dir.normalized(),
		"range": blast_range,
		"angle": blast_angle
	})
	
	# Update lines and polygon if ready
	if _left_line and _right_line and _fill_poly:
		_update_poly_and_lines(left_dir, right_dir, blast_color)
	else:
		# Store for _ready if called before ready
		set_meta("pending_setup", {
			"left": left_dir,
			"right": right_dir,
			"color": blast_color
		})

func _deal_cone_damage() -> void:
	if not has_meta("blast_vectors"):
		return
		
	var data = get_meta("blast_vectors")
	var fwd: Vector2 = data.forward
	var max_dist: float = data.range
	var half_angle_rad: float = deg_to_rad(data.angle * 0.5)
	
	var tree = get_tree()
	if not tree: return
	
	for node in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or node in _hit_enemies:
			continue
			
		# Skip charmed allies (Sin's mind control)
		if node.is_in_group("charmed_allies"):
			continue
			
		if not node.has_method("take_damage"):
			continue
			
		var to_enemy = node.global_position - global_position
		var dist = to_enemy.length()
		
		# Range check
		if dist > max_dist:
			continue
			
		# Angle check (Cone)
		# "All should" damage (Space in middle)
		var angle_to = fwd.angle_to(to_enemy)
		if absf(angle_to) > half_angle_rad:
			continue
			
		# Hit!
		var hit_dir = to_enemy.normalized()
		node.take_damage(blast_damage, false, hit_dir, is_burst)
		_hit_enemies.append(node)

func _update_poly_and_lines(left: Vector2, right: Vector2, col: Color) -> void:
	_left_line.points = [Vector2.ZERO, left]
	_right_line.points = [Vector2.ZERO, right]
	_left_line.default_color = col
	_right_line.default_color = col
	
	_fill_poly.polygon = PackedVector2Array([Vector2.ZERO, left, right])
	var fill_col = Color(1.0, 0.1, 0.1, 0.9)
	_fill_poly.color = fill_col

func _setup_visuals() -> void:
	# Shared material for all parts
	var mat = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	
	# Create Polygon Fill (Bottom layer)
	_fill_poly = Polygon2D.new()
	_fill_poly.antialiased = true
	_fill_poly.material = mat # Apply unshaded
	add_child(_fill_poly)

	# Create Lines (Top layer)
	_left_line = _create_line()
	_right_line = _create_line()
	_left_line.material = mat # Apply unshaded
	_right_line.material = mat # Apply unshaded
	add_child(_left_line)
	add_child(_right_line)
	
	if has_meta("pending_setup"):
		var data = get_meta("pending_setup")
		_update_poly_and_lines(data.left, data.right, data.color)

func _draw() -> void:
	# Draw Core Flash (bright center)
	var radius = blast_range * 0.35 # Larger flash
	var flash_color = Color(1.0, 0.95, 0.6, 1.0 * modulate.a)
	draw_circle(Vector2.ZERO, radius, flash_color)
	draw_circle(Vector2.ZERO, radius * 0.7, Color.WHITE)

func _create_line() -> Line2D:
	var l = Line2D.new()
	l.width = 18.0 # Thicker lines
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.antialiased = true
	# Create a gradient for fade-out look at tips if desired, 
	# but solid color is more reliable for visibility first.
	return l

func _animate() -> void:
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_EXPO)
	_tween.set_ease(Tween.EASE_OUT)
	
	# Fade out
	_tween.tween_property(self, "modulate:a", 0.0, duration)
	
	# Cleanup
	_tween.chain().tween_callback(queue_free)
