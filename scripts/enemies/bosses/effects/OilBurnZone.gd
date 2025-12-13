extends Node2D

## Oil Burn Manager (Optimized)
## Manages persistent burn polygons via a SINGLE Area2D to reduce overhead.
## Visuals: Continuous bubbling dark red/purple liquid.

var damage_rate_percent := 0.25
var _polygons: Array[PackedVector2Array] = []
var _damage_accum: Dictionary = {} # Store float damage per body instance ID

# Optimization: Single Area2D for all oil
var _area: Area2D = null

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
    
    # Add collision shape to the SHARED area
    if _area:
        var col = CollisionPolygon2D.new()
        col.polygon = points
        _area.add_child(col)
    
    queue_redraw()

func _draw() -> void:
    var color_base = Color(0.15, 0.0, 0.0, 1.0) # Dark red opaque
    # var color_edge = Color(0.4, 0.0, 0.0, 1.0)
    
    for poly in _polygons:
        draw_colored_polygon(poly, color_base)

func _physics_process(delta: float) -> void:
    if not _area: return
    
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
                
                if body.has_method("take_damage"):
                    body.take_damage(dmg_to_apply)
                elif body.has_method("take_shield_damage"):
                     body.take_shield_damage(dmg_to_apply)
