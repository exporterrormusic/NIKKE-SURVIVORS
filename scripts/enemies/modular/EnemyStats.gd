extends Resource
class_name ModularEnemyStats

@export var max_hp: int = 10
@export var move_speed: float = 150.0
@export var collision_damage: int = 1
@export var xp_value: int = 5
@export var tier: String = "normal" # normal, elite, boss
@export var behavior_type: String = "chase" # chase, swarm, ranged
