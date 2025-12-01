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
	queue_redraw()

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
		if distance <= radius:
			var hit_direction := ((enemy as Node2D).global_position - global_position).normalized()
			if enemy.has_method("take_damage"):
				# Enemy.take_damage takes (damage, is_critical, direction)
				enemy.take_damage(damage_per_tick, false, hit_direction)
			elif enemy.has_method("apply_damage"):
				enemy.apply_damage(damage_per_tick)
	
	# Also damage any overlapping areas/bodies that have apply_damage or take_damage methods
	# This handles clones and other damageable entities
	var overlapping_areas := get_overlapping_areas()
	for area in overlapping_areas:
		if not is_instance_valid(area):
			continue
		# Skip if it's an enemy (already handled above)
		if area.is_in_group("enemies"):
			continue
		# Check if it has a damage method
		_apply_damage_to_node(area)
	
	var overlapping_bodies := get_overlapping_bodies()
	for body in overlapping_bodies:
		if not is_instance_valid(body):
			continue
		# Skip if it's an enemy (already handled above)
		if body.is_in_group("enemies"):
			continue
		# Check if it has a damage method
		_apply_damage_to_node(body)

func _apply_damage_to_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var hit_direction: Vector2 = Vector2.ZERO
	if node is Node2D:
		hit_direction = ((node as Node2D).global_position - global_position).normalized()
	
	# Try different take_damage signatures
	if node.has_method("take_damage"):
		var method_info = node.get_method_list()
		var arg_count := 1  # Default assumption
		for method in method_info:
			if method["name"] == "take_damage":
				arg_count = method["args"].size()
				break
		
		if arg_count >= 3:
			node.take_damage(damage_per_tick, false, hit_direction)
		elif arg_count >= 2:
			node.take_damage(damage_per_tick, false)
		else:
			node.take_damage(damage_per_tick)
	elif node.has_method("apply_damage"):
		node.apply_damage(damage_per_tick)

func _draw() -> void:
	var progress := clampf(_elapsed / max(duration, 0.01), 0.0, 1.0)
	var fade := 1.0 - progress
	var base_glow := Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * fade * 0.9)
	draw_circle(Vector2.ZERO, radius * 1.15, base_glow)
	var core := Color(color.r, color.g, color.b, color.a * fade)
	draw_circle(Vector2.ZERO, radius, core)
	var ember_alpha := ember_color.a * fade
	for ember_variant in _embers:
		if not (ember_variant is Dictionary):
			continue
		var ember := ember_variant as Dictionary
		var angle: float = float(ember.get("angle", 0.0))
		var offset: float = float(ember.get("offset", 0.5))
		var dist := radius * offset * (0.6 + 0.4 * sin(_elapsed * 3.0 + angle))
		var pos := Vector2(cos(angle), sin(angle)) * dist
		var ember_size := float(ember.get("size", radius * 0.08))
		var flicker := 0.6 + 0.4 * sin(_elapsed * 10.0 + angle * 2.0)
		var ember_col := Color(ember_color.r, ember_color.g, ember_color.b, ember_alpha * flicker)
		draw_circle(pos, ember_size, ember_col)
	var smoke_alpha := smoke_color.a * fade * 0.6
	if smoke_alpha > 0.02:
		draw_circle(Vector2.ZERO, radius * 1.4, Color(smoke_color.r, smoke_color.g, smoke_color.b, smoke_alpha))
	var indicator_color := Color(1.0, 0.2, 0.05, 0.4 * fade)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, indicator_color, 3.0)


func _setup_editor_preview() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
