extends Area2D

@onready var sprite = $Sprite2D

var velocity = Vector2.ZERO
var lifetime: float = 0.0
var owner_node: Node = null
var start_position: Vector2 = Vector2.ZERO
var _start_position_set: bool = false  # Track if start position has been captured

# If true, bullet will pierce every damageable target it hits (doesn't queue_free on hit)
@export var pierce_all: bool = false
# Optional limited pierce count; 0 = unlimited when pierce_all is true
@export var pierce_count: int = 0

# Max range - bullet despawns after traveling this distance (0 = no limit, use lifetime)
@export var max_range: float = 0.0

# Critical hit settings
const BASE_CRIT_CHANCE := 0.15  # 15% base chance to crit
const CRIT_MULTIPLIER := 2.0  # 2x damage on crit
var base_damage := 3

var _hit_nodes: Array = []

# Default max ranges by weapon type
const RANGE_SNIPER := 0.0  # Unlimited (despawns off-screen via lifetime)
const RANGE_ASSAULT := 1100.0  # Slightly past camera edge
const RANGE_SMG := 750.0  # 2/3 screen width
const RANGE_SHOTGUN := 750.0  # 2/3 screen width
const RANGE_MINIGUN := 1100.0  # Like assault rifle

# Performance: disable dynamic lights on bullets (they're expensive!)
const ENABLE_BULLET_LIGHTS := false

func _ready():
	# VISUAL DEBUG: Turn BLUE if script loads successfully
	if $Sprite2D: $Sprite2D.modulate = Color(0, 0, 10, 1)
	
	print("[BULLET_DEBUG] Spawned at ", global_position, " Layer: ", collision_layer, " Mask: ", collision_mask)
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
	collision_mask = 7
	collision_layer = 0 # Bullets shouldn't be hit by things?
	
	# Dynamic lights are VERY expensive with many bullets - disabled by default
	if ENABLE_BULLET_LIGHTS:
		var light = PointLight2D.new()
		light.name = "BulletLight"
		light.color = Color(1.0, 0.95, 0.7)  # Warm bullet glow
		light.energy = 0.4
		light.texture = _create_light_texture()
		light.texture_scale = 0.15
		light.shadow_enabled = false
		add_child(light)

func _auto_detect_range() -> void:
	# Detect bullet type from scene/node name
	var bullet_name := name.to_lower()
	
	if "sniper" in bullet_name or "snow" in bullet_name:
		max_range = RANGE_SNIPER  # Sniper has no limit
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
		# Hit something!
		global_position = result.position
		_on_body_entered(result.collider)
		# _on_body_entered might free us, so return
		return
	else:
		global_position = next_pos
	
	lifetime += delta
	if lifetime > 5.0:
		queue_free()
		return
	
	# Check max range
	if max_range > 0.0:
		var traveled := global_position.distance_to(start_position)
		if traveled >= max_range:
			queue_free()
			return
	
	# Check boulder collision (reparenting to EffectsLayer breaks Area2D overlap)
	if _check_boulder_collision():
		queue_free()
		return

func _check_boulder_collision() -> bool:
	"""Manual boulder collision check since bullets are in EffectsLayer (different scene tree branch)."""
	var boulders := get_tree().get_nodes_in_group("boulders")
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_to(boulder_pos) < boulder_radius:
			return true
	return false



func _on_body_entered(body):
	# Handle both Body (CharacterBody2D) and Area (HitboxComponent) collisions
	var target = body
	
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

	# Only apply damage to targets that can take damage
	if not body.has_method("take_damage"):
		return

	# Prevent repeated hits on the same target
	if _hit_nodes.has(body):
		return

	# Roll for critical hit - base chance + shop bonus (capped at 100%)
	var crit_chance := BASE_CRIT_CHANCE
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_crit_chance"):
		crit_chance += player.get_crit_chance()
	crit_chance = minf(crit_chance, 1.0)  # Cap at 100%
	var is_crit := randf() < crit_chance
	var damage := base_damage
	if is_crit:
		damage = int(base_damage * CRIT_MULTIPLIER)
	
	# Pass hit direction (bullet's travel direction) to enemy for knockback visual
	var hit_direction = velocity.normalized()
	
	# Determine killer source based on owner type
	var killer_source := "player"
	if is_instance_valid(owner_node) and (owner_node is NayutaClone or owner_node is SummonedAlly):
		killer_source = "summon"
	
	body.take_damage(damage, is_crit, hit_direction, false, killer_source)
	_hit_nodes.append(body)

	# If we are not piercing, or we have a limited pierce_count that reached 0, destroy
	if not pierce_all:
		queue_free()
		return
	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			queue_free()
