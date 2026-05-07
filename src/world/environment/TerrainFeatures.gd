extends Node
class_name TerrainFeatures
## Manages terrain features like grass fields and obstacle boulders.
##
## Extracted from EnvironmentController to reduce god class size.

const PhysicalGrassFieldScript := preload("res://src/world/physical_grass_field.gd")
const SnowyBoulderScript := preload("res://src/world/environment/snowy_boulder.gd")

var _grass_field: Node2D = null
var _boulder_container: Node2D = null
var _boulders: Array[Node2D] = []
var _player_ref: Node2D = null
var _rng: RandomNumberGenerator = null
var _world_bounds: Rect2 = Rect2()
var _enabled: bool = true


## Initialize terrain features
func setup(rng: RandomNumberGenerator, world_bounds: Rect2, player: Node2D = null) -> void:
	_rng = rng
	_world_bounds = world_bounds
	_player_ref = player


## Enable/disable terrain features
func set_enabled(enabled: bool) -> void:
	_enabled = enabled


## Update grass field based on biome
func update_grass_field(biome: BiomeDefinition, parent: Node2D) -> void:
	if not _enabled:
		return
	
	# Remove existing grass
	if _grass_field:
		_grass_field.queue_free()
		_grass_field = null
	
	# Create grass for biomes that should have grass (grasslands, sakura grove, rain forest)
	var grass_biomes = [&"grasslands", &"sakura_grove", &"rain_forest"]
	if biome and biome.biome_id in grass_biomes:
		_grass_field = PhysicalGrassFieldScript.new()
		_grass_field.name = "GrassField" # Explicit name for cleanup whitelist
		_grass_field.world_bounds = _world_bounds # Set bounds directly
		parent.add_child(_grass_field)
		print("[TerrainFeatures] Created grass field for biome: ", biome.biome_id, " with bounds: ", _world_bounds)


## Update grass with player position
func update_grass_player_position(_delta: float) -> void:
	if _grass_field and _player_ref and is_instance_valid(_player_ref):
		_grass_field.update_player_position(_player_ref.global_position)


## Spawn obstacle boulders (or bush clusters for grass biomes)
func spawn_boulders(biome: BiomeDefinition, parent: Node2D, count: int = 40) -> void:
	if not _enabled:
		return
	
	# Clear existing boulders
	clear_boulders()
	
	# Create boulder container
	if not _boulder_container:
		_boulder_container = Node2D.new()
		_boulder_container.name = "BoulderContainer"
		parent.add_child(_boulder_container)
	
	# Determine if this is a grass biome (use bushes) or other (use boulders)
	var grass_biomes = [&"grasslands", &"sakura_grove"]
	var use_bushes := biome != null and biome.biome_id in grass_biomes
	
	if use_bushes:
		_spawn_bush_clusters(count * 2) # More bush clusters than boulders
	else:
		_spawn_rock_boulders(count)


func _spawn_bush_clusters(bush_count: int) -> void:
	"""Spawn individual bushes (not clustered) with matching collision."""
	# Load bush textures
	var bush_textures: Array[Texture2D] = []
	if ResourceLoader.exists("res://assets/textures/decorations/bush1.png"):
		bush_textures.append(load("res://assets/textures/decorations/bush1.png"))
	if ResourceLoader.exists("res://assets/textures/decorations/bush2.png"):
		bush_textures.append(load("res://assets/textures/decorations/bush2.png"))
	
	if bush_textures.is_empty():
		push_warning("[TerrainFeatures] No bush textures found, falling back to boulders")
		_spawn_rock_boulders(bush_count / 2)
		return
	
	var bushes_spawned := 0
	
	for _i in range(bush_count):
		# Find valid position - adapt margins for small arenas
		var arena_size = min(_world_bounds.size.x, _world_bounds.size.y)
		var margin := 200.0 if arena_size < 4000 else 500.0 # Smaller margin for exploration
		var safe_rect := _world_bounds.grow(-margin)
		
		var bush_pos := Vector2(
			_rng.randf_range(safe_rect.position.x, safe_rect.end.x),
			_rng.randf_range(safe_rect.position.y, safe_rect.end.y)
		)
		
		# Skip if too close to player spawn (scale with arena size)
		var exclusion := 400.0 if arena_size < 4000 else 800.0
		if bush_pos.length() < exclusion:
			continue
		
		# Pick random texture
		var tex: Texture2D = bush_textures[_rng.randi() % bush_textures.size()]
		
		# Random size (0.20 to 0.30 scale - no tiny bushes)
		var base_size := _rng.randf_range(0.20, 0.30)
		
		# Calculate collision radius based on sprite size
		var tex_radius: float = float(min(tex.get_width(), tex.get_height())) * 0.4 * base_size
		
		# Create bush using SwayableBush (has sway shader + bump reaction)
		var bush_body := SwayableBush.new()
		bush_body.global_position = bush_pos
		bush_body.collision_layer = 0
		bush_body.set_collision_layer_value(16, true) # Same layer as boulders
		bush_body.collision_mask = 0 # StaticBody doesn't need to detect
		
		# Add collision shape sized to match sprite
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = tex_radius
		collision.shape = shape
		bush_body.add_child(collision)
		
		# Add sprite as child of body
		var bush := Sprite2D.new()
		bush.texture = tex
		bush.z_index = 5 # Above grass layer
		bush.scale = Vector2(base_size, base_size)
		
		# Random rotation for natural look
		bush.rotation = _rng.randf_range(-0.15, 0.15)
		
		# Slight brightness variation
		var brightness := _rng.randf_range(0.92, 1.08)
		bush.modulate = Color(brightness, brightness, brightness, 1.0)
		
		bush_body.add_child(bush)
		_boulder_container.add_child(bush_body)
		_boulders.append(bush_body)
		bushes_spawned += 1
	
	print("[TerrainFeatures] Spawned ", bushes_spawned, " individual bushes")


func _spawn_rock_boulders(count: int) -> void:
	"""Spawn snowy boulders for non-grass biomes."""
	for i in range(count):
		var boulder = SnowyBoulderScript.new()
		_boulder_container.add_child(boulder)
		
		# Try to find valid position
		var valid_pos := false
		var pos := Vector2.ZERO
		var attempts := 0
		
		while not valid_pos and attempts < 20:
			attempts += 1
			# Adapt margins for small arenas
			var arena_size = min(_world_bounds.size.x, _world_bounds.size.y)
			var margin = 200.0 if arena_size < 4000 else 600.0
			var safe_rect = _world_bounds.grow(-margin)
			
			pos = Vector2(
				_rng.randf_range(safe_rect.position.x, safe_rect.end.x),
				_rng.randf_range(safe_rect.position.y, safe_rect.end.y)
			)
			
			# Scale exclusion for small arenas
			var exclusion = 400.0 if arena_size < 4000 else 800.0
			if pos.length() > exclusion:
				valid_pos = true
		
		if not valid_pos:
			continue
			
		boulder.global_position = pos
		
		var boulder_size := _rng.randf_range(0.8, 1.5)
		boulder.scale = Vector2(boulder_size, boulder_size)
		
		_boulders.append(boulder)
	
	print("[TerrainFeatures] Spawned ", count, " boulders")


## Clear all boulders
func clear_boulders() -> void:
	for boulder in _boulders:
		if is_instance_valid(boulder):
			boulder.queue_free()
	_boulders.clear()


## Set player reference for grass interaction
func set_player(player: Node2D) -> void:
	_player_ref = player


## Get grass field reference
func get_grass_field() -> Node2D:
	return _grass_field


## Clean up
func cleanup() -> void:
	clear_boulders()
	if _grass_field:
		_grass_field.queue_free()
		_grass_field = null
	if _boulder_container:
		_boulder_container.queue_free()
		_boulder_container = null
