extends Node
class_name ProjectileCache
## Centralized scene cache to prevent concurrent preload race conditions.
## All combat effect scenes should be loaded through this singleton.

# =============================================================================
# BULLET SCENES
# =============================================================================
const BulletScene: PackedScene = preload("res://scenes/effects/Bullet.tscn")
const AssaultBulletScene: PackedScene = preload("res://scenes/effects/AssaultBullet.tscn")
const SMGBulletScene: PackedScene = preload("res://scenes/effects/SMGBullet.tscn")
const SnowWhiteBulletScene: PackedScene = preload("res://scenes/effects/SnowWhiteBullet.tscn")

# =============================================================================
# EXPLOSIVE/MISSILE SCENES
# =============================================================================
const MissileScene: PackedScene = preload("res://scenes/effects/Missile.tscn")
const RocketScene: PackedScene = preload("res://scenes/effects/Rocket.tscn")
const ExplosionScene: PackedScene = preload("res://scenes/effects/Explosion.tscn")
const ExplosionEffectScene: PackedScene = preload("res://scenes/effects/ExplosionEffect.tscn")
const GroundFireScene: PackedScene = preload("res://scenes/effects/GroundFire.tscn")

# =============================================================================
# MELEE/EFFECT SCENES
# =============================================================================
const SlashScene: PackedScene = preload("res://scenes/effects/Slash.tscn")
const ScarletWaveScene: PackedScene = preload("res://scenes/effects/ScarletWave.tscn")
const KiloPelletScene: PackedScene = preload("res://scenes/effects/KiloPellet.tscn")

# =============================================================================
# UTILITY SCENES
# =============================================================================
const TurretScene: PackedScene = preload("res://scenes/effects/Turret.tscn")
const HealingCrossScene: PackedScene = preload("res://scenes/effects/HealingCross.tscn")
const XPOrbScene: PackedScene = preload("res://scenes/effects/XPOrb.tscn")

# Pooling System
static var _pools: Dictionary = {}

# =============================================================================
# POOL CLEANUP (Call on game exit to prevent RID leaks)
# =============================================================================
static func clear_all_pools() -> void:
	## Free all pooled objects to prevent RID leaks on exit.
	## Call this from a level's _exit_tree or from main menu when returning.
	for type in _pools.keys():
		var pool_list: Array = _pools[type]
		for node in pool_list:
			if is_instance_valid(node):
				node.queue_free()
		pool_list.clear()
	_pools.clear()
	print("[ProjectileCache] All pools cleared")

# =============================================================================
# BULLET FACTORY METHODS
# =============================================================================
static func create_bullet() -> Node:
	return _get_from_pool("bullet", BulletScene)

static func _get_from_pool(type: String, scene: PackedScene) -> Node:
	if _pools.has(type) and not _pools[type].is_empty():
		var node = _pools[type].pop_back()
		if is_instance_valid(node):
			# Safety net: Ensure node is detached
			if node.get_parent():
				node.get_parent().remove_child(node)
				
			node.set_process(true)
			node.set_physics_process(true)
			node.visible = true
			if node.has_method("reset"):
				node.reset()
			return node
	
	# Create new if pool empty
	var new_node = scene.instantiate()
	new_node.set_meta("pool_type", type)
	return new_node

static func return_to_pool(node: Node) -> void:
	if not is_instance_valid(node):
		return
		
	var type = node.get_meta("pool_type", "")
	if type == "":
		node.queue_free()
		return
		
	# 1. Immediate Visual Hiding (Safe)
	node.visible = false
	node.set_process(false)
	node.set_physics_process(false)
	
	# 2. Defer Physics Property Changes (Critical)
	if node is Area2D:
		node.set_deferred("monitoring", false)
		node.set_deferred("monitorable", false)
	
	# 3. Defer Removal and Storage
	# We use a lambda to delay this until end of frame (Physics Safe)
	var do_return = func():
		if is_instance_valid(node):
			var parent = node.get_parent()
			if parent:
				parent.remove_child(node)
			
			if not _pools.has(type):
				_pools[type] = []
			
			# Prevent double-return (critical for pool safety)
			if node in _pools[type]:
				return
				
			_pools[type].append(node)
			
	do_return.call_deferred()


static func create_assault_bullet() -> Node:
	return _get_from_pool("assault_bullet", AssaultBulletScene)

static func create_smg_bullet() -> Node:
	return _get_from_pool("smg_bullet", SMGBulletScene)

static func create_snow_white_bullet() -> Node:
	return _get_from_pool("snow_white_bullet", SnowWhiteBulletScene)

# =============================================================================
# EXPLOSIVE FACTORY METHODS
# =============================================================================
static func create_missile() -> Node:
	return MissileScene.instantiate()

static func create_rocket() -> Node:
	return _get_from_pool("rocket", RocketScene)

static func create_explosion() -> Node:
	# DEBUG: User reports "Purple Explosion" during Scarlet Burst.
	# Scarlet should NOT spawn explosions. Trace who calls this.
	return ExplosionScene.instantiate()

static func create_explosion_effect() -> Node:
	return ExplosionEffectScene.instantiate()

static func create_ground_fire() -> Node:
	return GroundFireScene.instantiate()

# =============================================================================
# MELEE/EFFECT FACTORY METHODS
# =============================================================================
static func create_slash() -> Node:
	return SlashScene.instantiate()

static func create_scarlet_wave() -> Node:
	return ScarletWaveScene.instantiate()

static func create_kilo_pellet() -> Node:
	return KiloPelletScene.instantiate()

# =============================================================================
# UTILITY FACTORY METHODS
# =============================================================================
static func create_turret() -> Node:
	return TurretScene.instantiate()

static func create_healing_cross() -> Node:
	return HealingCrossScene.instantiate()

static func create_xp_orb() -> Node:
	return _get_from_pool("xp_orb", XPOrbScene)

# =============================================================================
# CACHE WARMING
# =============================================================================
static func warm_up_cache(parent: Node) -> void:
	"""
	Pre-instantiates a batch of common projectiles and effects to force 
	shader compilation and texture upload at map start, preventing initial stutter.
	"""
	print("[ProjectileCache] Warming up asset cache...")
	# Note: We add directly to parent instead of a temp container because
	# return_to_pool uses deferred removal. If we freed a temp container immediately,
	# the children would be destroyed before being pooled.
	
	# List of common projectiles to warm up
	var items_to_warm = [
		{"factory": Callable(ProjectileCache, "create_bullet"), "count": 10},
		{"factory": Callable(ProjectileCache, "create_xp_orb"), "count": 20},
		{"factory": Callable(ProjectileCache, "create_assault_bullet"), "count": 5},
		{"factory": Callable(ProjectileCache, "create_smg_bullet"), "count": 5},
		{"factory": Callable(ProjectileCache, "create_slash"), "count": 2},
		{"factory": Callable(ProjectileCache, "create_explosion"), "count": 2},
	]
	
	# Create them, add to tree (forces ready/draw), then return to pool
	var created_nodes = []
	for item in items_to_warm:
		try_warm_item(item, parent, created_nodes)
	
	for node in created_nodes:
		# Ensure they are hidden/offscreen immediately (though return_to_pool does this too)
		if node is Node2D:
			node.position = Vector2(-9999, -9999)
			node.visible = false
		return_to_pool(node)
		
	print("[ProjectileCache] Cache warmup complete. Pools populated.")

static func try_warm_item(item: Dictionary, parent: Node, created_nodes: Array) -> void:
	# Helpler to catch potential errors during warming
	for i in range(item.count):
		var node = item.factory.call()
		if node:
			parent.add_child(node)
			created_nodes.append(node)
