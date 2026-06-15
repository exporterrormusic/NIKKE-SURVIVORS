extends Node2D
class_name BurstTurret

## Simplified turret specifically for Rapunzel's "6000? Really?" burst talent
## Minimal visual overhead - no complex _draw(), just a simple static appearance
## Fires rockets with staggered timing then self-destructs

var ammo := 4
var max_ammo := 4
var spawner_node: Node = null # For killer_source tracking
var fire_delay := 0.0 # Initial delay before first shot

# Minimal state
var _fire_timer: Timer = null
var _rng := RandomNumberGenerator.new()
var _current_angle := 0.0
var _target: Node2D = null
var _scan_phase := 0 # De-syncs enemy scans so 20 turrets don't all scan the same frame

# 2x the size of Snow White's turrets, gold energy styling
const TURRET_COLOR := Color(0.4, 0.38, 0.45, 0.95) # Gunmetal
const ACCENT_COLOR := Color(1.0, 0.82, 0.35, 0.95) # Rapunzel gold
const BARREL_COLOR := Color(0.25, 0.25, 0.3, 1.0) # Dark barrel
const GLOW_COLOR := Color(1.0, 0.8, 0.4) # Soft gold halo
const BASE_SIZE := 32.0

# One unshaded material shared by all turrets (was per-instance)
static var _shared_unshaded_mat: CanvasItemMaterial = null

func _ready() -> void:
	_rng.randomize()
	_scan_phase = _rng.randi_range(0, 29)
	z_index = 50

	# Unshaded so it's visible at night
	if _shared_unshaded_mat == null:
		_shared_unshaded_mat = CanvasItemMaterial.new()
		_shared_unshaded_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = _shared_unshaded_mat

	# Energy pulse via modulate (no redraw cost)
	var pulse := create_tween().set_loops()
	pulse.tween_property(self, "self_modulate", Color(1.35, 1.28, 1.1), 0.45).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(self, "self_modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)
	
	# Setup fire timer - fires every 0.8 seconds for faster action
	_fire_timer = Timer.new()
	_fire_timer.wait_time = 0.8
	_fire_timer.one_shot = false
	add_child(_fire_timer)
	_fire_timer.timeout.connect(_shoot)
	
	# Apply fire_delay to stagger initial shots
	if fire_delay > 0.0:
		get_tree().create_timer(fire_delay).timeout.connect(func(): _fire_timer.start())
	else:
		var random_delay = _rng.randf_range(0.0, 0.2)
		get_tree().create_timer(random_delay).timeout.connect(func(): _fire_timer.start())
	
	queue_redraw()

func _process(_delta: float) -> void:
	# Minimal processing - just rotate toward nearest enemy occasionally.
	# _scan_phase staggers the scans across turrets.
	if (Engine.get_process_frames() + _scan_phase) % 30 == 0:
		_find_target()

	if _target and is_instance_valid(_target):
		var to_target = (_target.global_position - global_position).normalized()
		var new_angle: float = to_target.angle()
		# Only redraw when the barrel visibly moves
		if absf(angle_difference(new_angle, _current_angle)) > 0.02:
			_current_angle = new_angle
			queue_redraw()

func _find_target() -> void:
	var enemies = TargetCache.get_enemies()
	var closest: Node2D = null
	var min_dist_sq := INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		var dist_sq = global_position.distance_squared_to(enemy.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest = enemy
	
	_target = closest

func _draw() -> void:
	# Soft gold glow halo (pulsed via self_modulate tween)
	draw_circle(Vector2.ZERO, BASE_SIZE * 2.0, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.08))
	draw_circle(Vector2.ZERO, BASE_SIZE * 1.5, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.14))
	draw_circle(Vector2.ZERO, BASE_SIZE * 1.15, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.2))

	# Hex body
	var points := PackedVector2Array()
	for i in range(6):
		var angle := TAU * i / 6.0
		points.append(Vector2(cos(angle), sin(angle)) * BASE_SIZE)
	draw_colored_polygon(points, TURRET_COLOR)

	# Outer ring
	draw_arc(Vector2.ZERO, BASE_SIZE, 0, TAU, 12, ACCENT_COLOR, 3.0)

	# Barrel
	var barrel_dir := Vector2.from_angle(_current_angle)
	draw_line(Vector2.ZERO, barrel_dir * (BASE_SIZE + 28.0), BARREL_COLOR, 8.0)
	draw_line(Vector2.ZERO, barrel_dir * (BASE_SIZE + 28.0), ACCENT_COLOR, 5.0)

	# Center pivot
	draw_circle(Vector2.ZERO, 9.0, BARREL_COLOR)
	draw_circle(Vector2.ZERO, 6.0, ACCENT_COLOR)

func _shoot() -> void:
	if ammo <= 0:
		return
	
	# Get enemies for targeting
	var enemies = TargetCache.get_enemies()
	if enemies.is_empty():
		return
	
	# Sort by distance
	var sorted_enemies: Array[Node2D] = []
	for e in enemies:
		if is_instance_valid(e) and e is Node2D:
			sorted_enemies.append(e)
	sorted_enemies.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	
	if sorted_enemies.is_empty():
		return
	
	# Fire 1 rocket per shot (reduced from 2)
	ammo -= 1
	
	var rocket = ProjectileCache.create_rocket()
	get_parent().add_child(rocket)
	
	# Fire from center
	rocket.global_position = global_position
	
	var target = sorted_enemies[0]
	var target_pos = target.global_position
	var dir = (target_pos - global_position).normalized()
	rocket.direction = dir
	rocket.target_position = target_pos # Tell rocket where to explode
	rocket.explode_at_target = true # Explode when reaching target
	rocket.rotation = dir.angle()
	
	# Performance optimizations
	if is_instance_valid(spawner_node):
		rocket.owner_node = spawner_node
		rocket.killer_source_override = "rapunzel_burst"
	rocket.homing_enabled = false
	rocket.target_node = null
	rocket.exhaust_enabled = false
	rocket.trail_enabled = false
	rocket.smoke_enabled = false
	rocket.lightweight_mode = true
	rocket.scale = Vector2(0.8, 0.8) # 2x the old burst-turret rockets
	rocket.explosion_glow_boost = 1.6 # Brighter, more dramatic blasts
	rocket.ground_fire_enabled = false
	
	# Simple damage calculation
	var player_node = get_parent().get_node_or_null("Player")
	if player_node and player_node.has_method("calc_damage"):
		var turret_damage: int = maxi(1, int(player_node.calc_damage() * 0.4))
		rocket.damage = turret_damage
		rocket.explosion_damage = turret_damage
	else:
		rocket.damage = 2
		rocket.explosion_damage = 2
	rocket.explosion_radius = 100.0 # 2x blast
	
	# Check if out of ammo
	if ammo <= 0:
		_spawn_minimal_destruction()
		queue_free()

func _spawn_minimal_destruction() -> void:
	# Minimal destruction effect - just 4 sparks instead of 12
	for i in range(4):
		var spark := _create_simple_spark()
		get_parent().add_child(spark)
		spark.global_position = global_position

func _create_simple_spark() -> Node2D:
	# Create a minimal spark that just fades out
	var spark := Node2D.new()
	spark.set_script(preload("res://scripts/player/TurretSpark.gd"))
	return spark
