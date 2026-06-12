extends Area2D

# Cached ShopMenu reference to avoid load() in hot paths
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

@onready var sprite = $Sprite2D

var velocity = Vector2.ZERO
var lifetime: float = 0.0
var owner_node: Node = null
var start_position: Vector2 = Vector2.ZERO
var _start_position_set: bool = false # Track if start position has been captured

# Object pooling support
var pool_id: String = "" # Empty = not pooled, otherwise identifies the pool

# If true, bullet will pierce every damageable target it hits (doesn't queue_free on hit)
@export var pierce_all: bool = false
# Optional limited pierce count; 0 = unlimited when pierce_all is true
@export var pierce_count: int = 0

# Max range - bullet despawns after traveling this distance (0 = no limit, use lifetime)
@export var max_range: float = 0.0

# Critical hit settings
const BASE_CRIT_CHANCE := 0.15 # 15% base chance to crit
const CRIT_MULTIPLIER := 2.0 # 2x damage on crit
var base_damage := 3

# Weapon type source for Goddess Fall XP/Burst tracking
var weapon_type_source: String = ""

# For ShielderShield collision detection - uses weapon_type_source or defaults to "smg"
var killer_source: String:
	get:
		return weapon_type_source if weapon_type_source != "" else "smg"

var _hit_nodes: Array = []

# Default max ranges by weapon type
const RANGE_SNIPER := 0.0 # Unlimited (despawns off-screen via lifetime)
const RANGE_ASSAULT := 1100.0 # Slightly past camera edge
const RANGE_SMG := 750.0 # 2/3 screen width
const RANGE_SHOTGUN := 750.0 # 2/3 screen width
const RANGE_MINIGUN := 1100.0 # Like assault rifle

# Performance: disable dynamic lights on bullets (they're expensive!)
const ENABLE_BULLET_LIGHTS := false

## Reset bullet for object pooling
func reset() -> void:
	velocity = Vector2.ZERO
	lifetime = 0.0
	owner_node = null
	start_position = Vector2.ZERO
	_start_position_set = false
	pierce_all = false
	pierce_count = 0
	max_range = 0.0
	base_damage = 3
	_hit_nodes.clear()
	visible = true
	modulate.a = 1.0
	monitoring = true
	monitorable = true
	set_process(true)
	set_physics_process(true)

## Despawn bullet - returns to pool if pooled, otherwise queue_free
func _despawn() -> void:
	if has_meta("pool_type"):
		ProjectileCache.return_to_pool(self)
		return
	queue_free()

# Frame counter for throttled checks
var _frame_counter: int = 0

func _ready():
	# VISUAL DEBUG: Turn BLUE if script loads successfully
	if $Sprite2D: $Sprite2D.modulate = Color(0, 0, 10, 1)
	
	# DEBUG PRINT REMOVED FOR PERFORMANCE
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("area_entered", Callable(self, "_on_body_entered")) # Handle HitboxComponent (Area2D) hits
	# Don't set start_position here - bullet isn't positioned yet
	# It will be set on first physics frame
	
	# Auto-detect max range based on bullet type if not already set
	if max_range == 0.0:
		_auto_detect_range()
	
	# Use CACHED shader material for performance (no new Shader.new() per bullet!)
	$Sprite2D.material = ShaderCache.get_bullet_glow_material()

	# Reparent to EffectsLayer so bullets aren't darkened by CanvasModulate
	# Uses centralized VisualLayerHelper utility to avoid code duplication
	# DEBUG: DISABLED TO RULE OUT CANVAS LAYER PHYSICS ISSUES
	# VisualLayerHelper.reparent_to_effects_layer(self)
	
	# DEBUG: FORCE COLLISION MASK
	# Layer 1(1) = World, Layer 2(2) = Player/Enemies(Old), Layer 3(4) = Hitbox/Enemies
	# Set mask to 1 | 2 | 4 = 7
	collision_mask = 15
	# Set layer to 4 (Enemy Projectiles) so Scarlet can slash them
	collision_layer = 4
	add_to_group("enemy_projectiles")
	# Debug print removed for performance - was causing lag with many bullets
	
	# Dynamic lights are VERY expensive with many bullets - disabled by default
	if ENABLE_BULLET_LIGHTS:
		var light = PointLight2D.new()
		light.name = "BulletLight"
		light.color = Color(1.0, 0.95, 0.7) # Warm bullet glow
		light.energy = 0.4
		light.texture = _create_light_texture()
		light.texture_scale = 0.15
		light.shadow_enabled = false
		add_child(light)

func _auto_detect_range() -> void:
	# Detect bullet type from scene/node name
	var bullet_name := name.to_lower()
	
	if "sniper" in bullet_name or "snow" in bullet_name:
		max_range = RANGE_SNIPER # Sniper has no limit
	elif "smg" in bullet_name:
		max_range = RANGE_SMG
	elif "shotgun" in bullet_name or "pellet" in bullet_name or "kilo" in bullet_name:
		max_range = RANGE_SHOTGUN
	elif "assault" in bullet_name or "ar" in bullet_name:
		max_range = RANGE_ASSAULT
	elif "minigun" in bullet_name or "marian" in bullet_name or "crown" in bullet_name:
		max_range = RANGE_MINIGUN
	else:
		# Default: assault rifle range for unknown bullets
		max_range = RANGE_ASSAULT

func _create_light_texture() -> Texture2D:
	# Use cached texture for performance
	return TextureCache.get_light_texture_64()

func _physics_process(delta):
	# Apply Global Enemy Time Scale (Bullet Time) - ONLY for non-player projectiles
	var time_scale = 1.0
	var game_manager = get_node_or_null("/root/GameManager")
	if not (owner_node and owner_node.is_in_group("player")):
		time_scale = game_manager.enemy_time_scale if game_manager else 1.0
	delta *= time_scale

	# Capture start position on first frame (after bullet has been positioned)
	if not _start_position_set:
		start_position = global_position
		_start_position_set = true
	
	var frame_movement = velocity * delta
	var current_pos = global_position
	var next_pos = current_pos + frame_movement
	
	# RAYCAST CHECK to prevent tunneling (high speed/low fps misses)
	var space_state = get_world_2d().direct_space_state
	# Mask 7 = World(1) + Enemy(2) + Hitbox(4)
	var query = PhysicsRayQueryParameters2D.create(current_pos, next_pos, 7, [self])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		# Check if this is a boulder we should phase through BEFORE setting position
		var collider = result.collider
		
		# PHASE THROUGH enemy projectiles - don't stop player bullets on other bullets
		if collider.is_in_group("enemy_projectiles") and not collider.has_method("take_damage"):
			global_position = next_pos
		elif collider is StaticBody2D and collider.is_in_group("boulders"):
			var player_ref = get_tree().get_first_node_in_group("player")
			if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and player_ref and player_ref.has_method("is_playing_character") and player_ref.is_playing_character("wells"):
				# Phase through boulder - continue to next_pos, don't stop at collision point
				global_position = next_pos
				# Skip the rest of the collision handling
			else:
				# Trigger bump shake on SwayableBush if this is a player bullet
				if collider.has_method("trigger_bump") and owner_node and owner_node.is_in_group("player"):
					collider.trigger_bump(0.7, true)
				# Not phasing - normal collision handling
				global_position = result.position
				_on_body_entered(collider)
				return
		else:
			# Not a boulder - normal collision handling
			global_position = result.position
			_on_body_entered(collider)
			return
	else:
		global_position = next_pos
	
	lifetime += delta
	if lifetime > 5.0:
		_despawn()
		return
	
	# Check max range
	if max_range > 0.0:
		var traveled := global_position.distance_to(start_position)
		if traveled >= max_range:
			_despawn()
			return
	
	# ADDITIONAL: Area-based enemy collision for more forgiving hitbox
	# Only for assault rifle, sniper, and shotgun - SMG is fine with raycast only
	var bullet_name := name.to_lower()
	var needs_forgiving_hitbox := "assault" in bullet_name or "sniper" in bullet_name or "snow" in bullet_name or "shotgun" in bullet_name or "pellet" in bullet_name or "kilo" in bullet_name
	
	if needs_forgiving_hitbox:
		const BULLET_HITBOX_RADIUS := 24.0 # Larger hitbox for forgiveness
		var enemies := TargetCache.get_enemies()
		var radius_sq := BULLET_HITBOX_RADIUS * BULLET_HITBOX_RADIUS
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			if enemy is Node2D:
				var enemy_node: Node2D = enemy as Node2D
				var dist_sq: float = global_position.distance_squared_to(enemy_node.global_position)
				if dist_sq < radius_sq:
					_on_body_entered(enemy)
					return # Bullet should be destroyed or pierced
	
	# Check boulder collision every frame for accuracy
	_frame_counter += 1
	if _check_boulder_collision():
		_despawn()
		return

func _check_boulder_collision() -> bool:
	"""Manual boulder collision check using cached boulder list for performance."""
	# Skip if Chrono-Intangibility upgrade is active AND playing Wells
	var player = get_tree().get_first_node_in_group("player")
	if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and player and player.has_method("is_playing_character") and player.is_playing_character("wells"):
		return false
	
	var boulders := TargetCache.get_boulders()
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_squared_to(boulder_pos) < boulder_radius * boulder_radius:
			# Trigger bump shake on SwayableBush if owner is player
			if boulder.has_method("trigger_bump"):
				if owner_node and owner_node.is_in_group("player"):
					boulder.trigger_bump(0.7, true)
			return true
	return false


func _on_body_entered(body):
	# Handle both Body (CharacterBody2D) and Area (HitboxComponent) collisions
	var _target = body
	
	# VISUAL DEBUG: Turn red on detected collision
	if sprite: sprite.modulate = Color(10, 0, 0, 1)
	
	# Don't damage owner or player if owner is player/turret
	if body == owner_node:
		return
	if owner_node and body.name == "Player":
		return
	
	# Don't damage charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	
	# Ignore other projectiles - phase through enemy bullets
	if body.is_in_group("enemy_projectiles") and not body.has_method("take_damage"):
		return

	# Check for Shield Hit (Area2D child of ShielderShield)
	# Skip shields if Chrono-Intangibility upgrade is active AND playing Wells
	var player = get_tree().get_first_node_in_group("player")
	var has_chrono: bool = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and player and player.has_method("is_playing_character") and player.is_playing_character("wells")
	
	var shield_root = null
	if body is Area2D:
		shield_root = body.get_parent()
	elif body.has_method("take_shield_damage"):
		shield_root = body
		
	if shield_root and shield_root.has_method("take_shield_damage"):
		if has_chrono:
			# Phase through shields - don't damage or stop
			return
		# Shield hit! Destroy bullet.
		shield_root.take_shield_damage(base_damage)
		_despawn()
		return

	# Only apply damage to targets that can take damage
	if not body.has_method("take_damage"):
		# If it's a wall (StaticBody2D or TileMap), destroy the bullet
		if body is TileMap or body is StaticBody2D:
			# Simple and reliable boulder check - if it's in the boulders group, it's a boulder
			var is_boulder = body.is_in_group("boulders")
			
			if is_boulder:
				var player_ref = get_tree().get_first_node_in_group("player")
				if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and player_ref and player_ref.has_method("is_playing_character") and player_ref.is_playing_character("wells"):
					return # Phase through boulder

			_despawn()
		return

	# Prevent repeated hits on the same target
	if _hit_nodes.has(body):
		return
		
	# Check if target is protected by a shield (stop piercing if so)
	var protected = false
	if body.has_method("is_protected_by_shield") and body.is_protected_by_shield():
		protected = true

	# Roll for critical hit - base chance + shop bonus (capped at 100%)
	var crit_chance := BASE_CRIT_CHANCE
	# Player variable reused from earlier in function
	if player and player.has_method("get_crit_chance"):
		crit_chance += player.get_crit_chance()
	crit_chance = minf(crit_chance, 1.0) # Cap at 100%
	var is_crit := randf() < crit_chance
	var damage := base_damage
	if is_crit:
		damage = int(base_damage * CRIT_MULTIPLIER)
	
	# Pass hit direction (bullet's travel direction) to enemy for knockback visual
	var hit_direction = velocity.normalized()
	
	# Determine killer source based on owner type and weapon type
	var killer_source := weapon_type_source if weapon_type_source != "" else "player"
	if is_instance_valid(owner_node) and (owner_node.is_in_group("nayuta_clones") or owner_node.is_in_group("summoned_allies")):
		killer_source = "summon"
	
	body.take_damage(damage, is_crit, hit_direction, false, killer_source)
	_hit_nodes.append(body)
	
	# If protected, the damage was redirected to the shield, but we MUST stop the bullet from piercing
	if protected:
		_despawn()
		return

	# If we are not piercing, or we have a limited pierce_count that reached 0, destroy
	if not pierce_all:
		_despawn()
		return
	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			_despawn()
