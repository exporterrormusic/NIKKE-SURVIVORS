extends Control
class_name VenetianBlindsBackground
## Animated background with venetian blind effect.
## Displays a carousel of background images with angled blind strips.
## Images are tinted with a monochrome blue cyberpunk aesthetic.

@export var background_textures: PackedStringArray = []
@export var blind_base_width: float = 540.0
@export var blind_angle_degrees: float = 15.0
@export var carousel_speed: float = 100.0
@export var overlay_color: Color = Color(0.02, 0.05, 0.1, 0.25)  # Very light overlay

# Monochrome tint - convert to grayscale then apply blue
# This creates a unified look where all images have similar color tone
const MONOCHROME_HUE := Color(0.75, 0.9, 1.0, 1.0)  # Brighter, lighter blue
const DESATURATION := 0.6  # Lower = more original color shows through

const SUPPORTED_EXTENSIONS := [".png", ".jpg", ".jpeg", ".webp"]
const BACKGROUNDS_DIRECTORY := "res://assets/backgrounds"

static var _prepared_cache: Dictionary = {}
static var _default_texture_paths_cache: PackedStringArray = PackedStringArray()
static var _shared_textures: Array[Texture2D] = []
static var _textures_loaded: bool = false
static var _shared_animation_offset: float = 0.0  # Persists across menu instances
static var _animation_offset_initialized: bool = false  # Track if we've set random start
static var _last_process_frame: int = -1  # Prevents double-updating when multiple instances exist

var _textures: Array[Texture2D] = []
var _prepared_textures: Array[Dictionary] = []
var _hex_overlay: ColorRect = null


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
	
	# Defer heavy texture loading to next frame for faster initial display
	call_deferred("_deferred_load")


func _deferred_load() -> void:
	_load_textures()
	_prepare_textures()
	
	# Initialize random animation offset on first load
	if not _animation_offset_initialized:
		_animation_offset_initialized = true
		var textures = _get_active_textures()
		if not textures.is_empty():
			var total_width = _get_blind_width() * textures.size()
			_shared_animation_offset = randf() * total_width
	
	queue_redraw()


func _setup_hex_overlay() -> void:
	# Create a separate overlay for digital screen effects
	# This sits on top of the blinds and applies CRT/LCD effects
	_hex_overlay = ColorRect.new()
	_hex_overlay.name = "ScreenEffectOverlay"
	_hex_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hex_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hex_overlay.color = Color(0, 0, 0, 0)  # Transparent base
	add_child(_hex_overlay)
	
	# Load and apply digital screen shader to the overlay
	var screen_shader = load("res://resources/shaders/hexagon_grid_overlay.gdshader")
	if screen_shader:
		var screen_material = ShaderMaterial.new()
		screen_material.shader = screen_shader
		# Visible but not distracting effects
		screen_material.set_shader_parameter("scanline_intensity", 0.2)
		screen_material.set_shader_parameter("scanline_count", 140.0)  # Fewer = bigger/thicker
		screen_material.set_shader_parameter("brightness_wave_speed", 0.5)
		screen_material.set_shader_parameter("brightness_wave_intensity", 0.08)
		screen_material.set_shader_parameter("vignette_strength", 0.2)
		screen_material.set_shader_parameter("refresh_line_speed", 0.4)  # Slower
		screen_material.set_shader_parameter("refresh_line_intensity", 0.18)
		screen_material.set_shader_parameter("refresh_line_width", 0.08)  # Thicker
		screen_material.set_shader_parameter("screen_size", size)
		_hex_overlay.material = screen_material


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_prepare_textures()
		# Update shader screen size
		if _hex_overlay and _hex_overlay.material:
			_hex_overlay.material.set_shader_parameter("screen_size", size)
		queue_redraw()


func _process(delta: float) -> void:
	# Only update animation once per frame, even if multiple instances exist
	var current_frame = Engine.get_process_frames()
	if _last_process_frame == current_frame:
		queue_redraw()
		return
	_last_process_frame = current_frame
	
	var textures = _get_active_textures()
	if textures.is_empty():
		return
	var total_width = _get_blind_width() * textures.size()
	if total_width <= 0.0:
		return
	_shared_animation_offset = fposmod(_shared_animation_offset + carousel_speed * delta, total_width)
	queue_redraw()


func _draw() -> void:
	var textures = _get_active_textures()
	if textures.is_empty():
		# Dark blue base when no textures
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.12))
		draw_rect(Rect2(Vector2.ZERO, size), overlay_color)
		return

	var blind_width = _get_blind_width()
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

	# Semi-transparent overlay for unified look
	draw_rect(Rect2(Vector2.ZERO, size), overlay_color)


func set_background_textures(paths: PackedStringArray) -> void:
	background_textures = paths
	_load_textures()
	_prepare_textures()
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
		var texture = load(path)
		if texture is Texture2D:
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

	# Images are already processed with monochrome effect, use white to show them as-is
	var colors = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])

	draw_polygon(points, colors, uvs, texture)
	_draw_blind_edges(points)


func _calculate_tint_color() -> Color:
	# No longer used for drawing - images are pre-processed
	return MONOCHROME_HUE


func _draw_blind_edges(points: PackedVector2Array) -> void:
	if points.size() < 4:
		return
	# Subtle light edge for separation between blinds
	var edge_color = Color(0.6, 0.8, 1.0, 0.15)
	var thickness = 1.5
	
	# Draw edge lines
	draw_line(points[0], points[3], edge_color, thickness)
	draw_line(points[1], points[2], edge_color, thickness)


func _get_blind_width() -> float:
	if size.y <= 0.0:
		return blind_base_width
	var scale_factor = size.y / 1080.0
	return blind_base_width * max(scale_factor, 0.25)


func _get_active_textures() -> Array:
	if not _prepared_textures.is_empty():
		return _prepared_textures
	if _textures.is_empty():
		return []
	var entries: Array = []
	for texture in _textures:
		if texture:
			entries.append({
				"texture": texture,
				"uv_top_left": Vector2(0.0, 0.0),
				"uv_top_right": Vector2(1.0, 0.0),
				"uv_bottom_right": Vector2(1.0, 1.0),
				"uv_bottom_left": Vector2(0.0, 1.0)
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
	final_image.fill(Color(0, 0, 0, 0))
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
	
	# Look for background/environment images in the backgrounds directory
	if DirAccess.dir_exists_absolute(BACKGROUNDS_DIRECTORY):
		var dir := DirAccess.open(BACKGROUNDS_DIRECTORY)
		if dir:
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				if not dir.current_is_dir():
					var lower = entry.to_lower()
					for ext in SUPPORTED_EXTENSIONS:
						if lower.ends_with(ext):
							environment_paths.append("%s/%s" % [BACKGROUNDS_DIRECTORY, entry])
							break
				entry = dir.get_next()
			dir.list_dir_end()
	
	# Check character folders for burst images
	var characters_dir := "res://assets/characters"
	if DirAccess.dir_exists_absolute(characters_dir):
		var dir := DirAccess.open(characters_dir)
		if dir:
			var folders: Array[String] = []
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				if dir.current_is_dir() and not entry.begins_with("."):
					folders.append(entry)
				entry = dir.get_next()
			dir.list_dir_end()
			folders.sort()
			
			for folder_name in folders:
				var burst_path := "%s/%s/burst.png" % [characters_dir, folder_name]
				if ResourceLoader.exists(burst_path):
					character_paths.append(burst_path)
	
	# Shuffle both arrays for random order each time
	character_paths.shuffle()
	environment_paths.shuffle()
	
	# Build rotation pattern: CHARACTER - BACKGROUND - CHARACTER - BACKGROUND
	# Loop characters to always maintain the alternating pattern
	var char_count := character_paths.size()
	var env_count := environment_paths.size()
	
	if char_count == 0 and env_count == 0:
		_default_texture_paths_cache = paths
		return paths
	
	# Total pairs = max of both counts, so we cover all images
	var total_pairs := maxi(char_count, env_count)
	
	for i in range(total_pairs):
		# Add character (loop if we've run out)
		if char_count > 0:
			paths.append(character_paths[i % char_count])
		
		# Add background (loop if we've run out)
		if env_count > 0:
			paths.append(environment_paths[i % env_count])
	
	_default_texture_paths_cache = paths.duplicate()
	return paths
