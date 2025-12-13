
import os

content = """extends Node2D

## Oil Burn Manager (Optimized)
## Manages persistent burn polygons via a SINGLE Area2D to reduce overhead.
## Visuals: Continuous bubbling dark red/purple liquid.

var damage_rate_percent := 0.25
var _polygons: Array[PackedVector2Array] = []
var _damage_accum: Dictionary = {} # Store float damage per body instance ID

# Optimization: Single Area2D for all oil
var _area: Area2D = null

func _ready() -> void:
\tz_index = -5
\t
\t# Create the single physics manager
\t_area = Area2D.new()
\t_area.name = "BurnArea"
\t_area.collision_layer = 0
\t_area.collision_mask = 3 # Player (1) + Enemies (2)
\t_area.monitorable = false
\t_area.monitoring = true
\tadd_child(_area)

func add_burn_poly(points: PackedVector2Array) -> void:
\t# Add polygon to visual list
\t_polygons.append(points)
\t
\t# Add collision shape to the SHARED area
\tif _area:
\t\tvar col = CollisionPolygon2D.new()
\t\tcol.polygon = points
\t\t_area.add_child(col)
\t\t
\t# Create Eraser for Grass Mask
\tif GrassMaskManager.instance:
\t\tvar mask_poly = Polygon2D.new()
\t\tmask_poly.polygon = points
\t\tmask_poly.color = Color.WHITE
\t\tmask_poly.z_index = 0 # Flat on ground
\t\t
\t\t# Set transform to match this node
\t\tmask_poly.global_position = global_position
\t\tmask_poly.global_rotation = global_rotation
\t\tmask_poly.global_scale = global_scale
\t\t
\t\tGrassMaskManager.instance.add_eraser(mask_poly)
\t
\tqueue_redraw()

func _draw() -> void:
\tvar color_base = Color(0.15, 0.0, 0.0, 1.0) # Dark red opaque
\t
\tfor poly in _polygons:
\t\tdraw_colored_polygon(poly, color_base)

func _physics_process(delta: float) -> void:
\tif not _area: return
\t
\tvar bodies = _area.get_overlapping_bodies()
\tfor body in bodies:
\t\t# STRICT TARGET FILTERING: Only Player, Charmed Enemies, and Summons
\t\tvar is_valid_target = false
\t\tif body.is_in_group("player"): is_valid_target = true
\t\telif body.is_in_group("charmed_allies"): is_valid_target = true
\t\telif body.is_in_group("summons") or body.is_in_group("clones"): is_valid_target = true
\t\telif body.is_in_group("shielder_shields"): is_valid_target = true # Shields burn too?
\t\t
\t\tif not is_valid_target:
\t\t\tcontinue
\t\t\t
\t\tif body.has_method("take_damage") or body.has_method("take_shield_damage"):
\t\t\t# calculate dps
\t\t\tvar max_hp = 100.0
\t\t\tif "max_hp" in body: 
\t\t\t\tmax_hp = float(body.max_hp)
\t\t\t
\t\t\tvar dps = max_hp * damage_rate_percent
\t\t\tvar frame_damage = dps * delta
\t\t\t
\t\t\t# Accumulate
\t\t\tvar bid = body.get_instance_id()
\t\t\tif not _damage_accum.has(bid):
\t\t\t\t_damage_accum[bid] = 0.0
\t\t\t
\t\t\t_damage_accum[bid] += frame_damage
\t\t\t
\t\t\t# Apply full integer chunks
\t\t\tif _damage_accum[bid] >= 1.0:
\t\t\t\tvar dmg_to_apply = int(_damage_accum[bid])
\t\t\t\t_damage_accum[bid] -= dmg_to_apply
\t\t\t\t
\t\t\t\tif body.has_method("take_damage"):
\t\t\t\t\tbody.take_damage(dmg_to_apply)
\t\t\t\telif body.has_method("take_shield_damage"):
\t\t\t\t\t body.take_shield_damage(dmg_to_apply)
"""

file_path = r"c:\Users\rmdou\Desktop\movement-test\scripts\enemies\bosses\effects\OilBurnZone.gd"
with open(file_path, "w") as f:
    f.write(content)

print(f"Successfully wrote {file_path} with explicit tabs.")
