extends Area2D
class_name SnowWhiteBullet
## Snow White's piercing bullet that can optionally leave a burning trail
## when the "Best Girl" shop upgrade is purchased.
## Should be instantiated from SnowWhiteBullet.tscn for proper sprite display.

const SnowWhiteBurnTrailScript = preload("res://scripts/characters/effects/SnowWhiteBurnTrail.gd")
# Cached ShopMenu reference to avoid load() in hot collision path
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

@onready var sprite = $Sprite2D

var velocity := Vector2.ZERO
var lifetime: float = 0.0
var owner_node: Node = null
var killer_source: String = "sniper" # For ShielderShield and other collision handlers
var killer_source_override: String = "" # For manual override (e.g., summons)
var start_position: Vector2 = Vector2.ZERO
var _start_position_set: bool = false

@export var pierce_all: bool = true
@export var pierce_count: int = 0
@export var max_range: float = 0.0

# Trail settings - creates ONE trail that follows bullet path
var leave_burn_trail: bool = false
var _trail_node: Node2D = null # Single trail that tracks all positions
var _trail_record_interval: float = 0.03 # Record position every 30ms (was 15ms)
var _trail_timer: float = 0.0

# Critical hit settings
const BASE_CRIT_CHANCE := 0.15
const CRIT_MULTIPLIER := 2.0
var base_damage := 3

var _hit_nodes: Array = []
var _original_modulate = Color(0.6, 0.9, 1.0, 1.0)

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	connect("area_entered", _on_area_entered)
	
	# Add to projectiles group for ShielderShield detection
	add_to_group("projectiles")
	
	# Ensure detection of Shields (Layer 1 = World, Layer 16 = Shields)
	# Original mask was 2 (Enemies), so we must add 1 if we want to hit walls/shields on Layer 1
	collision_mask |= 1 | 16
	
	# Apply icy blue tint to sprite if it exists
	if sprite:
		sprite.modulate = _original_modulate
	
	# Connect to environment modulate changes to keep sprite bright
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env and env.has_signal("modulate_changed"):
		env.modulate_changed.connect(_on_modulate_changed)
		_on_modulate_changed(env.current_modulate if "current_modulate" in env else Color.WHITE)
	
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
	_handle_hit(body)

func _on_area_entered(area: Area2D) -> void:
	# Check for Shield (Layer 16)
	# ShielderShield Area is child of the ShielderShield Node
	var shield_root = area.get_parent()
	if shield_root and shield_root.has_method("take_shield_damage"):
		_handle_hit(shield_root, true)

func _handle_hit(target: Node, is_shield: bool = false) -> void:
	if target == owner_node:
		return
	if owner_node and target.name == "Player":
		return
	if target.is_in_group("charmed_allies"):
		return
	
	# Validate target methods
	if is_shield:
		if not target.has_method("take_shield_damage"): return
	else:
		if not target.has_method("take_damage"): return
	
	if _hit_nodes.has(target):
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
	
	if is_shield:
		# Check if Chrono-Intangibility upgrade allows phasing through shields
		var p = get_tree().get_first_node_in_group("player")
		var wells_in_squad = p and p.has_method("is_character_in_squad") and p.is_character_in_squad("wells")
		if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and wells_in_squad:
			# Bullet phases through shield completely - no damage, no stop, continue flying
			# Don't add to _hit_nodes so it can hit the enemy behind
			return
		
		# Determine killer source for burst tracking
		var shield_source := "sniper"
		if killer_source_override != "":
			shield_source = killer_source_override
		target.take_shield_damage(damage, shield_source)
		
		# Force stop on shield hit (Shields block piercing shots)
		_finalize_trail()
		queue_free()
		return
	else:
		# Check if target is protected by a shield (Snow White bullets shouldn't pierce shields via body hits)
		# UNLESS Chrono-Intangibility is active
		var protected = false
		var p = get_tree().get_first_node_in_group("player")
		var wells_in_squad = p and p.has_method("is_character_in_squad") and p.is_character_in_squad("wells")
		var can_pierce_shield = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and wells_in_squad
		
		if not can_pierce_shield:
			if target.has_method("is_protected_by_shield") and target.is_protected_by_shield():
				protected = true
			
		# Determine killer source for burst tracking and Goddess Fall XP
		var effective_source := killer_source # Use class property (defaults to "sniper")
		if killer_source_override != "":
			effective_source = killer_source_override
		elif is_instance_valid(owner_node) and (owner_node is NayutaClone or owner_node is SummonedAlly):
			effective_source = "summon"
			
		var is_burst_attack: bool = "burst" in effective_source.to_lower()
		target.take_damage(damage, is_crit, hit_direction, is_burst_attack, effective_source)
		
		# If protected, the damage was redirected to the shield, stop the bullet
		if protected:
			_finalize_trail()
			queue_free()
			return
	
	_hit_nodes.append(target)
	
	if not pierce_all:
		_finalize_trail()
		queue_free()
		return
	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			_finalize_trail()
			queue_free()

func _on_modulate_changed(color: Color) -> void:
	if sprite:
		var inverse = Color(
			1.0 / max(color.r, 0.001),
			1.0 / max(color.g, 0.001),
			1.0 / max(color.b, 0.001),
			1.0 / max(color.a, 0.001)
		)
		sprite.modulate = inverse * _original_modulate
