extends Node
class_name NightGlowManager

## Manages night glow effects for sprites (player, enemies, summons)
## Call NightGlowManager.set_night_mode(true/false) to enable/disable
## Sprites can register themselves to receive glow shader automatically

static var is_night_mode: bool = false
static var glow_intensity: float = 0.3
static var glow_shader: Shader = null
static var _shared_glow_material: ShaderMaterial = null
static var registered_sprites: Array[CanvasItem] = []

const SHADER_PATH := "res://resources/shaders/sprite_night_glow.gdshader"

static func set_night_mode(enabled: bool, intensity: float = 0.3) -> void:
	is_night_mode = enabled
	glow_intensity = intensity
	
	# Load shader if needed
	if enabled and glow_shader == null:
		if ResourceLoader.exists(SHADER_PATH):
			glow_shader = load(SHADER_PATH) as Shader
	
	# Update all registered sprites
	for sprite in registered_sprites:
		if is_instance_valid(sprite):
			_apply_glow_to_sprite(sprite, enabled)

static func register_sprite(sprite: CanvasItem) -> void:
	"""Register a sprite to receive night glow effect."""
	if sprite and not registered_sprites.has(sprite):
		registered_sprites.append(sprite)
		# Apply current state
		if is_night_mode:
			_apply_glow_to_sprite(sprite, true)

static func unregister_sprite(sprite: CanvasItem) -> void:
	"""Unregister a sprite from night glow effect."""
	var idx := registered_sprites.find(sprite)
	if idx >= 0:
		registered_sprites.remove_at(idx)
	# Remove glow if present
	if sprite and is_instance_valid(sprite):
		_apply_glow_to_sprite(sprite, false)

static func _apply_glow_to_sprite(sprite: CanvasItem, enabled: bool) -> void:
	"""Apply or remove glow shader from a sprite."""
	if not is_instance_valid(sprite):
		return
	
	if enabled:
		# Load shader if needed
		if glow_shader == null:
			if ResourceLoader.exists(SHADER_PATH):
				glow_shader = load(SHADER_PATH) as Shader
		
		if glow_shader == null:
			return
			
		# Create shared material once, reuse for all sprites
		if _shared_glow_material == null:
			_shared_glow_material = ShaderMaterial.new()
			_shared_glow_material.shader = glow_shader
			_shared_glow_material.set_shader_parameter("glow_color", Color(1.0, 0.95, 0.85, 1.0))
			_shared_glow_material.set_shader_parameter("glow_size", 2.0)
		
		# Update parameters for current global state
		_shared_glow_material.set_shader_parameter("enabled_float", 1.0)
		_shared_glow_material.set_shader_parameter("glow_intensity", glow_intensity)
		
		# Check if already has our shared material
		if sprite.material == _shared_glow_material:
			return
		
		# Store original material if any (for restoration)
		if sprite.material and sprite.material != _shared_glow_material:
			sprite.set_meta("_original_material", sprite.material)
		
		sprite.material = _shared_glow_material
	else:
		# Restore original material
		if sprite.has_meta("_original_material"):
			sprite.material = sprite.get_meta("_original_material")
			sprite.remove_meta("_original_material")
		else:
			sprite.material = null

static func get_is_night() -> bool:
	return is_night_mode

static func cleanup() -> void:
	"""Remove all glow effects and clear registrations."""
	for sprite in registered_sprites:
		if is_instance_valid(sprite):
			_apply_glow_to_sprite(sprite, false)
	registered_sprites.clear()
	_shared_glow_material = null
	is_night_mode = false
	glow_shader = null
