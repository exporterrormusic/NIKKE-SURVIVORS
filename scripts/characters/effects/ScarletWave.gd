extends Area2D

@onready var visual = $SwordSlashVisual
@onready var collision_shape = $CollisionShape2D

var velocity := Vector2.ZERO
var lifetime := 0.0
var owner_node: Node = null

@export var pierce_all: bool = true
@export var pierce_count: int = 0
@export var damage: int = 6
@export var base_damage: int = 6 # Starting damage at spawn
@export var min_damage: int = 1 # Minimum damage at max range
@export var max_distance: float = 800.0 # Distance at which damage is minimum

# Vampiric Slash healing mode
var heal_mode: bool = false # When true, heals owner per hit instead of damaging enemies
var heal_percent: float = 0.0 # Percent of owner's max HP to heal per enemy hit (e.g. 0.05 = 5%)

# In One Strike: enemies killed by the wave explode (set by ScarletController).
var in_one_strike: bool = false
var in_one_strike_radius: float = 180.0
var in_one_strike_damage: int = 0
var in_one_strike_owner: Node = null

var _cached_env: Node = null # environment_controller (for world bounds)
const WORLD_MARGIN := 60.0   # despawn this far inside the border, so teleports stay off the wall

# Critical hit settings
const BASE_CRIT_CHANCE := 0.05 # HoloCure clone: 5% base crit
const CRIT_MULTIPLIER := 1.5 # HoloCure clone: 1.5x on crit

var _hit_nodes: Array = []
var _spawn_position: Vector2 = Vector2.ZERO
var _initial_scale: float = 1.0

func _ready():
	# Ensure monitoring is enabled
	monitoring = true
	monitorable = true
	collision_layer = 4
	collision_mask = 2
	
	# Connect signal
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	
	# Note: _spawn_position will be set in first _physics_process since
	# global_position may not be set yet when _ready runs
	base_damage = damage
	_initial_scale = scale.x
	
	# Ensure collision shape is enabled
	if collision_shape:
		collision_shape.disabled = false
	
	# Assign to effects layer to avoid night darkening
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 0 # Use default relative z-index logic if possible, or inherit

	
	# Configure a wide, less-curved, thin wave
	# - Smaller arc_degrees for flatter curve
	# - Larger radius for wider coverage
	# - High inner_ratio for thin line
	visual.update_visual({
		"radius": 140.0,
		"arc_degrees": 90.0,
		"inner_ratio": 0.88,
		"core_color": Color(0.62, 0.36, 0.95, 0.9),
		"edge_color": Color(0.9, 0.82, 1.0, 1.0),
		"glow_color": Color(0.4, 0.2, 0.7, 0.6),
		"fade": 1.0,
		"wipe_progress": 1.0,
		"sparkle_count": 0, # no cross "+" sparkles - keep it a clean arc
		"sparkle_seed": randi()
	})

func _physics_process(delta):
	# Set spawn position on first frame (after global_position is properly set)
	if _spawn_position == Vector2.ZERO and global_position != Vector2.ZERO:
		_spawn_position = global_position
	
	global_position += velocity * delta
	lifetime += delta

	# Despawn once the wave leaves the playable map, so the "Nothing Personal"
	# teleport can never drop the player outside the world.
	if _is_outside_world():
		queue_free()
		return

	# Check boulder collision (reparenting to EffectsLayer breaks Area2D overlap)
	if _check_boulder_collision():
		queue_free()
		return
	
	# Manual collision check as backup (in case signal doesn't fire)
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body not in _hit_nodes:
			_on_body_entered(body)
	
	# Calculate distance from spawn point
	var distance_traveled := global_position.distance_to(_spawn_position)
	var distance_ratio := clampf(distance_traveled / max_distance, 0.0, 1.0)
	
	# Expand size as it travels (1.0 to 2.0 scale)
	var new_scale := _initial_scale * (1.0 + distance_ratio * 1.0)
	scale = Vector2(new_scale, new_scale)
	
	# Reduce damage as it travels (base_damage down to min_damage)
	damage = int(lerpf(float(base_damage), float(min_damage), distance_ratio))
	
	# Lifespan safety
	if lifetime > 3.5:
		queue_free()

func _is_outside_world() -> bool:
	if _cached_env == null or not is_instance_valid(_cached_env):
		_cached_env = get_tree().get_first_node_in_group("environment_controller")
	if _cached_env == null:
		return false
	var bounds = _cached_env.get("_world_bounds")
	if not (bounds is Rect2) or (bounds as Rect2).size == Vector2.ZERO:
		return false
	return not (bounds as Rect2).grow(-WORLD_MARGIN).has_point(global_position)


func _check_boulder_collision() -> bool:
	"""Manual boulder collision check since waves are in EffectsLayer (different scene tree branch)."""
	# Skip if Chrono-Intangibility upgrade is active AND playing Wells
	var shop = load("res://scripts/ui/ShopMenu.gd")
	var player = get_tree().get_first_node_in_group("player")
	if shop and shop.has_character_upgrade("wells", "chrono_intangibility") and player and player.has_method("is_playing_character") and player.is_playing_character("wells"):
		return false
	
	var boulders := get_tree().get_nodes_in_group("boulders")
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_to(boulder_pos) < boulder_radius:
			return true
	return false


func _on_body_entered(body: Node) -> void:
	if body == owner_node:
		return
	if not body.has_method("take_damage"):
		return
	if _hit_nodes.has(body):
		return
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	
	_hit_nodes.append(body)
	var hit_pos: Vector2 = body.global_position # capture before take_damage may free it

	# Roll for critical hit - base chance + shop bonus (capped at 100%)
	var crit_chance := BASE_CRIT_CHANCE
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_crit_chance"):
		crit_chance += player.get_crit_chance()
	crit_chance = minf(crit_chance, 1.0) # Cap at 100%
	var is_crit := randf() < crit_chance
	var final_damage := damage
	if is_crit:
		final_damage = int(damage * CRIT_MULTIPLIER)
	
	# Determine killer source based on owner type
	var hit_direction := velocity.normalized() if velocity.length() > 0 else Vector2.RIGHT
	var killer_source := "sword" # Scarlet weapon type for BurstConfig (5% per hit)
	if is_instance_valid(owner_node) and (owner_node is NayutaClone or owner_node is SummonedAlly):
		killer_source = "summon"
	
	# Apply damage to enemy
	body.take_damage(final_damage, is_crit, hit_direction, false, killer_source)
	
	# Vampiric Slash: also heal owner per enemy hit
	if heal_mode and owner_node and owner_node.has_method("heal"):
		var owner_max_hp := 10 # Default fallback
		if "max_hp" in owner_node:
			owner_max_hp = owner_node.max_hp
		# Use ceili to ensure at least 1 HP healed per hit
		var heal_amount := maxi(1, ceili(owner_max_hp * heal_percent))
		owner_node.heal(heal_amount)

	# In One Strike: if this hit killed the enemy, detonate at its position.
	if in_one_strike and _enemy_is_dead(body):
		_spawn_in_one_strike(hit_pos)

	# Piercing behavior
	if not pierce_all:
		queue_free()
		return
	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			queue_free()


func _enemy_is_dead(body: Node) -> bool:
	if not is_instance_valid(body):
		return true
	if body.is_in_group("dying"):
		return true
	if "hp" in body and body.hp <= 0:
		return true
	return false


## Spawn a turret-Detonation-sized blast (matches Snow White) for the skill's damage.
func _spawn_in_one_strike(pos: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return

	var explosion = ProjectileCache.create_explosion()
	if explosion.has_method("initialize"):
		explosion.initialize(in_one_strike_damage, in_one_strike_radius)
	explosion.owner_node = in_one_strike_owner
	explosion.killer_source_override = "scarlet_in_one_strike"
	if explosion.has_node("Sprite2D"):
		explosion.get_node("Sprite2D").visible = false
	parent.add_child(explosion)
	explosion.global_position = pos

	var visual = ProjectileCache.create_explosion_effect()
	if visual:
		if "radius" in visual:
			visual.radius = in_one_strike_radius
		if visual.has_method("apply_scarlet_tint"):
			visual.apply_scarlet_tint()
		parent.add_child(visual)
		visual.global_position = pos
