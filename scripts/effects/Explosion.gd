extends Area2D


const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

var time = 0.0
var _light: PointLight2D = null
var _damaged_bodies: Array = []  # Track who we've already damaged
var owner_node: Node = null  # Track who spawned this explosion for killer_source
var killer_source_override: String = ""  # Override killer_source if set
var damage: int = 30 # Default damage if not initialized
var radius: float = 100.0 # Default radius

# Performance: disable explosion lights (less impactful since they're short-lived)
const ENABLE_EXPLOSION_LIGHTS := false

func initialize(dmg: int, r: float = 100.0) -> void:
	damage = dmg
	radius = r

func _ready():
	print("DEBUG: Explosion _ready started. Radius: ", radius, " Damage: ", damage)
	add_to_group("explosions")
	
	# Instant AOE check using Physics Server (reliable, no frame delay needed)
	var shape = CircleShape2D.new()
	shape.radius = radius
	
	# Wait for physics frame to avoid "Space state is inaccessible" error during load/warmup
	# AND to ensure our position has been set by the spawner (since add_child triggers _ready immediately)
	print("DEBUG: Explosion awaiting physics frame...")
	await get_tree().physics_frame
	
	print("DEBUG: Explosion resumed. Is inside tree: ", is_inside_tree())
	if not is_inside_tree():
		print("DEBUG: Explosion NOT in tree, aborting.")
		return

	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = global_transform # Capture Transform NOW, after position is set
	query.collision_mask = 1 | 2 | 4 # Widen mask to catch everything possible
	query.collide_with_areas = true # IMPORTANT: Hit shields (Area2D)
	query.collide_with_bodies = true # Hit enemies (CharacterBody2D)
		
	var space_state = get_world_2d().direct_space_state
	# direct_space_state can be null if called at awkward times (e.g. shutdown/change)
	if space_state:
		print("DEBUG: Explosion Querying Space State... Mask: ", query.collision_mask)
		var results = space_state.intersect_shape(query, 32) # Max 32 hits
		print("DEBUG: Explosion Hit Count: ", results.size())
		for res in results:
			if res and res.collider:
				print("DEBUG: Explosion Hit Candidate: ", res.collider.name, " Type: ", res.collider.get_class(), " Layer: ", res.collider.collision_layer)
				_try_damage_body(res.collider)
	else:
		print("DEBUG: Explosion Space State is NULL!")
			
	modulate.a = 1.0

	# Explosion lights are short-lived but still add up - optional
	if ENABLE_EXPLOSION_LIGHTS:
		_light = PointLight2D.new()
		_light.name = "ExplosionLight"
		_light.color = Color(1.0, 0.7, 0.3)  # Warm orange
		_light.energy = 2.5  # Very bright initially
		_light.texture = _create_light_texture()
		_light.texture_scale = radius / 64.0  # Scale light with radius
		_light.shadow_enabled = false
		add_child(_light)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	if _light:
		tween.tween_property(_light, "energy", 0.0, 0.25)  # Light fades with explosion
	await tween.finished
	queue_free()

func _create_light_texture() -> Texture2D:
	# Use cached texture for performance
	return TextureCache.get_light_texture_64()

func _process(delta):
	time += delta
	if has_node("Sprite2D"):
		$Sprite2D.material.set_shader_parameter("time", time)

func _on_body_entered(body):
	# Fallback/Redundancy
	# _try_damage_body(body) 
	pass

func _try_damage_body(body) -> void:
	# Skip if already damaged this body
	if body in _damaged_bodies:
		return
	if body == get_parent().get_node_or_null("Player"):
		return
		
	# Check for Shield Hit (Area2D child of ShielderShield) via explicit detection
	# (This handles the case where we hit the shield area directly)
	var shield_root = null
	if body is Area2D:
		shield_root = body.get_parent()
	elif body.has_method("take_shield_damage"):
		shield_root = body
		
	if shield_root and shield_root.has_method("take_shield_damage"):
		_damaged_bodies.append(body)
		# Shield hit!
		print("Explosion Damaging Shield: ", shield_root.name, " Dmg: ", damage)
		shield_root.take_shield_damage(damage, "explosion") 
	if shield_root and shield_root.has_method("take_shield_damage"):
		_damaged_bodies.append(body)
		# Shield hit!
		print("Explosion Damaging Shield: ", shield_root.name, " Dmg: ", damage)
		shield_root.take_shield_damage(damage, "explosion") 
		return

	# BUG FIX: Explosions pierce shields because they are area checks.
	# We must verify Line of Sight from explosion center to target.
	if not _has_line_of_sight(body):
		return
		
	if not body.has_method("take_damage"):
		return
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	_damaged_bodies.append(body)
	print("Explosion Damaging Body: ", body.name, " Dmg: ", damage)
	var hit_direction = (body.global_position - global_position).normalized()
	var killer_source := "rocket"  # Default to rocket (Rapunzel) for BurstConfig (10% per hit)
	if killer_source_override != "":
		killer_source = killer_source_override
	elif is_instance_valid(owner_node) and (owner_node is NayutaClone or owner_node is SummonedAlly):
		killer_source = "summon"
	body.take_damage(damage, false, hit_direction, false, killer_source)

func _has_line_of_sight(target: Node2D) -> bool:
	# If Chrono-Intangibility is active, ignore all shields (always LOS)
	# If Chrono-Intangibility is active, ignore all shields (always LOS)
	var player = get_tree().get_first_node_in_group("player")
	var wells_in_squad = player and player.has_method("is_character_in_squad") and player.is_character_in_squad("wells")
	if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and wells_in_squad:
		return true

	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return true # Safe fallback
		
	var query = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.collision_mask = 1 | 2 | 4 
	# Shields are typically Areas (Layer 4 or similar?) or just Areas.
	# If we hit an AREA (Shield) before the body, we are blocked.
	query.collide_with_areas = true 
	query.collide_with_bodies = true
	
	# Exclude the target itself from blocking
	query.exclude = [target]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		# If we hit something that is a Shield or child of Shield, line of sight is blocked
		if collider.is_in_group("shielder_shields") or collider.is_in_group("boss_shields"):
			return false
		if collider.get_parent() and (collider.get_parent().is_in_group("shielder_shields") or collider.get_parent().is_in_group("boss_shields")):
			return false
		# Also check if we hit a wall/terrain (Layer 1 typically)
		# But usually explosions might want to hit around corners? 
		# For strict shield checking, reducing 'piercing walls' is acceptable side effect.
		# If collider is specifically the Shielder owner?
		if collider == target:
			return true
			
		# If we hit something else (Wall? another enemy?)
		# Usually we only care about shields.
		# If we hit a wall, technically the explosion is blocked by the wall.
		return false # Blocked by something that isn't the target
		
	return true
