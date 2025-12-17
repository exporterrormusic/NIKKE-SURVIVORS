@tool
extends Area2D
class_name GroundFire

@export var radius: float = 120.0
@export var duration: float = 3.0
@export var damage_per_tick: int = 6
@export var tick_interval: float = 0.5
@export var color: Color = Color(1.0, 0.45, 0.1, 0.6)
@export var glow_color: Color = Color(1.0, 0.42, 0.1, 0.4)
@export var ember_color: Color = Color(1.0, 0.65, 0.25, 0.8)
@export var smoke_color: Color = Color(0.4, 0.4, 0.4, 0.35)
@export var ember_count: int = 18

# If true, this fire was created by player and won't damage player characters
var is_friendly: bool = true

var _elapsed := 0.0
var _tick_elapsed := 0.0
var _rng := RandomNumberGenerator.new()
var _embers: Array = []
var _is_editor_preview := false

func _ready() -> void:
	_is_editor_preview = Engine.is_editor_hint()
	
	# Set up collision detection
	collision_layer = 0  # Ground fire doesn't need a layer (not targetable)
	collision_mask = 1 | 4  # Detect player (1) and enemies (4)
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)
	
	# Render below enemies (which are typically z_index 0-10)
	z_index = -5
	
	var shape := CircleShape2D.new()
	shape.radius = radius
	var collider := CollisionShape2D.new()
	collider.shape = shape
	call_deferred("add_child", collider)
	_rng.randomize()
	_embers = []
	for i in range(max(ember_count, 0)):
		_embers.append({
			"angle": _rng.randf_range(0.0, TAU),
			"offset": _rng.randf_range(0.2, 0.9),
			"speed": _rng.randf_range(1.5, 3.5),
			"size": _rng.randf_range(radius * 0.05, radius * 0.12)
		})
	set_process(true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _is_editor_preview:
		_setup_editor_preview()
	
	# Assign to effects layer to avoid night darkening
	call_deferred("_assign_to_effects_layer")
	queue_redraw()

func _assign_to_effects_layer() -> void:
	if Engine.is_editor_hint(): return
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 0 # Default for ground fire


func _process(delta: float) -> void:
	if _is_editor_preview:
		_elapsed += delta
		_tick_elapsed += delta
		if _tick_elapsed >= tick_interval:
			_tick_elapsed = 0.0
		for i in range(_embers.size()):
			var ember: Dictionary = _embers[i]
			ember["angle"] = ember.get("angle", 0.0) + delta * ember.get("speed", 2.0)
			_embers[i] = ember
		if _elapsed >= max(duration, 0.1):
			_elapsed = 0.0
		queue_redraw()
		return
	_elapsed += delta
	_tick_elapsed += delta
	if _elapsed >= duration:
		_return_to_pool()
		return
	if _tick_elapsed >= tick_interval:
		_tick_elapsed = 0.0
		_apply_damage()
	for i in range(_embers.size()):
		var ember: Dictionary = _embers[i]
		ember["angle"] = ember.get("angle", 0.0) + delta * ember.get("speed", 2.0)
		_embers[i] = ember
	# Reduce redraw frequency - ground fire doesn't need 60 FPS
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()

func _return_to_pool() -> void:
	queue_free()

func reset() -> void:
	_elapsed = 0.0
	_tick_elapsed = 0.0
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)
	# Re-randomize embers for variety
	for i in range(_embers.size()):
		var ember: Dictionary = _embers[i]
		ember["angle"] = _rng.randf_range(0.0, TAU)
		_embers[i] = ember
	queue_redraw()

# Cached enemy list to avoid get_nodes_in_group every tick
var _enemy_cache: Array = []
var _enemy_cache_timer := 0.0
const ENEMY_CACHE_INTERVAL := 0.15

func _apply_damage() -> void:
	if _is_editor_preview:
		return
	
	# Update enemy cache periodically
	_enemy_cache_timer += tick_interval
	if _enemy_cache_timer >= ENEMY_CACHE_INTERVAL:
		_enemy_cache_timer = 0.0
		_enemy_cache = get_tree().get_nodes_in_group("enemies")
	
	# Damage enemies using cached list
	for enemy in _enemy_cache:
		if not is_instance_valid(enemy):
			continue
		if not (enemy is Node2D):
			continue
		var distance := (enemy as Node2D).global_position.distance_to(global_position)
		# Account for enemy scale - larger enemies (bosses/elites) have bigger hitboxes
		var enemy_scale: float = enemy.scale.x if enemy.scale.x > 1.0 else 1.0
		var enemy_hitbox_bonus: float = 30.0 * (enemy_scale - 1.0)
		var effective_radius: float = radius + enemy_hitbox_bonus
		if distance <= effective_radius:
			var hit_direction := ((enemy as Node2D).global_position - global_position).normalized()
			
			# Check HP before damage to detect kill
			var was_alive = true
			if enemy.has_method("is_dead") and enemy.is_dead():
				was_alive = false
			elif "hp" in enemy and enemy.hp <= 0:
				was_alive = false
			
			if enemy.has_method("take_damage"):
				# Use source "burn_dot" to prevent XP/burst generation in Goddess Fall
				enemy.take_damage(damage_per_tick, false, hit_direction, false, "burn_dot")
			elif enemy.has_method("apply_damage"):
				enemy.apply_damage(damage_per_tick)
				
			# Check HP after damage to detect kill
			var is_dead = false
			if enemy.has_method("is_dead") and enemy.is_dead():
				is_dead = true
			elif "hp" in enemy and enemy.hp <= 0:
				is_dead = true
				
			# If we killed it, heal the player
			if was_alive and is_dead and is_friendly:
				_heal_player_on_kill()

	# Also damage any overlapping areas/bodies (same as before)
	var overlapping_areas := get_overlapping_areas()
	for area in overlapping_areas:
		if not is_instance_valid(area): continue
		if area.is_in_group("enemies"): continue
		if is_friendly and (area.is_in_group("player") or area.is_in_group("characters")): continue
		_apply_damage_to_node(area)
	
	var overlapping_bodies := get_overlapping_bodies()
	for body in overlapping_bodies:
		if not is_instance_valid(body): continue
		if body.is_in_group("enemies"): continue
		if is_friendly and (body.is_in_group("player") or body.is_in_group("characters")): continue
		_apply_damage_to_node(body)

func _apply_damage_to_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var hit_direction: Vector2 = Vector2.ZERO
	if node is Node2D:
		hit_direction = ((node as Node2D).global_position - global_position).normalized()
	
	# Check for Shield Hit first
	var shield_root = null
	if node is Area2D:
		shield_root = node.get_parent()
	elif node.has_method("take_shield_damage"):
		shield_root = node
		
	if shield_root and shield_root.has_method("take_shield_damage"):
		shield_root.take_shield_damage(damage_per_tick, "burn_dot")
		return

	# Try different take_damage signatures
	if node.has_method("take_damage"):
		var method_info = node.get_method_list()
		var arg_count := 1  # Default assumption
		for method in method_info:
			if method["name"] == "take_damage":
				arg_count = method["args"].size()
				break
		
		if arg_count >= 5:
			node.take_damage(damage_per_tick, false, hit_direction, false, "burn_dot")
		elif arg_count >= 3:
			node.take_damage(damage_per_tick, false, hit_direction)
		elif arg_count >= 2:
			node.take_damage(damage_per_tick, false)
		else:
			node.take_damage(damage_per_tick)
	elif node.has_method("apply_damage"):
		node.apply_damage(damage_per_tick)

func _heal_player_on_kill() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		# Rapunzel Upgrade Logic: 2% of Max HP (min 1)
		var heal_amount := 1
		if "max_hp" in player:
			heal_amount = maxi(1, int(player.max_hp * 0.02))
		else:
			heal_amount = 5 # Fallback if max_hp not found
			
		if player.has_method("heal"):
			player.heal(heal_amount)
		elif "hp" in player:
			player.hp = mini(player.hp + heal_amount, player.max_hp if "max_hp" in player else 100)
			# Update HUD if available
			if player.get("player_hud"):
				player.player_hud.update_health(player.hp, player.max_hp, heal_amount, true)

func _draw() -> void:
	var progress := clampf(_elapsed / max(duration, 0.01), 0.0, 1.0)
	var fade := 1.0 - progress
	
	# User requested hitbox to be circular (it already is visually CircleShape2D, but let's reinforce circle visuals)
	# Also requested 20% bigger size - we'll scale drawing slightly
	var draw_radius: float = radius * 1.2
	
	var base_glow := Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * fade * 0.9)
	draw_circle(Vector2.ZERO, draw_radius * 1.15, base_glow)
	var core := Color(color.r, color.g, color.b, color.a * fade)
	draw_circle(Vector2.ZERO, draw_radius, core)
	
	var ember_alpha := ember_color.a * fade
	for ember_variant in _embers:
		if not (ember_variant is Dictionary): continue
		var ember := ember_variant as Dictionary
		var angle: float = float(ember.get("angle", 0.0))
		var offset: float = float(ember.get("offset", 0.5))
		var dist: float = draw_radius * offset * (0.6 + 0.4 * sin(_elapsed * 3.0 + angle))
		var pos := Vector2(cos(angle), sin(angle)) * dist
		var ember_size := float(ember.get("size", radius * 0.08))
		var flicker := 0.6 + 0.4 * sin(_elapsed * 10.0 + angle * 2.0)
		var ember_col := Color(ember_color.r, ember_color.g, ember_color.b, ember_alpha * flicker)
		draw_circle(pos, ember_size, ember_col)
		
	var smoke_alpha := smoke_color.a * fade * 0.6
	if smoke_alpha > 0.02:
		draw_circle(Vector2.ZERO, draw_radius * 1.4, Color(smoke_color.r, smoke_color.g, smoke_color.b, smoke_alpha))
	var indicator_color := Color(1.0, 0.2, 0.05, 0.4 * fade)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, indicator_color, 3.0)


func _setup_editor_preview() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
