extends Node2D
class_name SnowWhiteBurstBeam

## Wide cone beam burst effect for Snow White
## Deals massive damage to all enemies within the cone
## With Frostburn talent: applies burn DOT for 3s (% max HP/s)
## With Soul Harvest talent: kills generate burst gauge

@export var duration: float = 0.8
@export var beam_range: float = 1200.0
@export var beam_angle_degrees: float = 90.0
@export var damage: int = 50

@export var outer_color: Color = Color(0.55, 0.75, 1.0, 0.5)
@export var mid_color: Color = Color(0.68, 0.85, 1.0, 0.65)
@export var inner_color: Color = Color(0.82, 0.94, 1.0, 0.8)
@export var core_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export_range(6, 96, 1) var arc_steps: int = 32

var owner_node: Node = null
var _age: float = 0.0
var _forward: Vector2 = Vector2.RIGHT
var _has_dealt_damage: bool = false

# Talent bonuses
var burn_level: int = 0  # 0=none, 1-3=talent level for frostburn
var gauge_on_kill: bool = false  # Soul Harvest talent
var _enemies_killed: int = 0  # Track kills for gauge generation

func _ready() -> void:
	set_process(true)
	set_notify_transform(true)
	z_index = 420
	queue_redraw()

func configure(forward: Vector2, range_distance: float = -1.0, angle_degrees: float = -1.0, colors: Dictionary = {}) -> void:
	_forward = forward.normalized() if forward.length() > 0.0 else Vector2.RIGHT
	if range_distance > 0:
		beam_range = clampf(range_distance, 200.0, 2400.0)
	if angle_degrees > 0:
		beam_angle_degrees = clampf(angle_degrees, 5.0, 170.0)
	if not colors.is_empty():
		outer_color = colors.get("outer", outer_color)
		mid_color = colors.get("mid", mid_color)
		inner_color = colors.get("inner", inner_color)
		core_color = colors.get("core", core_color)
		flash_color = colors.get("flash", flash_color)
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	
	# Deal damage once at the start
	if not _has_dealt_damage:
		_has_dealt_damage = true
		_apply_cone_damage()
	
	if _age >= duration:
		queue_free()
		return
	queue_redraw()

func _apply_cone_damage() -> void:
	var parent := get_parent()
	if parent == null:
		return
	
	var base_angle := _forward.angle()
	var half_angle := deg_to_rad(beam_angle_degrees * 0.5)
	var range_sq := beam_range * beam_range
	
	# Track enemies for burn and kill counting
	var hit_enemies: Array[Node2D] = []
	
	# Find all enemies in scene
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		if not node is Node2D:
			continue
		
		var enemy := node as Node2D
		var to_enemy := enemy.global_position - global_position
		var distance_sq := to_enemy.length_squared()
		
		# Check if within range
		if distance_sq > range_sq:
			continue
		
		# Check if within cone angle
		var angle_to_enemy := to_enemy.angle()
		var angle_diff: float = abs(wrapf(angle_to_enemy - base_angle, -PI, PI))
		if angle_diff > half_angle:
			continue
		
		hit_enemies.append(enemy)
		
		# Apply damage with hit direction
		var hit_direction := to_enemy.normalized()
		var enemy_hp_before := 0
		if "hp" in enemy:
			enemy_hp_before = enemy.hp
		
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, false, hit_direction)
		elif enemy.has_method("apply_damage"):
			enemy.apply_damage(damage)
		
		# Check if enemy was killed
		if "hp" in enemy and enemy.hp <= 0 and enemy_hp_before > 0:
			_enemies_killed += 1
		
		# Register burst hit for points
		if owner_node and owner_node.has_method("register_burst_hit"):
			owner_node.register_burst_hit(enemy, true)  # from_burst = true
	
	# Apply frostburn DOT to surviving enemies if talent is unlocked
	if burn_level > 0:
		for enemy in hit_enemies:
			if is_instance_valid(enemy) and "hp" in enemy and enemy.hp > 0:
				_apply_frostburn(enemy)
	
	# Grant burst gauge for kills if Soul Harvest is unlocked
	if gauge_on_kill and _enemies_killed > 0 and owner_node:
		# Each kill adds to burst gauge (10 per kill)
		if "burst_current" in owner_node:
			owner_node.burst_current = mini(owner_node.burst_current + _enemies_killed * 10, owner_node.burst_max)
			if owner_node.has_method("_update_burst_bar"):
				owner_node._update_burst_bar()

func _apply_frostburn(enemy: Node2D) -> void:
	"""Apply frostburn DOT based on talent level."""
	if not is_instance_valid(enemy) or not "max_hp" in enemy:
		return
	
	# Burn rates: 10/25/33.4% max HP/s for normal, 4/8/12% for elite/boss
	var burn_rates := [0.0, 0.10, 0.25, 0.334]  # Per second
	var elite_rates := [0.0, 0.04, 0.08, 0.12]  # Reduced for elite/boss
	
	var is_elite_or_boss: bool = enemy.has_meta("enemy_tier") and enemy.get_meta("enemy_tier") in ["elite", "boss", "tank"]
	var burn_rate: float = elite_rates[burn_level] if is_elite_or_boss else burn_rates[burn_level]
	var burn_duration := 3.0
	var damage_per_tick := int(enemy.max_hp * burn_rate)  # Per second
	
	# Create burn effect node
	var burn := Node.new()
	burn.set_script(_get_burn_script())
	burn.name = "Frostburn"
	burn.set("damage_per_second", damage_per_tick)
	burn.set("duration", burn_duration)
	burn.set("owner_node", owner_node)
	enemy.add_child(burn)

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
		parent.take_damage(tick_damage, false, Vector2.ZERO)
	elif \"hp\" in parent:
		parent.hp -= tick_damage
		if parent.hp <= 0 and parent.has_method(\"die\"):
			parent.die()
"""
	script.reload()
	return script

func _draw() -> void:
	if duration <= 0.0:
		return
	var progress := clampf(_age / max(duration, 0.0001), 0.0, 1.0)
	var alpha_multiplier := _alpha_from_progress(progress)
	if alpha_multiplier <= 0.01:
		return
	_draw_beam_layers(alpha_multiplier)

func _alpha_from_progress(progress: float) -> float:
	# Quick fade in, hold, then fade out
	if progress < 0.1:
		return lerpf(0.0, 1.0, progress / 0.1)
	if progress < 0.5:
		return 1.0
	return lerpf(1.0, 0.0, (progress - 0.5) / 0.5)

func _draw_beam_layers(alpha_multiplier: float) -> void:
	var base_angle := _forward.angle()
	var total_angle := deg_to_rad(beam_angle_degrees)
	
	# Build arc points
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(arc_steps + 1):
		var t := float(i) / float(max(arc_steps, 1))
		var angle := base_angle - total_angle * 0.5 + total_angle * t
		var direction := Vector2.RIGHT.rotated(angle)
		points.append(direction * beam_range)
	
	# Draw layers from outer to inner
	var layer_settings := [
		{ "color": outer_color, "scale": 1.0 },
		{ "color": mid_color, "scale": 0.88 },
		{ "color": inner_color, "scale": 0.76 },
		{ "color": core_color, "scale": 0.62 }
	]
	
	for settings in layer_settings:
		var color: Color = settings["color"]
		var layer_scale: float = settings["scale"]
		var final_color := Color(color.r, color.g, color.b, color.a * alpha_multiplier)
		if final_color.a <= 0.01:
			continue
		var scaled := PackedVector2Array()
		for point in points:
			scaled.append(point * layer_scale)
		var colors := PackedColorArray()
		colors.resize(scaled.size())
		for index in range(scaled.size()):
			colors[index] = final_color
		draw_polygon(scaled, colors)
	
	_draw_edge_highlights(points, alpha_multiplier)

func _draw_edge_highlights(points: PackedVector2Array, alpha_multiplier: float) -> void:
	if points.size() < 3:
		return
	
	var outline_color := Color(inner_color.r, inner_color.g, inner_color.b, inner_color.a * 0.55 * alpha_multiplier)
	var base_angle := _forward.angle()
	var total_angle := deg_to_rad(beam_angle_degrees)
	
	# Draw edge lines
	var left_dir := Vector2.RIGHT.rotated(base_angle - total_angle * 0.5)
	var right_dir := Vector2.RIGHT.rotated(base_angle + total_angle * 0.5)
	draw_line(Vector2.ZERO, left_dir * beam_range, outline_color, max(8.0, beam_range * 0.012), true)
	draw_line(Vector2.ZERO, right_dir * beam_range, outline_color, max(8.0, beam_range * 0.012), true)
	
	# Draw shimmer circles along arc
	var shimmer_color := Color(core_color.r, core_color.g, core_color.b, core_color.a * 0.8 * alpha_multiplier)
	var segments := 6
	for index in range(segments):
		var fraction := (float(index) + 1.0) / (float(segments) + 1.0)
		var midpoint_a := left_dir.lerp(right_dir, fraction) * beam_range
		var midpoint_b := midpoint_a * 0.7
		draw_circle(midpoint_a, beam_range * 0.045, shimmer_color)
		draw_circle(midpoint_b, beam_range * 0.035, shimmer_color * Color(1.0, 1.0, 1.0, 0.6))
