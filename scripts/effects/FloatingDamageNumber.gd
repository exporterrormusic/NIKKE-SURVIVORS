extends Node2D
class_name FloatingDamageNumber

# HoloCure-style floating damage/healing numbers with pop animation

enum NumberType { DAMAGE, CRITICAL, HEAL }

# HoloCure-style colors - bold and readable
const DAMAGE_COLOR := Color(1.0, 1.0, 1.0, 1.0)       # White for normal damage
const CRITICAL_COLOR := Color(1.0, 0.9, 0.2, 1.0)     # Bright yellow for crits
const HEAL_COLOR := Color(0.35, 1.0, 0.45, 1.0)       # Bright green for healing

const FLOAT_SPEED := 80.0           # Pixels per second upward
const FLOAT_DURATION := 0.9         # Total lifetime
const FADE_START := 0.6             # When to start fading (0-1 of duration)
const SPREAD_X := 30.0              # Random horizontal spread
const SPREAD_Y := 15.0              # Random vertical spread
const POP_SCALE := 1.6              # Initial scale multiplier for pop effect
const POP_DURATION := 0.12          # How long the pop animation takes
const OUTLINE_WIDTH := 2.5          # Thickness of black outline

var _value: int = 0
var _type: NumberType = NumberType.DAMAGE
var _elapsed := 0.0
var _velocity := Vector2.ZERO
var _base_scale := 1.0
var _font_size := 20
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	z_index = 100
	
	# Random spread offset
	var offset := Vector2(
		_rng.randf_range(-SPREAD_X, SPREAD_X),
		_rng.randf_range(-SPREAD_Y, SPREAD_Y)
	)
	position += offset
	
	# Initial upward velocity with slight horizontal drift
	_velocity = Vector2(_rng.randf_range(-20, 20), -FLOAT_SPEED)
	
	# Set scale and font size based on type
	match _type:
		NumberType.CRITICAL:
			_base_scale = 1.6
			_font_size = 28
		NumberType.HEAL:
			_base_scale = 1.3
			_font_size = 22
		_:
			_base_scale = 1.0
			_font_size = 20
	
	# Start with pop scale
	scale = Vector2.ONE * _base_scale * POP_SCALE

func setup(value: int, type: NumberType = NumberType.DAMAGE) -> void:
	_value = value
	_type = type

func _process(delta: float) -> void:
	_elapsed += delta
	
	if _elapsed >= FLOAT_DURATION:
		# Return to pool if pooled, otherwise free
		if EffectPool._instance and self in EffectPool._instance._damage_number_pool:
			EffectPool._instance.return_damage_number(self)
		else:
			queue_free()
		return
	
	var progress := _elapsed / FLOAT_DURATION
	
	# Move upward with deceleration
	_velocity.y *= 0.98
	position += _velocity * delta
	
	# Pop animation (scale down from POP_SCALE to 1.0)
	var pop_progress := clampf(_elapsed / POP_DURATION, 0.0, 1.0)
	var pop_factor := lerpf(POP_SCALE, 1.0, _ease_out_back(pop_progress))
	scale = Vector2.ONE * _base_scale * pop_factor
	
	# Fade out near end
	var fade_progress := clampf((progress - FADE_START) / (1.0 - FADE_START), 0.0, 1.0)
	modulate.a = 1.0 - fade_progress
	
	# Only redraw every other frame for performance
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()

func _draw() -> void:
	var color: Color
	var prefix := ""
	
	match _type:
		NumberType.DAMAGE:
			color = DAMAGE_COLOR
		NumberType.CRITICAL:
			color = CRITICAL_COLOR
			prefix = ""
		NumberType.HEAL:
			color = HEAL_COLOR
			prefix = "+"
	
	var text := prefix + str(_value)
	
	# HoloCure-style thick black outline for readability
	var shadow_color := Color(0, 0, 0, color.a * 0.95)
	
	# Draw outline at fewer angles for better performance (8 instead of 16)
	var outline_angles := 8
	for i in range(outline_angles):
		var angle := (float(i) / outline_angles) * TAU
		var offset := Vector2(cos(angle), sin(angle)) * OUTLINE_WIDTH
		draw_string(
			ThemeDB.fallback_font,
			offset,
			text,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			_font_size,
			shadow_color
		)
	
	# Draw main text on top
	draw_string(
		ThemeDB.fallback_font,
		Vector2.ZERO,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		_font_size,
		color
	)

func _ease_out_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)

# Static helper to spawn a damage number
static func spawn(parent: Node, pos: Vector2, value: int, type: NumberType = NumberType.DAMAGE) -> FloatingDamageNumber:
	var number := FloatingDamageNumber.new()
	number.setup(value, type)
	number.global_position = pos
	parent.add_child(number)
	return number

static func spawn_damage(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return spawn(parent, pos, value, NumberType.DAMAGE)

static func spawn_critical(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return spawn(parent, pos, value, NumberType.CRITICAL)

static func spawn_heal(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return spawn(parent, pos, value, NumberType.HEAL)
