extends CanvasLayer
class_name EnemyScreenEffects

## Screen-space effects triggered by special enemies (tank vignette, boss darken)

var _overlay: ColorRect = null
var _player: Node2D = null
var _current_vignette: float = 0.0
var _current_darken: float = 0.0

func _ready() -> void:
	layer = 90  # Above game, below UI
	
	_overlay = ColorRect.new()
	_overlay.name = "EffectOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color.TRANSPARENT
	add_child(_overlay)
	
	# Apply shader for vignette effect
	var mat := ShaderMaterial.new()
	mat.shader = _get_vignette_shader()
	mat.set_shader_parameter("vignette_intensity", 0.0)
	mat.set_shader_parameter("vignette_color", Color(0.8, 0.1, 0.05, 1.0))
	mat.set_shader_parameter("darken_amount", 0.0)
	_overlay.material = mat
	
	# Find player
	call_deferred("_find_player")

func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player")

func _get_vignette_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.8, 0.1, 0.05, 1.0);
uniform float darken_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(uv, center) * 2.0;
	
	// Vignette effect (red edges)
	float vignette = smoothstep(0.3, 1.2, dist) * vignette_intensity;
	vec4 vignette_effect = vec4(vignette_color.rgb, vignette * 0.6);
	
	// Darken effect (overall darkness)
	vec4 darken_effect = vec4(0.0, 0.0, 0.05, darken_amount);
	
	// Combine effects
	COLOR = max(vignette_effect, darken_effect);
}
"""
	return shader

func _process(_delta: float) -> void:
	if not _player or not is_instance_valid(_player):
		_find_player()
		return
	
	if not _overlay or not _overlay.material:
		return
	
	# Read effect values from player metadata
	var target_vignette := 0.0
	var target_darken := 0.0
	
	if _player.has_meta("tank_vignette"):
		target_vignette = _player.get_meta("tank_vignette")
		# Reset for next frame (will be set again by active tanks)
		_player.set_meta("tank_vignette", 0.0)
	
	if _player.has_meta("boss_darken"):
		target_darken = _player.get_meta("boss_darken")
	
	# Smooth transitions
	_current_vignette = lerpf(_current_vignette, target_vignette, 0.15)
	_current_darken = lerpf(_current_darken, target_darken, 0.1)
	
	# Update shader
	var mat := _overlay.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("vignette_intensity", _current_vignette)
		mat.set_shader_parameter("darken_amount", _current_darken)
