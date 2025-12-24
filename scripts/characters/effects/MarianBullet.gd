extends Area2D
class_name MarianBullet

## Marian's mystical purple bullet - uses shader for swirling sphere effect

var velocity: Vector2 = Vector2.ZERO
var owner_node: Node = null
var killer_source: String = "minigun" # For ShielderShield collision detection
var base_damage: int = 2
var lifespan: float = 3.0
var _age: float = 0.0
var start_position: Vector2 = Vector2.ZERO
var _start_position_set: bool = false

# Max range for minigun bullets
const MAX_RANGE := 1100.0

# Shader material for the mystical effect
var _shader_material: ShaderMaterial = null

func _ready() -> void:
	# Set up collision
	collision_layer = 4 # Projectile layer
	collision_mask = 2 # Enemy layer
	
	# Connect hit detection
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Create the visual
	_create_visual()
	
	# Assign to effects layer to prevent night darkening (deferred so node is in tree)
	call_deferred("_assign_to_effects_layer")
	
	z_index = 50

func _assign_to_effects_layer() -> void:
	"""Deferred call to assign to effects layer after node is in tree"""
	# Reparent to EffectsLayer so _draw() isn't darkened by world modulate
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 900

func _create_visual() -> void:
	# Load shader
	var shader = load("res://resources/shaders/marian_bullet.gdshader")
	if shader:
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = shader
		_shader_material.set_shader_parameter("time_scale", 2.5)
		_shader_material.set_shader_parameter("primary_color", Color(0.5, 0.1, 0.8, 1.0))
		_shader_material.set_shader_parameter("secondary_color", Color(0.1, 0.0, 0.2, 1.0))
		_shader_material.set_shader_parameter("accent_color", Color(0.8, 0.3, 1.0, 1.0))
		_shader_material.set_shader_parameter("swirl_intensity", 4.0)
		_shader_material.set_shader_parameter("glow_intensity", 1.2)
	
	# Create collision shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 8.0
	collision.shape = shape
	add_child(collision)

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifespan:
		queue_free()
		return
	
	# Capture start position on first frame
	if not _start_position_set:
		start_position = global_position
		_start_position_set = true
	
	# Move bullet
	global_position += velocity * delta
	
	# Check max range
	if MAX_RANGE > 0.0:
		var traveled := global_position.distance_to(start_position)
		if traveled >= MAX_RANGE:
			queue_free()
			return
	
	# Check boulder collision (reparenting to EffectsLayer breaks Area2D overlap)
	if _check_boulder_collision():
		queue_free()
		return

	# Check shield collision (Manual check due to reparenting)
	if _check_shield_collision():
		queue_free()
		return
	
	# Redraw for shader animation
	queue_redraw()

func _check_boulder_collision() -> bool:
	"""Manual boulder collision check since bullets are in EffectsLayer (different scene tree branch)."""
	# Skip if Chrono-Intangibility upgrade is active
	var shop = load("res://scripts/ui/ShopMenu.gd")
	# Skip if Chrono-Intangibility upgrade is active AND Wells is in squad
	var player = get_tree().get_first_node_in_group("player")
	if shop and shop.has_character_upgrade("wells", "chrono_intangibility") and player and player.has_method("is_character_in_squad") and player.is_character_in_squad("wells"):
		return false
	
	var boulders := TargetCache.get_boulders()
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_to(boulder_pos) < boulder_radius:
			return true
	return false

func _check_shield_collision() -> bool:
	"""Manual shield collision check."""
	# Skip if Chrono-Intangibility upgrade is active
	var shop = load("res://scripts/ui/ShopMenu.gd")
	# Skip if Chrono-Intangibility upgrade is active AND Wells is in squad
	var player = get_tree().get_first_node_in_group("player")
	if shop and shop.has_character_upgrade("wells", "chrono_intangibility") and player and player.has_method("is_character_in_squad") and player.is_character_in_squad("wells"):
		return false
	
	# Check boss shields first
	var shields := get_tree().get_nodes_in_group("boss_shields")
	# Also check generic shields
	shields.append_array(get_tree().get_nodes_in_group("shielder_shields"))
	
	for shield in shields:
		if not is_instance_valid(shield): continue
		if shield.has_method("is_active") and not shield.is_active(): continue
		if not (shield is Node2D): continue
		
		# Determine radius
		var radius: float = 120.0
		if "shield_radius" in shield:
			radius = shield.shield_radius
		
		if global_position.distance_to((shield as Node2D).global_position) < radius:
			if shield.has_method("take_shield_damage"):
				var dmg = _calculate_damage()
				shield.take_shield_damage(dmg, "minigun")
				return true
	return false

func _calculate_damage() -> int:
	# Basic damage calc - simplified for manual check
	# Usually would use player crit stats, but for now just use base
	# To be perfectly accurate we'd need player ref, but this is a fallback
	var player = get_tree().get_first_node_in_group("player")
	var is_crit = false
	if player and player.has_method("get_crit_chance"):
		if randf() < player.get_crit_chance():
			is_crit = true
			
	if is_crit:
		return base_damage * 2
	return base_damage


func _draw() -> void:
	# Draw the sphere - bigger and brighter with glowing effect
	var size := 32.0 # Larger size to match other bullets
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	
	# Outer glow - bright purple bloom
	draw_circle(Vector2.ZERO, size * 0.8, Color(0.8, 0.4, 1.0, 0.3))
	draw_circle(Vector2.ZERO, size * 0.6, Color(0.9, 0.6, 1.0, 0.5))
	
	# Core - bright and glowing
	draw_circle(Vector2.ZERO, size * 0.4, Color(1.0, 0.8, 1.0, 0.8))
	draw_circle(Vector2.ZERO, size * 0.25, Color(1.0, 0.95, 1.0, 1.0))
	
	# Bright center
	draw_circle(Vector2.ZERO, size * 0.12, Color(1.0, 1.0, 1.0, 1.0))
	
	# Draw swirling particles
	var time := _age * 3.0
	for i in range(6):
		var angle := time + float(i) * TAU / 6.0
		var radius := size * 0.35 * (0.7 + 0.3 * sin(time * 2.0 + float(i)))
		var pos := Vector2(cos(angle), sin(angle)) * radius
		var particle_size := 4.0 + 2.5 * sin(time * 4.0 + float(i) * 1.5)
		draw_circle(pos, particle_size, Color(1.0, 0.7, 1.0, 0.8))

func _on_body_entered(body: Node2D) -> void:
	_hit_target(body)

func _on_area_entered(area: Area2D) -> void:
	_hit_target(area)

func _hit_target(target: Node) -> void:
	# Skip if target is the owner
	if target == owner_node:
		return
	
	# Skip if not an enemy
	if not target.is_in_group("enemies"):
		return
	
	# Skip charmed enemies (they're friendly now)
	if target.is_in_group("charmed_allies"):
		return
	
	# Apply damage
	if target.has_method("take_damage"):
		target.take_damage(base_damage, false, velocity.normalized(), false, "minigun")
	elif "hp" in target:
		target.hp -= base_damage
	
	# Register burst hit with weapon type (Essential for burst accumulation)
	if owner_node and owner_node.has_method("register_burst_hit"):
		owner_node.register_burst_hit(target, false, "minigun", false)
	
	# Destroy bullet
	queue_free()
