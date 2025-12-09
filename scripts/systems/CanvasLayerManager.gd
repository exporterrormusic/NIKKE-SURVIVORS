extends Node
class_name CanvasLayerManager
## Centralized canvas layer management for proper visual separation.
##
## Organizes rendering into three distinct layers:
## - LAYER_WORLD: Game world (affected by CanvasModulate for day/night)
## - LAYER_EFFECTS: Visual effects (compensated to stay bright)
## - LAYER_UI: User interface (never affected by world lighting)
##
## Usage:
##   # Assign a node to the UI layer
##   CanvasLayerManager.assign_to_ui(my_hud_node)
##
##   # Get the effects layer reference
##   var fx_layer = CanvasLayerManager.get_effects_layer()

## Layer indices for z-order organization
const LAYER_WORLD = 0      # Terrain, enemies, player sprites
const LAYER_EFFECTS = 1    # Projectiles, particles, glows
const LAYER_UI = 2         # HUD, menus, overlays

## Cached layer references
static var _world_layer: CanvasLayer = null
static var _effects_layer: CanvasLayer = null
static var _ui_layer: CanvasLayer = null


## Assign a node to the world layer (affected by CanvasModulate)
static func assign_to_world(node: CanvasItem, z_index: int = 0) -> void:
	if node == null:
		push_error("[CanvasLayerManager] Cannot assign null node to world layer")
		return
	
	var layer = get_world_layer()
	if layer:
		_reparent_to_layer(node, layer, z_index)


## Assign a node to the effects layer (compensated modulate, stays bright)
static func assign_to_effects(node: CanvasItem, z_index: int = 900) -> void:
	if node == null:
		push_error("[CanvasLayerManager] Cannot assign null node to effects layer")
		return
	
	var layer = get_effects_layer()
	if layer:
		_reparent_to_layer(node, layer, z_index)


## Assign a node to the UI layer (never affected by world lighting)
static func assign_to_ui(node: CanvasItem, z_index: int = 100) -> void:
	if node == null:
		push_error("[CanvasLayerManager] Cannot assign null node to UI layer")
		return
	
	var layer = get_ui_layer()
	if layer:
		_reparent_to_layer(node, layer, z_index)


## Get or create the world layer reference
static func get_world_layer() -> CanvasLayer:
	if _world_layer != null and is_instance_valid(_world_layer):
		return _world_layer
	
	# World layer is typically the root/scene tree itself (layer 0)
	# Return null - world nodes don't need special layer assignment
	return null


## Get or create the effects layer reference
static func get_effects_layer() -> CanvasLayer:
	if _effects_layer != null and is_instance_valid(_effects_layer):
		return _effects_layer
	
	# Try to find EffectsLayer from EnvironmentController
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var env = tree.get_first_node_in_group("environment_controller")
		if env:
			var effects = env.get_node_or_null("EffectsLayer")
			if effects and effects is CanvasLayer:
				_effects_layer = effects
				return _effects_layer
	
	return null


## Get or create the UI layer reference
static func get_ui_layer() -> CanvasLayer:
	if _ui_layer != null and is_instance_valid(_ui_layer):
		return _ui_layer
	
	# Try to find UILayer in the scene
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		# Look for a CanvasLayer named "UILayer" or "HUD"
		var ui_layer = tree.root.find_child("UILayer", true, false)
		if ui_layer and ui_layer is CanvasLayer:
			_ui_layer = ui_layer
			return _ui_layer
		
		# Fallback: look for CanvasLayer in scene
		var canvas_layers = tree.get_nodes_in_group("ui_layer")
		if canvas_layers.size() > 0 and canvas_layers[0] is CanvasLayer:
			_ui_layer = canvas_layers[0]
			return _ui_layer
	
	return null


## Reparent a node to a canvas layer, preserving global transform
static func _reparent_to_layer(node: CanvasItem, layer: CanvasLayer, z_index: int) -> void:
	if Engine.is_editor_hint():
		return
	
	# Save global transform for Node2D types
	var saved_transform: Transform2D
	var is_node2d := node is Node2D
	if is_node2d:
		saved_transform = (node as Node2D).global_transform
	
	# Reparent to the layer
	var old_parent = node.get_parent()
	if old_parent:
		old_parent.remove_child(node)
	
	layer.add_child(node)
	node.z_index = z_index
	
	# Restore global transform
	if is_node2d:
		(node as Node2D).global_transform = saved_transform


## Clear cached layer references (useful for scene transitions)
static func clear_cache() -> void:
	_world_layer = null
	_effects_layer = null
	_ui_layer = null


## Debug: Print current layer assignments
static func debug_print_layers() -> void:
	print("[CanvasLayerManager] Layer Status:")
	print("  World Layer: ", _world_layer)
	print("  Effects Layer: ", _effects_layer)  
	print("  UI Layer: ", _ui_layer)
