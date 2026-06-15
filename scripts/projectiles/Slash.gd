extends Area2D

const ScarletBleedScript = preload("res://scripts/characters/effects/ScarletBleed.gd")

@onready var visual = $SwordSlashVisual

var _hit_bodies: Array = []
var owner_node: Node = null  # Track who created this slash
var killer_source: String = "sword"  # For ShielderShield collision detection
var killer_source_override: String = ""

# Critical hit settings
const BASE_CRIT_CHANCE := 0.05  # HoloCure clone: 5% base crit
const CRIT_MULTIPLIER := 1.5  # HoloCure clone: 1.5x on crit
var base_damage := 2
var override_visual_params: Dictionary = {}

# --- Scarlet attack-talent payloads (set by ScarletController before add_child) ---
## Parry: deflect enemy bullets back the way they came instead of destroying them.
var parry_enabled: bool = false
## Retaliation: damage multiplier applied to a deflected bullet (1.0 = Parry only).
var deflect_damage_mult: float = 1.0
## Eviscerate: total bleed damage to apply to each enemy hit (0 = no bleed).
var eviscerate_total: float = 0.0
## I am cheating: each successive melee hit on the same enemy doubles its damage.
var i_am_cheating_enabled: bool = false
## Reference back to ScarletController for parry/evasion callbacks.
var scarlet_controller: Node = null

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
		# I am cheating: each successive melee hit on the SAME enemy doubles its
		# damage (x2, x4, x8, x16), capped at 4 doublings. Tracked per enemy.
		var effective_base := base_damage
		if i_am_cheating_enabled:
			var cheat_hits: int = body.get_meta("scarlet_cheat_hits", 0)
			effective_base = int(round(base_damage * pow(2.0, float(mini(cheat_hits, 4)))))
			body.set_meta("scarlet_cheat_hits", cheat_hits + 1)

		# Roll for critical hit - base chance + shop bonus
		var crit_chance := BASE_CRIT_CHANCE
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_crit_chance"):
			crit_chance += player.get_crit_chance()
		crit_chance = minf(crit_chance, 1.0)  # Cap at 100%
		var is_crit := randf() < crit_chance
		var damage := effective_base
		if is_crit:
			damage = int(effective_base * CRIT_MULTIPLIER)
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

		# Eviscerate: apply/refresh a bleed DoT (+ blood trail) on the target.
		if eviscerate_total > 0.0:
			_apply_eviscerate_bleed(body)

func _apply_eviscerate_bleed(body: Node) -> void:
	if not is_instance_valid(body) or not (body is Node2D):
		return
	var existing = body.get_node_or_null("ScarletBleed")
	if existing and is_instance_valid(existing):
		existing.refresh(eviscerate_total, 5.0)
	else:
		var bleed = ScarletBleedScript.new()
		body.add_child(bleed)
		bleed.setup(body, eviscerate_total, 5.0)

func _on_area_entered(area):
	_handle_projectile(area)


## Each physics frame, sweep EVERYTHING currently overlapping the blade — not
## just the area_entered transition. The slash is short-lived and enemy bullets
## are fast, so relying only on the entry signal misses bullets that are already
## inside the arc when the swing starts. This makes delete/deflect reliable.
func _physics_process(_delta):
	# Burst-spawned slashes disable monitoring; get_overlapping_areas() errors then.
	if not monitoring:
		return
	for area in get_overlapping_areas():
		_handle_projectile(area)


func _handle_projectile(area) -> void:
	# Scarlet's blade interacts with enemy normal projectiles (not rockets/beams).
	if not is_instance_valid(area) or not area.is_in_group("enemy_projectiles"):
		return
	if area.is_in_group("rockets") or area.is_in_group("special_attacks"):
		return

	# Parry: deflect the bullet back the way it came instead of destroying it.
	# Without Parry (or for projectiles that can't be deflected), destroy it.
	if parry_enabled and area.has_method("deflect"):
		# Don't re-deflect a bullet that's already been turned (avoids ping-pong).
		if area.has_meta("from_charmed") and area.get_meta("from_charmed"):
			return
		area.deflect(deflect_damage_mult)
		if is_instance_valid(scarlet_controller) and scarlet_controller.has_method("on_parry_deflect"):
			scarlet_controller.on_parry_deflect()
	else:
		area.queue_free()
