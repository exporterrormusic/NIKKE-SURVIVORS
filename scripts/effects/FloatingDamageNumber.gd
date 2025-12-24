extends Node2D
class_name FloatingDamageNumber

# HoloCure-style floating damage/healing numbers with pop animation

enum NumberType {DAMAGE, CRITICAL, HEAL}

# HoloCure-style colors - bold and readable
const DAMAGE_COLOR := Color(1.0, 1.0, 1.0, 1.0) # White for normal damage
const CRITICAL_COLOR := Color(1.0, 0.9, 0.2, 1.0) # Bright yellow for crits
const HEAL_COLOR := Color(0.35, 1.0, 0.45, 1.0) # Bright green for healing

const FLOAT_SPEED := 80.0 # Pixels per second upward
const FLOAT_DURATION := 0.9 # Total lifetime
const FADE_START := 0.6 # When to start fading (0-1 of duration)
const SPREAD_X := 30.0 # Random horizontal spread
const SPREAD_Y := 15.0 # Random vertical spread
const POP_SCALE := 1.6 # Initial scale multiplier for pop effect
const POP_DURATION := 0.12 # How long the pop animation takes
const OUTLINE_WIDTH := 2.5 # Thickness of black outline

var _value: int = 0
var _type: NumberType = NumberType.DAMAGE
var _elapsed := 0.0
var _velocity := Vector2.ZERO
var _base_scale := 1.0
var _font_size := 20
var _rng := RandomNumberGenerator.new()

# Label based rendering for performance
var _label: Label

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
	
	# Create optimized Label
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Center anchor
	_label.anchors_preset = Control.PRESET_CENTER
	_label.position = Vector2(-50, -15) # Centering offset approx
	_label.custom_minimum_size = Vector2(100, 30)
	
	add_child(_label)
	
	_update_style()
	
	# Start with pop scale
	scale = Vector2.ONE * _base_scale * POP_SCALE
	
func _process(delta: float) -> void:
	_elapsed += delta
	
	if _elapsed >= FLOAT_DURATION:
		# Return to pool if pooled, otherwise free
		if ClassDB.class_exists("EffectPool") and EffectPool.get_instance():
			EffectPool.get_instance().return_damage_number(self)
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
	
func _update_style() -> void:
	if not _label: return
	
	var color: Color
	var prefix := ""
	
	match _type:
		NumberType.DAMAGE:
			color = DAMAGE_COLOR
		NumberType.CRITICAL:
			color = CRITICAL_COLOR
			prefix = ""
			_base_scale = 1.8
			_font_size = 34
		NumberType.HEAL:
			color = HEAL_COLOR
			prefix = "+"
			_base_scale = 1.4
			_font_size = 26
		_:
			_base_scale = 1.2
			_font_size = 24
			color = DAMAGE_COLOR

	_label.text = prefix + str(_value)
	
	# Use LabelSettings resource if we want outlines, but overrides are faster/easier for dynamic color
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, color.a * 0.95))
	_label.add_theme_constant_override("outline_size", 4) # Thicker outline for readability
	_label.add_theme_font_size_override("font_size", _font_size)

func setup(value: int, type: NumberType = NumberType.DAMAGE) -> void:
	_value = value
	_type = type
	_elapsed = 0.0
	modulate.a = 1.0
	if _label:
		_update_style()

func _ease_out_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)

# Static helper to spawn a damage number
static func spawn(parent: Node, pos: Vector2, value: int, type: NumberType = NumberType.DAMAGE) -> FloatingDamageNumber:
	# OPTIMIZATION: Delegate to EffectPool to prevent GC stutter
	if EffectPool.get_instance():
		return EffectPool.get_instance().spawn_damage_number(parent, pos, value, type)
		
	# Fallback if pool unavailable
	var number := FloatingDamageNumber.new()
	number.setup(value, type)
	number.global_position = pos
	parent.add_child.call_deferred(number)
	return number

static func spawn_damage(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return spawn(parent, pos, value, NumberType.DAMAGE)

static func spawn_critical(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return spawn(parent, pos, value, NumberType.CRITICAL)

static func spawn_heal(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return spawn(parent, pos, value, NumberType.HEAL)
