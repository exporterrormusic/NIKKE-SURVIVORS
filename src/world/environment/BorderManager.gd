extends Node
class_name BorderManager
## Manages world border physics (collision bodies around map edges).
##
## Extracted from EnvironmentController to reduce god class size.
## Creates invisible StaticBody2D borders with CollisionPolygon2D around
## the world bounds to keep entities inside the playable area.

const WORLD_BORDER_THICKNESS := 60.0
const WORLD_BORDER_COLOR := Color(0.08, 0.08, 0.1, 0.0)

var _border_overlay: Node2D = null
var _world_bounds: Rect2 = Rect2()


func ensure_border_overlay(parent: Node) -> Node2D:
	if _border_overlay != null:
		return _border_overlay
	
	var node := parent.get_node_or_null("BorderOverlay")
	if node and node is Node2D:
		_border_overlay = node
		return _border_overlay
	
	var border := Node2D.new()
	border.name = "BorderOverlay"
	border.z_index = -140
	parent.add_child(border)
	if Engine.is_editor_hint():
		border.owner = parent.get_tree().edited_scene_root
	_border_overlay = border
	return _border_overlay


func set_world_bounds(bounds: Rect2) -> void:
	_world_bounds = bounds
	_rebuild_borders()


func get_world_bounds() -> Rect2:
	return _world_bounds


func cleanup_saved_border_visuals() -> void:
	"""Recursively find all nodes named BorderOverlay and free visual children."""
	var root := _get_tree_root()
	if root == null:
		return
	var overlays: Array[Node] = []
	_collect_nodes_by_name(root, "BorderOverlay", overlays)
	for overlay in overlays:
		for child in overlay.get_children():
			if child is StaticBody2D:
				continue
			if child is CollisionPolygon2D:
				continue
			if child is Polygon2D or child is ColorRect or child is Sprite2D or child is CanvasItem:
				child.queue_free()


func _get_tree_root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		return tree.root
	return null


func _collect_nodes_by_name(node: Node, name_to_find: String, out_list: Array) -> void:
	if node.name == name_to_find:
		out_list.append(node)
	for child in node.get_children():
		if child is Node:
			_collect_nodes_by_name(child, name_to_find, out_list)


func _rebuild_borders() -> void:
	if _border_overlay == null:
		return
	
	for child in _border_overlay.get_children():
		child.queue_free()
	
	if _world_bounds.size == Vector2.ZERO:
		_border_overlay.visible = false
		return
	
	_border_overlay.visible = true
	var min_corner := _world_bounds.position
	var size := _world_bounds.size
	var max_corner := min_corner + size
	var thickness := WORLD_BORDER_THICKNESS
	
	var segments := [
		PackedVector2Array([
			Vector2(min_corner.x - thickness, min_corner.y - thickness),
			Vector2(min_corner.x, min_corner.y - thickness),
			Vector2(min_corner.x, max_corner.y + thickness),
			Vector2(min_corner.x - thickness, max_corner.y + thickness)
		]),
		PackedVector2Array([
			Vector2(max_corner.x, min_corner.y - thickness),
			Vector2(max_corner.x + thickness, min_corner.y - thickness),
			Vector2(max_corner.x + thickness, max_corner.y + thickness),
			Vector2(max_corner.x, max_corner.y + thickness)
		]),
		PackedVector2Array([
			Vector2(min_corner.x - thickness, min_corner.y - thickness),
			Vector2(max_corner.x + thickness, min_corner.y - thickness),
			Vector2(max_corner.x + thickness, min_corner.y),
			Vector2(min_corner.x - thickness, min_corner.y)
		]),
		PackedVector2Array([
			Vector2(min_corner.x - thickness, max_corner.y),
			Vector2(max_corner.x + thickness, max_corner.y),
			Vector2(max_corner.x + thickness, max_corner.y + thickness),
			Vector2(min_corner.x - thickness, max_corner.y + thickness)
		])
	]
	
	for polygon_points in segments:
		var body := StaticBody2D.new()
		body.collision_layer = 0
		body.set_collision_layer_value(16, true)
		body.collision_mask = 0
		var collision_shape := CollisionPolygon2D.new()
		collision_shape.polygon = polygon_points
		body.add_child(collision_shape)
		_border_overlay.add_child(body)
		if Engine.is_editor_hint():
			body.owner = _border_overlay.get_tree().edited_scene_root
