extends Node2D

# Heals player 10% of max HP every 3 seconds if within range
# Lasts for 9 seconds total

@export var heal_interval: float = 1.0
@export var heal_percent: float = 0.03
@export var lifespan: float = 9.0
@export var heal_radius: float = 180.0 # Bigger healing area
var burn_enabled: bool = false
var burn_percent: float = 0.03 # Can be overridden by controller (uses heal_percent logic)

var _lifetime: float = 0.0
var _heal_timer: float = 0.0
var _player: Node = null
var _rng := RandomNumberGenerator.new()
var _sparkles: Array = []
var _rays: Array = []

# Visual colors - heavenly golden theme
var cross_color := Color(1.0, 0.9, 0.5, 1.0) # Bright golden
var glow_color := Color(1.0, 0.95, 0.7, 0.5) # Warm heavenly glow
var zone_color := Color(1.0, 0.98, 0.8, 0.12) # Soft golden zone
var sparkle_color := Color(1.0, 1.0, 0.9, 0.9) # White-gold sparkles
var ray_color := Color(1.0, 0.95, 0.6, 0.3) # Radiating light rays

func _ready():
	# Find the player in the scene
	_player = get_parent().get_node_or_null("Player")
	# Set up additive blend for glow effect
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	
	_rng.randomize()
	# Initialize sparkles
	for i in range(12):
		_sparkles.append({
			"angle": _rng.randf() * TAU,
			"dist": _rng.randf_range(0.3, 0.9),
			"speed": _rng.randf_range(0.5, 1.5),
			"size": _rng.randf_range(3.0, 7.0),
			"phase": _rng.randf() * TAU
		})
	# Initialize light rays
	for i in range(8):
		_rays.append({
			"angle": i * TAU / 8.0 + _rng.randf_range(-0.1, 0.1),
			"length": _rng.randf_range(0.6, 1.0),
			"width": _rng.randf_range(8.0, 16.0),
			"phase": _rng.randf() * TAU
		})

func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= lifespan:
		queue_free()
		return
	
	_heal_timer += delta
	if _heal_timer >= heal_interval:
		_heal_timer = 0.0
		_try_heal_player()
		if burn_enabled:
			_try_burn_enemies()
	
	# Update sparkles
	for i in range(_sparkles.size()):
		var s = _sparkles[i]
		s["angle"] += delta * s["speed"]
		_sparkles[i] = s
	
	# Redraw for pulsing effect
	queue_redraw()

func _try_heal_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_parent().get_node_or_null("Player")
	if _player == null:
		return
	
	var dist = global_position.distance_to(_player.global_position)
	if dist <= heal_radius:
		# Heal 10% of max HP
		if _player.has_method("heal"):
			var heal_amount = int(ceil(_player.max_hp * heal_percent))
			_player.heal(heal_amount)

func _try_burn_enemies() -> void:
	# Burn enemies within radius
	var enemies = TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
			
		var dist = global_position.distance_to(enemy.global_position)
		if dist <= heal_radius:
			if enemy.has_method("take_damage"):
				# Calculate burn damage
				# Use current heal_percent as base (matches "same amount it would heal")
				var dmg_pct = heal_percent
				
				# Cap boss damage at 3%
				if enemy.is_in_group("bosses") or enemy.is_in_group("guardian_bosses") or enemy.is_in_group("gbosses"):
					dmg_pct = min(dmg_pct, 0.03)
				
				# Apply damage based on ENEMY max HP
				var max_hp = enemy.get("max_hp")
				if max_hp == null and enemy.has_method("get_max_hp"):
					max_hp = enemy.get_max_hp()
				
				if max_hp:
					# BALANCE FIX: Probabilistic damage with Bad Luck Protection
					# 1. Calculate base fractional damage (e.g. 0.03)
					# 2. Add accumulated "luck" multiplier from metadata
					# 3. If roll fails, multiply luck by 5 (exponential boost to guarantee hit soon)
					var expected_damage = float(max_hp) * dmg_pct
					var damage = int(floor(expected_damage))
					var remainder = expected_damage - damage
					
					# Retrieve luck multiplier (default 1.0)
					var luck_mult: float = enemy.get_meta("rapunzel_burn_luck", 1.0)
					
					# effective_chance scales with luck
					# For 1HP unit: 0.03 * 1 -> 0.03 * 5 -> 0.03 * 25 (0.75) -> 0.03 * 125 (Guaranteed)
					var effective_chance = remainder * luck_mult
					
					if randf() < effective_chance:
						damage += 1
						# Reset luck on success
						enemy.set_meta("rapunzel_burn_luck", 1.0)
					else:
						# Increase luck on failure (x5 exponential boost)
						if remainder > 0:
							enemy.set_meta("rapunzel_burn_luck", luck_mult * 5.0)
					
					if damage > 0:
						enemy.take_damage(damage)
					
					# Spawn hit effect if possible? Can overload visuals.
					# Just rely on damage numbers floating up (take_damage usually handles this)

func _draw() -> void:
	var pulse = 0.7 + 0.3 * sin(_lifetime * 2.5)
	var pulse_fast = 0.8 + 0.2 * sin(_lifetime * 5.0)
	var fade = 1.0 - (_lifetime / lifespan) * 0.25 # Slight fade near end
	
	# Draw radiating light rays (heavenly beams)
	_draw_light_rays(pulse, fade)
	
	# Draw outer glow rings (multiple layers for soft radiance)
	for i in range(3):
		var ring_radius = heal_radius * (0.4 + i * 0.3)
		var ring_alpha = glow_color.a * pulse * fade * (0.3 - i * 0.08)
		draw_circle(Vector2.ZERO, ring_radius, Color(glow_color.r, glow_color.g, glow_color.b, ring_alpha))
	
	# Draw healing zone (soft golden fill)
	var zone_alpha = zone_color.a * pulse * fade
	draw_circle(Vector2.ZERO, heal_radius, Color(zone_color.r, zone_color.g, zone_color.b, zone_alpha))
	
	# Draw central glow
	var central_glow = Color(1.0, 0.98, 0.85, 0.6 * pulse * fade)
	draw_circle(Vector2.ZERO, 50.0, central_glow)
	draw_circle(Vector2.ZERO, 30.0, Color(1.0, 1.0, 0.95, 0.7 * pulse * fade))
	
	# Draw golden cross (Christian/Latin cross style - vertical longer than horizontal)
	var cross_alpha = cross_color.a * fade
	var cc = Color(cross_color.r, cross_color.g, cross_color.b, cross_alpha)
	var vert_length = 32.0 # Vertical arm (longer)
	var horiz_length = 22.0 # Horizontal arm (shorter)
	var arm_width = 8.0
	var cross_offset_y = 4.0 # Offset so horizontal bar is higher (like a Latin cross)
	
	# Vertical bar with glow (full length)
	draw_rect(Rect2(-arm_width / 2 - 2, -vert_length - 2, arm_width + 4, vert_length * 2 + 4), Color(1.0, 0.95, 0.7, 0.4 * fade))
	draw_rect(Rect2(-arm_width / 2, -vert_length, arm_width, vert_length * 2), cc)
	# Horizontal bar with glow (positioned higher on the vertical)
	draw_rect(Rect2(-horiz_length - 2, -cross_offset_y - vert_length * 0.35 - arm_width / 2 - 2, horiz_length * 2 + 4, arm_width + 4), Color(1.0, 0.95, 0.7, 0.4 * fade))
	draw_rect(Rect2(-horiz_length, -cross_offset_y - vert_length * 0.35 - arm_width / 2, horiz_length * 2, arm_width), cc)
	
	# Bright center (pulsing)
	draw_circle(Vector2.ZERO, 10.0 * pulse_fast, Color(1.0, 1.0, 1.0, cross_alpha))
	draw_circle(Vector2.ZERO, 6.0, Color(1.0, 1.0, 0.95, cross_alpha))
	
	# Draw heavenly sparkles
	_draw_sparkles(pulse_fast, fade)
	
	# Zone border ring (gently pulsing golden)
	var ring_color = Color(1.0, 0.95, 0.6, 0.35 * pulse * fade)
	_draw_ring(Vector2.ZERO, heal_radius, ring_color, 3.0)
	# Inner decorative ring
	_draw_ring(Vector2.ZERO, heal_radius * 0.7, Color(1.0, 0.98, 0.8, 0.2 * pulse * fade), 1.5)

func _draw_light_rays(pulse: float, fade: float) -> void:
	for ray in _rays:
		var ray_pulse = 0.6 + 0.4 * sin(_lifetime * 1.5 + ray["phase"])
		var ray_alpha = ray_color.a * ray_pulse * fade * pulse
		var ray_len = heal_radius * ray["length"] * ray_pulse
		var angle = ray["angle"]
		var width = ray["width"] * ray_pulse
		
		# Draw tapered ray from center outward
		var inner_pt = Vector2.ZERO
		var outer_pt = Vector2(cos(angle), sin(angle)) * ray_len
		var perp = Vector2(-sin(angle), cos(angle))
		
		var points = PackedVector2Array([
			inner_pt + perp * (width * 0.3),
			inner_pt - perp * (width * 0.3),
			outer_pt - perp * (width * 0.1),
			outer_pt + perp * (width * 0.1)
		])
		var colors = PackedColorArray([
			Color(ray_color.r, ray_color.g, ray_color.b, ray_alpha),
			Color(ray_color.r, ray_color.g, ray_color.b, ray_alpha),
			Color(ray_color.r, ray_color.g, ray_color.b, ray_alpha * 0.2),
			Color(ray_color.r, ray_color.g, ray_color.b, ray_alpha * 0.2)
		])
		draw_polygon(points, colors)

func _draw_sparkles(pulse: float, fade: float) -> void:
	for s in _sparkles:
		var sparkle_pulse = 0.5 + 0.5 * sin(_lifetime * 4.0 + s["phase"])
		var pos = Vector2(cos(s["angle"]), sin(s["angle"])) * heal_radius * s["dist"]
		var size = s["size"] * sparkle_pulse * pulse
		var alpha = sparkle_color.a * sparkle_pulse * fade
		
		# Draw 4-point star sparkle
		var sc = Color(sparkle_color.r, sparkle_color.g, sparkle_color.b, alpha)
		draw_line(pos - Vector2(size, 0), pos + Vector2(size, 0), sc, 2.0, true)
		draw_line(pos - Vector2(0, size), pos + Vector2(0, size), sc, 2.0, true)
		# Diagonal arms (smaller)
		var diag = size * 0.6
		draw_line(pos - Vector2(diag, diag), pos + Vector2(diag, diag), sc, 1.5, true)
		draw_line(pos - Vector2(diag, -diag), pos + Vector2(diag, -diag), sc, 1.5, true)

func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments = 48
	var prev_pt = center + Vector2(radius, 0)
	for i in range(1, segments + 1):
		var angle = TAU * i / segments
		var pt = center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(prev_pt, pt, color, width, true)
		prev_pt = pt
