extends RefCounted
class_name ShaderCache

## Cached shaders for projectiles and effects
## Prevents expensive Shader.new() calls on every bullet spawn

# Bullet glow shader - cached globally
static var _bullet_glow_shader: Shader = null
static var _bullet_glow_material: ShaderMaterial = null

# Projectile glow shader with color tint
static var _projectile_glow_shader: Shader = null

# Simple unshaded shader for effects
static var _unshaded_shader: Shader = null

# Glow shader code - unshaded with brightness boost
const GLOW_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform float brightness_boost : hint_range(1.0, 3.0) = 1.4;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Boost RGB while preserving color ratios for bloom
	COLOR = vec4(tex.rgb * brightness_boost, tex.a);
}
"""

# Color-tinted glow shader for missiles/rockets
const TINTED_GLOW_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform float brightness_boost : hint_range(1.0, 3.0) = 1.5;
uniform vec3 tint_color : source_color = vec3(1.0, 0.8, 0.3);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 tinted = tex.rgb * tint_color * brightness_boost;
	COLOR = vec4(tinted, tex.a);
}
"""

# Simple unshaded shader
const UNSHADED_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
"""


static func get_bullet_glow_shader() -> Shader:
	if _bullet_glow_shader == null:
		_bullet_glow_shader = Shader.new()
		_bullet_glow_shader.code = GLOW_SHADER_CODE
	return _bullet_glow_shader


static func get_bullet_glow_material() -> ShaderMaterial:
	## Returns a SHARED material - do not modify parameters!
	## If you need custom params, use create_bullet_glow_material() instead
	if _bullet_glow_material == null:
		_bullet_glow_material = ShaderMaterial.new()
		_bullet_glow_material.shader = get_bullet_glow_shader()
		_bullet_glow_material.set_shader_parameter("brightness_boost", 1.4)
	return _bullet_glow_material


static func create_bullet_glow_material(brightness: float = 1.4) -> ShaderMaterial:
	## Creates a NEW material with custom brightness - use sparingly!
	var mat = ShaderMaterial.new()
	mat.shader = get_bullet_glow_shader()
	mat.set_shader_parameter("brightness_boost", brightness)
	return mat


static func get_projectile_glow_shader() -> Shader:
	if _projectile_glow_shader == null:
		_projectile_glow_shader = Shader.new()
		_projectile_glow_shader.code = TINTED_GLOW_SHADER_CODE
	return _projectile_glow_shader


static func create_projectile_glow_material(tint: Color = Color(1.0, 0.8, 0.3), brightness: float = 1.5) -> ShaderMaterial:
	## Creates a material with tint color for missiles/rockets
	var mat = ShaderMaterial.new()
	mat.shader = get_projectile_glow_shader()
	mat.set_shader_parameter("brightness_boost", brightness)
	mat.set_shader_parameter("tint_color", Vector3(tint.r, tint.g, tint.b))
	return mat


static func get_unshaded_shader() -> Shader:
	if _unshaded_shader == null:
		_unshaded_shader = Shader.new()
		_unshaded_shader.code = UNSHADED_SHADER_CODE
	return _unshaded_shader
