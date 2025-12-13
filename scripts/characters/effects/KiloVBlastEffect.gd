extends Node2D
class_name KiloVBlastEffect

## V-shaped blast effect for Kilo's special attack
## Creates a short-lived explosion behind the enemy when hit
## Deals damage to enemies caught in the blast

@export var duration: float = 0.35
@export var blast_range: float = 180.0
@export var blast_angle: float = 45.0
@export var blast_damage: int = 4
@export var arm_color: Color = Color(1.0, 0.45, 0.12, 1.0)
@export var core_color: Color = Color(1.0, 0.92, 0.55, 0.95)
@export var fill_color: Color = Color(0.96, 0.3, 0.05, 0.65)

var _age: float = 0.0
var _forward: Vector2 = Vector2.RIGHT
var _base_arm_color: Color = arm_color
var _base_fill_color: Color = fill_color
var _base_core_color: Color = core_color
var _hit_enemies: Array = []  # Track enemies hit to avoid double damage
var owner_node: Node = null
var is_burst: bool = false  # Whether this came from burst (affects burst charge)

func _ready() -> void:
	set_process(true)
	z_index = 420
	queue_redraw()
	# Deal damage on spawn
	_deal_blast_damage()
	
	# Assign to effects layer to avoid night darkening
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
			z_index = 420

func configure(forward: Vector2, range_distance: float, spread_degrees: float, color: Color, p_owner: Node = null, p_is_burst: bool = false, p_scale: float = 1.0) -> void:
	_forward = forward.normalized() if forward.length() > 0.0 else Vector2.RIGHT
	# Apply scale to range (and increase clamp max)
	blast_range = clampf(range_distance * p_scale, 60.0, 800.0) 
	blast_angle = clampf(spread_degrees, 12.0, 90.0)
	owner_node = p_owner
	is_burst = p_is_burst
	arm_color = Color(color.r, color.g, color.b, color.a)
	_base_arm_color = arm_color
	fill_color = Color(color.r * 0.85 + 0.15, color.g * 0.35, color.b * 0.2, clampf(color.a * 0.75, 0.0, 1.0))
	_base_fill_color = fill_color
	_base_core_color = Color(1.0, 0.95, 0.55, clampf(0.9 * color.a + 0.1, 0.0, 1.0))
	queue_redraw()

func _deal_blast_damage() -> void:
	# Find all enemies within the V-shaped blast area
	var half_angle := deg_to_rad(blast_angle * 0.5)
	
	for node in TargetCache.get_enemies():
		if not is_instance_valid(node):
			continue
		if not node.has_method("take_damage"):
			continue
		if _hit_enemies.has(node):
			continue
		
		var to_enemy: Vector2 = node.global_position - global_position
		var dist: float = to_enemy.length()
		
		# Check if within range
		if dist > blast_range:
			continue
		
		# Check if within the V angle
		var angle_to_enemy := _forward.angle_to(to_enemy)
		if absf(angle_to_enemy) > half_angle:
			continue
		
		# Deal damage
		var hit_dir: Vector2 = to_enemy.normalized()
		node.take_damage(blast_damage, false, hit_dir, is_burst)
		_hit_enemies.append(node)

func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var life_ratio: float = 1.0 - clampf(_age / max(duration, 0.001), 0.0, 1.0)
	var eased := pow(life_ratio, 0.45)
	var half_angle := deg_to_rad(blast_angle * 0.5)
	var left_dir := _forward.rotated(-half_angle)
	var right_dir := _forward.rotated(half_angle)
	var left_tip := left_dir * blast_range
	var right_tip := right_dir * blast_range

	_draw_core_flash(life_ratio)
	_draw_fill_sector(left_tip, right_tip, eased)
	_draw_arm(left_dir, left_tip, eased)
	_draw_arm(right_dir, right_tip, eased)

func _draw_core_flash(life_ratio: float) -> void:
	var flash_alpha := clampf(_base_core_color.a * (0.8 + 0.2 * life_ratio), 0.0, 1.0)
	var flash := Color(_base_core_color.r, _base_core_color.g, _base_core_color.b, flash_alpha)
	var radius := blast_range * (0.18 + 0.12 * life_ratio)
	draw_circle(Vector2.ZERO, radius, flash)
	# White glow center
	var white_alpha := clampf(0.9 * (0.6 + 0.4 * life_ratio), 0.0, 1.0)
	var white_glow := Color(1.0, 0.98, 0.9, white_alpha)
	draw_circle(Vector2.ZERO, radius * 0.72, white_glow)

func _draw_fill_sector(left_tip: Vector2, right_tip: Vector2, eased: float) -> void:
	var sector_color := Color(_base_fill_color.r, _base_fill_color.g, _base_fill_color.b, clampf(_base_fill_color.a * eased, 0.0, 1.0))
	var half_length := blast_range * (0.6 + 0.4 * eased)
	var left_point := left_tip.normalized() * half_length
	var right_point := right_tip.normalized() * half_length
	var sector_points := PackedVector2Array([
		Vector2.ZERO,
		left_point,
		right_point
	])
	var sector_colors := PackedColorArray([
		sector_color,
		Color(sector_color.r, sector_color.g, sector_color.b, sector_color.a * 0.8),
		Color(sector_color.r, sector_color.g, sector_color.b, sector_color.a * 0.8)
	])
	draw_polygon(sector_points, sector_colors)

func _draw_arm(_direction: Vector2, tip: Vector2, eased: float) -> void:
	var width: float = max(12.0, blast_range * 0.06) * (0.4 + 0.6 * eased)
	var glow_width: float = width * 1.8
	var arm_alpha := clampf(_base_arm_color.a * (0.65 + 0.35 * eased), 0.0, 1.0)
	var glow_alpha := clampf(arm_color.a * 0.75 * eased, 0.0, 1.0)
	var arm := Color(_base_arm_color.r, _base_arm_color.g, _base_arm_color.b, arm_alpha)
	var highlight_color := Color(1.0, 0.9, 0.6, clampf(0.85 * eased, 0.0, 1.0))
	
	# Glow layer
	draw_line(Vector2.ZERO, tip, Color(arm.r, arm.g, arm.b, glow_alpha), glow_width, true)
	# Main arm
	draw_line(Vector2.ZERO, tip, arm, width, true)
	# Highlight
	draw_line(Vector2.ZERO, tip, highlight_color, max(3.0, width * 0.4), true)
	
	# Sparkles along the arm
	var sparkle_count := 3
	for i in range(sparkle_count):
		var factor := float(i + 1) / float(sparkle_count + 1)
		var pos := tip * factor
		var sparkle_alpha := clampf(highlight_color.a * pow(eased, 0.65), 0.0, 1.0)
		draw_circle(pos, max(4.0, width * 0.2 * (1.0 - factor * 0.4)), Color(highlight_color.r, highlight_color.g, highlight_color.b, sparkle_alpha))
