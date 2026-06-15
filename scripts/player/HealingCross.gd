extends Node2D

# Heals player 10% of max HP every 3 seconds if within range
# Lasts for 9 seconds total

@export var heal_interval: float = 1.0
@export var heal_percent: float = 0.03
@export var lifespan: float = 9.0
@export var heal_radius: float = 180.0 # Bigger healing area
var burn_enabled: bool = false
var burn_percent: float = 0.03 # Can be overridden by controller (uses heal_percent logic)
var burn_damage_mult: float = 1.0 # "More, more!" - multiplies the burn damage
var stun_duration: float = 0.0 # "Oooh, Ahhhh" - stun seconds on an enemy's first hit from this aura
# "Personal Toy": a blessing aura that follows the player and never expires.
var follow_target: Node2D = null
var persistent: bool = false
var active: bool = true # When false the aura is hidden and does nothing (Personal Toy gating)
# Meta key marking an enemy already stunned by THIS aura. Unique per aura instance,
# and cleared on enemy reset() so a fresh (or pooled-reused) enemy can be stunned again.
@onready var _stun_meta_key: String = "blessing_stun_%d" % get_instance_id()

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
	# Personal Toy aura tracks the player.
	if follow_target and is_instance_valid(follow_target):
		global_position = follow_target.global_position

	# Inactive Personal Toy aura: hidden, no heal/burn.
	if not active:
		if visible:
			visible = false
		return
	if not visible:
		visible = true

	_lifetime += delta
	if not persistent and _lifetime >= lifespan:
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

## The HP the blessing heals per tick — also the basis for its burn damage.
func _resolve_player() -> Node:
	if follow_target and is_instance_valid(follow_target):
		return follow_target
	if _player == null or not is_instance_valid(_player):
		_player = get_parent().get_node_or_null("Player")
	return _player

func _heal_amount() -> int:
	var p = _resolve_player()
	if p == null:
		return 0
	return int(ceil(p.max_hp * heal_percent))

func _try_heal_player() -> void:
	var p = _resolve_player()
	if p == null:
		return

	var dist = global_position.distance_to(p.global_position)
	if dist <= heal_radius and p.has_method("heal"):
		p.heal(_heal_amount())

func _try_burn_enemies() -> void:
	# Burn damage = the HP this blessing heals per second (max HP x heal %),
	# scaled by "More, more!". Flat damage, independent of the enemy's own HP.
	var damage := int(round(float(_heal_amount()) * burn_damage_mult))
	if damage < 1:
		damage = 1

	var enemies = TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.is_in_group("charmed_allies"):
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist > heal_radius or not enemy.has_method("take_damage"):
			continue

		# "Oooh, Ahhhh": stun the enemy the first time THIS aura hits it. The mark
		# lives on the enemy and is cleared on reset(), so a respawned/pooled enemy
		# can be stunned again, while still only once per blessing area.
		if stun_duration > 0.0:
			if not enemy.has_meta(_stun_meta_key):
				enemy.set_meta(_stun_meta_key, true)
				if enemy.has_method("apply_stun"):
					enemy.apply_stun(stun_duration)

		enemy.take_damage(damage)

func _draw() -> void:
	var pulse = 0.7 + 0.3 * sin(_lifetime * 2.5)
	var pulse_fast = 0.8 + 0.2 * sin(_lifetime * 5.0)
	var fade = 1.0 if persistent else (1.0 - (_lifetime / lifespan) * 0.25) # Slight fade near end
	
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
