extends Control
class_name VenetianBlindsBackground
## Animated background with venetian blind effect.
## Displays a carousel of background images with angled blind strips.
## Images are tinted with a monochrome blue cyberpunk aesthetic.

const UI := preload("res://scripts/ui/UITheme.gd")

@export var background_textures: PackedStringArray = []
@export var blind_base_width: float = 540.0
@export var blind_angle_degrees: float = 15.0
@export var carousel_speed: float = 100.0
@export var overlay_color: Color = UI.VFX_VENETIAN_OVERLAY

# Monochrome tint - convert to grayscale then apply blue
# This creates a unified look where all images have similar color tone
const MONOCHROME_HUE := UI.VFX_VENETIAN_HUE
const DESATURATION := 0.6 # Lower = more original color shows through

const SUPPORTED_EXTENSIONS := [".png", ".jpg", ".jpeg", ".webp"]
const BACKGROUNDS_DIRECTORY := "res://assets/backgrounds"

static var _prepared_cache: Dictionary = {}
static var _default_texture_paths_cache: PackedStringArray = PackedStringArray()
static var _shared_textures: Array[Texture2D] = []
static var _textures_loaded: bool = false
static var _shared_animation_offset: float = 0.0 # Persists across menu instances
static var _animation_offset_initialized: bool = false # Track if we've set random start
static var _last_process_frame: int = -1 # Prevents double-updating when multiple instances exist

var _textures: Array[Texture2D] = []
var _prepared_textures: Array[Dictionary] = []
var _hex_overlay: ColorRect = null

# OPTIMIZATION: Cache computed values to avoid recalculation each frame
var _cached_texture_entries: Array = []
var _cached_blind_width: float = 0.0
var _cache_size: Vector2 = Vector2.ZERO


## Clear the static texture cache (call when changing visual settings)
static func clear_cache() -> void:
	_prepared_cache.clear()
	_default_texture_paths_cache.clear()
	_shared_textures.clear()
	_textures_loaded = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	# Don't clear cache - reuse processed textures across menu transitions
	_setup_hex_overlay()
	
	# Just load textures synchronously - they're small and fast
	# Skip all preparation - use raw textures with simple UVs (vertical blinds)
	_load_textures_sync()
	
	# Initialize random animation offset on first load
	if not _animation_offset_initialized:
		_animation_offset_initialized = true
		var textures = _get_active_textures()
		if not textures.is_empty():
			var total_width = _get_blind_width() * textures.size()
			_shared_animation_offset = randf() * total_width
	
	queue_redraw()


func _load_textures_sync() -> void:
	# Simple synchronous texture loading - uses cache if available
	if _textures_loaded and not _shared_textures.is_empty():
		_textures = _shared_textures.duplicate()
		return
	
	_textures.clear()
	var texture_paths = background_textures
	
	if texture_paths.is_empty():
		texture_paths = _build_default_texture_paths()
	
	background_textures = texture_paths
	
	for path in texture_paths:
		if not ResourceLoader.exists(path):
			continue
		var texture: Texture2D = null
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			texture = ResourceLoader.load_threaded_get(path) as Texture2D
		else:
			texture = load(path) as Texture2D
		if texture:
			_textures.append(texture)
	
	_shared_textures = _textures.duplicate()
	_textures_loaded = true


func _setup_hex_overlay() -> void:
	# Create a separate overlay for digital screen effects
	# This sits on top of the blinds and applies CRT/LCD effects
	_hex_overlay = ColorRect.new()
	_hex_overlay.name = "ScreenEffectOverlay"
	_hex_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hex_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hex_overlay.color = UI.TRANSPARENT
	add_child(_hex_overlay)
	
	# Load and apply digital screen shader to the overlay (use threaded if available)
	var shader_path := "res://resources/shaders/hexagon_grid_overlay.gdshader"
	var screen_shader: Shader = null
	var status := ResourceLoader.load_threaded_get_status(shader_path)
	if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		screen_shader = ResourceLoader.load_threaded_get(shader_path) as Shader
	else:
		screen_shader = load(shader_path) as Shader
	
	if screen_shader:
		var screen_material = ShaderMaterial.new()
		screen_material.shader = screen_shader
		# Visible but not distracting effects
		screen_material.set_shader_parameter("scanline_intensity", 0.2)
		screen_material.set_shader_parameter("scanline_count", 140.0) # Fewer = bigger/thicker
		screen_material.set_shader_parameter("brightness_wave_speed", 0.5)
		screen_material.set_shader_parameter("brightness_wave_intensity", 0.08)
		screen_material.set_shader_parameter("vignette_strength", 0.2)
		screen_material.set_shader_parameter("refresh_line_speed", 0.4) # Slower
		screen_material.set_shader_parameter("refresh_line_intensity", 0.18)
		screen_material.set_shader_parameter("refresh_line_width", 0.08) # Thicker
		screen_material.set_shader_parameter("screen_size", size)
		_hex_overlay.material = screen_material


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Invalidate cache on resize
		_cached_texture_entries.clear()
		_cache_size = Vector2.ZERO
		if _hex_overlay and _hex_overlay.material:
			_hex_overlay.material.set_shader_parameter("screen_size", size)
		queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	
	var current_frame = Engine.get_process_frames()
	if _last_process_frame == current_frame:
		return
	_last_process_frame = current_frame
	
	# Use cached values
	var textures = _get_cached_entries()
	if textures.is_empty():
		return
	var total_width = _get_cached_blind_width() * textures.size()
	if total_width <= 0.0:
		return
	_shared_animation_offset = fposmod(_shared_animation_offset + carousel_speed * delta, total_width)
	
	# PERFORMANCE: Redraw every 4th frame (was 3rd)
	if current_frame % 4 == 0:
		queue_redraw()


func _draw() -> void:
	# Use cached entries
	var textures = _get_cached_entries()
	if textures.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), UI.VFX_VENETIAN_BASE)
		draw_rect(Rect2(Vector2.ZERO, size), overlay_color)
		return

	var blind_width = _get_cached_blind_width()
	var angle_offset = size.y * tan(deg_to_rad(blind_angle_degrees))
	var total_width = blind_width * textures.size()
	if total_width <= 0.0:
		return

	var start_index = int(_shared_animation_offset / blind_width) - 1
	var blinds_needed = int(ceil((size.x + abs(angle_offset) + blind_width) / blind_width)) + 3

	for i in range(blinds_needed):
		var blind_x = (start_index + i) * blind_width - _shared_animation_offset
		var texture_index = posmod(start_index + i, textures.size())
		var texture_entry = textures[texture_index]
		_draw_blind(texture_entry, blind_x, blind_width, angle_offset)

	draw_rect(Rect2(Vector2.ZERO, size), overlay_color)


func set_background_textures(paths: PackedStringArray) -> void:
	background_textures = paths
	_load_textures()
	_prepare_textures()
	queue_redraw()


func _load_textures_fast() -> void:
	# Load textures but skip heavy preprocessing - call this for non-blocking startup
	# Use cached textures if already loaded (shared across menu instances)
	if _textures_loaded and not _shared_textures.is_empty():
		_textures = _shared_textures.duplicate()
		return
	
	_textures.clear()
	var texture_paths = background_textures
	
	if texture_paths.is_empty():
		texture_paths = _build_default_texture_paths()
	
	background_textures = texture_paths
	
	for path in texture_paths:
		if not ResourceLoader.exists(path):
			continue
		# Use threaded loading if available (MenuManager pre-requests these)
		var texture: Texture2D = null
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			texture = ResourceLoader.load_threaded_get(path) as Texture2D
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			texture = ResourceLoader.load_threaded_get(path) as Texture2D
		else:
			texture = load(path) as Texture2D
		
		if texture:
			_textures.append(texture)
	
	# Cache for reuse
	_shared_textures = _textures.duplicate()
	_textures_loaded = true
	# NOTE: No _prepare_textures() call - caller is responsible for async prep


func _load_textures_async() -> void:
	# Load textures asynchronously, yielding between each one to avoid frame freezes
	# Use cached textures if already loaded (shared across menu instances)
	if _textures_loaded and not _shared_textures.is_empty():
		_textures = _shared_textures.duplicate()
		return
	
	_textures.clear()
	var texture_paths = background_textures
	
	if texture_paths.is_empty():
		texture_paths = _build_default_texture_paths()
	
	background_textures = texture_paths
	
	for path in texture_paths:
		if not ResourceLoader.exists(path):
			continue
		
		# Check status - if still loading, yield until ready
		var status := ResourceLoader.load_threaded_get_status(path)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(path)
		
		var texture: Texture2D = null
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			texture = ResourceLoader.load_threaded_get(path) as Texture2D
		else:
			# Fallback to sync load if not pre-requested
			texture = load(path) as Texture2D
		
		if texture:
			_textures.append(texture)
		
		# Yield a frame between each texture load
		await get_tree().process_frame
	
	# Cache for reuse
	_shared_textures = _textures.duplicate()
	_textures_loaded = true


func _async_prepare_textures() -> void:
	# Prepare textures asynchronously, yielding between each one
	# Uses fast path (no monochrome CPU processing) to avoid frame freezes
	if size.y <= 0.0:
		return
	if _textures.is_empty():
		return
	
	var blind_width = int(round(_get_blind_width()))
	var angle_offset: int = int(round(abs(size.y * tan(deg_to_rad(blind_angle_degrees)))))
	var target_height = int(round(max(size.y, 1.0)))
	
	if blind_width <= 0 or target_height <= 0:
		return
	
	_prepared_textures.clear()
	
	for original in _textures:
		# Yield a frame between each texture to keep animation smooth
		await get_tree().process_frame
		
		# Use fast path that skips expensive monochrome CPU processing
		var prepared = _create_prepared_texture_fast(original, blind_width, angle_offset, target_height)
		if not prepared.is_empty():
			_prepared_textures.append(prepared)
		
		queue_redraw()


func _load_textures() -> void:
	# Use cached textures if already loaded (shared across menu instances)
	if _textures_loaded and not _shared_textures.is_empty():
		_textures = _shared_textures.duplicate()
		return
	
	_textures.clear()
	var texture_paths = background_textures
	
	if texture_paths.is_empty():
		texture_paths = _build_default_texture_paths()
	
	background_textures = texture_paths
	
	for path in texture_paths:
		if not ResourceLoader.exists(path):
			continue
		# Use threaded loading if available (MenuManager pre-requests these)
		var texture: Texture2D = null
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			texture = ResourceLoader.load_threaded_get(path) as Texture2D
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Wait for threaded load to complete (still better than sync load)
			texture = ResourceLoader.load_threaded_get(path) as Texture2D
		else:
			# Fallback to sync load if not pre-requested
			texture = load(path) as Texture2D
		
		if texture:
			_textures.append(texture)
	
	# Cache for reuse
	_shared_textures = _textures.duplicate()
	_textures_loaded = true
	
	_prepare_textures()


func _draw_blind(texture_entry: Dictionary, start_x: float, blind_width: float, angle_offset: float) -> void:
	var texture: Texture2D = texture_entry.get("texture", null)
	if not texture:
		return
	
	var uvs = PackedVector2Array([
		texture_entry.get("uv_top_left", Vector2(0.0, 0.0)),
		texture_entry.get("uv_top_right", Vector2(1.0, 0.0)),
		texture_entry.get("uv_bottom_right", Vector2(1.0, 1.0)),
		texture_entry.get("uv_bottom_left", Vector2(0.0, 1.0))
	])

	var points = PackedVector2Array([
		Vector2(start_x, 0.0),
		Vector2(start_x + blind_width, 0.0),
		Vector2(start_x + blind_width + angle_offset, size.y),
		Vector2(start_x + angle_offset, size.y)
	])

	# Apply monochrome blue tint via vertex colors (GPU-efficient)
	# This multiplies the texture by the tint color, giving a blue-ish aesthetic
	var tint = MONOCHROME_HUE
	var colors = PackedColorArray([tint, tint, tint, tint])

	draw_polygon(points, colors, uvs, texture)
	_draw_blind_edges(points)


func _calculate_tint_color() -> Color:
	# No longer used for drawing - images are pre-processed
	return MONOCHROME_HUE


func _draw_blind_edges(points: PackedVector2Array) -> void:
	if points.size() < 4:
		return
	# Subtle light edge for separation between blinds
	var edge_color = UI.VFX_VENETIAN_EDGE
	var thickness = 1.5
	
	# Draw edge lines
	draw_line(points[0], points[3], edge_color, thickness)
	draw_line(points[1], points[2], edge_color, thickness)


func _get_blind_width() -> float:
	if size.y <= 0.0:
		return blind_base_width
	var scale_factor = size.y / 1080.0
	return blind_base_width * max(scale_factor, 0.25)


func _get_cached_blind_width() -> float:
	"""Return cached blind width, recalculating if size changed."""
	if _cache_size != size or _cached_blind_width <= 0.0:
		_cached_blind_width = _get_blind_width()
		_cache_size = size
	return _cached_blind_width


func _get_cached_entries() -> Array:
	"""Return cached texture entries, rebuilding if needed."""
	if _cache_size == size and not _cached_texture_entries.is_empty():
		return _cached_texture_entries
	
	_cached_texture_entries = _get_active_textures()
	_cache_size = size
	return _cached_texture_entries


func _get_active_textures() -> Array:
	# Only use prepared textures if ALL are ready (same count as raw textures)
	# This prevents flickering during async preparation
	if not _prepared_textures.is_empty() and _prepared_textures.size() >= _textures.size():
		return _prepared_textures
	if _textures.is_empty():
		return []
	# Calculate tilted UV coordinates that crop a parallelogram from the texture
	# This achieves the tilted blinds effect without CPU image processing
	var blind_width = _get_blind_width()
	var angle_offset_pixels = size.y * tan(deg_to_rad(blind_angle_degrees))
	var entries: Array = []
	
	for i in range(_textures.size()):
		var texture = _textures[i]
		if texture:
			var tex_size = texture.get_size()
			if tex_size.x <= 0 or tex_size.y <= 0:
				continue
			
			# Calculate the effective width needed (blind + angle offset)
			var effective_width = blind_width + abs(angle_offset_pixels)
			
			# Calculate UV coordinates using COVER scaling (fill blind without squishing)
			# This ensures the image fills the full blind height without distortion
			var blind_aspect = effective_width / size.y # Aspect of the blind strip
			var tex_aspect = tex_size.x / tex_size.y # Aspect of the source texture
			
			var uv_width: float
			var uv_height: float
			
			if tex_aspect > blind_aspect:
				# Texture is wider than blind - crop horizontally, show full height
				uv_height = 1.0
				uv_width = blind_aspect / tex_aspect
			else:
				# Texture is taller than blind - crop vertically, show full width
				uv_width = 1.0
				uv_height = tex_aspect / blind_aspect
			
			# Calculate the UV offset for the angle (how much to shift bottom vs top)
			var uv_angle_offset = (abs(angle_offset_pixels) / effective_width) * uv_width
			var uv_blind_width = (blind_width / effective_width) * uv_width
			
			# Center the crop horizontally and vertically
			var uv_start_x = (1.0 - uv_width) / 2.0
			var uv_start_y = (1.0 - uv_height) / 2.0
			
			# Top edge: starts at uv_start, width = uv_blind_width
			var top_left_u = uv_start_x
			var top_right_u = uv_start_x + uv_blind_width
			
			# Bottom edge: shifted by uv_angle_offset
			var bottom_left_u = uv_start_x + uv_angle_offset
			var bottom_right_u = uv_start_x + uv_angle_offset + uv_blind_width
			
			entries.append({
				"texture": texture,
				"uv_top_left": Vector2(top_left_u, uv_start_y),
				"uv_top_right": Vector2(top_right_u, uv_start_y),
				"uv_bottom_right": Vector2(bottom_right_u, uv_start_y + uv_height),
				"uv_bottom_left": Vector2(bottom_left_u, uv_start_y + uv_height)
			})
	return entries


func _prepare_textures() -> void:
	_prepared_textures.clear()
	if size.y <= 0.0:
		return
	if _textures.is_empty():
		return
	
	var blind_width = int(round(_get_blind_width()))
	var angle_offset: int = int(round(abs(size.y * tan(deg_to_rad(blind_angle_degrees)))))
	var target_height = int(round(max(size.y, 1.0)))
	
	if blind_width <= 0 or target_height <= 0:
		return
	
	for original in _textures:
		var prepared = _create_prepared_texture(original, blind_width, angle_offset, target_height)
		if not prepared.is_empty():
			_prepared_textures.append(prepared)


func _create_prepared_texture(original: Texture2D, blind_width: int, angle_offset: int, target_height: int) -> Dictionary:
	if original == null:
		return {}
	
	var cache_key: String = _build_cache_key(original, blind_width, angle_offset, target_height)
	if _prepared_cache.has(cache_key):
		return _prepared_cache[cache_key]
	
	var source_image = original.get_image()
	if source_image == null or source_image.is_empty():
		var fallback: Dictionary = _make_texture_entry(original)
		_prepared_cache[cache_key] = fallback
		return fallback
	
	var image = source_image.duplicate()
	if image.is_compressed():
		var decompress_error: Error = image.decompress()
		if decompress_error != OK:
			var fallback_decompress: Dictionary = _make_texture_entry(original)
			_prepared_cache[cache_key] = fallback_decompress
			return fallback_decompress
	
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	
	var original_size: Vector2i = image.get_size()
	if original_size.x <= 0 or original_size.y <= 0:
		var fallback_empty: Dictionary = _make_texture_entry(original)
		_prepared_cache[cache_key] = fallback_empty
		return fallback_empty
	
	var effective_width: int = max(1, blind_width + abs(angle_offset))
	var target_width: int = effective_width
	var scale_x: float = float(effective_width) / float(original_size.x)
	var scale_y: float = float(target_height) / float(original_size.y)
	var scale_factor: float = max(scale_x, scale_y)
	
	if scale_factor <= 0.0:
		scale_factor = 1.0
	
	var scaled_width: int = max(1, int(round(original_size.x * scale_factor)))
	var scaled_height: int = max(1, int(round(original_size.y * scale_factor)))
	image.resize(scaled_width, scaled_height, Image.INTERPOLATE_LANCZOS)
	
	var final_image = Image.create(target_width, target_height, false, image.get_format())
	final_image.fill(UI.TRANSPARENT)
	var dest_pos = Vector2i(int(round((target_width - scaled_width) / 2.0)), int(round((target_height - scaled_height) / 2.0)))
	_blit_image_with_clipping(final_image, image, dest_pos)
	
	# Apply monochrome effect - convert to grayscale and tint
	_apply_monochrome_effect(final_image)
	
	var safe_width: int = max(target_width, 1)
	var top_left_u: float = 0.0
	var top_right_u: float = float(blind_width) / float(safe_width)
	var bottom_left_u: float = float(angle_offset) / float(safe_width)
	var bottom_right_u: float = float(angle_offset + blind_width) / float(safe_width)
	
	var prepared_texture = ImageTexture.create_from_image(final_image)
	var entry: Dictionary = {
		"texture": prepared_texture,
		"uv_top_left": Vector2(top_left_u, 0.0),
		"uv_top_right": Vector2(top_right_u, 0.0),
		"uv_bottom_right": Vector2(bottom_right_u, 1.0),
		"uv_bottom_left": Vector2(bottom_left_u, 1.0)
	}
	_prepared_cache[cache_key] = entry
	return entry


## Fast version that skips expensive CPU-based monochrome processing.
## Used during async loading to avoid frame freezes. Still does resizing for correct UVs.
func _create_prepared_texture_fast(original: Texture2D, blind_width: int, angle_offset: int, target_height: int) -> Dictionary:
	if original == null:
		return {}
	
	# Fast path uses a simpler cache key since we skip monochrome
	var cache_key: String = _build_cache_key(original, blind_width, angle_offset, target_height) + "_fast"
	if _prepared_cache.has(cache_key):
		return _prepared_cache[cache_key]
	
	var source_image = original.get_image()
	if source_image == null or source_image.is_empty():
		var fallback: Dictionary = _make_texture_entry(original)
		_prepared_cache[cache_key] = fallback
		return fallback
	
	var image = source_image.duplicate()
	if image.is_compressed():
		var decompress_error: Error = image.decompress()
		if decompress_error != OK:
			var fallback_decompress: Dictionary = _make_texture_entry(original)
			_prepared_cache[cache_key] = fallback_decompress
			return fallback_decompress
	
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	
	var original_size: Vector2i = image.get_size()
	if original_size.x <= 0 or original_size.y <= 0:
		var fallback_empty: Dictionary = _make_texture_entry(original)
		_prepared_cache[cache_key] = fallback_empty
		return fallback_empty
	
	var effective_width: int = max(1, blind_width + abs(angle_offset))
	var target_width: int = effective_width
	var scale_x: float = float(effective_width) / float(original_size.x)
	var scale_y: float = float(target_height) / float(original_size.y)
	var scale_factor: float = max(scale_x, scale_y)
	
	if scale_factor <= 0.0:
		scale_factor = 1.0
	
	var scaled_width: int = max(1, int(round(original_size.x * scale_factor)))
	var scaled_height: int = max(1, int(round(original_size.y * scale_factor)))
	# Use faster interpolation for speed (BILINEAR instead of LANCZOS)
	image.resize(scaled_width, scaled_height, Image.INTERPOLATE_BILINEAR)
	
	var final_image = Image.create(target_width, target_height, false, image.get_format())
	final_image.fill(UI.TRANSPARENT)
	var dest_pos = Vector2i(int(round((target_width - scaled_width) / 2.0)), int(round((target_height - scaled_height) / 2.0)))
	_blit_image_with_clipping(final_image, image, dest_pos)
	
	# SKIP monochrome effect for speed - images will have original colors
	# The overlay color in _draw provides some tinting anyway
	
	var safe_width: int = max(target_width, 1)
	var top_left_u: float = 0.0
	var top_right_u: float = float(blind_width) / float(safe_width)
	var bottom_left_u: float = float(angle_offset) / float(safe_width)
	var bottom_right_u: float = float(angle_offset + blind_width) / float(safe_width)
	
	var prepared_texture = ImageTexture.create_from_image(final_image)
	var entry: Dictionary = {
		"texture": prepared_texture,
		"uv_top_left": Vector2(top_left_u, 0.0),
		"uv_top_right": Vector2(top_right_u, 0.0),
		"uv_bottom_right": Vector2(bottom_right_u, 1.0),
		"uv_bottom_left": Vector2(bottom_left_u, 1.0)
	}
	_prepared_cache[cache_key] = entry
	return entry


static func _blit_image_with_clipping(dest: Image, src: Image, dest_pos: Vector2i) -> void:
	if dest == null or src == null:
		return
	var dest_size: Vector2i = dest.get_size()
	var src_size: Vector2i = src.get_size()
	if dest_size.x <= 0 or dest_size.y <= 0:
		return
	if src_size.x <= 0 or src_size.y <= 0:
		return
	
	for row in src_size.y:
		var dest_y: int = dest_pos.y + row
		if dest_y < 0 or dest_y >= dest_size.y:
			continue
		var dest_x: int = dest_pos.x
		var src_x: int = 0
		var remaining: int = src_size.x
		if dest_x < 0:
			var shift: int = min(-dest_x, remaining)
			dest_x += shift
			src_x += shift
			remaining -= shift
		if remaining <= 0:
			continue
		if dest_x >= dest_size.x:
			continue
		var max_copy: int = min(remaining, dest_size.x - dest_x)
		if max_copy <= 0:
			continue
		dest.blit_rect(src, Rect2i(Vector2i(src_x, row), Vector2i(max_copy, 1)), Vector2i(dest_x, dest_y))


## Apply monochrome effect to image - converts to grayscale and applies blue tint
static func _apply_monochrome_effect(image: Image) -> void:
	# PERFORMANCE FIX: CPU pixel processing is too slow for large backgrounds.
	# We rely on the shader/draw-time modulation for tinting instead.
	return
	if image == null or image.is_empty():
		return
	
	var img_size := image.get_size()
	var tint := MONOCHROME_HUE
	var desat := DESATURATION
	
	for y in img_size.y:
		for x in img_size.x:
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.01:
				continue
			
			# Calculate luminance
			var luminance := pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114
			
			# Apply slight brightness boost and contrast
			luminance = (luminance - 0.5) * 1.1 + 0.5
			luminance *= 1.15
			luminance = clampf(luminance, 0.0, 1.0)
			
			# Mix with grayscale based on desaturation amount
			var gray := Color(luminance, luminance, luminance, pixel.a)
			var desaturated := pixel.lerp(gray, desat)
			
			# Apply tint
			var final_color := Color(
				desaturated.r * tint.r,
				desaturated.g * tint.g,
				desaturated.b * tint.b,
				pixel.a
			)
			
			image.set_pixel(x, y, final_color)


static func _make_texture_entry(texture: Texture2D) -> Dictionary:
	return {
		"texture": texture,
		"uv_top_left": Vector2(0.0, 0.0),
		"uv_top_right": Vector2(1.0, 0.0),
		"uv_bottom_right": Vector2(1.0, 1.0),
		"uv_bottom_left": Vector2(0.0, 1.0)
	}


static func _build_cache_key(texture: Texture2D, blind_width: int, angle_offset: int, target_height: int) -> String:
	var identifier = texture.resource_path
	if identifier == "":
		identifier = str(texture.get_rid())
	var tex_size = texture.get_size()
	return "%s_%d_%d_%d_%d_%d" % [identifier, blind_width, angle_offset, target_height, int(tex_size.x), int(tex_size.y)]


func _build_default_texture_paths() -> PackedStringArray:
	if not _default_texture_paths_cache.is_empty():
		return _default_texture_paths_cache.duplicate()
	
	var environment_paths: Array[String] = []
	var character_paths: Array[String] = []
	var paths := PackedStringArray()
	
	# Use ResourceManifest for export-safe file listing
	ResourceManifest.ensure_initialized()
	for bg_path in ResourceManifest.background_files:
		if ResourceLoader.exists(bg_path):
			environment_paths.append(bg_path)
	
	for burst_path in ResourceManifest.character_burst_files:
		if ResourceLoader.exists(burst_path):
			character_paths.append(burst_path)
	
	# Shuffle both arrays for random order each time
	character_paths.shuffle()
	environment_paths.shuffle()
	
	# Verify we found enough characters. If not (and we expect many), try a fallback scan.
	# This handles cases where ResourceManifest might be stale or incomplete during development.
	if character_paths.size() < 5 and OS.has_feature("editor"):
		print("[VenetianBlinds] ResourceManifest found few characters (%d). Converting fallback scan..." % character_paths.size())
		var fallback_chars = _scan_characters_fallback()
		if fallback_chars.size() > character_paths.size():
			print("[VenetianBlinds] Fallback scan found more characters (%d). Using fallback list." % fallback_chars.size())
			character_paths = fallback_chars

	# Shuffle both arrays for random order each time
	character_paths.shuffle()
	environment_paths.shuffle()
	
	# Strict Alternation Logic: Character -> Background -> Character -> Background
	# We loop the shorter list to match the longer list's length to ensure we show
	# every unique item from the larger set (usually characters) without interruptions.
	
	var char_count := character_paths.size()
	var env_count := environment_paths.size()
	
	# Handle edge cases where one or both lists are empty
	if char_count == 0 and env_count == 0:
		_default_texture_paths_cache = paths
		return paths
	elif char_count == 0:
		# No characters, valid fallback (just backgrounds)
		paths.append_array(environment_paths)
		_default_texture_paths_cache = paths
		return paths
	elif env_count == 0:
		# No backgrounds, valid fallback (just characters)
		paths.append_array(character_paths)
		_default_texture_paths_cache = paths
		return paths
		
	# Determine strict pairing count based on the LARGER list
	# This ensures we cycle through ALL characters even if we only have a few backgrounds
	var total_pairs := maxi(char_count, env_count)
	
	for i in range(total_pairs):
		# Always append Character then Background
		paths.append(character_paths[i % char_count])
		paths.append(environment_paths[i % env_count])
	
	print("[VenetianBlinds] Built texture loop: %d strict pairs (Chars: %d, Bgs: %d). Total loop size: %d" % [total_pairs, char_count, env_count, paths.size()])
	
	_default_texture_paths_cache = paths.duplicate()
	return paths


func _scan_characters_fallback() -> Array[String]:
	# Fallback manual scan of assets/characters
	# Useful if ResourceManifest is stale or buggy
	var bursts: Array[String] = []
	var path := "res://assets/characters"
	var dir := DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				var burst_path := "%s/%s/burst.png" % [path, entry]
				if ResourceLoader.exists(burst_path):
					bursts.append(burst_path)
			entry = dir.get_next()
		dir.list_dir_end()
	return bursts
