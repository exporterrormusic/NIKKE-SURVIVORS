class_name Pool
## Generic node pool utility. Reusable across projectiles, effects, and enemies.
##
## Usage:
##   var bullet_pool := Pool.new(BulletScene, "bullet")
##   var b = bullet_pool.acquire()
##   ...
##   bullet_pool.release(b)
##
##   # Pre-warm when possible
##   bullet_pool.prewarm(20, parent_node)

## Scene to instantiate when pool is empty
var _scene: PackedScene

## Pool identifier (used for metadata)
var _pool_id: String

## Pooled instances (available for reuse)
var _pool: Array[Node] = []

## Scene tree for deferred operations
var _tree: SceneTree = null


func _init(scene: PackedScene, pool_id: String = "") -> void:
	_scene = scene
	_pool_id = pool_id
	if Engine.get_main_loop() is SceneTree:
		_tree = Engine.get_main_loop() as SceneTree


## Acquire a node from the pool (or create new if pool is empty).
## The returned node will be visible, processing, and have reset() called.
func acquire() -> Node:
	if not _pool.is_empty():
		var node = _pool.pop_back()
		if is_instance_valid(node):
			# Detach from parent if still attached
			if node.get_parent():
				node.get_parent().remove_child(node)
			
			node.set_process(true)
			node.set_physics_process(true)
			node.visible = true
			if node.has_method("reset"):
				node.reset()
			return node
	
	# Create new
	var new_node = _scene.instantiate()
	new_node.set_meta("pool_type", _pool_id)
	return new_node


## Return a node to the pool. Hides and disables it immediately,
## then defers reparenting to avoid physics-engine conflicts.
func release(node: Node) -> void:
	if not is_instance_valid(node):
		return
	
	# Immediate visual hiding (safe to do in any callback)
	node.visible = false
	node.set_process(false)
	node.set_physics_process(false)
	
	# Defer physics property changes (critical for Area2D nodes)
	if node is Area2D:
		node.set_deferred("monitoring", false)
		node.set_deferred("monitorable", false)
	
	# Defer removal and re-storage (avoids "parent busy" errors)
	var do_return = func():
		if not is_instance_valid(node):
			return
		var parent = node.get_parent()
		if parent:
			parent.remove_child(node)
		# Prevent double-return
		if node in _pool:
			return
		_pool.append(node)
	
	if _tree:
		_tree.root.call_deferred(do_return)
	else:
		do_return.call_deferred()


## Pre-warm the pool by instantiating count nodes and adding them as children
## of the given parent. Call at scene load to prevent mid-game stutter.
func prewarm(count: int, parent: Node) -> void:
	for i in range(count):
		var node = _scene.instantiate()
		node.visible = false
		node.set_process(false)
		node.set_physics_process(false)
		if node is Area2D:
			node.monitoring = false
			node.monitorable = false
		node.set_meta("pool_type", _pool_id)
		parent.add_child(node)
		_pool.append(node)


## Release all pooled nodes by freeing them. Call on scene exit.
func clear() -> void:
	for node in _pool:
		if is_instance_valid(node):
			node.queue_free()
	_pool.clear()


## Get current size of the available pool (not counting active instances).
func size() -> int:
	return _pool.size()


## Alias for backward compatibility — matches old acquire/release naming.
func get_instance() -> Node:
	return acquire()
