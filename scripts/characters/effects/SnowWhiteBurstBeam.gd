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

# Player level for damage scaling
var player_level: int = 1

# Talent bonuses
var burn_level: int = 0          # Incendiary Rounds rank (1-3)
var gauge_level: int = 0         # Fully Active rank (1-3) -> chance per kill
var gauge_per_kill: float = 0.0  # normal burst gain granted per successful kill-roll
var pierce_level: int = 0        # Pierce Through rank -> Weak Point mult
var stun_level: int = 0          # Stunned rank -> stun duration
var damage_multiplier: float = 1.0 # Focused Fire concentrated-beam damage scaling
var _enemies_killed: int = 0

const PIERCE_MULTS := [2.0, 4.0, 6.0]
const STUN_DURS := [2.0, 5.0, 7.0]
const GAUGE_CHANCES := [0.33, 0.66, 1.0]
const BURN_RATES := [0.10, 0.20, 0.30]
const BURN_BOSS_RATES := [0.05, 0.10, 0.15]

# Source identification for Shield/Burst logic
var source: String = "SnowWhiteBurst"
var killer_source: String = "SnowWhiteBurst"

func _ready() -> void:
	set_physics_process(true)
	set_process(false)
	set_notify_transform(true)
	z_index = 420
	# Assign to effects layer so beam glows at night
	call_deferred("_assign_to_effects_layer")
	queue_redraw()

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
			z_index = 420

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

func _physics_process(delta: float) -> void:
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
	
	# Damage scales off the player's attack (set by the controller) and the
	# Focused Fire concentrated-beam multiplier. No level scaling.
	var scaled_damage := int(damage * damage_multiplier)

	# Track enemies for burn and kill counting
	var hit_enemies: Array[Node2D] = []
	var hit_shields: Dictionary = {} # Track unique shields hit to prevent multi-damage
	var gauge_gain := 0.0 # Fully Active: accumulated burst refund
	
	# Find all enemies in scene
	var enemies = TargetCache.get_enemies()
	var space_state = get_world_2d().direct_space_state
	
	for node in enemies:
		if not is_instance_valid(node):
			continue
		if not node is Node2D:
			continue
			
		# Skip charmed allies (Sin's mind control)
		if node.is_in_group("charmed_allies"):
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
			
		# Check line of sight (Blockable by Shields on Layer 16 + World Layer 1)
		var query = PhysicsRayQueryParameters2D.create(global_position, enemy.global_position)
		query.collision_mask = 1 | 16 # World + Shields
		query.collide_with_areas = true
		query.collide_with_bodies = false
		
		var result = space_state.intersect_ray(query)
		if result:
			var collider = result.collider
			print("[SnowWhiteBeam] Ray hit: ", collider.name, " parent: ", collider.get_parent().name)
			
			# Identify shield root
			var shield_root = collider.get_parent()
			
			# Deal damage to shield (ONE TIME per burst)
			if shield_root.has_method("take_shield_damage"):
				var shield_id = shield_root.get_instance_id()
				if not hit_shields.has(shield_id):
					print("[SnowWhiteBeam] Damaging Shield: ", shield_root.name)
					shield_root.take_shield_damage(scaled_damage, "SnowWhiteBurst")
					hit_shields[shield_id] = true
			
			# BLOCK the hit on the enemy (Snow White's beam does not pierce shields)
			continue
		
		hit_enemies.append(enemy)

		# Apply damage with hit direction
		var hit_direction := to_enemy.normalized()
		var enemy_hp_before := 0
		if "hp" in enemy:
			enemy_hp_before = enemy.hp

		# Pierce Through: permanent Weak Point mark (set before damage so this hit
		# benefits too). Stunned: stun on hit.
		if pierce_level > 0:
			enemy.set_meta("damage_vulnerability", PIERCE_MULTS[mini(pierce_level, 3) - 1])
		if stun_level > 0 and enemy.has_method("apply_stun"):
			enemy.apply_stun(STUN_DURS[mini(stun_level, 3) - 1])

		# Determine source
		var damage_source: String = "SnowWhiteBurst"
		if owner_node and (owner_node.is_in_group("summoned_allies") or owner_node.name.contains("SummonedAlly")):
			damage_source = "summon"

		if enemy.has_method("take_damage"):
			enemy.take_damage(scaled_damage, false, hit_direction, true, damage_source) # from_burst = true
		elif enemy.has_method("apply_damage_with_source"):
			enemy.apply_damage_with_source(scaled_damage, damage_source)
		elif enemy.has_method("apply_damage"):
			enemy.apply_damage(scaled_damage, damage_source)

		# Check if enemy was killed; Fully Active rolls per kill to refund gauge.
		if "hp" in enemy and enemy.hp <= 0 and enemy_hp_before > 0:
			_enemies_killed += 1
			if gauge_level > 0 and randf() < GAUGE_CHANCES[mini(gauge_level, 3) - 1]:
				gauge_gain += gauge_per_kill

	
	# Apply frostburn DOT to surviving enemies if talent is unlocked
	if burn_level > 0:
		for enemy in hit_enemies:
			if is_instance_valid(enemy) and "hp" in enemy and enemy.hp > 0:
				_apply_frostburn(enemy)
	
	# Fully Active: grant the accumulated burst refund (enables chaining).
	if gauge_gain > 0.0 and is_instance_valid(owner_node):
		if owner_node.has_method("add_burst_charge"):
			owner_node.add_burst_charge(gauge_gain)
		elif owner_node.has_method("gain_burst"):
			owner_node.gain_burst(gauge_gain)

func _apply_frostburn(enemy: Node2D) -> void:
	"""Apply frostburn DOT based on talent level."""
	if not is_instance_valid(enemy) or not "max_hp" in enemy:
		return
	
	# Incendiary Rounds: 10/20/30% max HP/s for normal, 5/10/15% for bosses, over 3s.
	var is_boss: bool = enemy.has_meta("enemy_tier") and enemy.get_meta("enemy_tier") == "boss"
	var idx := mini(burn_level, 3) - 1
	var burn_rate: float = BURN_BOSS_RATES[idx] if is_boss else BURN_RATES[idx]
	var burn_duration := 3.0
	var damage_per_tick := int(enemy.max_hp * burn_rate) # Per second
	
	# Create burn effect node
	var burn := Node.new()
	burn.set_script(preload("res://scripts/effects/visuals/BurnTickEffect.gd"))
	burn.name = "Frostburn"
	burn.set("damage_per_second", damage_per_tick)
	burn.set("duration", burn_duration)
	burn.set("owner_node", owner_node)
	burn.set("damage_source", "SnowWhiteBurst")
	enemy.add_child(burn)

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
		{"color": outer_color, "scale": 1.0},
		{"color": mid_color, "scale": 0.88},
		{"color": inner_color, "scale": 0.76},
		{"color": core_color, "scale": 0.62}
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
