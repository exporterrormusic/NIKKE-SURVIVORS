# Extracted from scripts/characters/effects/CecilDrone.gd (was runtime-compiled embedded source).
extends Node2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 600.0
var damage: int = 3
var lifetime: float = 0.0
var max_lifetime: float = 2.0

func _ready() -> void:
	z_index = 45
	rotation = direction.angle()
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 45

func _process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Draw thick blue laser beam
	var length := 35.0
	var width := 12.0
	
	# Outer glow
	draw_line(Vector2.ZERO, Vector2(length, 0), Color(0.2, 0.5, 1.0, 0.3), width * 2.5)
	# Mid glow
	draw_line(Vector2.ZERO, Vector2(length, 0), Color(0.3, 0.7, 1.0, 0.6), width * 1.5)
	# Core
	draw_line(Vector2.ZERO, Vector2(length, 0), Color(0.7, 0.95, 1.0, 1.0), width)

func _physics_process(_delta: float) -> void:
	# Check for enemy collision
	var space := get_world_2d().direct_space_state
	if not space:
		return
	
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	
	var results := space.intersect_point(query, 8)
	for result in results:
		var collider = result.get("collider")
		if collider and collider.is_in_group("enemies"):
			# Skip charmed allies
			if collider.is_in_group("charmed_allies"):
				continue
				
			if collider.is_in_group("charmed_allies"): return
			if collider.has_method("take_damage"):
				collider.take_damage(damage, false, direction, false, "cecil_drone")
			queue_free()
			return
