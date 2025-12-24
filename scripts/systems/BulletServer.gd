extends Node2D
class_name BulletServer

# Singleton access
static var _instance: BulletServer = null
static var _creating_instance: bool = false # Prevent race condition

# PERFORMANCE: Cached player reference (avoids per-collision get_first_node_in_group)
static var _cached_player: Node = null
static var _cached_player_frame: int = -1
static var _cached_chrono_intangibility: bool = false
static var _cached_chrono_frame: int = -1

# Cached ShopMenu reference to avoid load() in hot collision path
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")
const SMG_BULLET_TEXTURE = preload("res://assets/projectiles/smg_bullet.png")

# Bullet settings
const MAX_BULLETS = 2000
const MASK_COLLISION = 7 # World(1) + Enemy(2 - legacy) + Hitbox(4)

const BULLET_SCALE = Vector2(0.12, 0.12)
const BULLET_COLOR = Color(0, 0.9, 1, 1) # Cyan from SMGBullet.tscn
# Assets
var _smg_texture: Texture2D
var _smg_texture_rid: RID
var _smg_texture_size: Vector2
var _glow_material_rid: RID
var _parent_canvas_item: RID

# State
var _bullets: Array[SimpleBullet] = []
var _pool: Array[SimpleBullet] = []

# Inner class for lightweight bullet data
class SimpleBullet:
	var active: bool = false
	var position: Vector2
	var velocity: Vector2
	var lifetime: float
	var max_range: float
	var start_position: Vector2
	var damage: int
	var owner: Node
	var is_player_owned: bool = false
	var visual_rid: RID
	var hit_uids: Dictionary = {} # Use instance ID to track hits
	var source_id: String = "smg" # Source weapon type for burst/XP tracking
	
	func _init(canvas_parent: RID):
		visual_rid = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(visual_rid, canvas_parent)
		RenderingServer.canvas_item_set_visible(visual_rid, false)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			if visual_rid.is_valid():
				RenderingServer.free_rid(visual_rid)


static func get_instance() -> BulletServer:
	# Return existing valid instance
	if is_instance_valid(_instance):
		return _instance
	# Prevent race condition - another call is already creating instance
	if _creating_instance:
		return null # Caller should handle null gracefully
	# Create new instance with lock
	_creating_instance = true
	_instance = BulletServer.new()
	_instance.name = "BulletServer"
	if Engine.get_main_loop() and Engine.get_main_loop().root:
		Engine.get_main_loop().root.call_deferred("add_child", _instance)
	_creating_instance = false
	return _instance

func _ready() -> void:
	# Load assets
	_smg_texture = SMG_BULLET_TEXTURE
	if _smg_texture:
		_smg_texture_rid = _smg_texture.get_rid()
		_smg_texture_size = _smg_texture.get_size()
	
	# Get shared material
	if ShaderCache.get_bullet_glow_material():
		_glow_material_rid = ShaderCache.get_bullet_glow_material().get_rid()
	
	_parent_canvas_item = get_canvas_item()
	
	# Pre-allocate pool
	for i in range(200):
		_pool.append(SimpleBullet.new(_parent_canvas_item))

func _exit_tree() -> void:
	# Clean up RIDs to prevent leaks
	for b in _bullets:
		if b.visual_rid.is_valid():
			RenderingServer.free_rid(b.visual_rid)
	_bullets.clear()
	
	for b in _pool:
		if b.visual_rid.is_valid():
			RenderingServer.free_rid(b.visual_rid)
	_pool.clear()
	
	if _instance == self:
		_instance = null
	print("[BulletServer] Cleanup complete")

func spawn_smg_bullet(pos: Vector2, vel: Vector2, damage: int, owner_node: Node) -> void:
	spawn_colored_bullet(pos, vel, damage, owner_node, BULLET_COLOR, "smg")

func spawn_colored_bullet(pos: Vector2, vel: Vector2, damage: int, owner_node: Node, color: Color, source_id: String = "smg") -> void:
	if not _smg_texture: return
	
	var bullet: SimpleBullet
	if _pool.is_empty():
		bullet = SimpleBullet.new(_parent_canvas_item)
	else:
		bullet = _pool.pop_back()
	
	# Initialize
	bullet.active = true
	bullet.position = pos
	bullet.start_position = pos
	bullet.velocity = vel
	bullet.damage = damage
	bullet.owner = owner_node
	bullet.lifetime = 0.0

	bullet.max_range = 750.0
	bullet.hit_uids.clear()
	bullet.source_id = source_id
	
	# Setup visual
	RenderingServer.canvas_item_clear(bullet.visual_rid)
	RenderingServer.canvas_item_add_texture_rect(bullet.visual_rid, Rect2(-_smg_texture_size / 2, _smg_texture_size), _smg_texture_rid)
	if _glow_material_rid.is_valid():
		RenderingServer.canvas_item_set_material(bullet.visual_rid, _glow_material_rid)
	
	# Apply Custom Color
	RenderingServer.canvas_item_set_modulate(bullet.visual_rid, color)
	
	# Apply Transform with Scale
	var xform = Transform2D(vel.angle(), pos)
	xform.x *= BULLET_SCALE.x
	xform.y *= BULLET_SCALE.y
	RenderingServer.canvas_item_set_transform(bullet.visual_rid, xform)
	
	RenderingServer.canvas_item_set_visible(bullet.visual_rid, true)
	
	_bullets.append(bullet)

# Reusable query object to avoid per-bullet allocation
var _query: PhysicsRayQueryParameters2D = null

func _physics_process(delta: float) -> void:
	if _bullets.is_empty():
		return
		
	# Apply Global Enemy Time Scale (Bullet Time)
	# Done inside loop per bullet
		
	var space_state = get_world_2d().direct_space_state
	var i = _bullets.size() - 1
	
	# Create reusable query once
	if _query == null:
		_query = PhysicsRayQueryParameters2D.new()
		_query.collision_mask = MASK_COLLISION
		_query.collide_with_areas = true
		_query.collide_with_bodies = true
	
	# PRE-CALCULATION: Get global time scale once per frame
	var enemy_time_scale := 1.0
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		enemy_time_scale = game_manager.enemy_time_scale
		
	while i >= 0:
		var b = _bullets[i]
		
		# Move
		var time_scale = 1.0
		# Optimization: Use cached boolean instead of group check + get_node every iteration
		if not b.is_player_owned:
			time_scale = enemy_time_scale
			
		var move_vec = b.velocity * (delta * time_scale)
		var next_pos = b.position + move_vec
		
		# Raycast for collision - reuse query object
		_query.from = b.position
		_query.to = next_pos
		_query.exclude.clear()
		if is_instance_valid(b.owner) and b.owner is CollisionObject2D:
			_query.exclude.append(b.owner.get_rid())
		
		var result = space_state.intersect_ray(_query)
		var destroyed = false
		
		if result:
			# Hit something
			if _handle_collision(b, result.collider):
				# Collision handled and bullet should be destroyed or stopped
				b.position = result.position
				destroyed = true
			else:
				# Collision ignored (pierced or non-blocking) - continue movement
				b.position = next_pos
		else:
			b.position = next_pos
			
		if not destroyed:
			# Lifecycle checks - use distance_squared for performance
			b.lifetime += delta
			if b.lifetime > 5.0:
				destroyed = true
			elif b.max_range > 0:
				var max_range_sq: float = b.max_range * b.max_range
				if b.position.distance_squared_to(b.start_position) > max_range_sq:
					destroyed = true
		
		if destroyed:
			_despawn_bullet(b)
			_bullets.remove_at(i)
		else:
			# Update visual with scale
			var xform = Transform2D(b.velocity.angle(), b.position)
			xform.x *= BULLET_SCALE.x
			xform.y *= BULLET_SCALE.y
			RenderingServer.canvas_item_set_transform(b.visual_rid, xform)
			
		i -= 1

func _handle_collision(b: SimpleBullet, collider: Object) -> bool:
	if not is_instance_valid(collider):
		return false
		
	# Ignore owner and allies
	if collider == b.owner: return false
	if collider.is_in_group("charmed_allies"): return false
	
	# Prevent multi-hit
	var id = collider.get_instance_id()
	if id in b.hit_uids:
		return false
	
	# PERFORMANCE: Get cached player reference (once per frame instead of per collision)
	var current_frame := Engine.get_process_frames()
	if current_frame != _cached_player_frame:
		_cached_player_frame = current_frame
		_cached_player = get_tree().get_first_node_in_group("player")
		# Also cache Chrono-Intangibility check once per frame
		if _cached_player and _cached_player.has_method("is_character_in_squad"):
			_cached_chrono_intangibility = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and _cached_player.is_character_in_squad("wells")
		else:
			_cached_chrono_intangibility = false
		_cached_chrono_frame = current_frame
		
	# Handle Shield (Shielder Enemy)
	# Check for Area2D parent or direct method
	var shield_root = null
	if collider is Area2D:
		shield_root = collider.get_parent()
	elif collider.has_method("take_shield_damage"):
		shield_root = collider
		
	if shield_root and shield_root.has_method("take_shield_damage"):
		# Check if Chrono-Intangibility upgrade allows phasing through shields
		if _cached_chrono_intangibility:
			# Bullet phases through shield - don't damage or destroy
			return false
		
		shield_root.take_shield_damage(b.damage)
		return true # Destroy bullet on shield hit
	
	# Determine if protected by shield
	if collider.has_method("is_protected_by_shield") and collider.is_protected_by_shield():
		# Check if Chrono-Intangibility allows phasing through protected enemies
		if _cached_chrono_intangibility:
			# Bullet phases through - continue to damage enemy normally below
			pass
		else:
			# Absorbed by shield elsewhere, just destroy bullet
			return true

	# Check for damageable
	if not collider.has_method("take_damage"):
		# Wall/Obstacle -> Destroy (unless it's a boulder and we can phase through)
		if collider is TileMap or collider is StaticBody2D:
			# PERFORMANCE: Use TargetCache instead of get_nodes_in_group per collision
			var is_boulder = false
			var boulders = TargetCache.get_boulders()
			for boulder in boulders:
				if is_instance_valid(boulder) and (boulder == collider or boulder.is_ancestor_of(collider)):
					is_boulder = true
					break
				# Spatial backup check
				if is_instance_valid(boulder):
					var b_rad = 150.0
					if "boulder_size" in boulder: b_rad = boulder.boulder_size * 0.5
					if b.position.distance_squared_to(boulder.global_position) < (b_rad * 1.2) ** 2:
						is_boulder = true
						break
			
			if is_boulder:
				if _cached_chrono_intangibility:
					return false # Phase through boulder
			
			return true
		return false # Pass through non-blocking
		
	# Apply damage
	var crit_chance = 0.15 # Base
	if _cached_player and _cached_player.has_method("get_crit_chance"):
		crit_chance += _cached_player.get_crit_chance()
	
	var is_crit = randf() < crit_chance
	var final_damage = b.damage * 2 if is_crit else b.damage
	
	var hit_dir = b.velocity.normalized()

	# Apply with weapon type source for Goddess Fall tracking
	collider.take_damage(final_damage, is_crit, hit_dir, false, b.source_id)
	
	b.hit_uids[id] = true
	
	# Return true to destroy (SMG bullets don't pierce by default)
	return true

func _despawn_bullet(b: SimpleBullet) -> void:
	b.active = false
	RenderingServer.canvas_item_set_visible(b.visual_rid, false)
	_pool.append(b)

func get_active_count() -> int:
	return _bullets.size()
