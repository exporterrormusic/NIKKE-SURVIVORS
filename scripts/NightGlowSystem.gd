extends CanvasLayer
class_name NightGlowSystem

# Night lighting system that adds glowing effects to bright/saturated colors
# Creates an atmospheric night feel with glowing reds, oranges, and other emissive colors

var _is_night := false
var _glow_intensity := 0.0
var _target_glow_intensity := 0.0
var _transition_speed := 2.0

# Glow overlay
var _glow_rect: ColorRect = null
var _glow_shader: Shader = null

# Ambient light color for night
var _ambient_color := Color(0.3, 0.35, 0.5, 1.0)

const GLOW_SHADER_CODE := """
shader_type canvas_item;

uniform float glow_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 night_tint : source_color = vec4(0.25, 0.3, 0.45, 1.0);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_softness : hint_range(0.1, 1.0) = 0.5;

void fragment() {
	// Get screen UV
	vec2 uv = SCREEN_UV;
	
	// Vignette effect
	vec2 centered = uv * 2.0 - 1.0;
	float vignette_dist = length(centered);
	float vignette = smoothstep(0.4, 0.4 + vignette_softness, vignette_dist);
	float vignette_factor = vignette * vignette_strength * glow_intensity;
	
	// Night color overlay
	vec4 night_overlay = vec4(night_tint.rgb, vignette_factor * 0.6);
	
	// Subtle blue tint at edges
	vec4 edge_tint = vec4(0.1, 0.15, 0.3, vignette_factor * 0.3);
	
	COLOR = mix(night_overlay, edge_tint, vignette * 0.5);
}
"""

func _ready() -> void:
	layer = 100  # High layer to be on top
	
	# Create glow shader
	_glow_shader = Shader.new()
	_glow_shader.code = GLOW_SHADER_CODE
	
	# Create glow overlay
	_glow_rect = ColorRect.new()
	_glow_rect.name = "NightGlowOverlay"
	_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_rect.anchors_preset = Control.PRESET_FULL_RECT
	_glow_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _glow_shader
	_glow_rect.material = shader_material
	
	add_child(_glow_rect)
	
	# Initial state
	_update_shader_params()
	
	set_process(true)

func _process(delta: float) -> void:
	# Smooth transition
	if abs(_glow_intensity - _target_glow_intensity) > 0.01:
		_glow_intensity = lerpf(_glow_intensity, _target_glow_intensity, delta * _transition_speed)
		_update_shader_params()
	
	# Ensure overlay covers viewport
	if _glow_rect:
		var viewport := get_viewport()
		if viewport:
			_glow_rect.size = viewport.get_visible_rect().size

func set_night_mode(enabled: bool, intensity: float = 0.7) -> void:
	_is_night = enabled
	_target_glow_intensity = intensity if enabled else 0.0
	
	if _glow_rect:
		_glow_rect.visible = enabled or _glow_intensity > 0.01

func set_ambient_color(color: Color) -> void:
	_ambient_color = color
	_update_shader_params()

func _update_shader_params() -> void:
	if _glow_rect == null or _glow_rect.material == null:
		return
	
	var mat := _glow_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("glow_intensity", _glow_intensity)
		mat.set_shader_parameter("night_tint", _ambient_color)
		mat.set_shader_parameter("vignette_strength", 0.5)
		mat.set_shader_parameter("vignette_softness", 0.6)
	
	_glow_rect.visible = _glow_intensity > 0.01

func is_night() -> bool:
	return _is_night

func get_glow_intensity() -> float:
	return _glow_intensity
