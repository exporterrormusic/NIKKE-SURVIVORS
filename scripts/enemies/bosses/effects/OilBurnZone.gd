extends Node2D

## Oil Burn Manager (Optimized)
## Manages persistent burn polygons via a SINGLE Area2D to reduce overhead.
## Visuals: Continuous bubbling dark red/purple liquid.

var damage_rate_percent := 0.25
var _polygons: Array[PackedVector2Array] = []
var _damage_accum: Dictionary = {} # Store float damage per body instance ID

# Optimization: Single Area2D for all oil
var _area: Area2D = null

# Performance Limits
const MAX_POLYGONS := 40 # Limit total active burn zones
var _collision_polys: Array[CollisionPolygon2D] = []
var _mask_polys: Array[Polygon2D] = []

func _ready() -> void:
	z_index = -5
	
	# Create the single physics manager
	_area = Area2D.new()
	_area.name = "BurnArea"
	_area.collision_layer = 0
	_area.collision_mask = 3 # Player (1) + Enemies (2)
	_area.monitorable = false
	_area.monitoring = true
	add_child(_area)

func add_burn_poly(points: PackedVector2Array) -> void:
	# Add polygon to visual list
	_polygons.append(points)
	
	# Optimization: Track nodes for cleanup
	if _area:
		var col = CollisionPolygon2D.new()
		col.polygon = points
		_area.add_child(col)
		_collision_polys.append(col)
		
	# Create Eraser for Grass Mask
	if GrassMaskManager.instance:
		var mask_poly = Polygon2D.new()
		mask_poly.polygon = points
		mask_poly.color = Color.WHITE
		mask_poly.z_index = 0 # Flat on ground
		
		# Set transform to match this node
		mask_poly.global_position = global_position
		mask_poly.global_rotation = global_rotation
		mask_poly.global_scale = global_scale
		
		GrassMaskManager.instance.add_eraser(mask_poly)
		_mask_polys.append(mask_poly)
		
	# Performance Limit: Remove oldest
	if _polygons.size() > MAX_POLYGONS:
		_polygons.pop_front()
		
		if _collision_polys.size() > 0:
			var old_col = _collision_polys.pop_front()
			if is_instance_valid(old_col): old_col.queue_free()
			
		if _mask_polys.size() > 0:
			var old_mask = _mask_polys.pop_front()
			if is_instance_valid(old_mask): old_mask.queue_free()
	
	queue_redraw()

func _draw() -> void:
	var color_base = Color(0.15, 0.0, 0.0, 1.0) # Dark red opaque
	
	for poly in _polygons:
		draw_colored_polygon(poly, color_base)

var _process_timer: float = 0.0
const PROCESS_INTERVAL: float = 0.1

func _physics_process(delta: float) -> void:
	if not _area: return
	
	_process_timer += delta
	if _process_timer < PROCESS_INTERVAL:
		return
		
	var process_delta = _process_timer
	_process_timer = 0.0
	
	var bodies = _area.get_overlapping_bodies()
	for body in bodies:
		# STRICT TARGET FILTERING: Only Player, Charmed Enemies, and Summons
		var is_valid_target = false
		if body.is_in_group("player"): is_valid_target = true
		elif body.is_in_group("charmed_allies"): is_valid_target = true
		elif body.is_in_group("summons") or body.is_in_group("clones"): is_valid_target = true
		elif body.is_in_group("shielder_shields"): is_valid_target = true # Shields burn too?
		
		if not is_valid_target:
			continue
			
		if body.has_method("take_damage") or body.has_method("take_shield_damage"):
			# Get max HP - try property access, then get method, then default
			var max_hp := 100.0
			if "max_hp" in body:
				max_hp = float(body.max_hp)
			elif body.get("max_hp") != null:
				max_hp = float(body.get("max_hp"))
			elif body.has_method("get_max_hp"):
				max_hp = float(body.get_max_hp())
			
			# 25% HP per 0.25s = 100% per second
			var dps = max_hp * damage_rate_percent * 4.0
			var frame_damage = dps * process_delta
			
			# Accumulate
			var bid = body.get_instance_id()
			if not _damage_accum.has(bid):
				_damage_accum[bid] = 0.0
			
			_damage_accum[bid] += frame_damage
			
			# Apply full integer chunks
			if _damage_accum[bid] >= 1.0:
				var dmg_to_apply = int(_damage_accum[bid])
				_damage_accum[bid] -= dmg_to_apply
				
				if body.has_method("take_damage"):
					body.take_damage(dmg_to_apply, false, Vector2.ZERO, false, "Boss:Burning Ground")
				elif body.has_method("take_shield_damage"):
					body.take_shield_damage(dmg_to_apply)
