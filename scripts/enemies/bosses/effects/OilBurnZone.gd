extends Node2D

## Oil Burn Manager (Replaces single zone)
## Manages persistent burn polygons stamped by the Boss Beam.
## Visuals: Continuous bubbling dark red/purple liquid.

var damage_rate_percent := 0.25
var _polygons: Array[PackedVector2Array] = []
var _time: float = 0.0

func _ready() -> void:
	z_index = -5
	# No collision area on root. We add CollisionPolygon2D children.

func add_burn_poly(points: PackedVector2Array) -> void:
	# Add polygon to visual list
	_polygons.append(points)
	
	# Create physics body for damage
	var area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 3 # Player (1) + Enemies (2)
	area.monitorable = false
	area.monitoring = true
	area.set_script(_get_damage_script())
	add_child(area)
	
	var col = CollisionPolygon2D.new()
	col.polygon = points
	area.add_child(col)
	
	queue_redraw()

func _draw() -> void:
	var color_base = Color(0.15, 0.0, 0.0, 1.0) # Dark red opaque
	var color_edge = Color(0.4, 0.0, 0.0, 1.0)
	
	for poly in _polygons:
		draw_colored_polygon(poly, color_base)
		# draw_polyline(poly, color_edge, 2.0) # Removed to allow visual merging
	
	# Optimizing bubbles: Draw random bubbles within known bounds of polygons?
	# Or just iterating points is too expensive. 
	# Effect: Draw some global bubbles masked by polygons? 
	# A simple way: Iterate polygons and draw a few bubbles in their "center" or along edges?
	# For now, solid shape is safest for performance.
	
func _process(delta: float) -> void:
	_time += delta
	# request redraw if animating bubbles

func _get_damage_script() -> GDScript:
	var script = GDScript.new()
	script.source_code = """
extends Area2D

var damage_rate_percent := 0.25
var _damage_accum: Dictionary = {} # Store float damage per body instance ID

func _physics_process(delta: float) -> void:
	var bodies = get_overlapping_bodies()
	# print("Oil Burn Process. Bodies: ", bodies.size()) # Debug spam
	
	for body in bodies:
		# STRICT TARGET FILTERING: Only Player, Charmed Enemies, and Summons
		var is_valid_target = false
		if body.is_in_group("player"): is_valid_target = true
		elif body.is_in_group("charmed_allies"): is_valid_target = true
		elif body.is_in_group("summons") or body.is_in_group("clones"): is_valid_target = true
		
		if not is_valid_target:
			continue
			
		if body.has_method("take_damage"):
             # ...
			# calculate dps
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

	# Clean up old bodies? For simplicity, we just keep the dict growing or check validity?
	# Small optimization: clean up keys for bodies not in list?
	# Not strictly necessary for boss fight length.
"""
	script.reload() # CRITICAL: Compile the script
	return script
