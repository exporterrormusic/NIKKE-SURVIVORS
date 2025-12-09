extends Node
class_name VisualLayerHelper
## Utility class for reparenting visual nodes to the EffectsLayer.
## Now uses CanvasLayerManager for consistent layer management.
##
## Eliminates duplicated reparenting boilerplate in Bullet.gd, projectile visuals, etc.

const PROJECTILE_BASE_Z_INDEX := 900


## Reparents a node to the EffectsLayer using CanvasLayerManager.
## This ensures projectiles/effects are not darkened by the world's CanvasModulate.
static func reparent_to_effects_layer(node: Node, z_index: int = PROJECTILE_BASE_Z_INDEX) -> void:
	if Engine.is_editor_hint():
		return
	
	# Use CanvasLayerManager for consistent layer assignment
	CanvasLayerManager.assign_to_effects(node, z_index)


## Helper to check if we should use the effects layer (for runtime only)
static func should_use_effects_layer() -> bool:
	return not Engine.is_editor_hint()
