extends Node
class_name NightOverlayManager
## Manages the smart night shader overlay (full-screen post-process for nighttime).
##
## Extracted from EnvironmentController to reduce god class size.
## Replaces the legacy CanvasModulate approach with a shader-based night
## effect that preserves bright elements like projectiles and effects.

const NIGHT_SHADER_PATH := "res://resources/shaders/visual_night_overlay.gdshader"

var _night_overlay: ColorRect = null
var _night_shader_material: ShaderMaterial = null
var _parent: Node = null


func setup(parent: Node) -> void:
	_parent = parent


## Apply smart night shader settings from the time definition.
func apply(time_def: TimeOfDayDefinition, canvas_modulate: CanvasModulate) -> void:
	if time_def == null or not time_def.use_smart_night_shader:
		_disable()
		return
	
	_ensure_overlay_exists()
	
	if _night_overlay == null or _night_shader_material == null:
		return
	
	# Apply shader parameters from definition
	_night_shader_material.set_shader_parameter("night_intensity", time_def.night_shader_intensity)
	_night_shader_material.set_shader_parameter("desaturation", time_def.night_desaturation)
	_night_shader_material.set_shader_parameter("darkness_factor", time_def.night_darkness)
	_night_shader_material.set_shader_parameter("vignette_strength", time_def.vignette_strength)
	
	# Enable the overlay
	_night_overlay.visible = true
	
	# Disable CanvasModulate when using shader (shader handles everything)
	if canvas_modulate:
		canvas_modulate.color = Color(1.0, 1.0, 1.0, 1.0)
	
	print("[NightOverlayManager] Smart night shader applied with intensity: ", time_def.night_shader_intensity)


func disable() -> void:
	_disable()


func _disable() -> void:
	if _night_overlay and is_instance_valid(_night_overlay):
		var parent_layer := _night_overlay.get_parent()
		_night_overlay.queue_free()
		_night_overlay = null
		if parent_layer and parent_layer.name == "NightShaderLayer":
			parent_layer.queue_free()


func _ensure_overlay_exists() -> void:
	if _night_overlay != null:
		return
	
	if not ResourceLoader.exists(NIGHT_SHADER_PATH):
		push_warning("[NightOverlayManager] Night shader not found: ", NIGHT_SHADER_PATH)
		return
	
	var shader := load(NIGHT_SHADER_PATH) as Shader
	if shader == null:
		push_warning("[NightOverlayManager] Failed to load night shader")
		return
	
	_night_shader_material = ShaderMaterial.new()
	_night_shader_material.shader = shader
	
	var night_layer := CanvasLayer.new()
	night_layer.name = "NightShaderLayer"
	night_layer.layer = 8
	_parent.add_child(night_layer)
	
	_night_overlay = ColorRect.new()
	_night_overlay.name = "NightOverlay"
	_night_overlay.material = _night_shader_material
	_night_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night_overlay.size = _get_viewport_size()
	_night_overlay.color = Color(1, 1, 1, 0)
	
	night_layer.add_child(_night_overlay)
	
	var viewport := _get_viewport()
	if viewport:
		viewport.size_changed.connect(_on_viewport_resize)
	
	_night_overlay.visible = false
	print("[NightOverlayManager] Night shader overlay initialized")


func _on_viewport_resize() -> void:
	if _night_overlay and is_instance_valid(_night_overlay):
		_night_overlay.size = _get_viewport_size()


func _get_viewport() -> Viewport:
	if _parent and _parent.get_viewport():
		return _parent.get_viewport()
	return null


func _get_viewport_size() -> Vector2:
	var vp := _get_viewport()
	if vp:
		return vp.get_visible_rect().size
	return Vector2(1920, 1080)
