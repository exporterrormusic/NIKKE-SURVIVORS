extends Area2D
class_name BaseProjectile
## Base class for all projectile types (bullets, rockets, missiles, etc.)
##
## Provides common functionality:
## - Owner tracking and friendly fire prevention
## - Killer source determination for burst/shield charging
## - Common collision filtering (charmed allies, other projectiles)
## - Lifetime management
##
## Subclasses should override:
## - _on_projectile_ready() - Custom initialization
## - _on_projectile_process(delta) - Per-frame updates
## - _on_projectile_physics(delta) - Physics updates
## - _on_hit_target(body) - When hitting a valid target
## - _get_base_damage() - Return damage amount

## Node that fired this projectile (for friendly fire prevention)
var owner_node: Node = null

## Override killer_source if set (for summon-spawned turrets)
var killer_source_override: String = ""

## Projectile velocity
var velocity: Vector2 = Vector2.ZERO

## Time projectile has been alive
var lifetime: float = 0.0

## Maximum lifetime before auto-despawn (0 = no limit)
@export var max_lifetime: float = 5.0

## Tracks nodes already hit (for pierce projectiles)
var _hit_nodes: Array = []

## Whether this projectile has already impacted (prevents multiple explosions)
var _has_impacted: bool = false


func _ready() -> void:
	add_to_group("projectiles")
	connect("body_entered", _on_body_entered)
	_on_projectile_ready()


func _process(delta: float) -> void:
	_on_projectile_process(delta)


func _physics_process(delta: float) -> void:
	lifetime += delta
	
	# Auto-despawn after max lifetime
	if max_lifetime > 0.0 and lifetime > max_lifetime:
		_despawn()
		return
	
	_on_projectile_physics(delta)


## Override in subclass for custom initialization
func _on_projectile_ready() -> void:
	pass


## Override in subclass for per-frame updates (visuals, particles, etc.)
func _on_projectile_process(_delta: float) -> void:
	pass


## Override in subclass for physics updates (movement, homing, etc.)
func _on_projectile_physics(_delta: float) -> void:
	# Default: move by velocity
	global_position += velocity * _delta


## Override in subclass: return base damage amount
func _get_base_damage() -> int:
	return 1


## Override in subclass: handle hitting a valid target
func _on_hit_target(_body: Node) -> void:
	pass


## Determine killer source based on owner type
func get_killer_source() -> String:
	if killer_source_override != "":
		return killer_source_override
	
	if is_instance_valid(owner_node):
		# Check if owner is a summon/clone type
		if owner_node.get_class() == "NayutaClone":
			return "summon"
		if owner_node.is_in_group("summoned_allies"):
			return "summon"
		# Check class names for known summon types
		var script = owner_node.get_script()
		if script:
			var script_path: String = script.resource_path
			if "NayutaClone" in script_path or "SummonedAlly" in script_path:
				return "summon"
	
	return "player"


## Check if a body should be ignored (friendly fire, already hit, etc.)
func should_ignore_target(body: Node) -> bool:
	# Ignore owner
	if body == owner_node:
		return true
	
	# Ignore player if owner is player-controlled
	if body.name == "Player" and owner_node != null:
		return true
	
	# Ignore charmed enemies (they're friendly)
	if body.is_in_group("charmed_allies"):
		return true
	
	# Ignore other projectiles
	if body.is_in_group("projectiles"):
		return true
	
	# Ignore summoned allies
	if body.is_in_group("summoned_allies"):
		return true
	
	if body.is_in_group("player_allies"):
		return true
	
	# Check if already hit (for pierce projectiles)
	if _hit_nodes.has(body):
		return true
	
	return false


## Apply damage to a target using the Damageable interface
func apply_damage_to(body: Node, is_crit: bool = false) -> void:
	if not body.has_method("take_damage"):
		return
	
	var damage := _get_base_damage()
	if is_crit:
		damage *= 2
	
	var hit_direction := velocity.normalized()
	var killer_source := get_killer_source()
	
	# Use the full take_damage signature
	body.take_damage(damage, is_crit, hit_direction, false, killer_source)
	
	# Track this node as hit
	_hit_nodes.append(body)


## Create a DamageInfo for this projectile
func create_damage_info(is_crit: bool = false) -> DamageInfo:
	var info := DamageInfo.from_projectile(
		_get_base_damage(),
		velocity,
		owner_node
	)
	info.is_crit = is_crit
	if killer_source_override != "":
		info.killer_source = killer_source_override
	return info


## Called when any body enters the projectile's collision area
func _on_body_entered(body: Node) -> void:
	if should_ignore_target(body):
		return
	
	# Check if body can take damage
	if not body.has_method("take_damage"):
		return
	
	_on_hit_target(body)


## Clean despawn (for timeout, off-screen, etc.)
func _despawn() -> void:
	queue_free()


## Check if projectile is out of bounds (useful for physics process)
func is_out_of_bounds(margin: float = 100.0) -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	
	var rect := viewport.get_visible_rect()
	return (
		global_position.x < rect.position.x - margin or
		global_position.x > rect.end.x + margin or
		global_position.y < rect.position.y - margin or
		global_position.y > rect.end.y + margin
	)


## Mark this projectile as having impacted (prevents multiple explosions)
func mark_impacted() -> bool:
	if _has_impacted:
		return false
	_has_impacted = true
	return true
