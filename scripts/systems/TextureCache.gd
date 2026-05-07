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
	# Use built-in GradientTexture2D — GPU-side, no per-pixel CPU work
	var grad := Gradient.new()
	grad.colors = [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
	grad.offsets = [0.0, 1.0]
	
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)  # Center of texture
	tex.fill_to = Vector2(1.0, 0.5)    # Edge point — defines the radius
	# Default interpolation is linear — no explicit assignment needed
	return tex

static func _create_ellipse_texture(width: int, height: int) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var half_w := width * 0.5
	var half_h := height * 0.5
	var inv_half_w_sq := 1.0 / (half_w * half_w)
	var inv_half_h_sq := 1.0 / (half_h * half_h)
	
	for y in height:
		var dy := (float(y) + 0.5 - half_h)
		for x in width:
			var dx := (float(x) + 0.5 - half_w)
			# Squared distance using ellipse equation (avoids sqrt)
			var dist_sq := dx * dx * inv_half_w_sq + dy * dy * inv_half_h_sq
			if dist_sq >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var alpha := (1.0 - sqrt(dist_sq))
				alpha = alpha * alpha  # Soft edge
				img.set_pixel(x, y, Color(0, 0, 0, alpha * 0.5))
	
	return ImageTexture.create_from_image(img)
