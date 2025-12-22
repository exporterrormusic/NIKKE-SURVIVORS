extends Node
class_name TextureCache

## Singleton texture cache to avoid creating identical textures repeatedly
## This dramatically reduces memory allocations and GPU texture uploads

static var _light_texture_64: Texture2D = null
static var _light_texture_32: Texture2D = null
static var _glow_texture_32: Texture2D = null
static var _glow_texture_64: Texture2D = null
static var _shadow_ellipse_texture: Texture2D = null

## Clean up cached textures to prevent RID leaks on exit
static func cleanup() -> void:
	_light_texture_64 = null
	_light_texture_32 = null
	_glow_texture_32 = null
	_glow_texture_64 = null
	_shadow_ellipse_texture = null
	print("[TextureCache] Cleanup complete")

static func get_light_texture_64() -> Texture2D:
	if _light_texture_64 == null:
		_light_texture_64 = _create_radial_gradient(64)
	return _light_texture_64

static func get_light_texture_32() -> Texture2D:
	if _light_texture_32 == null:
		_light_texture_32 = _create_radial_gradient(32)
	return _light_texture_32

static func get_glow_texture_32() -> Texture2D:
	if _glow_texture_32 == null:
		_glow_texture_32 = _create_radial_gradient(32)
	return _glow_texture_32

static func get_glow_texture_64() -> Texture2D:
	if _glow_texture_64 == null:
		_glow_texture_64 = _create_radial_gradient(64)
	return _glow_texture_64

static func get_shadow_ellipse(width: int = 48, height: int = 24) -> Texture2D:
	# Cache the most common shadow size
	if width == 48 and height == 24:
		if _shadow_ellipse_texture == null:
			_shadow_ellipse_texture = _create_ellipse_texture(width, height)
		return _shadow_ellipse_texture
	# For non-standard sizes, create on demand (rare)
	return _create_ellipse_texture(width, height)

static func _create_radial_gradient(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var max_radius: float = size * 0.5
	
	for y in size:
		for x in size:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center) / max_radius
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			alpha = alpha * alpha  # Quadratic falloff
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	
	return ImageTexture.create_from_image(img)

static func _create_ellipse_texture(width: int, height: int) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var center := Vector2(width * 0.5, height * 0.5)
	
	for y in height:
		for x in width:
			var nx := (float(x) - center.x) / (width * 0.5)
			var ny := (float(y) - center.y) / (height * 0.5)
			var dist := sqrt(nx * nx + ny * ny)
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			alpha = alpha * alpha  # Soft edge
			img.set_pixel(x, y, Color(0, 0, 0, alpha * 0.5))
	
	return ImageTexture.create_from_image(img)
