extends Area2D
class_name SnowWhiteBullet
## Snow White's piercing bullet that can optionally leave a burning trail
## when the "Best Girl" shop upgrade is purchased.
## Should be instantiated from SnowWhiteBullet.tscn for proper sprite display.

const SnowWhiteBurnTrailScript = preload("res://scripts/characters/effects/SnowWhiteBurnTrail.gd")

@onready var sprite = $Sprite2D

var velocity := Vector2.ZERO
var lifetime: float = 0.0
var owner_node: Node = null
var start_position: Vector2 = Vector2.ZERO
var _start_position_set: bool = false

@export var pierce_all: bool = true
@export var pierce_count: int = 0
@export var max_range: float = 0.0

# Trail settings - creates ONE trail that follows bullet path
var leave_burn_trail: bool = false
var _trail_node: Node2D = null  # Single trail that tracks all positions
var _trail_record_interval: float = 0.03  # Record position every 30ms (was 15ms)
var _trail_timer: float = 0.0

# Critical hit settings
const BASE_CRIT_CHANCE := 0.15
const CRIT_MULTIPLIER := 2.0
var base_damage := 3

var _hit_nodes: Array = []

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	
	# Apply icy blue tint to sprite if it exists
	if sprite:
		sprite.modulate = Color(0.6, 0.9, 1.0, 1.0)
	
	# High z-index for visibility
	z_index = 60

func _physics_process(delta: float) -> void:
	# Capture start position on first frame
	if not _start_position_set:
		start_position = global_position
		_start_position_set = true
		
		# Create the single trail node if burn trail is enabled
		if leave_burn_trail:
			_create_trail_node()
	
	global_position += velocity * delta
	
	# Record trail positions for burn effect
	if leave_burn_trail and _trail_node:
		_trail_timer += delta
		if _trail_timer >= _trail_record_interval:
			_trail_timer = 0.0
			_trail_node.add_point(global_position)
	
	lifetime += delta
	if lifetime > 5.0:
		_finalize_trail()
		queue_free()
		return
	
	# Check max range
	if max_range > 0.0:
		var traveled := global_position.distance_to(start_position)
		if traveled >= max_range:
			_finalize_trail()
			queue_free()
			return

func _create_trail_node() -> void:
	_trail_node = SnowWhiteBurnTrailScript.new()
	
	var parent = get_parent()
	if parent:
		parent.add_child(_trail_node)
		_trail_node.add_point(global_position)

func _finalize_trail() -> void:
	# Add final position and tell trail it's complete
	if _trail_node and is_instance_valid(_trail_node):
		_trail_node.add_point(global_position)
		_trail_node.finalize()

func _on_body_entered(body: Node2D) -> void:
	if body == owner_node:
		return
	if owner_node and body.name == "Player":
		return
	if body.is_in_group("charmed_allies"):
		return
	if not body.has_method("take_damage"):
		return
	if _hit_nodes.has(body):
		return
	
	# Roll for critical hit
	var crit_chance := BASE_CRIT_CHANCE
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_crit_chance"):
		crit_chance += player.get_crit_chance()
	crit_chance = minf(crit_chance, 1.0)
	var is_crit := randf() < crit_chance
	var damage := base_damage
	if is_crit:
		damage = int(base_damage * CRIT_MULTIPLIER)
	
	var hit_direction = velocity.normalized()
	
	# Determine killer source for burst tracking
	var killer_source := "player"
	if is_instance_valid(owner_node) and (owner_node is NayutaClone or owner_node is SummonedAlly):
		killer_source = "summon"
	
	# Pass killer_source directly to take_damage
	body.take_damage(damage, is_crit, hit_direction, false, killer_source)
	_hit_nodes.append(body)
	
	if not pierce_all:
		_finalize_trail()
		queue_free()
		return
	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			_finalize_trail()
			queue_free()
