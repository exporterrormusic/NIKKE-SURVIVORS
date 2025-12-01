extends Node
class_name CombatJuice

## Combat Juice System - Adds impactful game feel through visual effects
## Handles: hitstop, time dilation, camera effects, chromatic aberration, kill momentum

# Singleton reference
static var instance: CombatJuice = null

# Camera reference
var _camera: Camera2D = null
var _original_offset: Vector2 = Vector2.ZERO
var _shake_offset: Vector2 = Vector2.ZERO
var _punch_offset: Vector2 = Vector2.ZERO
var _punch_velocity: Vector2 = Vector2.ZERO

# Chromatic aberration overlay
var _chromatic_overlay: ColorRect = null
var _chromatic_material: ShaderMaterial = null
var _chromatic_strength: float = 0.0
var _chromatic_target: float = 0.0

# Time dilation
var _time_scale_target: float = 1.0
var _time_scale_recovery_speed: float = 8.0

# Kill momentum (zoom)
var _base_zoom: Vector2 = Vector2.ONE
var _kill_count: int = 0
var _kill_momentum: float = 0.0
var _kill_decay_timer: float = 0.0
const KILL_MOMENTUM_PER_KILL := 0.02  # Zoom out per kill (MORE NOTICEABLE)
const KILL_MOMENTUM_MAX := 0.25  # Max zoom out (25%)
const KILL_MOMENTUM_DECAY_DELAY := 2.0  # Seconds before momentum starts decaying
const KILL_MOMENTUM_DECAY_RATE := 0.03  # Per second (slower decay)

# Bullet rhythm
var _rhythm_pulse: float = 0.0
const RHYTHM_PULSE_STRENGTH := 0.03  # MORE NOTICEABLE rhythm
const RHYTHM_DECAY := 6.0

# Hitstop queue (for burst effects)
var _hitstop_remaining: float = 0.0

func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS  # Process even during hitstop
	_setup_chromatic_overlay()
	print("[CombatJuice] Initialized successfully!")

func _process(delta: float) -> void:
	# Handle hitstop (freezes gameplay but not this node)
	if _hitstop_remaining > 0:
		_hitstop_remaining -= delta
		if _hitstop_remaining <= 0:
			Engine.time_scale = _time_scale_target
	
	# Recover time scale smoothly
	if Engine.time_scale < _time_scale_target and _hitstop_remaining <= 0:
		Engine.time_scale = move_toward(Engine.time_scale, _time_scale_target, delta * _time_scale_recovery_speed)
	
	# Recover time scale target back to 1.0
	if _time_scale_target < 1.0:
		_time_scale_target = move_toward(_time_scale_target, 1.0, delta * 2.0)
	
	# Update chromatic aberration
	_update_chromatic(delta)
	
	# Update camera effects
	_update_camera(delta)
	
	# Update kill momentum
	_update_kill_momentum(delta)
	
	# Update rhythm pulse
	if _rhythm_pulse > 0:
		_rhythm_pulse = move_toward(_rhythm_pulse, 0.0, delta * RHYTHM_DECAY)

func _setup_chromatic_overlay() -> void:
	# Create chromatic aberration shader
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float aberration_strength : hint_range(0.0, 0.05) = 0.0;
uniform vec2 aberration_direction = vec2(1.0, 0.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 offset = aberration_direction * aberration_strength;
	
	float r = texture(SCREEN_TEXTURE, uv + offset).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv - offset).b;
	float a = texture(SCREEN_TEXTURE, uv).a;
	
	COLOR = vec4(r, g, b, a);
}
"""
	
	_chromatic_material = ShaderMaterial.new()
	_chromatic_material.shader = shader
	
	# Create overlay - will be added to a CanvasLayer by the Level
	_chromatic_overlay = ColorRect.new()
	_chromatic_overlay.name = "ChromaticAberration"
	_chromatic_overlay.material = _chromatic_material
	_chromatic_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chromatic_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

func get_chromatic_overlay() -> ColorRect:
	return _chromatic_overlay

func register_camera(camera: Camera2D) -> void:
	_camera = camera
	if _camera:
		_base_zoom = _camera.zoom
		_original_offset = _camera.offset
		print("[CombatJuice] Camera registered: ", _camera.name)

func _update_chromatic(delta: float) -> void:
	# Smoothly interpolate chromatic strength
	_chromatic_strength = move_toward(_chromatic_strength, _chromatic_target, delta * 10.0)
	_chromatic_target = move_toward(_chromatic_target, 0.0, delta * 3.0)
	
	if _chromatic_material:
		_chromatic_material.set_shader_parameter("aberration_strength", _chromatic_strength)

func _update_camera(delta: float) -> void:
	if not _camera:
		return
	
	# Decay punch offset with spring physics
	_punch_velocity *= 0.85
	_punch_offset += _punch_velocity * delta * 60.0
	_punch_offset *= 0.9
	
	# Decay shake offset
	_shake_offset *= 0.85
	
	# Apply rhythm pulse to zoom
	var rhythm_zoom = 1.0 + _rhythm_pulse * RHYTHM_PULSE_STRENGTH
	
	# Calculate final zoom with kill momentum
	var momentum_zoom = 1.0 - _kill_momentum
	var final_zoom = _base_zoom * momentum_zoom * rhythm_zoom
	
	# Apply all offsets
	_camera.offset = _original_offset + _shake_offset + _punch_offset
	_camera.zoom = final_zoom

func _update_kill_momentum(delta: float) -> void:
	# Decay momentum after delay
	if _kill_decay_timer > 0:
		_kill_decay_timer -= delta
	else:
		_kill_momentum = move_toward(_kill_momentum, 0.0, KILL_MOMENTUM_DECAY_RATE * delta)

# ============ PUBLIC API ============

## Trigger hitstop (brief freeze) - good for burst activation
static func hitstop(duration: float = 0.05) -> void:
	if instance:
		instance._do_hitstop(duration)

func _do_hitstop(duration: float) -> void:
	_hitstop_remaining = duration
	Engine.time_scale = 0.0

## Trigger time dilation (slow-mo) - good for burst/multi-kills
static func time_dilation(scale: float = 0.5, duration: float = 0.2) -> void:
	if instance:
		instance._do_time_dilation(scale, duration)

func _do_time_dilation(scale: float, _duration: float) -> void:
	_time_scale_target = scale
	Engine.time_scale = scale

## Trigger chromatic aberration pulse - good for burst activation
static func chromatic_pulse(strength: float = 0.02) -> void:
	if instance:
		instance._chromatic_target = strength
		instance._chromatic_strength = strength

## Camera punch in a direction - good for hit feedback
static func camera_punch(direction: Vector2, strength: float = 10.0) -> void:
	if instance:
		instance._do_camera_punch(direction, strength)

func _do_camera_punch(direction: Vector2, strength: float) -> void:
	_punch_velocity = direction.normalized() * strength

## Random camera shake - good for explosions
static func camera_shake(strength: float = 5.0) -> void:
	if instance:
		instance._shake_offset = Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)

## Register a kill for momentum system
static func register_kill(overkill_multiplier: float = 1.0) -> void:
	if instance:
		instance._do_register_kill(overkill_multiplier)

func _do_register_kill(overkill_multiplier: float) -> void:
	_kill_count += 1
	_kill_decay_timer = KILL_MOMENTUM_DECAY_DELAY
	
	# Add momentum based on overkill
	var momentum_add = KILL_MOMENTUM_PER_KILL * overkill_multiplier
	_kill_momentum = minf(_kill_momentum + momentum_add, KILL_MOMENTUM_MAX)

## Trigger bullet rhythm pulse - call when firing
static func bullet_rhythm_pulse() -> void:
	if instance:
		instance._rhythm_pulse = 1.0

## Full burst effect combo - hitstop + chromatic + time dilation
static func burst_effect() -> void:
	if instance:
		instance._do_burst_effect()

func _do_burst_effect() -> void:
	_do_hitstop(0.15)  # 150ms freeze (MORE NOTICEABLE)
	_chromatic_target = 0.04
	_chromatic_strength = 0.04
	# Time dilation kicks in after hitstop ends
	_time_scale_target = 0.4
	camera_shake(15.0)  # Stronger shake

## Reset all effects (call when level ends)
static func reset() -> void:
	if instance:
		instance._do_reset()

func _do_reset() -> void:
	Engine.time_scale = 1.0
	_time_scale_target = 1.0
	_hitstop_remaining = 0.0
	_chromatic_strength = 0.0
	_chromatic_target = 0.0
	_kill_momentum = 0.0
	_kill_count = 0
	_shake_offset = Vector2.ZERO
	_punch_offset = Vector2.ZERO
	_punch_velocity = Vector2.ZERO
	_rhythm_pulse = 0.0
	if _camera:
		_camera.zoom = _base_zoom
		_camera.offset = _original_offset
