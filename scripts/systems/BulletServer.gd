extends Node2D
class_name BulletServer

# Singleton access
static var _instance: BulletServer = null

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
	var visual_rid: RID
	var hit_uids: Dictionary = {} # Use instance ID to track hits
	
	func _init(canvas_parent: RID):
		visual_rid = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(visual_rid, canvas_parent)
		RenderingServer.canvas_item_set_visible(visual_rid, false)

static func get_instance() -> BulletServer:
	if not is_instance_valid(_instance):
		_instance = BulletServer.new()
		_instance.name = "BulletServer"
		if Engine.get_main_loop() and Engine.get_main_loop().root:
			Engine.get_main_loop().root.call_deferred("add_child", _instance)
	return _instance

func _ready() -> void:
	# Load assets
	_smg_texture = load("res://assets/projectiles/smg_bullet.png")
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

func spawn_smg_bullet(pos: Vector2, vel: Vector2, damage: int, owner_node: Node) -> void:
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
	
	# Setup visual
	RenderingServer.canvas_item_clear(bullet.visual_rid)
	RenderingServer.canvas_item_add_texture_rect(bullet.visual_rid, Rect2(-_smg_texture_size/2, _smg_texture_size), _smg_texture_rid)
	if _glow_material_rid.is_valid():
		RenderingServer.canvas_item_set_material(bullet.visual_rid, _glow_material_rid)
	
	# Apply Color
	RenderingServer.canvas_item_set_modulate(bullet.visual_rid, BULLET_COLOR)
	
	# Apply Transform with Scale
	var xform = Transform2D(vel.angle(), pos)
	xform.x *= BULLET_SCALE.x
	xform.y *= BULLET_SCALE.y
	RenderingServer.canvas_item_set_transform(bullet.visual_rid, xform)
	
	RenderingServer.canvas_item_set_visible(bullet.visual_rid, true)
	
	_bullets.append(bullet)

func _physics_process(delta: float) -> void:
	if _bullets.is_empty():
		return
		
	var space_state = get_world_2d().direct_space_state
	var i = _bullets.size() - 1
	
	while i >= 0:
		var b = _bullets[i]
		
		# Move
		var move_vec = b.velocity * delta
		var next_pos = b.position + move_vec
		
		# Raycast for collision
		# Exclude owner from raycast
		var exclude = []
		if is_instance_valid(b.owner):
			exclude.append(b.owner.get_rid())
			
		var query = PhysicsRayQueryParameters2D.create(b.position, next_pos, MASK_COLLISION, exclude)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		
		var result = space_state.intersect_ray(query)
		var destroyed = false
		
		if result:
			# Hit something
			b.position = result.position
			if _handle_collision(b, result.collider):
				destroyed = true
		else:
			b.position = next_pos
			
		if not destroyed:
			# Lifecycle checks
			b.lifetime += delta
			if b.lifetime > 5.0 or (b.max_range > 0 and b.position.distance_to(b.start_position) > b.max_range):
				destroyed = true
			
			# Check boulder collision manual check (if strictly needed, but let's assume world mask handles it if boulders have bodies)
			# Bullet.gd did a manual check because it was in EffectsLayer. We are in World (hopefully). 
			# BulletServer should be added to World scene mostly.
			# But if Boulders are Area2D, raycast handles them if mask is correct.
		
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
		
	# Handle Shield (Shielder Enemy)
	# Check for Area2D parent or direct method
	var shield_root = null
	if collider is Area2D:
		shield_root = collider.get_parent()
	elif collider.has_method("take_shield_damage"):
		shield_root = collider
		
	if shield_root and shield_root.has_method("take_shield_damage"):
		shield_root.take_shield_damage(b.damage)
		return true # Destroy bullet on shield hit
	
	# Determine if protected by shield
	if collider.has_method("is_protected_by_shield") and collider.is_protected_by_shield():
		# Absorbed by shield elsewhere, just destroy bullet
		return true

	# Check for damageable
	if not collider.has_method("take_damage"):
		# Wall/Obstacle -> Destroy
		if collider is TileMap or collider is StaticBody2D:
			return true
		return false # Pass through non-blocking
		
	# Apply damage
	var crit_chance = 0.15 # Base
	# Fetch player crit (simplified: assumed singleton or group)
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_crit_chance"):
		crit_chance += player.get_crit_chance()
	
	var is_crit = randf() < crit_chance
	var final_damage = b.damage * 2 if is_crit else b.damage
	
	var hit_dir = b.velocity.normalized()
	# Apply
	collider.take_damage(final_damage, is_crit, hit_dir, false, "player")
	
	b.hit_uids[id] = true
	
	# Return true to destroy (SMG bullets don't pierce by default)
	return true

func _despawn_bullet(b: SimpleBullet) -> void:
	b.active = false
	RenderingServer.canvas_item_set_visible(b.visual_rid, false)
	_pool.append(b)

func get_active_count() -> int:
	return _bullets.size()
