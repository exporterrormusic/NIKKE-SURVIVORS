extends Resource
class_name EnemyStats
## Enemy statistics resource.
##
## Defines stats for an enemy type. Used with resource-based enemy system
## for easier balancing without code changes.
##
## Usage:
##   var stats = EnemyStats.new()
##   stats.enemy_name = "Tank"
##   stats.base_hp = 500
##   stats.tier = "elite"

## Display name of the enemy type
@export var enemy_name: String = ""

## Base HP (will be scaled by wave)
@export var base_hp: int = 100

## Damage per hit
@export var damage: int = 10

## Movement speed
@export var speed: float = 150.0

## Enemy tier (affects scoring, drops, etc.)
@export_enum("basic", "tank", "elite", "boss", "super_boss") var tier: String = "basic"

## XP orbs dropped on death
@export var xp_orb_count: int = 5

##Score value when killed
@export var score_value: int = 100

## Pristine cores dropped (bosses only)
@export var pristine_core_drop: int = 0

## Whether this enemy can shoot
@export var can_shoot: bool = false

## Shoot cooldown (if can_shoot)
@export var shoot_cooldown: float = 2.0
