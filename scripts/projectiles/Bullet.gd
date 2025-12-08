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
	connect("body_entered", Callable(self, "_on_body_entered"))
	# Don't set start_position here - bullet isn't positioned yet
	# It will be set on first physics frame
	
	# Auto-detect max range based on bullet type if not already set
	if max_range == 0.0:
		_auto_detect_range()
	
	# Use CACHED shader material for performance (no new Shader.new() per bullet!)
	$Sprite2D.material = ShaderCache.get_bullet_glow_material()

	# Ensure this bullet and its drawable children live on the EffectsLayer so
	# they're not darkened by the world's CanvasModulate. Prefer reparenting
	# under the EnvironmentController's `EffectsLayer`, preserving global
	# transform; also set canvas_layer on descendant CanvasItems as a fallback.
	if not Engine.is_editor_hint():
		var tree := get_tree()
		if tree:
			var env = tree.get_first_node_in_group("environment_controller")
			if env:
				var effects = env.get_node_or_null("EffectsLayer")
				if effects and effects is CanvasLayer:
					# Preserve transform for Node2D
					var saved_xform = null
					if self is Node2D:
						saved_xform = (self as Node2D).global_transform
					var old_parent = get_parent()
					if old_parent:
						old_parent.remove_child(self)
					effects.add_child(self)
					if saved_xform != null:
						(self as Node2D).global_transform = saved_xform
					# Walk descendants and set canvas_layer/z so any leftover CanvasItems
					# are certainly on the effects layer.
					var stack = [self]
					while stack.size() > 0:
						var n = stack.pop_back()
						if n is CanvasItem and not (n is Area2D) and not (n is CollisionShape2D) and not (n is CollisionPolygon2D) and not (n is CollisionObject2D):
							var ci := n as CanvasItem
							ci.canvas_layer = 1
							ci.z_as_relative = false
							ci.z_index = 900
						for c in n.get_children():
							if c is Node:
								stack.append(c)
	
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
	
	global_position += velocity * delta
	
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

func _on_body_entered(body):
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
