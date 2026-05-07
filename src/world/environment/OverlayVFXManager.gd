extends Node
class_name OverlayVFXManager
## Manages animated shader-based overlays: snow, sakura, and flower effects.
##
## Extracted from EnvironmentController to reduce god class size.
## Handles: creating overlay nodes, per-frame animation in _process,
## applying biome settings to each overlay, and viewport-aligned polygon
## management for camera-following effects.

const SNOW_SHADER_PATH := "res://resources/shaders/falling_snow.gdshader"
const SAKURA_SHADER_PATH := "res://resources/shaders/falling_sakura.gdshader"
const FLOWER_SHADER_PATH := "res://resources/shaders/flower_patches.gdshader"
const ENABLE_SAKURA_OVERLAY := false

var _overlay_canvas: Node2D = null
var _snow_overlay: Polygon2D = null
var _sakura_overlay: Polygon2D = null
var _flower_overlay: Polygon2D = null
var _time_flow: float = 0.0
var _world_bounds: Rect2 = Rect2()
var _parent: Node = null
var _biome_getter: Callable = Callable()
var _night_getter: Callable = Callable()


func setup(parent: Node, biome_getter: Callable, night_getter: Callable) -> void:
	_parent = parent
	_biome_getter = biome_getter
	_night_getter = night_getter
	_ensure_overlay_canvas()


func ensure_overlay_canvas() -> Node2D:
	return _ensure_overlay_canvas()


func ensure_snow_overlay() -> Polygon2D:
	return _ensure_snow_overlay()


func ensure_sakura_overlay() -> Polygon2D:
	return _ensure_sakura_overlay()


func ensure_flower_overlay() -> Polygon2D:
	return _ensure_flower_overlay()


func get_snow_overlay() -> Polygon2D:
	return _snow_overlay


func get_sakura_overlay() -> Polygon2D:
	return _sakura_overlay


func get_flower_overlay() -> Polygon2D:
	return _flower_overlay


func set_world_bounds(bounds: Rect2) -> void:
	_world_bounds = bounds


func process(delta: float, camera_position: Vector2, camera_view_size: Vector2, world_offset: Vector2) -> void:
	_time_flow += delta
	var biome: BiomeDefinition = _biome_getter.call()
	
	_update_snow(delta, biome, camera_view_size, world_offset)
	_update_sakura(delta, biome, camera_view_size, world_offset)
	_update_overlay_transform(camera_position)


## Apply snow overlay settings from biome definition.
func apply_snow_settings(biome: BiomeDefinition) -> void:
	if _snow_overlay == null:
		return
	var snow_material := _snow_overlay.material as ShaderMaterial
	if snow_material == null:
		_snow_overlay.visible = false
		return
	if biome == null or biome.snowfall_density <= 0.0:
		_snow_overlay.visible = false
		snow_material.set_shader_parameter("density", 0.0)
		return
	_snow_overlay.visible = true
	var base_density := biome.snowfall_density * 0.55 + 0.15
	var density_scale := clampf(base_density * 0.42 + 0.06, 0.08, 0.95)
	snow_material.set_shader_parameter("density", density_scale)
	var flake_scale := clampf(biome.snowfall_scale * 0.36, 0.2, 1.0)
	snow_material.set_shader_parameter("flake_scale", flake_scale)
	snow_material.set_shader_parameter("view_size", _get_camera_view_size())
	snow_material.set_shader_parameter("world_offset", _compute_world_offset())
	snow_material.set_shader_parameter("world_scale", 0.0025)


## Apply sakura overlay settings from biome definition.
func apply_sakura_settings(biome: BiomeDefinition) -> void:
	if _sakura_overlay == null:
		return
	var sakura_material := _sakura_overlay.material as ShaderMaterial
	if sakura_material == null:
		_sakura_overlay.visible = false
		return
	if biome == null or biome.sakura_petal_density <= 0.01:
		_sakura_overlay.visible = false
		sakura_material.set_shader_parameter("density", 0.0)
		return
	_sakura_overlay.visible = true
	var density := clampf(biome.sakura_petal_density, 0.0, 1.0)
	var density_scale := clampf(lerpf(0.04, 0.32, density), 0.02, 0.42)
	sakura_material.set_shader_parameter("density", density_scale)
	sakura_material.set_shader_parameter("petal_scale", clampf(biome.sakura_petal_scale, 0.25, 3.0))
	sakura_material.set_shader_parameter("twinkle_strength", clampf(biome.sakura_twinkle_strength, 0.0, 1.0))
	var fall_speed := clampf(biome.sakura_fall_speed, 0.1, 2.0)
	var wind := clampf(biome.wind_strength, 0.0, 5.0)
	sakura_material.set_shader_parameter("wind_direction", Vector2(wind * 0.35, -fall_speed))
	sakura_material.set_shader_parameter("drift_amplitude", clampf(0.25 + wind * 0.25, 0.15, 0.85))
	
	var primary := biome.sakura_primary_color
	var secondary := biome.sakura_secondary_color
	
	var is_night: bool = _night_getter.call()
	
	# Override for "Firefly" effect in Sakura Grove at Night
	if is_night and biome.biome_id == &"sakura_grove":
		primary = Color(1.0, 0.9, 0.4, 1.0)
		secondary = Color(1.0, 0.6, 0.2, 0.8)
		var firefly_drift := Vector2(wind * 0.2, 0.15)
		sakura_material.set_shader_parameter("wind_direction", firefly_drift)
		sakura_material.set_shader_parameter("twinkle_strength", 0.95)
		sakura_material.set_shader_parameter("petal_scale", clampf(biome.sakura_petal_scale * 0.6, 0.1, 2.0))
	
	sakura_material.set_shader_parameter("primary_color", Vector4(primary.r, primary.g, primary.b, primary.a))
	sakura_material.set_shader_parameter("secondary_color", Vector4(secondary.r, secondary.g, secondary.b, secondary.a))
	sakura_material.set_shader_parameter("view_size", _get_camera_view_size())
	sakura_material.set_shader_parameter("world_offset", _compute_world_offset())
	sakura_material.set_shader_parameter("world_scale", 0.0021)


## Apply flower overlay settings from biome definition.
func apply_flower_settings(_biome: BiomeDefinition) -> void:
	# DISABLED: Flower overlay causing shader errors - hiding for now
	if _flower_overlay != null:
		_flower_overlay.visible = false


func update_layout(camera_view_size: Vector2, camera_position: Vector2) -> void:
	_update_overlay_layout(camera_view_size, camera_position)


## Build a rectangular polygon centered at origin for overlay shaders.
static func build_overlay_polygon(view_size: Vector2) -> PackedVector2Array:
	var half := view_size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])


func _ensure_overlay_canvas() -> Node2D:
	if _overlay_canvas != null:
		return _overlay_canvas
	var node := _parent.get_node_or_null("EnvironmentOverlay")
	if node and node is Node2D:
		var overlay := node as Node2D
		overlay.top_level = true
		overlay.z_index = 60
		overlay.z_as_relative = false
		_overlay_canvas = overlay
		return _overlay_canvas
	var environment_overlay := Node2D.new()
	environment_overlay.name = "EnvironmentOverlay"
	environment_overlay.z_index = 60
	environment_overlay.top_level = true
	environment_overlay.z_as_relative = false
	_parent.add_child(environment_overlay)
	if Engine.is_editor_hint():
		environment_overlay.owner = _parent.get_tree().edited_scene_root
	_overlay_canvas = environment_overlay
	return _overlay_canvas


func _ensure_snow_overlay() -> Polygon2D:
	if _overlay_canvas == null:
		return null
	if _snow_overlay != null:
		return _snow_overlay
	var snow_shader := load(SNOW_SHADER_PATH)
	var node := _overlay_canvas.get_node_or_null("SnowOverlay")
	if node and node is Polygon2D:
		var snow := node as Polygon2D
		if snow.material == null or not (snow.material is ShaderMaterial):
			if snow_shader:
				var snow_shader_material := ShaderMaterial.new()
				snow_shader_material.shader = snow_shader
				snow.material = snow_shader_material
		_snow_overlay = snow
		return _snow_overlay
	var snow_overlay := Polygon2D.new()
	snow_overlay.name = "SnowOverlay"
	snow_overlay.z_index = 50
	var view_size := _get_view_size()
	snow_overlay.polygon = build_overlay_polygon(view_size)
	if snow_shader:
		var snow_material := ShaderMaterial.new()
		snow_material.shader = snow_shader
		snow_overlay.material = snow_material
		(snow_overlay.material as ShaderMaterial).set_shader_parameter("view_size", view_size)
	_overlay_canvas.add_child(snow_overlay)
	if Engine.is_editor_hint():
		snow_overlay.owner = _parent.get_tree().edited_scene_root
	_snow_overlay = snow_overlay
	return _snow_overlay


func _ensure_sakura_overlay() -> Polygon2D:
	if _overlay_canvas == null:
		return null
	if _sakura_overlay != null:
		return _sakura_overlay
	var sakura_shader := load(SAKURA_SHADER_PATH)
	var node := _overlay_canvas.get_node_or_null("SakuraOverlay")
	if node and node is Polygon2D:
		var sakura := node as Polygon2D
		if ENABLE_SAKURA_OVERLAY:
			if sakura.material == null or not (sakura.material is ShaderMaterial):
				if sakura_shader:
					var sakura_material := ShaderMaterial.new()
					sakura_material.shader = sakura_shader
					sakura.material = sakura_material
			_sakura_overlay = sakura
			return _sakura_overlay
		sakura.visible = false
		return null
	if not ENABLE_SAKURA_OVERLAY:
		return null
	var sakura_overlay := Polygon2D.new()
	sakura_overlay.name = "SakuraOverlay"
	sakura_overlay.z_index = 48
	var view_size := _get_view_size()
	sakura_overlay.polygon = build_overlay_polygon(view_size)
	if sakura_shader:
		var sakura_material := ShaderMaterial.new()
		sakura_material.shader = sakura_shader
		sakura_overlay.material = sakura_material
	_overlay_canvas.add_child(sakura_overlay)
	if Engine.is_editor_hint():
		sakura_overlay.owner = _parent.get_tree().edited_scene_root
	_sakura_overlay = sakura_overlay
	return _sakura_overlay


func _ensure_flower_overlay() -> Polygon2D:
	if _overlay_canvas == null:
		return null
	if _flower_overlay != null:
		return _flower_overlay
	var flower_shader := load(FLOWER_SHADER_PATH)
	var node := _overlay_canvas.get_node_or_null("FlowerOverlay")
	if node and node is Polygon2D:
		var flowers := node as Polygon2D
		flowers.color = Color(1.0, 1.0, 1.0, 0.0)
		if flowers.material == null or not (flowers.material is ShaderMaterial):
			if flower_shader:
				var flower_material := ShaderMaterial.new()
				flower_material.shader = flower_shader
				flowers.material = flower_material
		_flower_overlay = flowers
		return _flower_overlay
	var flower_overlay := Polygon2D.new()
	flower_overlay.name = "FlowerOverlay"
	flower_overlay.z_index = -48
	flower_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
	var view_size := _get_view_size()
	flower_overlay.polygon = build_overlay_polygon(view_size)
	if flower_shader:
		var flower_material := ShaderMaterial.new()
		flower_material.shader = flower_shader
		flower_overlay.material = flower_material
		(flower_overlay.material as ShaderMaterial).set_shader_parameter("view_size", view_size)
	flower_overlay.visible = false
	_overlay_canvas.add_child(flower_overlay)
	if Engine.is_editor_hint():
		flower_overlay.owner = _parent.get_tree().edited_scene_root
	_flower_overlay = flower_overlay
	return _flower_overlay


func _update_snow(_delta: float, biome: BiomeDefinition, camera_view_size: Vector2, world_offset: Vector2) -> void:
	if _snow_overlay and _snow_overlay.material and _snow_overlay.visible:
		var snow_material := _snow_overlay.material as ShaderMaterial
		if snow_material:
			snow_material.set_shader_parameter("time_flow", _time_flow)
			snow_material.set_shader_parameter("view_size", camera_view_size)
			var wind_power := biome.wind_strength if biome else 0.4
			var wind_dir := Vector2(wind_power * 0.55, -0.65)
			snow_material.set_shader_parameter("wind_direction", wind_dir)
			snow_material.set_shader_parameter("world_offset", world_offset)


func _update_sakura(_delta: float, biome: BiomeDefinition, camera_view_size: Vector2, world_offset: Vector2) -> void:
	if _sakura_overlay and _sakura_overlay.material and _sakura_overlay.visible:
		var sakura_material := _sakura_overlay.material as ShaderMaterial
		if sakura_material:
			sakura_material.set_shader_parameter("time_flow", _time_flow)
			sakura_material.set_shader_parameter("view_size", camera_view_size)
			sakura_material.set_shader_parameter("world_offset", world_offset)
			var fall_speed := 0.85
			var wind_strength := 0.6
			if biome:
				fall_speed = clampf(biome.sakura_fall_speed, 0.1, 2.0)
				wind_strength = clampf(biome.wind_strength, 0.0, 5.0)
			var wind_vector := Vector2(wind_strength * 0.35, -fall_speed)
			sakura_material.set_shader_parameter("wind_direction", wind_vector)
			sakura_material.set_shader_parameter("drift_amplitude", clampf(0.25 + wind_strength * 0.25, 0.15, 0.85))


func _update_overlay_transform(camera_position: Vector2) -> void:
	if _overlay_canvas == null:
		return
	_overlay_canvas.global_position = camera_position
	_overlay_canvas.global_rotation = 0.0
	_overlay_canvas.global_scale = Vector2.ONE
	_update_snow_overlay_polygon(camera_position)
	_update_sakura_overlay_polygon(camera_position)
	_update_flower_overlay_polygon(camera_position)


func _update_overlay_layout(camera_view_size: Vector2, camera_position: Vector2) -> void:
	if _snow_overlay:
		var snow_material := _snow_overlay.material as ShaderMaterial
		if snow_material:
			snow_material.set_shader_parameter("view_size", camera_view_size)
		if _world_bounds.size == Vector2.ZERO:
			_snow_overlay.polygon = build_overlay_polygon(camera_view_size)
		else:
			_update_snow_overlay_polygon(camera_position)
	if _sakura_overlay:
		var sakura_material := _sakura_overlay.material as ShaderMaterial
		if sakura_material:
			sakura_material.set_shader_parameter("view_size", camera_view_size)
		if _world_bounds.size == Vector2.ZERO:
			_sakura_overlay.polygon = build_overlay_polygon(camera_view_size)
		else:
			_update_sakura_overlay_polygon(camera_position)
	if _flower_overlay:
		var flower_material := _flower_overlay.material as ShaderMaterial
		if flower_material:
			flower_material.set_shader_parameter("view_size", camera_view_size)
		if _world_bounds.size == Vector2.ZERO:
			_flower_overlay.polygon = build_overlay_polygon(camera_view_size)
		else:
			_update_flower_overlay_polygon(camera_position)


func _update_snow_overlay_polygon(camera_position: Vector2) -> void:
	if _snow_overlay == null:
		return
	if _world_bounds.size == Vector2.ZERO:
		_snow_overlay.polygon = build_overlay_polygon(_get_camera_view_size())
		return
	var min_corner := _world_bounds.position
	var max_corner := _world_bounds.position + _world_bounds.size
	var polygon := PackedVector2Array([
		Vector2(min_corner.x - camera_position.x, min_corner.y - camera_position.y),
		Vector2(max_corner.x - camera_position.x, min_corner.y - camera_position.y),
		Vector2(max_corner.x - camera_position.x, max_corner.y - camera_position.y),
		Vector2(min_corner.x - camera_position.x, max_corner.y - camera_position.y)
	])
	_snow_overlay.polygon = polygon


func _update_sakura_overlay_polygon(camera_position: Vector2) -> void:
	if _sakura_overlay == null:
		return
	if _world_bounds.size == Vector2.ZERO:
		_sakura_overlay.polygon = build_overlay_polygon(_get_camera_view_size())
		return
	var min_corner := _world_bounds.position
	var max_corner := _world_bounds.position + _world_bounds.size
	var polygon := PackedVector2Array([
		Vector2(min_corner.x - camera_position.x, min_corner.y - camera_position.y),
		Vector2(max_corner.x - camera_position.x, min_corner.y - camera_position.y),
		Vector2(max_corner.x - camera_position.x, max_corner.y - camera_position.y),
		Vector2(min_corner.x - camera_position.x, max_corner.y - camera_position.y)
	])
	_sakura_overlay.polygon = polygon


func _update_flower_overlay_polygon(_camera_position: Vector2) -> void:
	if _flower_overlay == null:
		return
	var view_size := _get_camera_view_size()
	_flower_overlay.polygon = build_overlay_polygon(view_size)


func _get_camera_view_size() -> Vector2:
	var viewport := _get_viewport()
	if viewport == null:
		return _get_view_size()
	var rect_size := viewport.get_visible_rect().size
	var camera := viewport.get_camera_2d()
	if camera:
		rect_size.x *= camera.zoom.x
		rect_size.y *= camera.zoom.y
	return rect_size


func _compute_world_offset() -> Vector2:
	var viewport := _get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var camera := viewport.get_camera_2d()
	if camera == null:
		return Vector2.ZERO
	var zoom := camera.zoom
	var view_size := viewport.get_visible_rect().size * zoom
	return camera.global_position - view_size * 0.5


func _get_view_size() -> Vector2:
	var viewport := _get_viewport()
	if viewport:
		return viewport.get_visible_rect().size
	return Vector2(1920.0, 1080.0)


func _get_viewport() -> Viewport:
	if _parent and _parent.get_viewport():
		return _parent.get_viewport()
	return null
