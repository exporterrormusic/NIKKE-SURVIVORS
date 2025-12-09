extends RefCounted
class_name DamageInfo
## Data class containing all information about a damage event.
## Provides a consistent interface for damage across all damageable entities.
##
## Usage:
##   var info := DamageInfo.new()
##   info.amount = 50
##   info.is_crit = true
##   info.direction = (target.global_position - attacker.global_position).normalized()
##   target.take_damage_info(info)

## The amount of damage to deal (before any modifiers)
var amount: int = 0

## Whether this damage is a critical hit (typically 2x damage)
var is_crit: bool = false

## Direction the damage came from (used for knockback visuals)
var direction: Vector2 = Vector2.ZERO

## Whether this damage is from a burst ability (affects burst gauge charging)
var from_burst: bool = false

## Source of the damage for tracking kills
## Valid values: "player", "projectile", "cecil_drone", "summon", "charmed_enemy", "unknown"
var killer_source: String = "player"

## Optional: The node that dealt the damage
var source_node: Node = null

## Optional: Additional damage multiplier (applied after base damage)
var damage_multiplier: float = 1.0


## Create a DamageInfo with just an amount (convenience constructor)
static func create(damage_amount: int) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = damage_amount
	return info


## Create a DamageInfo with full parameters (mirrors current take_damage signatures)
static func create_full(
	damage_amount: int,
	crit: bool = false,
	hit_direction: Vector2 = Vector2.ZERO,
	burst: bool = false,
	source: String = "player"
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = damage_amount
	info.is_crit = crit
	info.direction = hit_direction
	info.from_burst = burst
	info.killer_source = source
	return info


## Create a DamageInfo from a projectile hitting a target
static func from_projectile(
	damage_amount: int,
	projectile_velocity: Vector2,
	owner_node: Node = null
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = damage_amount
	info.direction = projectile_velocity.normalized()
	info.source_node = owner_node
	
	# Determine killer source based on owner type
	if is_instance_valid(owner_node):
		if owner_node.get_class() == "NayutaClone" or owner_node.is_in_group("summoned_allies"):
			info.killer_source = "summon"
		else:
			info.killer_source = "projectile"
	else:
		info.killer_source = "projectile"
	
	return info


## Get the final damage amount after applying multipliers
func get_final_damage() -> int:
	var final := int(amount * damage_multiplier)
	if is_crit:
		final *= 2
	return maxi(1, final)


## Returns a string representation for debugging
func _to_string() -> String:
	return "DamageInfo(amount=%d, crit=%s, dir=%s, burst=%s, source=%s)" % [
		amount, is_crit, direction, from_burst, killer_source
	]
