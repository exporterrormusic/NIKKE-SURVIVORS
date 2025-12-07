extends Node2D
class_name EnvironmentController

signal environment_changed(biome_id: StringName, time_id: StringName)

const BIOMES_DIR := "res://resources/biomes/"
const TIME_OF_DAY_DIR := "res://resources/time_of_day/"

var biome_definitions: Array = []
var time_of_day_definitions: Array = []
@export_range(512.0, 8192.0, 16.0) var ground_extent: float = 4096.0
@export_range(0, 2147483647, 1) var environment_seed: int = 0
@export var auto_initialize: bool = true
@export var use_fixed_seed: bool = false
@export var enable_physical_grass: bool = true  # Toggle grass system on/off

const GROUND_SHADER_PATH := "res://resources/shaders/procedural_ground.gdshader"
const SNOW_SHADER_PATH := "res://resources/shaders/falling_snow.gdshader"
const SAKURA_SHADER_PATH := "res://resources/shaders/falling_sakura.gdshader"
const FLOWER_SHADER_PATH := "res://resources/shaders/flower_patches.gdshader"
const ENABLE_SAKURA_OVERLAY := false
const SNOW_IMPRINT_TEXTURE_SIZE := 1024
const SNOW_IMPRINT_DEFAULT := 0.5
const SNOW_FOOTPRINT_FADE := 0.8
const SNOW_PATH_RADIUS := 120.0
const SNOW_PARTICLE_LIFETIME := 0.55
const SNOW_PARTICLE_GRAVITY := 480.0
const WORLD_BORDER_THICKNESS := 60.0
const WORLD_BORDER_COLOR := Color(0.08, 0.08, 0.1, 0.0)  # make border overlay fully transparent (keep collisions)
const VIGNETTE_SHADER_PATH := "res://resources/shaders/environment_vignette.gdshader"
const PhysicalGrassFieldScript := preload("res://src/world/physical_grass_field.gd")
const ProceduralBoulderScript := preload("res://src/world/environment/procedural_boulder.gd")

var _active_biome: BiomeDefinition = null
var _active_time: TimeOfDayDefinition = null
var _rng := RandomNumberGenerator.new()
var _time_flow: float = 0.0
var _biome_lookup: Dictionary = {}
var _time_lookup: Dictionary = {}
var _decoration_entries: Array[Dictionary] = []
var _effective_ground_extent: float = 0.0
var _snow_imprint_image: Image = null
var _snow_imprint_texture: ImageTexture = null
var _snow_imprint_enabled: bool = false
var _snow_particle_texture: Texture2D = null
var _current_ambient_path: String = ""
var _world_bounds: Rect2 = Rect2()
var _grass_field: Node2D = null  # PhysicalGrassField instance
var _player_ref: Node2D = null  # Track player for grass interaction
var _boulder_container: Node2D = null  # Container for boulders
var _boulders: Array[Node2D] = []  # Active boulder instances

@onready var _background: Polygon2D = _ensure_background()
@onready var _ground: Polygon2D = _ensure_ground()
@onready var _decor_container: Node2D = _ensure_decor_container()
@onready var _fog_overlay: ColorRect = _ensure_fog_overlay()
@onready var _overlay_canvas: Node2D = _ensure_overlay_canvas()
@onready var _vignette_overlay: ColorRect = _ensure_vignette_overlay()
@onready var _snow_overlay: Polygon2D = _ensure_snow_overlay()
@onready var _sakura_overlay: Polygon2D = _ensure_sakura_overlay()
@onready var _flower_overlay: Polygon2D = _ensure_flower_overlay()
@onready var _snow_pile_container: Node2D = _ensure_snow_pile_container()
@onready var _snow_particle_container: Node2D = _ensure_snow_particle_container()
@onready var _canvas_modulate: CanvasModulate = _ensure_canvas_modulate()
@onready var _sun_light: DirectionalLight2D = _ensure_sun_light()
@onready var _audio_director: AudioDirector = _resolve_audio_director()
@onready var _border_overlay: Node2D = _ensure_border_overlay()

func _ready() -> void:
	_load_biome_definitions()
	_load_time_of_day_definitions()
	_update_ground_geometry()
	_rebuild_lookups()
	_configure_rng(environment_seed)
	if auto_initialize:
		initialize_environment(environment_seed if use_fixed_seed else 0)
	set_process(true)
	var viewport := get_viewport()
	if viewport:
		viewport.size_changed.connect(_on_viewport_size_changed)
	_update_overlay_layout()
	# Ensure any previously saved visual border polygons are removed from
	# scenes. These could have been created earlier in-editor; proactively
	# clear them so borders remain invisible at runtime.
	_cleanup_saved_border_visuals()


func _cleanup_saved_border_visuals() -> void:
	# Recursively find all nodes named BorderOverlay and free any Polygon2D
	# children so no visible border squares remain if they were previously
	# persisted in editor scenes.
	var root := get_tree().root
	var overlays := []
	_collect_nodes_by_name(root, "BorderOverlay", overlays)
	for overlay in overlays:
		for child in overlay.get_children():
			# Preserve physics/collision bodies — remove visual-only nodes that
			# may have been saved into scenes earlier. This will remove the
			# persistent colored squares (Polygon2D / ColorRect / Sprite2D)
			# while keeping StaticBody2D + CollisionPolygon2D intact.
			if child is StaticBody2D:
				continue
			if child is CollisionPolygon2D:
				continue
			# Remove common visual node types that could be used to draw borders
			if child is Polygon2D or child is ColorRect or child is Sprite2D or child is CanvasItem:
				child.queue_free()


func _collect_nodes_by_name(node: Node, name_to_find: String, out_list: Array) -> void:
	if node.name == name_to_find:
		out_list.append(node)
	for child in node.get_children():
		if child is Node:
			_collect_nodes_by_name(child, name_to_find, out_list)

func _load_biome_definitions() -> void:
	biome_definitions.clear()
	# Use ResourceManifest for export-safe file listing
	ResourceManifest.ensure_initialized()
	for file_path in ResourceManifest.biome_files:
		if ResourceLoader.exists(file_path):
			var resource := load(file_path)
			if resource is BiomeDefinition:
				biome_definitions.append(resource)
				print("[Environment] Loaded biome: ", file_path.get_file())
	print("[Environment] Total biomes loaded: ", biome_definitions.size())

func _load_time_of_day_definitions() -> void:
	time_of_day_definitions.clear()
	# Use ResourceManifest for export-safe file listing
	ResourceManifest.ensure_initialized()
	for file_path in ResourceManifest.time_of_day_files:
		if ResourceLoader.exists(file_path):
			var resource := load(file_path)
			if resource is TimeOfDayDefinition:
				time_of_day_definitions.append(resource)
				print("[Environment] Loaded time of day: ", file_path.get_file())
	print("[Environment] Total time of day presets loaded: ", time_of_day_definitions.size())

func _process(delta: float) -> void:
	_time_flow += delta
	var shader_material := _get_shader_material()
	if shader_material:
		shader_material.set_shader_parameter("time_flow", _time_flow)
		if _active_biome:
			shader_material.set_shader_parameter("wind_strength", _active_biome.wind_strength)
	if _snow_overlay and _snow_overlay.material and _snow_overlay.visible:
		var snow_material := _snow_overlay.material as ShaderMaterial
		if snow_material:
			snow_material.set_shader_parameter("time_flow", _time_flow)
			snow_material.set_shader_parameter("view_size", _get_camera_view_size())
			var wind_power := _active_biome.wind_strength if _active_biome else 0.4
			var wind_dir := Vector2(wind_power * 0.55, -0.65)
			snow_material.set_shader_parameter("wind_direction", wind_dir)
			snow_material.set_shader_parameter("world_offset", _compute_camera_world_offset())
	if _sakura_overlay and _sakura_overlay.material and _sakura_overlay.visible:
		var sakura_material := _sakura_overlay.material as ShaderMaterial
		if sakura_material:
			sakura_material.set_shader_parameter("time_flow", _time_flow)
			sakura_material.set_shader_parameter("view_size", _get_camera_view_size())
			sakura_material.set_shader_parameter("world_offset", _compute_camera_world_offset())
			var fall_speed := 0.85
			var wind_strength := 0.6
			if _active_biome:
				fall_speed = clampf(_active_biome.sakura_fall_speed, 0.1, 2.0)
				wind_strength = clampf(_active_biome.wind_strength, 0.0, 5.0)
			var wind_vector := Vector2(wind_strength * 0.35, -fall_speed)
			sakura_material.set_shader_parameter("wind_direction", wind_vector)
			sakura_material.set_shader_parameter("drift_amplitude", clampf(0.25 + wind_strength * 0.25, 0.15, 0.85))
	# DISABLED: Flower overlay causing shader errors
	#if _flower_overlay and _flower_overlay.material and _flower_overlay.visible:
	#	var flower_material := _flower_overlay.material as ShaderMaterial
	#	if flower_material:
	#		flower_material.set_shader_parameter("time_flow", _time_flow)
	#		flower_material.set_shader_parameter("view_size", _get_camera_view_size())
	#		flower_material.set_shader_parameter("world_offset", _compute_camera_world_offset())
	_update_overlay_transform()
	_update_decoration_animations(delta)
	
	# Update grass with player position
	if _grass_field and _player_ref and is_instance_valid(_player_ref):
		_grass_field.update_player_position(_player_ref.global_position)

func _exit_tree() -> void:
	_stop_ambient_audio()

func initialize_environment(seed_override: int = 0, biome_id: StringName = &"", time_id: StringName = &"") -> void:
	_configure_rng(seed_override)
	_active_biome = _select_biome(biome_id)
	_active_time = _select_time_of_day(time_id)
	_apply_biome_to_ground()
	_apply_time_of_day_settings()
	_spawn_decorations()
	_update_grass_field()  # Create/update grass based on biome
	# Defer boulder spawning to reduce initial lag spike
	call_deferred("_spawn_boulders")  # Spawn obstacle boulders
	emit_signal("environment_changed", _get_biome_id(), _get_time_id())
	_update_ambient_audio()

func set_environment(biome_id: StringName, time_id: StringName, seed_override: int = 0) -> void:
	initialize_environment(seed_override, biome_id, time_id)

func set_time_of_day(time_id: StringName) -> void:
	"""Change only the time of day, preserving current biome."""
	var current_biome_id := _get_biome_id()
	_active_time = _select_time_of_day(time_id)
	_apply_time_of_day_settings()
	_update_ambient_audio()
	emit_signal("environment_changed", current_biome_id, _get_time_id())
	print("[Environment] Time of day changed to: ", _get_time_id())

func refresh(seed_override: int = -1) -> void:
	if seed_override >= 0:
		environment_seed = seed_override
	initialize_environment(environment_seed if use_fixed_seed else 0, _get_biome_id(), _get_time_id())

func register_player(player: Node2D) -> void:
	"""Register the player for grass interaction."""
	_player_ref = player

func get_active_biome() -> BiomeDefinition:
	return _active_biome

func get_active_time_of_day() -> TimeOfDayDefinition:
	return _active_time

func _configure_rng(seed_value: int) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

func set_world_bounds(bounds: Rect2) -> void:
	_world_bounds = bounds
	_update_ground_geometry()
	_update_border_overlay()
	_update_snow_overlay_polygon(_get_camera_global_position())
	_update_sakura_overlay_polygon(_get_camera_global_position())
	_update_flower_overlay_polygon(_get_camera_global_position())
	# Respawn boulders when bounds change (e.g., when entering a map)
	if _active_biome != null:
		_spawn_boulders()

func _rebuild_lookups() -> void:
	_biome_lookup.clear()
	_time_lookup.clear()
	for biome in biome_definitions:
		if biome == null:
			continue
		var key: StringName = biome.biome_id if biome.biome_id != &"" else StringName(biome.display_name.to_lower())
		_biome_lookup[key] = biome
	for tod in time_of_day_definitions:
		if tod == null:
			continue
		var key: StringName = tod.time_id if tod.time_id != &"" else StringName(tod.display_name.to_lower())
		_time_lookup[key] = tod

func _select_biome(requested_id: StringName) -> BiomeDefinition:
	if requested_id != &"" and _biome_lookup.has(requested_id):
		return _biome_lookup[requested_id]
	if biome_definitions.is_empty():
		return null
	return biome_definitions[_rng.randi_range(0, biome_definitions.size() - 1)]

func _select_time_of_day(requested_id: StringName) -> TimeOfDayDefinition:
	if requested_id != &"" and _time_lookup.has(requested_id):
		return _time_lookup[requested_id]
	if time_of_day_definitions.is_empty():
		return null
	return time_of_day_definitions[_rng.randi_range(0, time_of_day_definitions.size() - 1)]

func _get_biome_id() -> StringName:
	return _active_biome.biome_id if _active_biome and _active_biome.biome_id != &"" else StringName("")

func _get_time_id() -> StringName:
	return _active_time.time_id if _active_time and _active_time.time_id != &"" else StringName("")

func is_night_time() -> bool:
	if _active_time == null:
		return false
	var raw_id := String(_active_time.time_id) if _active_time.time_id != &"" else _active_time.display_name
	var lowered := raw_id.to_lower()
	if lowered.find("night") != -1 or lowered.find("midnight") != -1:
		return true
	if _active_time.light_energy <= 0.45:
		return true
	if _active_time.ambient_intensity <= 0.55:
		return true
	return false

func is_day_time() -> bool:
	return not is_night_time()

func _ensure_background() -> Polygon2D:
	var node := get_node_or_null("Background")
	if node and node is Polygon2D:
		return node
	var background := Polygon2D.new()
	background.name = "Background"
	background.z_index = -200
	background.color = Color(0.2, 0.3, 0.4, 1.0)
	add_child(background)
	if Engine.is_editor_hint():
		background.owner = get_tree().edited_scene_root
	return background

func _ensure_ground() -> Polygon2D:
	var node := get_node_or_null("Ground")
	if node and node is Polygon2D:
		return node
	var ground := Polygon2D.new()
	ground.name = "Ground"
	ground.z_index = -150
	ground.color = Color.WHITE
	add_child(ground)
	if Engine.is_editor_hint():
		ground.owner = get_tree().edited_scene_root
	return ground

func _ensure_decor_container() -> Node2D:
	var node := get_node_or_null("DecorContainer")
	if node and node is Node2D:
		return node
	var container := Node2D.new()
	container.name = "DecorContainer"
	container.z_index = -50
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root
	return container

func _ensure_border_overlay() -> Node2D:
	var node := get_node_or_null("BorderOverlay")
	if node and node is Node2D:
		return node
	var border := Node2D.new()
	border.name = "BorderOverlay"
	border.z_index = -140
	add_child(border)
	if Engine.is_editor_hint():
		border.owner = get_tree().edited_scene_root
	return border

func _ensure_fog_overlay() -> ColorRect:
	var node := get_node_or_null("FogOverlay")
	if node and node is ColorRect:
		var fog := node as ColorRect
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return fog
	var fog_overlay := ColorRect.new()
	fog_overlay.name = "FogOverlay"
	fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_overlay.color = Color(0.8, 0.85, 0.95, 0.0)
	fog_overlay.size = Vector2.ONE * _get_effective_ground_extent()
	fog_overlay.position = -fog_overlay.size * 0.5
	add_child(fog_overlay)
	if Engine.is_editor_hint():
		fog_overlay.owner = get_tree().edited_scene_root
	return fog_overlay

func _ensure_overlay_canvas() -> Node2D:
	var node := get_node_or_null("EnvironmentOverlay")
	if node and node is Node2D:
		var overlay := node as Node2D
		overlay.top_level = true
		overlay.z_index = 60
		overlay.z_as_relative = false
		return overlay
	var environment_overlay := Node2D.new()
	environment_overlay.name = "EnvironmentOverlay"
	environment_overlay.z_index = 60
	environment_overlay.top_level = true
	environment_overlay.z_as_relative = false
	add_child(environment_overlay)
	if Engine.is_editor_hint():
		environment_overlay.owner = get_tree().edited_scene_root
	return environment_overlay

func _ensure_vignette_overlay() -> ColorRect:
	if _overlay_canvas == null:
		return null
	var vignette_shader := load(VIGNETTE_SHADER_PATH)
	var node := _overlay_canvas.get_node_or_null("VignetteOverlay")
	if node and node is ColorRect:
		var vignette := node as ColorRect
		vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if vignette.material == null or not (vignette.material is ShaderMaterial):
			if vignette_shader:
				var shader_material := ShaderMaterial.new()
				shader_material.shader = vignette_shader
				vignette.material = shader_material
		return vignette
	var vignette_overlay := ColorRect.new()
	vignette_overlay.name = "VignetteOverlay"
	vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	vignette_overlay.z_index = 200
	if vignette_shader:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = vignette_shader
		vignette_overlay.material = shader_material
	_overlay_canvas.add_child(vignette_overlay)
	if Engine.is_editor_hint():
		vignette_overlay.owner = get_tree().edited_scene_root
	return vignette_overlay

func _configure_vignette_overlay(strength: float) -> void:
	if _vignette_overlay == null:
		return
	if strength <= 0.01:
		_vignette_overlay.visible = false
		BasicProjectileVisual.set_vignette_profile(0.0, 0.5, 0.4, _get_camera_view_size())
		return
	_vignette_overlay.visible = true
	var view_size := _get_camera_view_size()
	_vignette_overlay.size = view_size
	_vignette_overlay.position = -view_size * 0.5
	var shader_material := _vignette_overlay.material as ShaderMaterial
	var clamped_strength := clampf(strength, 0.0, 1.0)
	var inner_radius := lerpf(0.38, 0.62, clampf(1.0 - clamped_strength, 0.0, 1.0))
	var softness := lerpf(0.24, 0.48, 1.0 - clamped_strength)
	if shader_material:
		shader_material.set_shader_parameter("vignette_strength", clamped_strength)
		shader_material.set_shader_parameter("inner_radius", inner_radius)
		shader_material.set_shader_parameter("softness", softness)
		shader_material.set_shader_parameter("tint", Color(0.0, 0.0, 0.0, 1.0))
	BasicProjectileVisual.set_vignette_profile(clamped_strength, inner_radius, softness, view_size)

func _ensure_snow_overlay() -> Polygon2D:
	if _overlay_canvas == null:
		return null
	var snow_shader := load(SNOW_SHADER_PATH)
	var node := _overlay_canvas.get_node_or_null("SnowOverlay")
	if node and node is Polygon2D:
		var snow := node as Polygon2D
		if snow.material == null or not (snow.material is ShaderMaterial):
			if snow_shader:
				var snow_shader_material := ShaderMaterial.new()
				snow_shader_material.shader = snow_shader
				snow.material = snow_shader_material
		return snow
	var snow_overlay := Polygon2D.new()
	snow_overlay.name = "SnowOverlay"
	snow_overlay.z_index = 50
	var view_size := _get_view_size()
	snow_overlay.polygon = _build_overlay_polygon(view_size)
	if snow_shader:
		var snow_material := ShaderMaterial.new()
		snow_material.shader = snow_shader
		snow_overlay.material = snow_material
		(snow_overlay.material as ShaderMaterial).set_shader_parameter("view_size", view_size)
	_overlay_canvas.add_child(snow_overlay)
	if Engine.is_editor_hint():
		snow_overlay.owner = get_tree().edited_scene_root
	return snow_overlay

func _ensure_sakura_overlay() -> Polygon2D:
	if _overlay_canvas == null:
		return null
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
			return sakura
		sakura.visible = false
		return null
	if not ENABLE_SAKURA_OVERLAY:
		return null
	var sakura_overlay := Polygon2D.new()
	sakura_overlay.name = "SakuraOverlay"
	sakura_overlay.z_index = 48
	var view_size := _get_view_size()
	sakura_overlay.polygon = _build_overlay_polygon(view_size)
	if sakura_shader:
		var sakura_material := ShaderMaterial.new()
		sakura_material.shader = sakura_shader
		sakura_overlay.material = sakura_material
	_overlay_canvas.add_child(sakura_overlay)
	if Engine.is_editor_hint():
		sakura_overlay.owner = get_tree().edited_scene_root
	return sakura_overlay

func _ensure_flower_overlay() -> Polygon2D:
	if _overlay_canvas == null:
		return null
	var flower_shader := load(FLOWER_SHADER_PATH)
	var node := _overlay_canvas.get_node_or_null("FlowerOverlay")
	if node and node is Polygon2D:
		var flowers := node as Polygon2D
		flowers.color = Color(1.0, 1.0, 1.0, 0.0)  # Ensure transparent base
		if flowers.material == null or not (flowers.material is ShaderMaterial):
			if flower_shader:
				var flower_material := ShaderMaterial.new()
				flower_material.shader = flower_shader
				flowers.material = flower_material
		return flowers
	var flower_overlay := Polygon2D.new()
	flower_overlay.name = "FlowerOverlay"
	flower_overlay.z_index = -48  # Below ground level, so flowers appear on the ground
	flower_overlay.color = Color(1.0, 1.0, 1.0, 0.0)  # Transparent base - shader handles all colors
	var view_size := _get_view_size()
	flower_overlay.polygon = _build_overlay_polygon(view_size)
	if flower_shader:
		var flower_material := ShaderMaterial.new()
		flower_material.shader = flower_shader
		flower_overlay.material = flower_material
		(flower_overlay.material as ShaderMaterial).set_shader_parameter("view_size", view_size)
	flower_overlay.visible = false  # Start hidden, enable when biome has flowers
	_overlay_canvas.add_child(flower_overlay)
	if Engine.is_editor_hint():
		flower_overlay.owner = get_tree().edited_scene_root
	return flower_overlay

func _build_overlay_polygon(view_size: Vector2) -> PackedVector2Array:
	var half := view_size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])

func _ensure_snow_pile_container() -> Node2D:
	var node := get_node_or_null("SnowPiles")
	if node and node is Node2D:
		return node
	var container := Node2D.new()
	container.name = "SnowPiles"
	container.z_index = -45
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root
	return container

func _ensure_snow_particle_container() -> Node2D:
	var node := get_node_or_null("SnowParticles")
	if node and node is Node2D:
		return node
	var container := Node2D.new()
	container.name = "SnowParticles"
	container.z_index = -40
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root
	return container

func _ensure_canvas_modulate() -> CanvasModulate:
	var node := get_node_or_null("CanvasModulate")
	if node and node is CanvasModulate:
		return node
	var canvas_modulate := CanvasModulate.new()
	canvas_modulate.name = "CanvasModulate"
	canvas_modulate.color = Color(1.0, 1.0, 1.0, 1.0)
	add_child(canvas_modulate)
	if Engine.is_editor_hint():
		canvas_modulate.owner = get_tree().edited_scene_root
	return canvas_modulate

func _ensure_sun_light() -> DirectionalLight2D:
	var node := get_node_or_null("SunLight")
	if node and node is DirectionalLight2D:
		return node
	var sun := DirectionalLight2D.new()
	sun.name = "SunLight"
	sun.color = Color(1.0, 0.95, 0.85, 1.0)
	sun.energy = 1.0
	sun.rotation = Vector2(-0.5, 1.0).angle()
	sun.editor_only = false
	add_child(sun)
	if Engine.is_editor_hint():
		sun.owner = get_tree().edited_scene_root
	return sun

func _update_ground_geometry() -> void:
	var use_world_bounds := _world_bounds.size != Vector2.ZERO
	var polygon := PackedVector2Array()
	var uvs := PackedVector2Array()
	if use_world_bounds:
		var min_corner := _world_bounds.position
		var max_corner := _world_bounds.position + _world_bounds.size
		polygon = PackedVector2Array([
			Vector2(min_corner.x, min_corner.y),
			Vector2(max_corner.x, min_corner.y),
			Vector2(max_corner.x, max_corner.y),
			Vector2(min_corner.x, max_corner.y)
		])
		var uv_scale := Vector2(max(0.01, _world_bounds.size.x) / 512.0, max(0.01, _world_bounds.size.y) / 512.0)
		uvs = PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(uv_scale.x, 0.0),
			Vector2(uv_scale.x, uv_scale.y),
			Vector2(0.0, uv_scale.y)
		])
		_effective_ground_extent = maxf(_world_bounds.size.x, _world_bounds.size.y)
	else:
		var view_size := _get_view_size()
		var dynamic_extent := maxf(ground_extent, maxf(view_size.x, view_size.y) * 6.0)
		_effective_ground_extent = dynamic_extent
		var half := _effective_ground_extent * 0.5
		polygon = PackedVector2Array([
			Vector2(-half, -half),
			Vector2(half, -half),
			Vector2(half, half),
			Vector2(-half, half)
		])
		var uv_scalar := _effective_ground_extent / 512.0
		uvs = PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(uv_scalar, 0.0),
			Vector2(uv_scalar, uv_scalar),
			Vector2(0.0, uv_scalar)
		])
	if _ground:
		_ground.polygon = polygon
		_ground.uv = uvs
		_ground.offset = Vector2.ZERO
	var sky_polygon := PackedVector2Array()
	if use_world_bounds:
		var expansion := Vector2(WORLD_BORDER_THICKNESS, WORLD_BORDER_THICKNESS)
		var min_corner := _world_bounds.position - expansion
		var max_corner := _world_bounds.position + _world_bounds.size + expansion
		sky_polygon = PackedVector2Array([
			Vector2(min_corner.x, min_corner.y),
			Vector2(max_corner.x, min_corner.y),
			Vector2(max_corner.x, max_corner.y),
			Vector2(min_corner.x, max_corner.y)
		])
	else:
		var sky_half := _effective_ground_extent * 0.75
		sky_polygon = PackedVector2Array([
			Vector2(-sky_half, -sky_half),
			Vector2(sky_half, -sky_half),
			Vector2(sky_half, sky_half),
			Vector2(-sky_half, sky_half)
		])
	if _background:
		_background.polygon = sky_polygon
		_background.uv = uvs
	if _fog_overlay:
		if use_world_bounds:
			_fog_overlay.size = _world_bounds.size
			_fog_overlay.position = _world_bounds.position
		else:
			_fog_overlay.size = Vector2.ONE * _effective_ground_extent
			_fog_overlay.position = -_fog_overlay.size * 0.5
	_update_border_overlay()
	_update_overlay_layout()


func _update_border_overlay() -> void:
	if _border_overlay == null:
		return
	for child in _border_overlay.get_children():
		child.queue_free()
	if _world_bounds.size == Vector2.ZERO:
		_border_overlay.visible = false
		return
	_border_overlay.visible = true
	var min_corner := _world_bounds.position
	var size := _world_bounds.size
	var max_corner := min_corner + size
	var thickness := WORLD_BORDER_THICKNESS
	var segments := [
		PackedVector2Array([
			Vector2(min_corner.x - thickness, min_corner.y - thickness),
			Vector2(min_corner.x, min_corner.y - thickness),
			Vector2(min_corner.x, max_corner.y + thickness),
			Vector2(min_corner.x - thickness, max_corner.y + thickness)
		]),
		PackedVector2Array([
			Vector2(max_corner.x, min_corner.y - thickness),
			Vector2(max_corner.x + thickness, min_corner.y - thickness),
			Vector2(max_corner.x + thickness, max_corner.y + thickness),
			Vector2(max_corner.x, max_corner.y + thickness)
		]),
		PackedVector2Array([
			Vector2(min_corner.x - thickness, min_corner.y - thickness),
			Vector2(max_corner.x + thickness, min_corner.y - thickness),
			Vector2(max_corner.x + thickness, min_corner.y),
			Vector2(min_corner.x - thickness, min_corner.y)
		]),
		PackedVector2Array([
			Vector2(min_corner.x - thickness, max_corner.y),
			Vector2(max_corner.x + thickness, max_corner.y),
			Vector2(max_corner.x + thickness, max_corner.y + thickness),
			Vector2(min_corner.x - thickness, max_corner.y + thickness)
		])
	]
	for polygon_points in segments:
		var body := StaticBody2D.new()
		body.collision_layer = 1  # Default layer
		body.collision_mask = 0   # Doesn't collide with anything, just blocks
		var collision_shape := CollisionPolygon2D.new()
		collision_shape.polygon = polygon_points
		body.add_child(collision_shape)
		
		# We used to add a visible Polygon2D so the borders showed up as
		# colored squares on the sides of the map. Keep the collision
		# polygon only (CollisionPolygon2D) and do not add a visual Polygon2D
		# so the border remains functionally present but invisible.
		# (If you need editor-visible visuals later, re-enable Polygon2D under
		# Engine.is_editor_hint() only.)
		
		_border_overlay.add_child(body)
		if Engine.is_editor_hint():
			body.owner = get_tree().edited_scene_root

func _get_shader_material() -> ShaderMaterial:
	if not _ground:
		return null
	if _ground.material and _ground.material is ShaderMaterial:
		return _ground.material
	var shader := load(GROUND_SHADER_PATH)
	if shader == null:
		return null
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	_ground.material = shader_material
	return shader_material

func _apply_biome_to_ground() -> void:
	var shader_material := _get_shader_material()
	if not shader_material:
		return
	var biome := _active_biome
	if biome == null:
		shader_material.set_shader_parameter("base_color", Color(0.22, 0.28, 0.3, 1.0))
		shader_material.set_shader_parameter("secondary_color", Color(0.18, 0.24, 0.28, 1.0))
		shader_material.set_shader_parameter("accent_color", Color(0.35, 0.4, 0.48, 1.0))
		shader_material.set_shader_parameter("noise_scale", 6.0)
		shader_material.set_shader_parameter("detail_strength", 0.35)
		shader_material.set_shader_parameter("wave_strength", 0.12)
		shader_material.set_shader_parameter("wave_speed", 0.45)
		shader_material.set_shader_parameter("patchwork_strength", 0.3)
		shader_material.set_shader_parameter("color_variation", 0.2)
		# Procedural ground details (defaults off for null biome)
		shader_material.set_shader_parameter("pebble_density", 0.0)
		shader_material.set_shader_parameter("pebble_size", 0.08)
		shader_material.set_shader_parameter("pebble_color", Color(0.35, 0.32, 0.28, 1.0))
		shader_material.set_shader_parameter("crack_intensity", 0.0)
		shader_material.set_shader_parameter("highlight_spots", 0.0)
		shader_material.set_shader_parameter("spot_color", Color(0.85, 0.78, 0.35, 1.0))
		shader_material.set_shader_parameter("ground_shadow_strength", 0.0)
		shader_material.set_shader_parameter("shimmer_intensity", 0.0)
		shader_material.set_shader_parameter("snow_cover", 0.0)
		shader_material.set_shader_parameter("snow_brightness", 1.0)
		shader_material.set_shader_parameter("snow_tint_color", Vector3(0.86, 0.92, 1.0))
		shader_material.set_shader_parameter("snow_tint_strength", 0.0)
		shader_material.set_shader_parameter("snow_shadow_strength", 0.0)
		shader_material.set_shader_parameter("snow_drift_scale", 0.6)
		shader_material.set_shader_parameter("snow_crust_strength", 0.0)
		shader_material.set_shader_parameter("snow_ice_highlight", 0.0)
		shader_material.set_shader_parameter("snow_sparkle_intensity", 0.0)
		_apply_snow_overlay_settings(null)
		_apply_sakura_overlay_settings(null)
		_apply_flower_overlay_settings(null)
		_configure_snow_imprint_state(null)
		return
	
	# Use biome's defined colors instead of hardcoded Spotify green
	shader_material.set_shader_parameter("base_color", biome.base_color)
	shader_material.set_shader_parameter("secondary_color", biome.secondary_color)
	shader_material.set_shader_parameter("accent_color", biome.accent_color)
	shader_material.set_shader_parameter("noise_scale", biome.noise_scale)
	shader_material.set_shader_parameter("detail_strength", biome.detail_strength)
	shader_material.set_shader_parameter("wave_strength", biome.wave_strength)
	shader_material.set_shader_parameter("wave_speed", biome.wave_speed)
	shader_material.set_shader_parameter("patchwork_strength", biome.patchwork_strength)
	shader_material.set_shader_parameter("color_variation", biome.color_variation)
	shader_material.set_shader_parameter("wind_strength", biome.wind_strength)
	
	# Procedural ground details
	shader_material.set_shader_parameter("pebble_density", biome.pebble_density)
	shader_material.set_shader_parameter("pebble_size", biome.pebble_size)
	shader_material.set_shader_parameter("pebble_color", biome.pebble_color)
	shader_material.set_shader_parameter("crack_intensity", biome.crack_intensity)
	shader_material.set_shader_parameter("highlight_spots", biome.highlight_spots)
	shader_material.set_shader_parameter("spot_color", biome.spot_color)
	shader_material.set_shader_parameter("ground_shadow_strength", biome.ground_shadow_strength)
	shader_material.set_shader_parameter("shimmer_intensity", biome.shimmer_intensity)
	
	shader_material.set_shader_parameter("snow_cover", biome.snow_cover)
	shader_material.set_shader_parameter("snow_brightness", biome.snow_brightness)
	shader_material.set_shader_parameter("snow_tint_color", Vector3(biome.snow_tint_color.r, biome.snow_tint_color.g, biome.snow_tint_color.b))
	shader_material.set_shader_parameter("snow_tint_strength", biome.snow_tint_strength)
	shader_material.set_shader_parameter("snow_shadow_strength", biome.snow_shadow_strength)
	shader_material.set_shader_parameter("snow_drift_scale", biome.snow_drift_scale)
	shader_material.set_shader_parameter("snow_crust_strength", biome.snow_crust_strength)
	shader_material.set_shader_parameter("snow_ice_highlight", biome.snow_ice_highlight)
	shader_material.set_shader_parameter("snow_sparkle_intensity", biome.snow_sparkle_intensity)
	if _background:
		_background.color = biome.sky_color
	_apply_snow_overlay_settings(biome)
	_apply_sakura_overlay_settings(biome)
	_apply_flower_overlay_settings(biome)
	_configure_snow_imprint_state(biome)

func _apply_time_of_day_settings() -> void:
	var is_default_day := _active_time != null and _active_time.time_id == &"day"
	if is_default_day:
		if _canvas_modulate:
			# Slightly reduce daytime brightness to prevent washed-out look
			var day_color := Color(0.95, 0.95, 0.95, 1.0)
			_canvas_modulate.color = day_color
			_update_projectile_ambient_compensation(day_color)
		if _fog_overlay:
			_fog_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
		if _background:
			if _active_biome:
				_background.color = _active_biome.sky_color
			else:
				_background.color = Color(1.0, 1.0, 1.0, 1.0)
		if _sun_light:
			_sun_light.visible = false
			_sun_light.energy = 0.0
		_configure_vignette_overlay(0.0)
		BasicProjectileVisual.set_time_of_day(true)
		# Adjust bloom for daytime (subtle)
		_update_bloom_for_time_of_day(true)
		return
	if _canvas_modulate and _active_time:
		var modulate_color := _active_time.get_canvas_modulate()
		_canvas_modulate.color = modulate_color
		_update_projectile_ambient_compensation(modulate_color)
	elif _canvas_modulate:
		var default_color := Color(1.0, 1.0, 1.0, 1.0)
		_canvas_modulate.color = default_color
		_update_projectile_ambient_compensation(default_color)
	if _fog_overlay:
		if _active_time:
			var fog_color := _active_time.fog_color
			fog_color.a = clamp(_active_time.fog_alpha, 0.0, 1.0)
			_fog_overlay.color = fog_color
		else:
			_fog_overlay.color = Color(0.8, 0.85, 0.95, 0.0)
	if _background and _active_time and _active_biome:
		var tint_strength: float = clamp(_active_time.ambient_intensity, 0.0, 1.5)
		var target := _active_biome.sky_color.lerp(_active_biome.horizon_color, 0.35)
		_background.color = target.lerp(_active_time.sky_tint, tint_strength * 0.5)
	elif _background and _active_time:
		_background.color = _active_time.sky_tint
	if _sun_light:
		if _active_time:
			_sun_light.visible = true
			_sun_light.color = _active_time.light_color
			_sun_light.energy = maxf(0.0, _active_time.light_energy)
			var angle := deg_to_rad(_active_time.light_angle_degrees)
			_sun_light.rotation = angle
		else:
			_sun_light.color = Color(1.0, 0.96, 0.85, 1.0)
			_sun_light.energy = 1.0
	var vignette_strength := 0.0
	if _active_time:
		vignette_strength = clampf(_active_time.vignette_strength, 0.0, 1.0)
	_configure_vignette_overlay(vignette_strength)
	BasicProjectileVisual.set_time_of_day(is_day_time())
	# Adjust bloom for nighttime (more visible)
	_update_bloom_for_time_of_day(is_day_time())

func _update_bloom_for_time_of_day(is_daytime: bool) -> void:
	"""Adjust WorldEnvironment bloom based on time of day."""
	# Find the WorldEnvironment in the Level scene
	var level = get_parent()
	if level == null:
		return
	
	var world_env = level.get_node_or_null("WorldEnvironment")
	if world_env == null or not (world_env is WorldEnvironment):
		return
	
	var env = world_env.environment
	if env == null:
		return
	
	if is_daytime:
		# Daytime: very subtle bloom to avoid washing out
		env.glow_intensity = 0.2
		env.glow_strength = 0.6
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.5  # Higher threshold = less glow
		env.glow_hdr_scale = 1.0
	else:
		# Nighttime: more visible bloom for that glowy effect
		env.glow_intensity = 0.6
		env.glow_strength = 1.0
		env.glow_bloom = 0.15
		env.glow_hdr_threshold = 0.9  # Lower threshold = more glow
		env.glow_hdr_scale = 2.0

func _update_projectile_ambient_compensation(modulate_color: Color) -> void:
	var luminance := modulate_color.r * 0.299 + modulate_color.g * 0.587 + modulate_color.b * 0.114
	var clamped_luminance := clampf(luminance, 0.2, 1.25)
	var compensation_strength := clampf(1.0 / clamped_luminance, 1.0, 4.0)
	BasicProjectileVisual.set_ambient_compensation(compensation_strength)

func _spawn_decorations() -> void:
	for entry in _decoration_entries:
		var node: Node2D = entry.get("node")
		if node and is_instance_valid(node):
			node.queue_free()
	_decoration_entries.clear()
	if _decor_container == null:
		return
	if _active_biome == null or not _active_biome.has_decorations():
		return
	var radius: float = maxf(_active_biome.decoration_spawn_radius, _get_effective_ground_extent() * 0.45)
	for i in range(_active_biome.decoration_count):
		var texture: Texture2D = _active_biome.decoration_textures[_rng.randi_range(0, _active_biome.decoration_textures.size() - 1)]
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.z_index = -40
		sprite.position = _random_point_in_circle(radius)
		var scale_factor := lerpf(_active_biome.decoration_min_scale, _active_biome.decoration_max_scale, _rng.randf())
		sprite.scale = Vector2.ONE * scale_factor
		sprite.rotation = _rng.randf_range(-0.35, 0.35)
		sprite.modulate = Color(1.0, 1.0, 1.0, _active_biome.decoration_alpha)
		_decor_container.add_child(sprite)
		_decoration_entries.append({
			"node": sprite,
			"phase": _rng.randf_range(0.0, TAU),
			"base_rotation": sprite.rotation,
			"base_scale": sprite.scale
		})

func _random_point_in_circle(radius: float) -> Vector2:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * radius
	return Vector2(cos(angle), sin(angle)) * distance

func _update_decoration_animations(delta: float) -> void:
	if _decoration_entries.is_empty():
		return
	if _active_biome == null:
		return
	for entry in _decoration_entries:
		var sprite: Sprite2D = entry.get("node")
		if sprite == null or not is_instance_valid(sprite):
			continue
		var phase: float = float(entry.get("phase", 0.0))
		phase += delta * (_active_biome.wind_strength * 0.75 + 0.25)
		entry["phase"] = phase
		var sway := sin(phase) * 0.2 * _active_biome.decoration_variation
		sprite.rotation = float(entry.get("base_rotation", 0.0)) + sway
		var base_scale: Vector2 = entry.get("base_scale", Vector2.ONE)
		var scale_wave := 1.0 + sin(phase * 1.7) * 0.05 * _active_biome.decoration_variation
		sprite.scale = base_scale * scale_wave

func _update_grass_field() -> void:
	"""Create or remove grass field based on current biome."""
	if not enable_physical_grass:
		_remove_grass_field()
		return
	
	# Check if current biome should have grass
	var should_have_grass := _should_biome_have_grass()
	
	if should_have_grass and _grass_field == null:
		_create_grass_field()
	elif not should_have_grass and _grass_field != null:
		_remove_grass_field()
	elif should_have_grass and _grass_field != null:
		_update_grass_field_settings()

func _should_biome_have_grass() -> bool:
	"""Determine if current biome should have physical grass."""
	if _active_biome == null:
		return false
	
	# Add grass to grassy biomes and sakura biome
	var biome_id = _get_biome_id()
	var grass_biomes = ["grassy_field", "field", "meadow", "plains", "grassland", "grasslands", "sakura", "cherry_blossom"]
	
	return biome_id in grass_biomes or _active_biome.display_name.to_lower().contains("grass") or _active_biome.display_name.to_lower().contains("sakura")

func _create_grass_field() -> void:
	"""Create a new grass field instance."""
	if _grass_field != null:
		_grass_field.queue_free()
	
	_grass_field = PhysicalGrassFieldScript.new()
	_grass_field.z_index = -1  # Background grass behind player
	_grass_field.name = "PhysicalGrass"
	
	# Configure based on world bounds if available, otherwise use extent
	var use_world_bounds := _world_bounds.size != Vector2.ZERO
	if use_world_bounds:
		# For objective mode, use world bounds to constrain grass field
		# Pass world bounds directly to grass field for proper clipping
		_grass_field.set_world_bounds(_world_bounds)
		_grass_field.field_size = _world_bounds.size
		_grass_field.position = Vector2.ZERO
	else:
		# Fallback to extent-based sizing (centered at origin)
		var extent = _get_effective_ground_extent()
		_grass_field.field_size = Vector2(extent * 2.0, extent * 2.0)
		_grass_field.position = Vector2.ZERO
	
	_grass_field.grass_density = 1.5  # Adjusted for new spacing
	_grass_field.blade_height = 54.0  # Increased 35% from 40.0 for taller grass
	_grass_field.sway_strength = 8.0  # Gentler sway
	_grass_field.interaction_radius = 85.0
	
	# Apply biome-specific settingsd
	if _active_biome:
		_grass_field.wind_speed = _active_biome.wind_strength * 0.8
		
		# Use biome's defined grass colors (from the biome definition)
		# Most biomes define these, but fallback to green if not defined
		var base_color = Color(0.3, 0.6, 0.2, 1.0)  # Default green
		var tip_color = Color(0.5, 0.8, 0.4, 1.0)   # Default light green
		
		# If biome has custom grass colors, use them
		if "grass_color_base" in _active_biome and _active_biome.grass_color_base != Color.BLACK:
			base_color = _active_biome.grass_color_base
		if "grass_color_tip" in _active_biome and _active_biome.grass_color_tip != Color.BLACK:
			tip_color = _active_biome.grass_color_tip
		
		_grass_field.grass_color_base = base_color
		_grass_field.grass_color_tip = tip_color
	
	add_child(_grass_field)
	
	# print("✓ Created physical grass field (", _grass_field.field_size, ")")

func _remove_grass_field() -> void:
	"""Remove the grass field if it exists."""
	if _grass_field != null:
		_grass_field.queue_free()
		_grass_field = null
		# print("✗ Removed physical grass field")

func _update_grass_field_settings() -> void:
	"""Update grass field settings to match current biome."""
	if _grass_field == null or _active_biome == null:
		return
	
	# Update wind
	if _grass_field.has_method("set_wind_direction"):
		var wind_dir = Vector2(_active_biome.wind_strength, 0).normalized()
		_grass_field.set_wind_direction(wind_dir)
	
	# Update colors
	if _grass_field.has_method("set_grass_colors"):
		var base_color = Color(0.3, 0.6, 0.2, 1.0)  # Default green
		var tip_color = Color(0.5, 0.8, 0.4, 1.0)   # Default light green
		
		# If biome has custom grass colors, use them
		if "grass_color_base" in _active_biome and _active_biome.grass_color_base != Color.BLACK:
			base_color = _active_biome.grass_color_base
		if "grass_color_tip" in _active_biome and _active_biome.grass_color_tip != Color.BLACK:
			tip_color = _active_biome.grass_color_tip
		
		_grass_field.set_grass_colors(base_color, tip_color)

## Boulder management functions

func _ensure_boulder_container() -> Node2D:
	"""Ensure boulder container exists."""
	if _boulder_container == null:
		_boulder_container = Node2D.new()
		_boulder_container.name = "Boulders"
		_boulder_container.z_index = 0  # Same as player for Y-sorting
		_boulder_container.y_sort_enabled = true
		add_child(_boulder_container)
	return _boulder_container

func _spawn_boulders() -> void:
	"""Spawn boulders across the map based on world bounds."""
	_clear_boulders()
	
	if _world_bounds.size == Vector2.ZERO:
		return  # No bounds set yet
	
	_ensure_boulder_container()
	
	# Calculate number of boulders based on map size
	# Reduce density for objective mode's large map - fewer obstacles for better navigation
	var map_area = _world_bounds.size.x * _world_bounds.size.y
	var camera_area = 1920.0 * 1080.0
	var num_boulders = max(3, int(map_area / camera_area * 0.4))  # Reduced from 1.2 to 0.4
	
	var min_distance_between = 1500.0  # Increased from 800 for more spread
	var edge_margin = 200.0  # Keep boulders away from edges
	var min_distance_from_center = 2000.0  # Keep boulders away from EDEN (at 0,0)
	
	var spawn_area = Rect2(
		_world_bounds.position + Vector2(edge_margin, edge_margin),
		_world_bounds.size - Vector2(edge_margin * 2, edge_margin * 2)
	)
	
	var placed_positions: Array[Vector2] = []
	var attempts = 0
	var max_attempts = num_boulders * 20
	
	while _boulders.size() < num_boulders and attempts < max_attempts:
		attempts += 1
		
		# Random position in spawn area
		var pos = Vector2(
			_rng.randf_range(spawn_area.position.x, spawn_area.position.x + spawn_area.size.x),
			_rng.randf_range(spawn_area.position.y, spawn_area.position.y + spawn_area.size.y)
		)
		
		# Check distance from center (EDEN at 0,0)
		if pos.length() < min_distance_from_center:
			continue
		
		# Check distance from other boulders
		var too_close = false
		for placed_pos in placed_positions:
			if pos.distance_to(placed_pos) < min_distance_between:
				too_close = true
				break
		
		if too_close:
			continue
		
		# Spawn boulder
		var boulder = ProceduralBoulderScript.new()
		boulder.position = pos
		boulder.boulder_size = _rng.randf_range(210.0, 330.0)  # Tripled: was 70-110, now 210-330
		boulder.variation_seed = _rng.randi()
		
		_boulder_container.add_child(boulder)
		_boulders.append(boulder)
		placed_positions.append(pos)
	
	# print("Spawned ", _boulders.size(), " boulders across the map")

func _clear_boulders() -> void:
	"""Remove all boulders."""
	for boulder in _boulders:
		if is_instance_valid(boulder):
			boulder.queue_free()
	_boulders.clear()


func _apply_snow_overlay_settings(biome: BiomeDefinition) -> void:
	if _snow_overlay == null:
		return
	var snow_material := _snow_overlay.material as ShaderMaterial
	if snow_material == null:
		_snow_overlay.visible = false
		return
	if biome == null or biome.snowfall_density <= 0.0:
		_snow_overlay.visible = false
		snow_material.set_shader_parameter("density", 0.0)
		snow_material.set_shader_parameter("flake_scale", 1.0)
		snow_material.set_shader_parameter("view_size", _get_view_size())
		return
	_snow_overlay.visible = true
	var base_density := biome.snowfall_density * 0.55 + 0.15
	var density_scale := clampf(base_density * 0.42 + 0.06, 0.08, 0.95)
	snow_material.set_shader_parameter("density", density_scale)
	var flake_scale := clampf(biome.snowfall_scale * 0.36, 0.2, 1.0)
	snow_material.set_shader_parameter("flake_scale", flake_scale)
	snow_material.set_shader_parameter("view_size", _get_camera_view_size())
	snow_material.set_shader_parameter("world_offset", _compute_camera_world_offset())
	snow_material.set_shader_parameter("world_scale", 0.0025)

func _apply_sakura_overlay_settings(biome: BiomeDefinition) -> void:
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
	sakura_material.set_shader_parameter("primary_color", Vector4(primary.r, primary.g, primary.b, primary.a))
	sakura_material.set_shader_parameter("secondary_color", Vector4(secondary.r, secondary.g, secondary.b, secondary.a))
	sakura_material.set_shader_parameter("view_size", _get_camera_view_size())
	sakura_material.set_shader_parameter("world_offset", _compute_camera_world_offset())
	sakura_material.set_shader_parameter("world_scale", 0.0021)

func _apply_flower_overlay_settings(_biome: BiomeDefinition) -> void:
	# DISABLED: Flower overlay causing shader errors - hiding for now
	if _flower_overlay != null:
		_flower_overlay.visible = false

func _configure_snow_imprint_state(biome: BiomeDefinition) -> void:
	var shader_material := _get_shader_material()
	if shader_material == null:
		return
	if biome == null or biome.snow_cover <= 0.05:
		_snow_imprint_enabled = false
		shader_material.set_shader_parameter("snow_imprint_strength", 0.0)
		_clear_snow_imprint()
		_clear_snow_piles()
		return
	_ensure_snow_imprint_resources()
	_snow_imprint_enabled = true
	shader_material.set_shader_parameter("snow_imprint_texture", _snow_imprint_texture)
	shader_material.set_shader_parameter("snow_imprint_texel_size", Vector2(1.0 / SNOW_IMPRINT_TEXTURE_SIZE, 1.0 / SNOW_IMPRINT_TEXTURE_SIZE))
	shader_material.set_shader_parameter("snow_imprint_strength", clampf(biome.snow_cover * 1.1, 0.2, 2.0))
	_clear_snow_imprint()
	_clear_snow_piles()

func _ensure_snow_imprint_resources() -> void:
	if _snow_imprint_image != null and _snow_imprint_texture != null:
		return
	_snow_imprint_image = Image.create(SNOW_IMPRINT_TEXTURE_SIZE, SNOW_IMPRINT_TEXTURE_SIZE, false, Image.FORMAT_RF)
	_snow_imprint_image.fill(Color(SNOW_IMPRINT_DEFAULT, SNOW_IMPRINT_DEFAULT, SNOW_IMPRINT_DEFAULT, 1.0))
	_snow_imprint_texture = ImageTexture.create_from_image(_snow_imprint_image)
	var shader_material := _get_shader_material()
	if shader_material:
		shader_material.set_shader_parameter("snow_imprint_texture", _snow_imprint_texture)
		shader_material.set_shader_parameter("snow_imprint_texel_size", Vector2(1.0 / SNOW_IMPRINT_TEXTURE_SIZE, 1.0 / SNOW_IMPRINT_TEXTURE_SIZE))

func _clear_snow_imprint(value: float = SNOW_IMPRINT_DEFAULT) -> void:
	if _snow_imprint_image == null:
		return
	_snow_imprint_image.fill(Color(value, value, value, 1.0))
	if _snow_imprint_texture:
		_snow_imprint_texture.update(_snow_imprint_image)

func _clear_snow_piles() -> void:
	if _snow_pile_container == null:
		return
	for child in _snow_pile_container.get_children():
		child.queue_free()

func _seed_snow_piles(_biome: BiomeDefinition) -> void:
	# Small obstacles (snow piles) are disabled — keep obstacles limited to procedural boulders only
	_clear_snow_piles()
	return

func _add_snow_stamp(local_position: Vector2, radius: float, delta: float) -> void:
	if not _snow_imprint_enabled or _snow_imprint_image == null:
		return
	var extent := _get_effective_ground_extent()
	var half_extent := extent * 0.5
	var uv := Vector2(
		(local_position.x + half_extent) / extent,
		(local_position.y + half_extent) / extent
	)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return
	var center_px := Vector2i(
		int(round(clampf(uv.x, 0.0, 1.0) * float(SNOW_IMPRINT_TEXTURE_SIZE - 1))),
		int(round(clampf(uv.y, 0.0, 1.0) * float(SNOW_IMPRINT_TEXTURE_SIZE - 1)))
	)
	var radius_px := int(max(1.0, round((radius / extent) * float(SNOW_IMPRINT_TEXTURE_SIZE))))
	for y_offset in range(-radius_px, radius_px + 1):
		var py := center_px.y + y_offset
		if py < 0 or py >= SNOW_IMPRINT_TEXTURE_SIZE:
			continue
		for x_offset in range(-radius_px, radius_px + 1):
			var px := center_px.x + x_offset
			if px < 0 or px >= SNOW_IMPRINT_TEXTURE_SIZE:
				continue
			var dist := sqrt(float(x_offset * x_offset + y_offset * y_offset)) / float(radius_px)
			if dist > 1.0:
				continue
			var falloff := pow(clampf(1.0 - dist, 0.0, 1.0), 2.2)
			var current := _snow_imprint_image.get_pixel(px, py).r
			var target := clampf(current + delta * falloff, 0.0, 1.0)
			_snow_imprint_image.set_pixel(px, py, Color(target, target, target, 1.0))
	if _snow_imprint_texture:
		_snow_imprint_texture.update(_snow_imprint_image)

func supports_snow_imprints() -> bool:
	return _snow_imprint_enabled and _snow_imprint_image != null

func add_snow_footprint(world_position: Vector2, radius: float = 80.0, depth: float = SNOW_FOOTPRINT_FADE) -> void:
	if not supports_snow_imprints():
		return
	var local := to_local(world_position)
	_add_snow_stamp(local, radius, -abs(depth))
	_add_snow_stamp(local, radius * 1.35, abs(depth) * 0.18)
	_emit_snow_particles(world_position, abs(depth))

func add_snow_path_sample(world_position: Vector2, radius: float = SNOW_PATH_RADIUS, depth: float = SNOW_FOOTPRINT_FADE) -> void:
	if not supports_snow_imprints():
		return
	var local := to_local(world_position)
	_add_snow_stamp(local, radius, -abs(depth))
	_add_snow_stamp(local, radius * 1.5, abs(depth) * 0.22)
	if depth > 0.3:
		_emit_snow_particles(world_position, abs(depth) * 0.6)
func add_snow_accumulation(world_position: Vector2, radius: float, height: float) -> void:
	if not supports_snow_imprints():
		return
	var local := to_local(world_position)
	_add_snow_stamp(local, radius, abs(height))

func emit_snow_kickup(world_position: Vector2, strength: float = 0.45) -> void:
	if not supports_snow_imprints():
		return
	_emit_snow_particles(world_position, clampf(strength, 0.0, 1.0))

func _update_overlay_layout() -> void:
	var view_size := _get_camera_view_size()
	if _snow_overlay:
		var snow_material := _snow_overlay.material as ShaderMaterial
		if snow_material:
			snow_material.set_shader_parameter("view_size", view_size)
		if _world_bounds.size == Vector2.ZERO:
			_snow_overlay.polygon = _build_overlay_polygon(view_size)
		else:
			_update_snow_overlay_polygon(_get_camera_global_position())
	if _sakura_overlay:
		var sakura_material := _sakura_overlay.material as ShaderMaterial
		if sakura_material:
			sakura_material.set_shader_parameter("view_size", view_size)
		if _world_bounds.size == Vector2.ZERO:
			_sakura_overlay.polygon = _build_overlay_polygon(view_size)
		else:
			_update_sakura_overlay_polygon(_get_camera_global_position())
	if _flower_overlay:
		var flower_material := _flower_overlay.material as ShaderMaterial
		if flower_material:
			flower_material.set_shader_parameter("view_size", view_size)
		if _world_bounds.size == Vector2.ZERO:
			_flower_overlay.polygon = _build_overlay_polygon(view_size)
		else:
			_update_flower_overlay_polygon(_get_camera_global_position())
	if _vignette_overlay:
		_vignette_overlay.size = view_size
		_vignette_overlay.position = -view_size * 0.5

func _update_overlay_transform() -> void:
	if _overlay_canvas == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_2d()
	if camera == null:
		return
	var camera_position := camera.global_position
	_overlay_canvas.global_position = camera_position
	_overlay_canvas.global_rotation = 0.0
	_overlay_canvas.global_scale = Vector2.ONE
	_update_snow_overlay_polygon(camera_position)
	_update_sakura_overlay_polygon(camera_position)
	_update_flower_overlay_polygon(camera_position)

func _get_camera_view_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return _get_view_size()
	var rect_size := viewport.get_visible_rect().size
	var camera := viewport.get_camera_2d()
	if camera:
		rect_size.x *= camera.zoom.x
		rect_size.y *= camera.zoom.y
	return rect_size

func _get_camera_global_position() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var camera := viewport.get_camera_2d()
	if camera == null:
		return Vector2.ZERO
	return camera.global_position

func _on_viewport_size_changed() -> void:
	_update_overlay_layout()

func _get_view_size() -> Vector2:
	var viewport := get_viewport()
	if viewport:
		return viewport.get_visible_rect().size
	return Vector2(1920.0, 1080.0)

func _compute_camera_world_offset() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var camera := viewport.get_camera_2d()
	if camera == null:
		return Vector2.ZERO
	var zoom := camera.zoom
	var view_size := viewport.get_visible_rect().size * zoom
	return camera.global_position - view_size * 0.5

func _get_effective_ground_extent() -> float:
	return maxf(_effective_ground_extent, ground_extent)

func _update_snow_overlay_polygon(camera_position: Vector2) -> void:
	if _snow_overlay == null:
		return
	if _world_bounds.size == Vector2.ZERO:
		_snow_overlay.polygon = _build_overlay_polygon(_get_camera_view_size())
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
		_sakura_overlay.polygon = _build_overlay_polygon(_get_camera_view_size())
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
	# Flower overlay always covers the screen - shader uses world_offset for positioning
	var view_size := _get_camera_view_size()
	_flower_overlay.polygon = _build_overlay_polygon(view_size)

func _emit_snow_particles(world_position: Vector2, strength: float) -> void:
	if _snow_particle_container == null:
		return
	var texture := _get_snow_particle_texture()
	var particles := GPUParticles2D.new()
	particles.one_shot = true
	particles.amount = int(round(clampf(lerpf(10.0, 22.0, clampf(strength, 0.0, 1.0)), 6.0, 28.0)))
	particles.lifetime = SNOW_PARTICLE_LIFETIME
	particles.explosiveness = 0.6
	particles.speed_scale = 1.0
	particles.texture = texture
	particles.process_material = _create_snow_particle_material(strength)
	particles.global_position = world_position
	_snow_particle_container.add_child(particles)
	particles.finished.connect(Callable(particles, "queue_free"))
	particles.emitting = true

func _create_snow_particle_material(strength: float) -> ParticleProcessMaterial:
	var particle_material := ParticleProcessMaterial.new()
	particle_material.gravity = Vector3(0.0, SNOW_PARTICLE_GRAVITY, 0.0)
	var intensity := clampf(strength, 0.0, 1.0)
	var velocity := lerpf(55.0, 120.0, intensity)
	particle_material.initial_velocity_min = velocity * 0.35
	particle_material.initial_velocity_max = velocity * 0.9
	particle_material.direction = Vector3(0.0, -0.75, 0.0)
	particle_material.spread = 78.0
	particle_material.angular_velocity_min = -8.0
	particle_material.angular_velocity_max = 8.0
	particle_material.scale_min = 0.32
	particle_material.scale_max = 0.62
	particle_material.damping_min = 1.6
	particle_material.damping_max = 3.9
	particle_material.color_ramp = _get_snow_particle_ramp()
	return particle_material

func _get_snow_particle_texture() -> Texture2D:
	if _snow_particle_texture != null:
		return _snow_particle_texture
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := float(x) / float(size - 1)
			var v := float(y) / float(size - 1)
			var dx := u - 0.5
			var dy := v - 0.5
			var dist := sqrt(dx * dx + dy * dy) * 2.2
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			var color := Color(0.96, 0.99, 1.0, pow(alpha, 1.5) * 0.9)
			image.set_pixel(x, y, color)
	_snow_particle_texture = ImageTexture.create_from_image(image)
	return _snow_particle_texture

func _get_snow_particle_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.95, 0.98, 1.0, 0.75),
		Color(0.95, 0.98, 1.0, 0.35),
		Color(0.95, 0.98, 1.0, 0.0)
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp

func _resolve_audio_director() -> AudioDirector:
	if not get_tree():
		return null
	var root := get_tree().root
	var candidate := root.find_child("AudioDirector", true, false)
	if candidate and candidate is AudioDirector:
		return candidate
	return null

func _get_audio_director() -> AudioDirector:
	if _audio_director == null or not is_instance_valid(_audio_director):
		_audio_director = _resolve_audio_director()
	return _audio_director

func _update_ambient_audio() -> void:
	var director := _get_audio_director()
	if director == null:
		return
	var desired_path := ""
	if _active_biome and _active_biome.ambient_loop_path.strip_edges() != "":
		desired_path = _active_biome.ambient_loop_path.strip_edges()
	if desired_path == _current_ambient_path:
		return
	if desired_path != "" and ResourceLoader.exists(desired_path):
		_current_ambient_path = desired_path
		director.play_ambient_loop(desired_path)
		return
	_stop_ambient_audio()

func _stop_ambient_audio() -> void:
	_current_ambient_path = ""
	var director := _get_audio_director()
	if director:
		director.stop_ambient()
