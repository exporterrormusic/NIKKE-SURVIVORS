extends Node2D
class_name GrassMaskManager

## Singleton-like manager for the global grass mask.
## Renders "eraser" objects into a SubViewport to generate a mask texture.

static var instance: GrassMaskManager = null

var _viewport: SubViewport = null
var _camera: Camera2D = null

var _main_camera: Camera2D = null

func _init() -> void:
	if not instance:
		instance = self

func _ready() -> void:
	# Create Viewport and Camera programmatically if not in scene
	if not _viewport:
		_setup_viewport()
	
	z_index = -100 # Manager itself doesn't need to be visible
	
func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SubViewport"
	_viewport.size = Vector2(1024, 1024) # Default, will resize on first sync
	_viewport.transparent_bg = false
	# Use UPDATE_ONCE — we manually trigger re-render when erasers move or are added.
	# This avoids rendering the SubViewport every frame when nothing changes.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	
	# Black background (Grass visible) 
	# White shapes will be drawn to erase grass
	
	add_child(_viewport)
	
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_viewport.add_child(_camera)
	
	# Add a Background ColorRect (Black)
	var bg = ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(100000, 100000)
	bg.position = Vector2(-50000, -50000)
	bg.z_index = -4096
	_viewport.add_child(bg)

var _last_screen_size: Vector2i = Vector2i.ZERO

func _process(_delta: float) -> void:
	# Sync with main camera
	if not is_instance_valid(_main_camera):
		var viewport = get_viewport()
		if viewport:
			_main_camera = viewport.get_camera_2d()
	
	if is_instance_valid(_main_camera):
		_camera.global_position = _main_camera.global_position
		_camera.zoom = _main_camera.zoom
		_camera.rotation = _main_camera.rotation
		
		# Only resize viewport when screen size actually changes (avoid per-frame allocation)
		var screen_cur_size = Vector2i(get_viewport().get_visible_rect().size)
		if screen_cur_size != _last_screen_size:
			_last_screen_size = screen_cur_size
			_viewport.size = screen_cur_size
		
		# Manually trigger a re-render so the mask follows the camera
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func add_eraser(node: Node2D) -> void:
	"""Add a visual node to the mask scene."""
	if _viewport:
		_viewport.add_child(node)
	else:
		push_warning("GrassMaskManager: Viewport missing!")

func get_mask_texture() -> ViewportTexture:
	if _viewport:
		return _viewport.get_texture()
	return null
