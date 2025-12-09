extends RefCounted
class_name Damageable
## Interface documentation for damageable entities.
##
## This is NOT a base class - it documents the expected interface that all
## damageable entities (Player, Enemy, SummonedAlly, NayutaClone, etc.) should follow.
##
## GDScript uses duck-typing, so entities don't need to explicitly extend this.
## Instead, they just need to implement the expected methods.
##
## Required Methods:
##   func take_damage(dmg: int, is_crit: bool = false, direction: Vector2 = Vector2.ZERO, 
##                    from_burst: bool = false, killer_source: String = "player") -> void
##
## Optional Methods:
##   func take_damage_info(info: DamageInfo) -> void  # Preferred new interface
##   func heal(amount: int) -> void
##   func is_invincible() -> bool
##   func get_current_hp() -> int
##   func get_max_hp() -> int
##
## Example Implementation:
## ```gdscript
## extends CharacterBody2D
## 
## var hp: int = 100
## var max_hp: int = 100
## 
## func take_damage(dmg: int, is_crit: bool = false, direction: Vector2 = Vector2.ZERO,
##                  from_burst: bool = false, killer_source: String = "player") -> void:
##     hp -= dmg
##     if hp <= 0:
##         die()
## 
## # Alternative: Use DamageInfo for cleaner interface
## func take_damage_info(info: DamageInfo) -> void:
##     hp -= info.get_final_damage()
##     if hp <= 0:
##         die()
## ```
##
## Checking if a node is damageable:
## ```gdscript
## if body.has_method("take_damage"):
##     body.take_damage(damage, is_crit, direction)
## ```

## Utility function to check if a node implements the Damageable interface
static func is_damageable(node: Node) -> bool:
	return node != null and node.has_method("take_damage")


## Utility function to safely apply damage to any damageable node
## Returns true if damage was applied, false otherwise
static func apply_damage(node: Node, info: DamageInfo) -> bool:
	if node == null:
		return false
	
	# Prefer the new take_damage_info method if available
	if node.has_method("take_damage_info"):
		node.take_damage_info(info)
		return true
	
	# Fall back to legacy take_damage signature
	if node.has_method("take_damage"):
		node.take_damage(
			info.get_final_damage(),
			info.is_crit,
			info.direction,
			info.from_burst,
			info.killer_source
		)
		return true
	
	return false


## Utility function to safely heal any healable node
static func apply_heal(node: Node, amount: int) -> bool:
	if node == null:
		return false
	
	if node.has_method("heal"):
		node.heal(amount)
		return true
	
	return false
