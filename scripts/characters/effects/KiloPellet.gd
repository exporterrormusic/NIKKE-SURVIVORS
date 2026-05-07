extends Area2D
class_name KiloPellet

## Kilo's shotgun pellet - Rewritten for reliability.
## Handles collision (forced detection) and visual effects.

const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

var velocity := Vector2.ZERO
var lifetime := 0.0
var owner_node: Node = null
var start_position := Vector2.ZERO
var _start_position_set := false

const MAX_RANGE := 750.0
const PELLET_COLOR := Color(1.0, 0.74, 0.32, 1.0)
const SPECIAL_COLOR := Color(1.0, 0.28, 0.08, 1.0)
const BURST_COLOR := Color(1.0, 0.45, 0.12, 1.0)
const LINE_COLOR := Color(1.0, 0.35, 0.08, 0.85)
const BASE_RADIUS := 10.0

# Damage & Config
var base_damage := 2
var is_special := false
var is_burst := false
var burn_level := 0
var is_intangible: bool = false
var size_level := 0
var pierce_all := false
var pierce_count := 0

# Static tracking for lines
static var all_special_pellets: Array[KiloPellet] = []
static var all_burst_pellets: Array[KiloPellet] = []
var wave_index: int = 0
var pellet_index: int = 0
var _hit_nodes: Array = []

func _ready() -> void:
	# CRITICAL: Force detection of World (1), Bodies (2), Hitboxes (4)
	# Default to 7 (1|2|4)
	collision_mask = 1 | 2 | 4
	
	# Check for Wells' Chrono-Intangibility upgrade
	# If active, REMOVE Layer 1 (World) from mask
	var player = get_tree().get_first_node_in_group("player")
	
	# Debug upgrade logic (Uncommented for user feedback)
	var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
	var is_in_squad = false
	
	if player and player.has_method("is_character_in_squad"):
		is_in_squad = player.is_character_in_squad("wells")
		
		# Fallback check for capitalization or ID mismatch
		if not is_in_squad:
			# Try capital "Wells" just in case
			if player.is_character_in_squad("Wells"):
				is_in_squad = true
				
	if has_upgrade:
		print("[KiloPellet] Upgrade ACTIVE. InSquad: ", is_in_squad)
	
	if has_upgrade and is_in_squad:
		print("[KiloPellet] Applying Intangibility")
		is_intangible = true
		# We CANNOT remove Layer 4 (Value 4) because Boulders share it with Hitboxes
		# So we only remove Layer 1 (World) if they use it, and rely on logic for Layer 4
		collision_mask = 2 | 4
	
	monitoring = true
	
	connect("body_entered", Callable(self, "_on_body_entered"))
	if not area_entered.is_connected(Callable(self, "_on_body_entered")):
		area_entered.connect(Callable(self, "_on_body_entered"))

	# Visual registration
	if is_special: all_special_pellets.append(self)
	if is_burst: all_burst_pellets.append(self)
	
	# Night visibility
	var mat = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	z_index = 500 # High z-index to stay on top
	
	add_to_group("projectiles")
	queue_redraw()

func _exit_tree() -> void:
	if is_special: all_special_pellets.erase(self)
	if is_burst: all_burst_pellets.erase(self)

func _physics_process(delta: float) -> void:
	if not _start_position_set:
		start_position = global_position
		_start_position_set = true
	
	# Tunneling Prevention (RayCast ahead)
	var space_state = get_world_2d().direct_space_state
	var motion = velocity * delta
	var query = PhysicsRayQueryParameters2D.create(global_position, global_position + motion, collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	if result:
		_on_body_entered(result.collider)
		if not is_instance_valid(self) or is_queued_for_deletion():
			return

	position += motion
	lifetime += delta
	
	if lifetime > 3.0 or global_position.distance_to(start_position) >= MAX_RANGE:
		queue_free()
		return
	
	if is_special or is_burst:
		queue_redraw()

func _on_body_entered(body: Node) -> void:
	# Robust Player filtering
	if body == owner_node or body.name == "Player" or body.is_in_group("player"):
		return
	# Ignore other projectiles (and self)
	if body.is_in_group("projectiles") or body.is_in_group("enemy_projectiles") or body is KiloPellet:
		return
		
	if _hit_nodes.has(body): return
	if body.is_in_group("charmed_allies"): return
	
	# Debug what we are hitting and stopping on
	# print("[KiloPellet] Hit: ", body.name, " Layer: ", body.collision_layer if "collision_layer" in body else "?")
	
	# Detect damageable
	# Ignore boulders if intangible
	if body.is_in_group("boulders") and is_intangible:
		return
		
	var damageable = body.has_method("take_damage") or "hp" in body
	
	# Hit a Wall/Boulder? (Not damageable and on Layer 1)
	if not damageable:
		# Check if it's a Shield (handle by ignoring, let Shield consume us)
		var p = body.get_parent()
		if p and (p.is_in_group("shielder_shields") or p.is_in_group("boss_shields")):
			return
			
		# If we hit it, it means mask included it (so no intangibility)
		# Just destroy pellet
		if not is_special: # Special pellets might pierce walls? usually no.
			pass # Logic below handles queue_free if not pierce_all
		
		# For walls, we generally destroy immediately unless bounce logic exists (none here)
		# BUT wait, special pellets trigger V-blast on hit?
		# "On Hit: Trigger V-shaped blast"
		# Should it trigger on Wall?
		# Usually V-blast attacks enemies.
		# If hitting wall, maybe just die.
		queue_free()
		return
	
	_hit_nodes.append(body)
	var hit_dir = velocity.normalized()
	
	# 1. SPAWN BLAST (Before damage to ensure execution)
	if is_special:
		_spawn_blast(body.global_position, hit_dir)
		if burn_level > 0:
			_apply_burn(body)
			
	# 2. DEAL DAMAGE
	if body.has_method("take_damage"):
		var is_crit = randf() < 0.15
		var dmg = base_damage * (2.0 if is_crit else 1.0)
		# Pass is_burst and "kilo" source
		body.take_damage(int(dmg), is_crit, hit_dir, is_burst, "kilo")
	
	if not pierce_all:
		queue_free()

func _spawn_blast(pos: Vector2, dir: Vector2) -> void:
	# Instantiating KiloVBlast
	var blast = KiloVBlast.new()
	var parent_node = get_parent()
	if parent_node:
		parent_node.add_child(blast)
		
		# Calculate Blast Damage (e.g. 1.5x pellet damage)
		# Size upgrade affects range
		var range_mult = 1.0 + (0.3 * size_level) # +30% range per level
		var b_range = 180.0 * range_mult
		var b_damage = int(base_damage * 1.5)
		
		# Setup with full params
		blast.setup(dir, pos, SPECIAL_COLOR, b_damage, b_range, owner_node, is_burst)

func _apply_burn(body: Node) -> void:
	if not is_instance_valid(body) or not "max_hp" in body:
		return
	
	# Burn rates: 15/25/35% HP/s for normal, 5/10/15% for elite/boss
	var burn_rates := [0.0, 0.15, 0.25, 0.35]
	var elite_rates := [0.0, 0.05, 0.10, 0.15]
	
	var is_elite: bool = body.has_meta("enemy_tier") and body.get_meta("enemy_tier") in ["elite", "boss", "tank"]
	var burn_rate: float = elite_rates[burn_level] if is_elite else burn_rates[burn_level]
	var burn_duration := 3.0
	var damage_per_second := int(body.max_hp * burn_rate)
	
	# Check if already has burn
	if body.has_node("KiloBurn"):
		var existing = body.get_node("KiloBurn")
		existing.set("duration", burn_duration) # Refresh duration
		return
	
	# Create burn effect
	var burn = Node.new()
	burn.name = "KiloBurn"
	burn.set_script(_get_burn_script())
	burn.set("damage_per_second", damage_per_second)
	burn.set("duration", burn_duration)
	burn.set("owner_node", owner_node)
	body.add_child(burn)

func _get_burn_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node

var damage_per_second: int = 0
var duration: float = 3.0
var owner_node: Node = null
var _timer: float = 0.0
var _tick_timer: float = 0.0
const TICK_INTERVAL := 0.5

func _process(delta: float) -> void:
	_timer += delta
	_tick_timer += delta
	
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_apply_tick()
	
	if _timer >= duration:
		queue_free()

func _apply_tick() -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		queue_free()
		return
	
	var tick_damage := int(damage_per_second * TICK_INTERVAL)
	if tick_damage <= 0:
		return
	
	if parent.has_method(\"take_damage\"):
		parent.take_damage(tick_damage, false, Vector2.ZERO, false, "kilo")
	elif \"hp\" in parent:
		parent.hp -= tick_damage
		if parent.hp <= 0 and parent.has_method(\"die\"):
			parent.die()
"""
	script.reload()
	return script

# === DRAWING LOGIC (Preserved from original as user liked visuals) ===
func _draw() -> void:
	var color = SPECIAL_COLOR if is_special else (BURST_COLOR if is_burst else PELLET_COLOR)
	var radius = BASE_RADIUS * (1.5 if size_level > 0 else 1.0)
	
	# Glows
	draw_circle(Vector2.ZERO, radius * 2.0, Color(color.r, color.g, color.b, 0.2))
	draw_circle(Vector2.ZERO, radius * 1.4, Color(color.r, color.g, color.b, 0.5))
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius * 0.5, Color.WHITE)
	
	_draw_lines()

func _draw_lines() -> void:
	if not (is_special or is_burst): return
	var peers = all_special_pellets if is_special else all_burst_pellets
	
	for p in peers:
		if p == self or not is_instance_valid(p): continue
		var local_pos = to_local(p.global_position)
		if local_pos.length() > 600: continue
		
		draw_line(Vector2.ZERO, local_pos, LINE_COLOR, 4.0)
