extends Node2D
class_name ScarletTeleportStrike
## The AOE strike from Scarlet's "Nothing Personal, Kid" teleport. It damages
## every enemy in radius, stuns the SURVIVORS (Surprise), and spawns a big purple
## blast at the teleport landing so it's unmistakable. Does NOT heal (separate
## from Vampiric Slash).

var damage: int = 0
var radius: float = 200.0
var stun_duration: float = 0.0
var owner_node: Node = null

const VISUAL_RADIUS_MULT := 1.5 # explosion visual is bigger than the damage area


func _ready() -> void:
	# Let global_position settle (set by the controller after add_child) first.
	call_deferred("_strike")


func _strike() -> void:
	# Damage + Surprise stun.
	for enemy in TargetCache.get_enemies():
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		if enemy.is_in_group("charmed_allies"):
			continue
		if enemy.global_position.distance_to(global_position) > radius:
			continue
		if not enemy.has_method("take_damage"):
			continue
		var dir: Vector2 = (enemy.global_position - global_position).normalized()
		enemy.take_damage(damage, false, dir, false, "sword")
		# Surprise: stun the survivors (enemies the AOE didn't kill).
		if stun_duration > 0.0 and not _enemy_dead(enemy) and enemy.has_method("apply_stun"):
			enemy.apply_stun(stun_duration)

	_spawn_blast()
	queue_free()


func _enemy_dead(enemy) -> bool:
	if not is_instance_valid(enemy):
		return true
	if enemy.is_in_group("dying"):
		return true
	if "hp" in enemy and enemy.hp <= 0:
		return true
	return false


## Big purple blast (reusing the shared explosion visual) at the landing point.
func _spawn_blast() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var visual = ProjectileCache.create_explosion_effect()
	if visual == null:
		return
	if "radius" in visual:
		visual.radius = radius * VISUAL_RADIUS_MULT
	if visual.has_method("apply_scarlet_tint"):
		visual.apply_scarlet_tint()
	parent.add_child(visual)
	visual.global_position = global_position
