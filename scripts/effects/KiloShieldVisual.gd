extends Node2D
class_name KiloShieldVisual

## Visual shield effect for Kilo's "Protect Me Talos" upgrade
## Cyan bubble shield that appears when shield > 0

var owner_player: Node2D = null

# Visual settings
var shield_radius: float = 70.0
var _pulse_time: float = 0.0
var _shimmer_offset: float = 0.0
var _flash_intensity: float = 0.0

# Shield state
var _shield_current: int = 0
var _shield_max: int = 1
var _is_visible: bool = false

# Colors - cyan to distinguish from Cecil's blue
const COLOR_OUTER := Color(0.2, 0.9, 0.9, 0.25)
const COLOR_INNER := Color(0.3, 1.0, 1.0, 0.15)
const COLOR_RING := Color(0.4, 1.0, 1.0, 0.6)
const COLOR_SHIMMER := Color(0.6, 1.0, 1.0, 0.4)
const COLOR_FLASH := Color(1.0, 1.0, 1.0, 0.8)

func _ready() -> void:
	z_index = 35
	top_level = true
	
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

func initialize(player: Node2D) -> void:
	owner_player = player

func update_shield(current: int, max_shield: int) -> void:
	var had_shield: bool = _shield_current > 0
	
	# Flash when gaining shield (only if we already had some)
	if current > _shield_current and had_shield:
		_flash_intensity = 0.5
	
	_shield_current = current
	_shield_max = max_shield
	_is_visible = current > 0

func on_shield_hit() -> void:
	"""Called when shield absorbs damage - trigger flash effect"""
	_flash_intensity = 1.0

func _process(delta: float) -> void:
	if not owner_player or not is_instance_valid(owner_player):
		queue_free()
		return
	
	# Follow player
	global_position = owner_player.global_position
	
	# Update animations
	_pulse_time += delta
	_shimmer_offset += delta * 1.5
	
	# Decay flash
	if _flash_intensity > 0:
		_flash_intensity = maxf(_flash_intensity - delta * 3.0, 0.0)
	
	visible = _is_visible
	if _is_visible:
		queue_redraw()

func _draw() -> void:
	if not _is_visible or _shield_max <= 0:
		return
	
	var shield_percent: float = float(_shield_current) / float(_shield_max)
	var pulse: float = sin(_pulse_time * 2.0) * 0.1 + 1.0
	var current_radius: float = shield_radius * pulse
	
	# Shield strength affects opacity
	var strength_alpha: float = 0.5 + shield_percent * 0.5
	
	# Inner glow fill
	var inner := COLOR_INNER
	inner.a *= strength_alpha
	draw_circle(Vector2.ZERO, current_radius * 0.9, inner)
	
	# Outer fill
	var outer := COLOR_OUTER
	outer.a *= strength_alpha
	draw_circle(Vector2.ZERO, current_radius, outer)
	
	# Main ring
	var ring := COLOR_RING
	ring.a *= strength_alpha
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 48, ring, 3.0, true)
	
	# Shimmer effect - rotating highlight
	var shimmer_angle: float = _shimmer_offset
	var shimmer_arc: float = PI * 0.4
	var shimmer := COLOR_SHIMMER
	shimmer.a *= strength_alpha * 0.7
	draw_arc(Vector2.ZERO, current_radius, shimmer_angle, shimmer_angle + shimmer_arc, 16, shimmer, 4.0, true)
	draw_arc(Vector2.ZERO, current_radius, shimmer_angle + PI, shimmer_angle + PI + shimmer_arc, 16, shimmer, 4.0, true)
	
	# Inner shimmer ring
	var inner_shimmer := COLOR_SHIMMER
	inner_shimmer.a *= strength_alpha * 0.5
	draw_arc(Vector2.ZERO, current_radius * 0.85, shimmer_angle + PI * 0.5, shimmer_angle + PI * 0.5 + shimmer_arc * 0.7, 12, inner_shimmer, 2.0, true)
	
	# Flash effect when hit
	if _flash_intensity > 0:
		var flash := COLOR_FLASH
		flash.a = _flash_intensity * 0.6
		draw_circle(Vector2.ZERO, current_radius * 1.1, flash)
		
		# Bright ring
		var ring_flash := COLOR_FLASH
		ring_flash.a = _flash_intensity
		draw_arc(Vector2.ZERO, current_radius * 1.05, 0, TAU, 48, ring_flash, 5.0, true)
	
	# Shield percentage indicator (small dots around edge)
	var num_dots := 8
	var filled_dots := int(shield_percent * num_dots)
	for i in range(num_dots):
		var angle: float = (TAU / num_dots) * i - PI * 0.5
		var dot_pos := Vector2(cos(angle), sin(angle)) * (current_radius + 8)
		var dot_color: Color
		if i < filled_dots:
			dot_color = COLOR_RING
			dot_color.a = 0.9
		else:
			dot_color = COLOR_RING
			dot_color.a = 0.2
		draw_circle(dot_pos, 3.0, dot_color)
