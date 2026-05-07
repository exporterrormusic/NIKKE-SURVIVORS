extends Node
class_name ScreenFogManager
## Manages the screen-space fog overlay (Zelda-style depth fog).
##
## Extracted from EnvironmentController to reduce god class size.
## Provides a full-screen shader-based fog effect that moves with the camera.

const SCREEN_FOG_SHADER_PATH := "res://resources/shaders/screen_fog.gdshader"

var _screen_fog_overlay: ColorRect = null
var _screen_fog_material: ShaderMaterial = null
var _screen_fog_layer: CanvasLayer = null
var _fog_time: float = 0.0
var _parent: Node = null


func setup(parent: Node) -> void:
	_parent = parent


## Apply screen fog settings from the time definition.
func apply(time_def: TimeOfDayDefinition) -> void:
	if time_def == null or not time_def.use_screen_fog:
		_disable()
		return
	
	_ensure_overlay_exists()
	
	if _screen_fog_overlay == null or _screen_fog_material == null:
		return
	
	_screen_fog_material.set_shader_parameter("fog_density", time_def.screen_fog_density)
	_screen_fog_material.set_shader_parameter("fog_color", time_def.screen_fog_color)
	
	_screen_fog_overlay.visible = true
	print("[ScreenFogManager] Screen fog applied with density: ", time_def.screen_fog_density)


func process(delta: float) -> void:
	if _screen_fog_overlay == null or not _screen_fog_overlay.visible:
		return
	if _screen_fog_material == null:
		return
	
	_fog_time += delta
	_screen_fog_material.set_shader_parameter("time", _fog_time)
	
	var viewport := _get_viewport()
	if viewport:
		var viewport_size := viewport.get_visible_rect().size
		_screen_fog_material.set_shader_parameter("viewport_size", viewport_size)
		
		var camera := viewport.get_camera_2d()
		if camera:
			_screen_fog_material.set_shader_parameter("camera_position", camera.global_position)


func disable() -> void:
	_disable()


func _disable() -> void:
	if _screen_fog_overlay and is_instance_valid(_screen_fog_overlay):
		_screen_fog_overlay.visible = false


func _ensure_overlay_exists() -> void:
	if _screen_fog_overlay != null:
		return
	
	if not ResourceLoader.exists(SCREEN_FOG_SHADER_PATH):
		push_warning("[ScreenFogManager] Screen fog shader not found: ", SCREEN_FOG_SHADER_PATH)
		return
	
	var shader := load(SCREEN_FOG_SHADER_PATH) as Shader
	if shader == null:
		push_warning("[ScreenFogManager] Failed to load screen fog shader")
		return
	
	_screen_fog_material = ShaderMaterial.new()
	_screen_fog_material.shader = shader
	
	# Load a noise texture for the fog
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.01
	noise.fractal_octaves = 4
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.noise = noise
	noise_tex.seamless = true
	_screen_fog_material.set_shader_parameter("noise_texture", noise_tex)
	
	# Create a CanvasLayer for the overlay
	_screen_fog_layer = CanvasLayer.new()
	_screen_fog_layer.name = "ScreenFogLayer"
	_screen_fog_layer.layer = 80
	_parent.add_child(_screen_fog_layer)
	
	_screen_fog_overlay = ColorRect.new()
	_screen_fog_overlay.name = "ScreenFogOverlay"
	_screen_fog_overlay.material = _screen_fog_material
	_screen_fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_fog_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_fog_overlay.size = _get_viewport_size()
	_screen_fog_overlay.color = Color(1, 1, 1, 0)
	
	_screen_fog_layer.add_child(_screen_fog_overlay)
	
	var viewport := _get_viewport()
	if viewport:
		viewport.size_changed.connect(_on_viewport_resize)
	
	_screen_fog_overlay.visible = false
	print("[ScreenFogManager] Screen fog overlay initialized")


func _on_viewport_resize() -> void:
	if _screen_fog_overlay and is_instance_valid(_screen_fog_overlay):
		_screen_fog_overlay.size = _get_viewport_size()


func _get_viewport() -> Viewport:
	if _parent and _parent.get_viewport():
		return _parent.get_viewport()
	return null


func _get_viewport_size() -> Vector2:
	var vp := _get_viewport()
	if vp:
		return vp.get_visible_rect().size
	return Vector2(1920, 1080)
