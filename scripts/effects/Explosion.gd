extends Area2D


const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

var time = 0.0
var _light: PointLight2D = null
var _damaged_bodies: Array = [] # Track who we've already damaged
var owner_node: Node = null # Track who spawned this explosion for killer_source
var killer_source_override: String = "" # Override killer_source if set
var damage: int = 30 # Default damage if not initialized
var radius: float = 100.0 # Default radius
var _activated := false # Activation (damage + fade) runs on first process, so pooled reuse re-runs it
var _skip_los := false  # Perf: skip line-of-sight raycasts when no shields exist this blast

## Snow White turret missile debuffs applied to enemies this explosion damages.
var armor_pierce_mult: float = 0.0  # >0: permanent damage-taken mark (x2/x4/x6)
var incendiary_total: float = 0.0   # >0: flat burn DoT total over INCENDIARY_DURATION
var stun_duration: float = 0.0      # >0: stun enemies hit (Rapunzel "Concussive Blast")
const BurnDOTScript := preload("res://scripts/effects/BurnDOT.gd")
const INCENDIARY_SOURCE := "snow_white_incendiary"
const INCENDIARY_DURATION := 5.0

# Performance: disable explosion lights (less impactful since they're short-lived)
const ENABLE_EXPLOSION_LIGHTS := false

func initialize(dmg: int, r: float = 100.0) -> void:
	damage = dmg
	radius = r


func _ready():
	add_to_group("explosions")
	# Activation (collision setup, damage scan, fade) is deferred to the first
	# _process frame so a pooled explosion re-runs it after the caller has set
	# damage/radius/etc. (see _activate).

## Reset state for pool reuse. Called by ProjectileCache before the caller
## re-configures this explosion.
func reset() -> void:
	_activated = false
	_damaged_bodies.clear()
	time = 0.0
	modulate = Color(1, 1, 1, 1)
	owner_node = null
	killer_source_override = ""
	armor_pierce_mult = 0.0
	incendiary_total = 0.0
	stun_duration = 0.0

func _activate() -> void:
	# Proper Area2D setup - use engine's collision list instead of manual query
	collision_layer = 0
	set_deferred("collision_mask", 15) # Layers 1, 2, 3, 4 (Enemies/Hitboxes)
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)

	# Update collision shape to match radius
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is CircleShape2D:
		shape_node.shape.radius = radius

	# Wait for physics update to populate overlaps
	await get_tree().physics_frame
	await get_tree().physics_frame

	if not is_inside_tree():
		return

	_process_explosion_overlaps()

	modulate.a = 1.0

	# Explosion lights are short-lived but still add up - optional
	if ENABLE_EXPLOSION_LIGHTS:
		_light = PointLight2D.new()
		_light.name = "ExplosionLight"
		_light.color = Color(1.0, 0.7, 0.3) # Warm orange
		_light.energy = 2.5 # Very bright initially
		_light.texture = _create_light_texture()
		_light.texture_scale = radius / 64.0 # Scale light with radius
		_light.shadow_enabled = false
		add_child(_light)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	if _light:
		tween.tween_property(_light, "energy", 0.0, 0.25) # Light fades with explosion
	await tween.finished
	_finish()

func _finish() -> void:
	if _light and is_instance_valid(_light):
		_light.queue_free()
		_light = null
	ProjectileCache.return_to_pool(self)

func _process_explosion_overlaps() -> void:
	# Perf: line-of-sight raycasts only exist to stop explosions punching through
	# shields (and walls/boulders). When no shields are active this blast, skip them
	# entirely - the dominant per-target raycast cost during big bursts.
	_skip_los = get_tree().get_nodes_in_group("shielder_shields").is_empty() and get_tree().get_nodes_in_group("boss_shields").is_empty()

	# Use standard get_overlapping_bodies which reads safe current state
	var bodies = get_overlapping_bodies()
	for body in bodies:
		_try_damage_body(body)
	
	# Also check areas for shields ONLY (not HitboxComponents)
	# HitboxComponents are processed via their parent ModularEnemy body
	var areas = get_overlapping_areas()
	for area in areas:
		# Skip HitboxComponents - they're handled via parent enemy body
		# Check by name, script, and parent group
		if area.name == "HitboxComponent":
			continue
		if area.get_parent() and area.get_parent().is_in_group("enemies"):
			continue # This area belongs to an enemy, body loop handles it
		if area.get_script() and area.get_script().resource_path.find("HitboxComponent") != -1:
			continue
		_try_damage_body(area)

# REMOVED: force_damage_check / _perform_damage_check (unsafe manual query)

func _create_light_texture() -> Texture2D:
	# Use cached texture for performance
	return TextureCache.get_light_texture_64()

func _process(delta):
	if not _activated:
		_activated = true
		_activate()
	time += delta
	if has_node("Sprite2D"):
		$Sprite2D.material.set_shader_parameter("time", time)

func _on_body_entered(_body):
	# Fallback/Redundancy
	# _try_damage_body(body) 
	pass

func _try_damage_body(body) -> void:
	# Resolve unique logical entity (Root) to prevent double-hitting
	# (e.g. prevents hitting both CharacterBody and HitboxArea of same enemy)
	var root_entity = body
	if body.get_parent() and (body.get_parent().is_in_group("enemies") or body.get_parent().is_in_group("characters")):
		root_entity = body.get_parent()
		
	# Skip if already damaged this logical entity
	if root_entity in _damaged_bodies:
		return
		
	var player = get_tree().get_first_node_in_group("player")
	if body == player:
		return
		
	# Check for Shield Hit (Area2D child of ShielderShield) via explicit detection
	# (This handles the case where we hit the shield area directly)
	var shield_root = null
	if body is Area2D:
		shield_root = body.get_parent()
	elif body.has_method("take_shield_damage"):
		shield_root = body
		
	if shield_root and shield_root.has_method("take_shield_damage"):
		_damaged_bodies.append(root_entity)
		# Shield hit!
		# print("Explosion Damaging Shield: ", shield_root.name, " Dmg: ", damage)
		shield_root.take_shield_damage(damage, "explosion")
		return

	# BUG FIX: Explosions pierce shields because they are area checks.
	# We must verify Line of Sight from explosion center to target.
	if not _has_line_of_sight(body):
		return
		
	if not body.has_method("take_damage"):
		# If the body itself can't take damage (e.g. Enemy Root), we don't count it as "damaged"
		# so that we don't block the HitboxComponent from taking damage later.
		return
	
	# Skip player if hit somehow
	if body.is_in_group("player"):
		return
		
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	
	# FIX: Skip bodies that are in the "enemies" group AND have a HitboxComponent child
	# These should ONLY be damaged via their HitboxComponent to prevent double damage/text
	if body.is_in_group("enemies") and body.has_node("HitboxComponent"):
		# Let the HitboxComponent (in areas loop) handle this enemy
		_damaged_bodies.append(root_entity) # Still mark as damaged so HitboxComponent can deal it
		# The HitboxComponent will be processed and will call body.take_damage via forwarding
		# We need to damage the HitboxComponent directly instead
		var hitbox = body.get_node("HitboxComponent")
		if hitbox and hitbox.has_method("take_damage"):
			var hit_direction = (body.global_position - global_position).normalized()
			var killer_source := "rocket"
			if killer_source_override != "":
				killer_source = killer_source_override
			elif is_instance_valid(owner_node) and (owner_node.is_in_group("summons") or owner_node.is_in_group("summoned_allies") or owner_node.is_in_group("clones")):
				killer_source = "summon"
			_apply_missile_debuffs(root_entity)
			hitbox.take_damage(damage, false, hit_direction, false, killer_source)
		return
		
	_damaged_bodies.append(root_entity)
	var hit_direction = (body.global_position - global_position).normalized()
	var killer_source := "rocket" # Default to rocket (Rapunzel) for BurstConfig (10% per hit)
	if killer_source_override != "":
		killer_source = killer_source_override
	elif is_instance_valid(owner_node) and (owner_node.is_in_group("summons") or owner_node.is_in_group("summoned_allies") or owner_node.is_in_group("clones")):
		killer_source = "summon"
	_apply_missile_debuffs(root_entity)
	body.take_damage(damage, false, hit_direction, false, killer_source)


## Apply Snow White turret missile debuffs (Armor-Piercing mark / Incendiary burn)
## to an enemy this explosion damaged. No-ops when neither talent fed values in.
func _apply_missile_debuffs(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	if armor_pierce_mult > 0.0:
		enemy.set_meta("armor_pierce_vulnerability", armor_pierce_mult)
	if stun_duration > 0.0 and enemy.has_method("apply_stun"):
		enemy.apply_stun(stun_duration)
	if incendiary_total > 0.0:
		var existing: Node = null
		for child in enemy.get_children():
			if child.get_script() == BurnDOTScript and child._source_id == INCENDIARY_SOURCE:
				existing = child
				break
		if existing:
			existing.refresh()
		else:
			var dot = BurnDOTScript.new()
			dot.use_flat = true
			dot.flat_total = incendiary_total
			dot.duration = INCENDIARY_DURATION
			dot.damage_source = INCENDIARY_SOURCE
			enemy.add_child(dot)
			dot.setup(enemy, INCENDIARY_SOURCE, INCENDIARY_DURATION)

func _has_line_of_sight(target: Node2D) -> bool:
	# Perf: no shields active this blast -> no raycast needed.
	if _skip_los:
		return true
	# If Chrono-Intangibility is active, ignore all shields (always LOS)
	var player = get_tree().get_first_node_in_group("player")
	var playing_wells = player and player.has_method("is_playing_character") and player.is_playing_character("wells")
	if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and playing_wells:
		return true

	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return true # Safe fallback
		
	# Offset start slightly towards target to avoid starting inside the collision of the shooter or target
	var start_pos = global_position
	var end_pos = target.global_position
	var diff = end_pos - start_pos
	
	# If target is at the center, LOS is guaranteed (it's the thing that triggered impact)
	if diff.length() < 1.0:
		return true
		
	var dir_to_target = diff.normalized()
	
	# Small offset to prevent starting exactly on a collider edge
	var ray_start = start_pos + dir_to_target * 2.0
	
	var query = PhysicsRayQueryParameters2D.create(ray_start, end_pos)
	query.collision_mask = 1 | 8 # World (1) + Ally layer (8) - only detect things that block explosions
	
	# Important: include specific shield groups in detection if they use Areas
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	# Exclude both the explosion itself and the target (we want to check if anything is BETWEEN them)
	query.exclude = [self, target]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		# If we hit something that is a Shield, LOS is blocked
		if collider.is_in_group("shielder_shields") or collider.is_in_group("boss_shields"):
			return false
		if collider.get_parent() and (collider.get_parent().is_in_group("shielder_shields") or collider.get_parent().is_in_group("boss_shields")):
			return false
			
		# Walls block explosions too
		if collider.get_collision_layer_value(1):
			return false
			
		# If we hit another enemy, typically explosions should pass through them to hit others
		# So if the only thing hit wasn't a shield or wall, we have LOS
		return true
		
	return true
