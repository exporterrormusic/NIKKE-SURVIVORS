extends Node
class_name PlayerCloneManager
## Manages player clone spawning (Nayuta's Duplicity upgrade).
## Extracted from PlayerCore for separation of concerns.

const NayutaCloneScript = preload("res://scripts/characters/effects/NayutaClone.gd")

## Reference back to PlayerCore
var player: PlayerCore = null

## Whether Nayuta's Duplicity upgrade is active
var has_duplicity_upgrade: bool = false


func _ready() -> void:
	if not player:
		player = get_parent() as PlayerCore


func on_enemy_killed(is_direct_kill: bool) -> void:
	"""Called when an enemy is killed by the player. Chance to spawn a clone."""
	if not has_duplicity_upgrade:
		return
	if not is_direct_kill:
		return
	if randf() >= 0.10:
		return
	
	_spawn_duplicity_clone()


func _spawn_duplicity_clone() -> void:
	"""Spawn a clone at the player's position for Nayuta's Duplicity upgrade."""
	var clone: Node2D = NayutaCloneScript.new()
	
	# CRITICAL: Set collision layers BEFORE adding to scene tree
	clone.collision_layer = 8 # Allies layer (detected by EnemyLaser mask)
	clone.collision_mask = 5 # World (1) + Enemies (4)
	
	# Deferred add to avoid "parent busy" errors during physics callbacks
	player.get_parent().call_deferred("add_child", clone)
	clone.global_position = player.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	
	# Clone stats: 25% player HP with level scaling, 20% damage multiplier
	var hp_level_mult := 1.0 + (player.level - 1) * 0.25
	var clone_hp: int = maxi(1, int((player.max_hp / 4.0) * hp_level_mult))
	var clone_attack: float = 0.2
	
	# Determine weapon type - use Nayuta's weapon pool if available
	var weapon_type: String = "smg"
	var current_controller = player.get_current_controller()
	if current_controller and current_controller.has_method("get_weapon_pool"):
		var weapon_pool: Array = current_controller.get_weapon_pool()
		if weapon_pool.size() > 0:
			weapon_type = weapon_pool[randi() % weapon_pool.size()]
	
	clone.call("initialize", player, weapon_type, clone_hp, clone_attack, false, player.level)
