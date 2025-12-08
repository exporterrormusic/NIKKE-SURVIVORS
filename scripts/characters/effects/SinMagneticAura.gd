extends Node2D
class_name SinMagneticAura

## Sin's "Magnetic Personality" upgrade aura
## Passively charms enemies that get close to the player
## Medium radius, continuous effect

const AURA_RADIUS := 200.0  # Double the original radius for better coverage
const CHARM_INTERVAL := 0.5  # Check for enemies every 0.5s
const AURA_PULSE_DURATION := 1.5  # Visual pulse timing

var player: Node2D = null
var controller: RefCounted = null  # Reference to SinController for talent checks
var _charm_timer: float = 0.0
var _pulse_time: float = 0.0

# Pink/magenta color for the aura (distinct from Sin's purple charm)
const AURA_COLOR := Color(1.0, 0.3, 0.6, 0.3)
const PULSE_COLOR := Color(1.0, 0.5, 0.8, 0.5)

func _ready() -> void:
	top_level = true
	z_index = -1
	
	# Unshaded for visibility
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func initialize(player_ref: Node2D, controller_ref: RefCounted = null) -> void:
	player = player_ref
	controller = controller_ref
	print("[SinMagneticAura] Magnetic Personality aura initialized")

func _process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		queue_free()
		return
	
	# Follow player
	global_position = player.global_position
	
	# Visual pulse
	_pulse_time += delta
	if _pulse_time >= AURA_PULSE_DURATION:
		_pulse_time = 0.0
	
	# Charm check timer
	_charm_timer += delta
	if _charm_timer >= CHARM_INTERVAL:
		_charm_timer = 0.0
		_charm_nearby_enemies()
	
	queue_redraw()

func _charm_nearby_enemies() -> void:
	var tree := get_tree()
	if not tree:
		return
	
	var enemies := tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		# Skip already charmed enemies
		if enemy.is_in_group("charmed_allies"):
			continue
		
		# Skip bosses and elites (they're too powerful to charm passively)
		if enemy.has_meta("is_boss") and enemy.get_meta("is_boss"):
			continue
		if enemy.has_meta("is_elite") and enemy.get_meta("is_elite"):
			continue
		
		# Check for tank tier - only charmable with captivating level 3
		if enemy.has_meta("enemy_tier"):
			var tier = enemy.get_meta("enemy_tier")
			if tier == "tank":
				var can_charm_tanks := false
				if controller and "captivating_level" in controller:
					can_charm_tanks = controller.captivating_level >= 3
				if not can_charm_tanks:
					continue
			if tier in ["elite", "boss", "super_boss"]:
				continue
		
		# Check range
		var dist: float = enemy.global_position.distance_to(global_position)
		if dist > AURA_RADIUS:
			continue
		
		# Charm the enemy!
		_apply_charm_to_enemy(enemy)

func _apply_charm_to_enemy(enemy: Node2D) -> void:
	# Use the same charm system as Sin's normal ability
	# This properly sets up the charmed state and behavior
	
	# Check if this is a tank (needs force=true)
	var is_tank := false
	if enemy.has_meta("enemy_tier") and enemy.get_meta("enemy_tier") == "tank":
		is_tank = true
	
	if enemy.has_method("set_charmed"):
		# Remove from enemies group and add to charmed group
		enemy.remove_from_group("enemies")
		enemy.add_to_group("charmed_allies")
		
		# Set proper charmed state with player as owner (force=true for tanks)
		enemy.set_charmed(player, true, is_tank)
	else:
		# Fallback for enemies without set_charmed method
		enemy.add_to_group("charmed_allies")
		enemy.remove_from_group("enemies")
		_apply_charm_visual(enemy)
	
	print("[SinMagneticAura] Enemy charmed by aura!")

func _apply_charm_visual(enemy: Node2D) -> void:
	# Add a pink glow shader or modulate
	var sprite: Node = enemy.get_node_or_null("Sprite2D")
	if not sprite:
		sprite = enemy.get_node_or_null("AnimatedSprite2D")
	
	if sprite and sprite is CanvasItem:
		# Create pink tint shader
		var shader_mat := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;
uniform vec4 tint_color : source_color = vec4(1.0, 0.4, 0.7, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.5;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = mix(tex, vec4(tint_color.rgb, tex.a), intensity);
}
"""
		shader_mat.shader = shader
		shader_mat.set_shader_parameter("tint_color", Color(1.0, 0.4, 0.7, 1.0))
		shader_mat.set_shader_parameter("intensity", 0.4)
		sprite.material = shader_mat

func _draw() -> void:
	# Draw aura circle
	var pulse_factor: float = sin(_pulse_time / AURA_PULSE_DURATION * TAU) * 0.5 + 0.5
	
	# Outer ring
	var outer_color := AURA_COLOR
	outer_color.a = 0.15 + pulse_factor * 0.15
	draw_arc(Vector2.ZERO, AURA_RADIUS, 0.0, TAU, 48, outer_color, 3.0, true)
	
	# Inner glow ring
	var inner_radius: float = AURA_RADIUS * (0.7 + pulse_factor * 0.1)
	var inner_color := PULSE_COLOR
	inner_color.a = 0.1 + pulse_factor * 0.2
	draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, 32, inner_color, 2.0, true)
	
	# Hearts particles around edge (for "magnetic personality" theme)
	var heart_count := 3
	for i in range(heart_count):
		var angle: float = (_pulse_time / AURA_PULSE_DURATION + float(i) / float(heart_count)) * TAU
		var pos := Vector2(cos(angle), sin(angle)) * (AURA_RADIUS - 10)
		_draw_heart(pos, 6.0, PULSE_COLOR)

func _draw_heart(center: Vector2, size: float, color: Color) -> void:
	# Simple heart shape using circles and triangle
	var half := size * 0.5
	draw_circle(center + Vector2(-half * 0.5, -half * 0.3), half * 0.5, color)
	draw_circle(center + Vector2(half * 0.5, -half * 0.3), half * 0.5, color)
	var points := PackedVector2Array([
		center + Vector2(-size * 0.5, 0),
		center + Vector2(size * 0.5, 0),
		center + Vector2(0, size * 0.7)
	])
	draw_colored_polygon(points, color)
