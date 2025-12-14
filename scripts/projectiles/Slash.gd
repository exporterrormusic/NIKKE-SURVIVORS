extends Area2D

@onready var visual = $SwordSlashVisual

var _hit_bodies: Array = []
var owner_node: Node = null  # Track who created this slash
var killer_source: String = "sword"  # For ShielderShield collision detection
var killer_source_override: String = ""

# Critical hit settings
const BASE_CRIT_CHANCE := 0.15  # 15% base chance to crit
const CRIT_MULTIPLIER := 2.0  # 2x damage on crit
var base_damage := 2
var override_visual_params: Dictionary = {}

func _ready():
	# Ensure we can hit enemy projectiles (Layer 3 / Value 4)
	collision_mask |= 4
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("area_entered", Callable(self, "_on_area_entered"))
	
	var params = {
		"radius": 260.0,
		"arc_degrees": 90.0,
		"core_color": Color(0.95, 0.85, 1.0, 0.9),
		"edge_color": Color(1.0, 1.0, 1.0, 1.0),
		"glow_color": Color(0.7, 0.5, 0.9, 0.6),
		"fade": 1.0,
		"wipe_progress": 0.0,
		"sparkle_count": 8,
		"sparkle_seed": randi()
	}
	
	# Apply any pre-set overrides (Fixes 1-frame color glitch)
	if not override_visual_params.is_empty():
		params.merge(override_visual_params, true)
		
	visual.update_visual(params)
	
	# Sweep animation - fast swing like Link to the Past
	var tween = create_tween()
	tween.tween_property(visual, "wipe_progress", 1.0, 0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	
	# Brief hold at full extension
	await get_tree().create_timer(0.04).timeout
	
	# Fade out
	var fade_tween = create_tween()
	fade_tween.tween_property(visual, "modulate:a", 0.0, 0.06)
	await fade_tween.finished
	
	queue_free()

var tracking: bool = true

func _process(_delta):
	if tracking:
		var mouse_pos = get_global_mouse_position()
		var direction = (mouse_pos - get_parent().global_position).normalized()
		position = direction * 30
		rotation = direction.angle()

func _on_body_entered(body):
	if body == get_parent():
		return
	if body in _hit_bodies:
		return
	# Don't hit the player (friendly fire)
	if body.is_in_group("player"):
		return
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	if body.has_method("take_damage"):
		# Roll for critical hit - base chance + shop bonus
		var crit_chance := BASE_CRIT_CHANCE
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_crit_chance"):
			crit_chance += player.get_crit_chance()
		crit_chance = minf(crit_chance, 1.0)  # Cap at 100%
		var is_crit := randf() < crit_chance
		var damage := base_damage
		if is_crit:
			damage = int(base_damage * CRIT_MULTIPLIER)
		# Pass hit direction (slash direction) for knockback visual
		var hit_direction = Vector2.from_angle(rotation)
		# Determine killer source based on owner type
		var killer_source := "sword"  # Scarlet weapon type for BurstConfig (5% per hit)
		if killer_source_override != "":
			killer_source = killer_source_override
		elif is_instance_valid(owner_node) and (owner_node is NayutaClone or owner_node is SummonedAlly):
			killer_source = "summon"
			
		var is_burst_attack: bool = "burst" in killer_source.to_lower()
		body.take_damage(damage, is_crit, hit_direction, is_burst_attack, killer_source)
		_hit_bodies.append(body)

func _on_area_entered(area):
	# Scarlet's blade destroys enemy normal projectiles
	if area.is_in_group("enemy_projectiles"):
		print("[Slash] Hit enemy projectile: ", area.name)
		# Exclude rockets and special attacks
		if not area.is_in_group("rockets") and not area.is_in_group("special_attacks"):
			# Destroy the bullet
			area.queue_free()
			
			# Optional: Play a small "clash" sound or effect?
			# For now just destroy as requested.
