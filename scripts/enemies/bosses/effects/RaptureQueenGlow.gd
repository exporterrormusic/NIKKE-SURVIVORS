extends Node2D

## Glowing eyes and mouth overlay for RAPTURE QUEEN - N01
## Pulsing red glow that intensifies before beam attacks

var _time: float = 0.0
var _is_regenerating: bool = false
var _is_teleporting: bool = false
var _beam_charging: bool = false

# Eye positions (relative to sprite center, adjust based on actual sprite)
const LEFT_EYE_POS := Vector2(-25, -40)
const RIGHT_EYE_POS := Vector2(25, -40)
const MOUTH_POS := Vector2(0, -10)

# Glow sizes settings (Smaller and softer)
const EYE_RADIUS := 5.0 # Reduced from 8.0
const MOUTH_WIDTH := 20.0 # Reduced from 30.0
const MOUTH_HEIGHT := 10.0 # Reduced from 15.0

func _ready() -> void:
	z_index = 5  # Above sprite
	
	# Unshaded material
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var pulse = 0.7 + 0.3 * sin(_time * 4.0)
	var eye_color: Color
	var mouth_color: Color
	
	if _is_regenerating:
		# Green/purple regen glow
		eye_color = Color(0.3, 1.0, 0.5, pulse)
		mouth_color = Color(0.5, 0.3, 1.0, pulse * 0.8)
	elif _beam_charging:
		# Intense red before beam
		var charge_pulse = 0.5 + 0.5 * sin(_time * 15.0)
		eye_color = Color(1.0, 0.1, 0.05, charge_pulse)
		mouth_color = Color(1.0, 0.2, 0.1, charge_pulse)
	else:
		# Normal red glow
		eye_color = Color(1.0, 0.1, 0.05, pulse * 0.9)
		mouth_color = Color(1.0, 0.15, 0.1, pulse * 0.7)
	
	# Draw eyes
	_draw_glowing_eye(LEFT_EYE_POS, EYE_RADIUS, eye_color)
	_draw_glowing_eye(RIGHT_EYE_POS, EYE_RADIUS, eye_color)
	
	# Draw mouth
	_draw_glowing_mouth(MOUTH_POS, mouth_color)
	
	# Teleport glitch effect
	if _is_teleporting:
		_draw_teleport_glitch()

func _draw_glowing_eye(pos: Vector2, radius: float, color: Color) -> void:
	# Outer glow (Very soft, large)
	draw_circle(pos, radius * 3.0, Color(color.r, color.g, color.b, color.a * 0.15))
	# Mid glow
	draw_circle(pos, radius * 1.8, Color(color.r, color.g, color.b, color.a * 0.3))
	# Inner glow
	draw_circle(pos, radius * 1.2, Color(color.r, color.g, color.b, color.a * 0.4))
	# Core (Smaller, less sharp)
	draw_circle(pos, radius * 0.6, Color(color.r, color.g, color.b, color.a * 0.8))
	# Center bright spot (White hot)
	draw_circle(pos, radius * 0.3, Color(1.0, 0.9, 0.8, color.a * 0.9))

func _draw_glowing_mouth(pos: Vector2, color: Color) -> void:
	var half_w = MOUTH_WIDTH / 2.0
	var half_h = MOUTH_HEIGHT / 2.0
	
	# Soft gradient effect using overlapping rects/circles is hard with standard draw commands without texture
	# We'll use low alpha stacked rects for softness
	
	# Outer glow
	var glow_rect = Rect2(pos - Vector2(half_w * 1.5, half_h * 2.0), Vector2(MOUTH_WIDTH * 1.5, MOUTH_HEIGHT * 2.0))
	draw_rect(glow_rect, Color(color.r, color.g, color.b, color.a * 0.15))
	
	# Inner glow
	var inner_rect = Rect2(pos - Vector2(half_w * 1.1, half_h * 1.2), Vector2(MOUTH_WIDTH * 1.1, MOUTH_HEIGHT * 1.2))
	draw_rect(inner_rect, Color(color.r, color.g, color.b, color.a * 0.3))
	
	# Core (Slightly smaller than definition to avoid sharp box)
	var core_rect = Rect2(pos - Vector2(half_w * 0.8, half_h * 0.6), Vector2(MOUTH_WIDTH * 0.8, MOUTH_HEIGHT * 0.6))
	draw_rect(core_rect, Color(color.r, color.g, color.b, color.a * 0.6))

func _draw_teleport_glitch() -> void:
	# Draw scan lines
	for i in range(8):
		var y = -60 + i * 15 + sin(_time * 30.0 + i) * 5.0
		var width = randf_range(20, 60)
		var x = randf_range(-40, 40 - width)
		draw_line(Vector2(x, y), Vector2(x + width, y), Color(0.2, 0.8, 1.0, 0.7), 2.0)

func set_regenerating(state: bool) -> void:
	_is_regenerating = state

func start_teleport() -> void:
	_is_teleporting = true

func end_teleport() -> void:
	_is_teleporting = false

func set_beam_charging(state: bool) -> void:
	_beam_charging = state
