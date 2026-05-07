extends Node2D
class_name EnvironmentController

signal environment_changed(biome_id: StringName, time_id: StringName)
signal modulate_changed(color: Color)

const BIOMES_DIR := "res://resources/biomes/"
const TIME_OF_DAY_DIR := "res://resources/time_of_day/"

var biome_definitions: Array = []
var time_of_day_definitions: Array = []
@export_range(512.0, 8192.0, 16.0) var ground_extent: float = 4096.0
@export_range(0, 2147483647, 1) var environment_seed: int = 0
@export var auto_initialize: bool = false # Level.gd controls initialization timing
@export var use_fixed_seed: bool = false
@export var enable_physical_grass: bool = true # Toggle grass system on/off

const GROUND_SHADER_PATH := "res://resources/shaders/procedural_ground.gdshader"
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
var _current_ambient_path: String = ""
var _world_bounds: Rect2 = Rect2()
var _grass_field: Node2D = null # PhysicalGrassField instance
var _player_ref: Node2D = null # Track player for grass interaction

var current_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)
var _weather_system: WeatherSystem = null # Delegated weather effects
var _terrain_features: TerrainFeatures = null # Delegated terrain (grass, boulders)

# Legacy boulder references (still used by _ensure_boulder_container)
var _boulder_container: Node2D = null
var _boulders: Array[Node2D] = []

# Modular manager references
var _border_manager: BorderManager = null
var _lightning_manager: LightningManager = null
var _night_overlay_manager: NightOverlayManager = null
var _screen_fog_manager: ScreenFogManager = null
var _snow_imprint_manager: SnowImprintManager = null
var _overlay_vfx: OverlayVFXManager = null

@onready var _background: Polygon2D = _ensure_background()
@onready var _ground: Polygon2D = _ensure_ground()
@onready var _decor_container: Node2D = _ensure_decor_container()
@onready var _fog_overlay: ColorRect = _ensure_fog_overlay()
@onready var _lightning_overlay: ColorRect = _ensure_lightning_overlay()
@onready var _vignette_overlay: ColorRect = _ensure_vignette_overlay()
@onready var _canvas_modulate: CanvasModulate = _ensure_canvas_modulate()
@onready var _sun_light: DirectionalLight2D = _ensure_sun_light()
@onready var _audio_director = get_node_or_null("/root/AudioDirector")
@onready var _effects_layer: CanvasLayer = _ensure_effects_layer()

func _ready() -> void:
	add_to_group("environment_controller")
	
	# Initialize module system
	# Note: BiomeManager disabled for now - conflicts with existing biome loading
	# _biome_manager = BiomeManager.new()
	# add_child(_biome_manager)
	# _biome_manager.load_biomes()

	# Fix BulletServer canvas on map reload
	if BulletServer.get_instance():
		BulletServer.get_instance().update_parent_canvas(_effects_layer.get_canvas())
	
	_terrain_features = TerrainFeatures.new()
	_terrain_features.name = "TerrainFeatures"
	add_child(_terrain_features)
	
	_weather_system = WeatherSystem.new()
	_weather_system.name = "WeatherSystem"
	add_child(_weather_system)
	_weather_system.set_audio_director(_audio_director)
	
	# Initialize modular managers
	_border_manager = BorderManager.new()
	_border_manager.name = "BorderManager"
	add_child(_border_manager)
	_border_manager.ensure_border_overlay(self)
	
	_lightning_manager = LightningManager.new()
	_lightning_manager.name = "LightningManager"
	add_child(_lightning_manager)
	
	_night_overlay_manager = NightOverlayManager.new()
	_night_overlay_manager.name = "NightOverlayManager"
	add_child(_night_overlay_manager)
	_night_overlay_manager.setup(self)
	
	_screen_fog_manager = ScreenFogManager.new()
	_screen_fog_manager.name = "ScreenFogManager"
	add_child(_screen_fog_manager)
	_screen_fog_manager.setup(self)
	
	_snow_imprint_manager = SnowImprintManager.new()
	_snow_imprint_manager.name = "SnowImprintManager"
	add_child(_snow_imprint_manager)
	_snow_imprint_manager.setup(self, Callable(self, "_get_ground_for_snow"))
	
	_overlay_vfx = OverlayVFXManager.new()
	_overlay_vfx.name = "OverlayVFX"
	add_child(_overlay_vfx)
	_overlay_vfx.setup(self, Callable(self, "get_active_biome"), Callable(self, "is_night_time"))
	# Ensure overlay overlays are created
	_overlay_vfx.ensure_snow_overlay()
	_overlay_vfx.ensure_sakura_overlay()
	_overlay_vfx.ensure_flower_overlay()
	
	# Legacy setup
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
	_border_manager.cleanup_saved_border_visuals()
	
	# Remove any old vignette overlays
	var overlay_canvas: Node2D = _overlay_vfx.ensure_overlay_canvas() if _overlay_vfx else null
	if overlay_canvas:
		var old_vignette = overlay_canvas.get_node_or_null("VignetteOverlay")
		if old_vignette:
			overlay_canvas.remove_child(old_vignette)
			old_vignette.queue_free()
	var vignette_layer: CanvasLayer = get_node_or_null("VignetteLayer")
	if vignette_layer:
		remove_child(vignette_layer)
		vignette_layer.queue_free()

	# Debug hook: force night-mode at startup if enabled in DebugSettings
	# This exercises the projectile compensation path for testing
	if DebugSettings.force_night:
		# Example night tint (dark bluish). This should exercise the
		# compensation path for projectile visuals.
		var test_night := Color(0.28, 0.32, 0.4, 1.0)
		if _canvas_modulate:
			_canvas_modulate.color = test_night
			current_modulate = test_night
			# Emit the same signal used at runtime so other nodes react
			modulate_changed.emit(test_night)
		# Ensure EffectsLayer gets its inverse modulate applied now
		_on_modulate_changed(test_night)
		# Tell projectile visuals it's night and set a stronger vignette and
		# ambient compensation so compensation math is exercised during test.
		BasicProjectileVisual.set_time_of_day(false)
		BasicProjectileVisual.set_ambient_compensation(2.5)
		var vp := get_viewport()
		var view_size := Vector2.ZERO
		if vp:
			view_size = vp.get_visible_rect().size
		BasicProjectileVisual.set_vignette_profile(0.85, 0.45, 0.35, view_size)


# Cleanup moved to BorderManager.cleanup_saved_border_visuals()

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
	
	# Delegate overlay VFX animation to manager
	var cam_pos := _get_camera_global_position()
	var cam_view := _get_camera_view_size()
	var world_off := _compute_camera_world_offset()
	if _overlay_vfx:
		_overlay_vfx.process(delta, cam_pos, cam_view, world_off)
	
	_update_decoration_animations(delta)
	
	# Update grass with player position
	if _grass_field and _player_ref and is_instance_valid(_player_ref):
		_grass_field.update_player_position(_player_ref.global_position)
	
	# Delegate lightning to manager (fallback when WeatherSystem not present)
	if not _weather_system and _lightning_manager:
		_lightning_manager.process(delta)
	
	# Delegate screen fog animation to manager
	if _screen_fog_manager:
		_screen_fog_manager.process(delta)

func _exit_tree() -> void:
	_stop_ambient_audio()

func initialize_environment(seed_override: int = 0, biome_id: StringName = &"", time_id: StringName = &"") -> void:
	print("Initialize environment called with biome: ", str(biome_id))
	_configure_rng(seed_override)
	_active_biome = _select_biome(biome_id)
	_active_time = _select_time_of_day(time_id)
	if _lightning_manager:
		_lightning_manager.set_biome(_active_biome)
		_lightning_manager.setup(_rng, _lightning_overlay, _audio_director)
	
	# Remove fog overlay for storm map
	if _active_biome and _active_biome.biome_id == &"rain_forest" and _fog_overlay:
		_fog_overlay.queue_free()
		_fog_overlay = null
	
	_apply_biome_to_ground()
	_apply_time_of_day_settings()
	_spawn_decorations()
	
	# Delegate terrain features to module
	if _terrain_features and _active_biome:
		_terrain_features.setup(_rng, _world_bounds, _player_ref)
		_terrain_features.update_grass_field(_active_biome, self)
		# Configure grass shader settings after creation
		call_deferred("_update_grass_field_settings")
		call_deferred("_delegate_boulder_spawn", _active_biome)
	
	# Configure weather system with new biome
	if _weather_system and _active_biome:
		_weather_system.configure(_active_biome, _lightning_overlay)
		_weather_system.start()
	
	emit_signal("environment_changed", _get_biome_id(), _get_time_id())
	_update_ambient_audio()

func _delegate_boulder_spawn(biome: BiomeDefinition) -> void:
	if _terrain_features:
		_terrain_features.spawn_boulders(biome, self, 5) # Reduced to 5 (Rare)

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
	if _border_manager:
		_border_manager.set_world_bounds(bounds)
	if _overlay_vfx:
		_overlay_vfx.set_world_bounds(bounds)
		_overlay_vfx.update_layout(_get_camera_view_size(), _get_camera_global_position())
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

# Border overlay managed by BorderManager

func _ensure_fog_overlay() -> ColorRect:
	var node := get_node_or_null("FogOverlay")
	if node and node is ColorRect:
		var fog := node as ColorRect
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return fog
	var fog_overlay := ColorRect.new()
	fog_overlay.name = "FogOverlay"
	fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_overlay.color = Color(0.0, 0.0, 0.0, 0.0) # Start transparent
	fog_overlay.visible = false # Hidden until explicitly enabled
	fog_overlay.size = Vector2(1920, 1080)
	fog_overlay.position = Vector2(0, 0)
	fog_overlay.z_index = 50
	
	# Try to add to ScreenFlashLayer CanvasLayer for proper screen space
	var screen_flash_layer = _find_screen_flash_layer()
	if screen_flash_layer:
		screen_flash_layer.add_child(fog_overlay)
	else:
		# Fallback: add as direct child with top_level
		fog_overlay.top_level = true
		add_child(fog_overlay)
	
	if Engine.is_editor_hint():
		fog_overlay.owner = get_tree().edited_scene_root
	return fog_overlay

func _find_screen_flash_layer() -> CanvasLayer:
	# Find the ScreenFlashLayer in the level
	var level = get_parent()
	while level and not (level is Node2D and level.name == "Level"):
		level = level.get_parent()
	if level:
		return level.get_node_or_null("ScreenFlashLayer")
	return null

func _ensure_lightning_overlay() -> ColorRect:
	var node := get_node_or_null("LightningOverlay")
	if node and node is ColorRect:
		var lightning := node as ColorRect
		lightning.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return lightning
	var lightning_overlay := ColorRect.new()
	lightning_overlay.name = "LightningOverlay"
	lightning_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lightning_overlay.color = Color(1.0, 1.0, 1.0, 0.0) # White flash, initially transparent
	lightning_overlay.size = Vector2.ONE * _get_effective_ground_extent()
	lightning_overlay.position = - lightning_overlay.size * 0.5
	add_child(lightning_overlay)
	if Engine.is_editor_hint():
		lightning_overlay.owner = get_tree().edited_scene_root
	return lightning_overlay

# Overlay canvas managed by OverlayVFXManager

func _ensure_vignette_overlay() -> ColorRect:
	# Remove old vignette from overlay canvas if it exists
	var overlay_canvas: Node2D = _overlay_vfx.ensure_overlay_canvas() if _overlay_vfx else null
	if overlay_canvas:
		var old_node = overlay_canvas.get_node_or_null("VignetteOverlay")
		if old_node:
			overlay_canvas.remove_child(old_node)
			old_node.queue_free()
	
	var vignette_shader := load(VIGNETTE_SHADER_PATH)
	# Check if VignetteLayer exists
	var vignette_layer := get_node_or_null("VignetteLayer") as CanvasLayer
	if vignette_layer == null:
		vignette_layer = CanvasLayer.new()
		vignette_layer.name = "VignetteLayer"
		vignette_layer.layer = 90 # Above game world, below HUD at 99
		add_child(vignette_layer)
		if Engine.is_editor_hint():
			vignette_layer.owner = get_tree().edited_scene_root
	
	var node := vignette_layer.get_node_or_null("VignetteOverlay")
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
	vignette_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Explicitly set size to viewport for proper coverage
	var viewport_size := Vector2(1920, 1080) # Default fallback
	if Engine.get_main_loop() and Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		if tree.root:
			viewport_size = tree.root.get_visible_rect().size
	vignette_overlay.size = viewport_size
	if vignette_shader:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = vignette_shader
		vignette_overlay.material = shader_material
	vignette_layer.add_child(vignette_overlay)
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
	# Ensure the overlay is sized correctly
	_vignette_overlay.size = view_size
	var shader_material := _vignette_overlay.material as ShaderMaterial
	var clamped_strength := clampf(strength, 0.0, 1.0)
	# Smaller inner radius = more aggressive vignette (edges start darkening sooner)
	var inner_radius := lerpf(0.2, 0.5, clampf(1.0 - clamped_strength, 0.0, 1.0))
	var softness := lerpf(0.3, 0.6, 1.0 - clamped_strength)
	if shader_material:
		shader_material.set_shader_parameter("vignette_strength", clamped_strength)
		shader_material.set_shader_parameter("inner_radius", inner_radius)
		shader_material.set_shader_parameter("softness", softness)
		shader_material.set_shader_parameter("tint", Color(0.0, 0.0, 0.0, 1.0))
		shader_material.set_shader_parameter("base_alpha", 0.0)
		print("[EnvironmentController] Vignette configured: strength=", clamped_strength, " inner=", inner_radius, " softness=", softness)
	else:
		push_warning("[EnvironmentController] Vignette overlay has no shader material!")
	# Enable vignette compensation for projectiles
	BasicProjectileVisual.set_vignette_profile(clamped_strength, inner_radius, softness, view_size)

# Snow/sakura/flower overlays managed by OverlayVFXManager

# Snow piles/particles managed by SnowImprintManager

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

func _ensure_effects_layer() -> CanvasLayer:
	var node := get_node_or_null("EffectsLayer")
	if node and node is CanvasLayer:
		return node
	var effects_layer := CanvasLayer.new()
	effects_layer.name = "EffectsLayer"
	effects_layer.layer = 1
	effects_layer.follow_viewport_enabled = true # CRITICAL: Must follow camera or projectiles drift!
	effects_layer.set("modulate", Color(1.0, 1.0, 1.0, 1.0))
	add_child(effects_layer)
	if Engine.is_editor_hint():
		effects_layer.owner = get_tree().edited_scene_root
	return effects_layer

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
		var expansion := Vector2(60.0, 60.0)
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
			_fog_overlay.position = - _fog_overlay.size * 0.5
	if _border_manager:
		_border_manager.set_world_bounds(_world_bounds)
	_update_overlay_layout()


# Border physics managed by BorderManager

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
		if _overlay_vfx:
			_overlay_vfx.apply_snow_settings(null)
			_overlay_vfx.apply_sakura_settings(null)
			_overlay_vfx.apply_flower_settings(null)
		if _snow_imprint_manager:
			_snow_imprint_manager.configure(null)
		
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
	if _overlay_vfx:
		_overlay_vfx.apply_snow_settings(biome)
		_overlay_vfx.apply_sakura_settings(biome)
		_overlay_vfx.apply_flower_settings(biome)
	if _snow_imprint_manager:
		_snow_imprint_manager.configure(biome)
	_update_ambient_audio()

func _apply_time_of_day_settings() -> void:
	var is_default_day := _active_time != null and _active_time.time_id == &"day"
	if is_default_day:
		# Disable global CanvasModulate - we apply darkness to specific sprites only
		if _canvas_modulate:
			_canvas_modulate.color = Color(1.0, 1.0, 1.0, 1.0) # Always white (no global effect)
		var day_color := Color(0.95, 0.95, 0.95, 1.0)
		current_modulate = day_color
		modulate_changed.emit(day_color)
		# Apply darkening to ground only
		if _ground:
			_ground.modulate = day_color
		BasicProjectileVisual.set_time_of_day(true)
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
	
	# Delegate to NightOverlayManager (smart night shader) or fall back to legacy CanvasModulate
	if _active_time and _active_time.use_smart_night_shader:
		_night_overlay_manager.apply(_active_time, _canvas_modulate)
		# Still emit modulate signal for other systems, but use white
		current_modulate = Color(1.0, 1.0, 1.0, 1.0)
		modulate_changed.emit(current_modulate)
	else:
		# Disable smart shader overlay
		if _night_overlay_manager:
			_night_overlay_manager.disable()
		
		# Legacy: Global CanvasModulate handles the base darkening
		var modulate_color := Color(1.0, 1.0, 1.0, 1.0)
		if _active_time:
			modulate_color = _active_time.get_canvas_modulate()
		
		if _canvas_modulate:
			_canvas_modulate.color = modulate_color
			
		current_modulate = modulate_color
		modulate_changed.emit(modulate_color)
	
	# Ground modulate is handled by CanvasModulate now, but we can add extra tint if needed
	# For now, reset to white so it just takes the global darken
	if _ground:
		_ground.modulate = Color.WHITE
	BasicProjectileVisual.set_time_of_day(_active_time == null or _active_time.time_id == &"day")
	if _fog_overlay:
		var has_biome_fog := _active_biome and _active_biome.fog_density > 0.0 and _active_biome.biome_id != &"rain_forest"
		var has_time_fog := _active_time and _active_time.fog_alpha > 0.0 and (_active_biome == null or _active_biome.biome_id != &"rain_forest")
		if has_biome_fog or has_time_fog:
			var fog_color := Color(0.8, 0.85, 0.95, 0.0)
			if _active_time:
				fog_color = _active_time.fog_color
				fog_color.a = clamp(_active_time.fog_alpha, 0.0, 1.0)
			# Blend with biome fog if present
			if has_biome_fog:
				var biome_fog_color: Color = _active_biome.fog_color
				biome_fog_color.a = _active_biome.fog_density
				# Use biome fog if it's denser, otherwise blend
				if biome_fog_color.a > fog_color.a:
					fog_color = biome_fog_color
				else:
					fog_color = fog_color.blend(biome_fog_color)
			_fog_overlay.color = fog_color
			_fog_overlay.visible = true
		else:
			_fog_overlay.color = Color(0, 0, 0, 0) # Fully transparent
			_fog_overlay.visible = false
	if _background and _active_time and _active_biome:
		var tint_strength: float = clamp(_active_time.ambient_intensity, 0.0, 1.5)
		var target := _active_biome.sky_color.lerp(_active_biome.horizon_color, 0.35)
		_background.color = target.lerp(_active_time.sky_tint, tint_strength * 0.5)
	elif _background and _active_time:
		_background.color = _active_time.sky_tint
	if _sun_light:
		if _active_time:
			# Only enable sun light during the day
			# At night, we don't want additive light since we aren't globally darkening
			if is_night_time():
				_sun_light.visible = false
				_sun_light.energy = 0.0
			else:
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
	
	# Apply screen-space fog (Zelda-style) — delegated to ScreenFogManager
	if _screen_fog_manager:
		_screen_fog_manager.apply(_active_time)
	
	# Enable/disable night glow on sprites
	var is_night := is_night_time()
	NightGlowManager.set_night_mode(is_night, 0.35 if is_night else 0.0)
	
	BasicProjectileVisual.set_time_of_day(is_day_time())
	# Adjust bloom for nighttime (more visible)
	_update_bloom_for_time_of_day(not is_night)
	
	# Update sakura/firefly overlay since it depends on time of day
	if _active_biome and _overlay_vfx:
		_overlay_vfx.apply_sakura_settings(_active_biome)
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
		env.glow_hdr_threshold = 1.5 # Higher threshold = less glow
		env.glow_hdr_scale = 1.0
	else:
		# Nighttime: Subtle bloom for glowy effect
		env.glow_enabled = true
		env.glow_intensity = 0.15
		env.glow_strength = 0.5
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.3 # High threshold to only glow very bright things
		env.glow_hdr_scale = 1.2

# Smart night shader managed by NightOverlayManager

func _update_projectile_ambient_compensation(modulate_color: Color) -> void:
	# Calculate brightness of the environment
	var brightness := (modulate_color.r + modulate_color.g + modulate_color.b) / 3.0
	# Avoid division by zero
	brightness = maxf(brightness, 0.1)
	# Compensation is inverse of brightness (darker night = brighter compensation)
	var compensation := 1.0 / brightness
	BasicProjectileVisual.set_ambient_compensation(compensation)

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
	# DISABLED: Grass now managed by TerrainFeatures module
	# This old code was conflicting with TerrainFeatures
	return
	
	# if not enable_physical_grass:
	# 	_remove_grass_field()
	# 	return
	# 
	# # Check if current biome should have grass
	# var should_have_grass := _should_biome_have_grass()
	# 
	# if should_have_grass and _grass_field == null:
	# 	_create_grass_field()
	# elif not should_have_grass and _grass_field != null:
	# 	_remove_grass_field()
	# elif should_have_grass and _grass_field != null:
	# 	_update_grass_field_settings()

func _should_biome_have_grass() -> bool:
	"""Determine if current biome should have physical grass."""
	if _active_biome == null:
		return false
	
	# Add grass to grassy biomes and sakura biome
	var biome_id = _get_biome_id()
	var grass_biomes = ["grassy_field", "field", "meadow", "plains", "grassland", "grasslands", "sakura", "cherry_blossom", "rain_forest"]
	
	return biome_id in grass_biomes or _active_biome.display_name.to_lower().contains("grass") or _active_biome.display_name.to_lower().contains("sakura")

func _create_grass_field() -> void:
	"""Create a new grass field instance."""
	if _grass_field != null:
		_grass_field.queue_free()
	
	_grass_field = PhysicalGrassFieldScript.new()
	_grass_field.z_index = -1 # Background grass behind player
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
	
	_grass_field.grass_density = 1.5 # Adjusted for new spacing
	_grass_field.blade_height = 54.0 # Increased 35% from 40.0 for taller grass
	_grass_field.sway_strength = 8.0 # Gentler sway
	_grass_field.interaction_radius = 85.0
	
	# Apply biome-specific settingsd
	if _active_biome:
		_grass_field.wind_speed = _active_biome.wind_strength * 0.8
		
		# Use biome's defined grass colors (from the biome definition)
		# Most biomes define these, but fallback to green if not defined
		var base_color = Color(0.3, 0.6, 0.2, 1.0) # Default green
		var tip_color = Color(0.5, 0.8, 0.4, 1.0) # Default light green
		
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
	# Get grass field from TerrainFeatures if available
	if not _grass_field and _terrain_features:
		_grass_field = _terrain_features.get_grass_field()
		if _grass_field:
			print("[EnvironmentController] Fetched grass field from TerrainFeatures")
		else:
			print("[EnvironmentController] WARNING: TerrainFeatures has no grass field!")
	
	if _grass_field == null or _active_biome == null:
		print("[EnvironmentController] Cannot update grass settings - grass_field: ", _grass_field != null, " biome: ", _active_biome != null)
		return
	
	print("[EnvironmentController] Configuring grass shader for biome: ", _active_biome.biome_id)
	
	# Update wind
	if _grass_field.has_method("set_wind_direction"):
		var wind_dir = Vector2(_active_biome.wind_strength, 0).normalized()
		_grass_field.set_wind_direction(wind_dir)
	
	# Update colors
	if _grass_field.has_method("set_grass_colors"):
		var base_color = Color(0.3, 0.6, 0.2, 1.0) # Default green
		var tip_color = Color(0.5, 0.8, 0.4, 1.0) # Default light green
		
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
		_boulder_container.z_index = 0 # Same as player for Y-sorting
		_boulder_container.y_sort_enabled = true
		add_child(_boulder_container)
	return _boulder_container

func _spawn_boulders() -> void:
	"""Spawn boulders across the map based on world bounds."""
	_clear_boulders()
	
	if _world_bounds.size == Vector2.ZERO:
		return # No bounds set yet
	
	_ensure_boulder_container()
	
	# Calculate number of boulders based on map size
	# Reduce density for objective mode's large map - fewer obstacles for better navigation
	var map_area = _world_bounds.size.x * _world_bounds.size.y
	var camera_area = 1920.0 * 1080.0
	var num_boulders = max(3, int(map_area / camera_area * 0.4)) # Reduced from 1.2 to 0.4
	
	var min_distance_between = 1500.0 # Increased from 800 for more spread
	var edge_margin = 200.0 # Keep boulders away from edges
	var min_distance_from_center = 2500.0 # Keep boulders away from player spawn area (EDEN at 0,0)
	
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
		boulder.boulder_size = _rng.randf_range(210.0, 330.0) # Tripled: was 70-110, now 210-330
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


# Snow overlay settings managed by OverlayVFXManager.apply_snow_settings()

# Sakura overlay settings managed by OverlayVFXManager.apply_sakura_settings()

# Flower overlay settings managed by OverlayVFXManager.apply_flower_settings()
# Snow imprint state managed by SnowImprintManager.configure()

# Snow imprint resources/clearing/stamping managed by SnowImprintManager

func supports_snow_imprints() -> bool:
	if _snow_imprint_manager:
		return _snow_imprint_manager.is_enabled()
	return false

func add_snow_footprint(world_position: Vector2, radius: float = 80.0, depth: float = 0.8) -> void:
	if _snow_imprint_manager:
		_snow_imprint_manager.add_footprint(world_position, self, radius, depth)

func add_snow_path_sample(world_position: Vector2, radius: float = 120.0, depth: float = 0.8) -> void:
	if _snow_imprint_manager:
		_snow_imprint_manager.add_path_sample(world_position, self, radius, depth)

func add_snow_accumulation(world_position: Vector2, radius: float, height: float) -> void:
	if _snow_imprint_manager:
		_snow_imprint_manager.add_accumulation(world_position, self, radius, height)

func emit_snow_kickup(world_position: Vector2, strength: float = 0.45) -> void:
	if _snow_imprint_manager:
		_snow_imprint_manager.emit_kickup(world_position, self, strength)

func _update_overlay_layout() -> void:
	var cam_view := _get_camera_view_size()
	var cam_pos := _get_camera_global_position()
	if _overlay_vfx:
		_overlay_vfx.update_layout(cam_view, cam_pos)
	if _vignette_overlay:
		pass
	if _fog_overlay:
		_fog_overlay.size = cam_view
		_fog_overlay.position = Vector2(0, 0)

# Overlay transform managed by OverlayVFXManager.process()

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

# Overlay polygon updates managed by OverlayVFXManager

func get_world_bounds() -> Rect2:
	if _border_manager:
		return _border_manager.get_world_bounds()
	return _world_bounds

# Overlay polygon methods managed by OverlayVFXManager

# Snow particle emission managed by SnowImprintManager

func _get_ground_for_snow() -> Polygon2D:
	"""Return the ground Polygon2D for snow imprint shader access."""
	return _ground

func _get_audio_director():
	if _audio_director == null or not is_instance_valid(_audio_director):
		_audio_director = get_node_or_null("/root/AudioDirector")
	return _audio_director

func _update_ambient_audio() -> void:
	var director: Node = _get_audio_director()
	if director == null:
		return
	var desired_path := ""
	if _active_biome and _active_biome.ambient_loop_path.strip_edges() != "":
		desired_path = _active_biome.ambient_loop_path.strip_edges()
	
	# Special handling for rain biome - use ambient system with crossfade
	if _active_biome and _active_biome.biome_id == &"rain_forest":
		# Prefer the biome's ambient path if available (supports mp3/ogg/wav)
		if desired_path != "" and ResourceLoader.exists(desired_path):
			# Use ambient system which now crossfades loop endpoints for smooth looping
			if desired_path != _current_ambient_path:
				director.play_ambient_loop(desired_path)
				_current_ambient_path = desired_path
			return
		# Fallback: try common rain filenames
		var fallback_paths := ["res://assets/sounds/sfx/environment/rain.mp3", "res://assets/sounds/sfx/environment/rain.ogg", "res://assets/sounds/sfx/environment/rain.wav"]
		for p in fallback_paths:
			if ResourceLoader.exists(p):
				# Use ambient crossfader for rain
				if p != _current_ambient_path:
					director.play_ambient_loop(p)
					_current_ambient_path = p
				break
		return
	
	# Stop rain ambient if not in rain biome
	if _current_ambient_path != "":
		director.stop_ambient()
		_current_ambient_path = ""
	
	# For all biomes, use the normal ambient system
	if desired_path == _current_ambient_path:
		return
	if desired_path != "" and ResourceLoader.exists(desired_path):
		_current_ambient_path = desired_path
		director.play_ambient_loop(desired_path)
		return
	_stop_ambient_audio()

func _stop_ambient_audio() -> void:
	_current_ambient_path = ""
	var director: Node = _get_audio_director()
	if director:
		director.stop_ambient()

# Lightning managed by LightningManager

func _on_modulate_changed(color: Color) -> void:
	var effects_layer := _ensure_effects_layer()
	if effects_layer:
		# Set the EffectsLayer modulate to the inverse of the canvas modulate
		# This compensates for the darkening, keeping effects bright
		var inverse_color := Color(1.0 / color.r, 1.0 / color.g, 1.0 / color.b, 1.0)
		effects_layer.set("modulate", inverse_color)

# Screen-space fog managed by ScreenFogManager
