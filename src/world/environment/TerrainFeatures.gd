extends Node
class_name TerrainFeatures
## Manages terrain features like grass fields and obstacle boulders.
##
## Extracted from EnvironmentController to reduce god class size.

const PhysicalGrassFieldScript := preload("res://src/world/physical_grass_field.gd")
const ProceduralBoulderScript := preload("res://src/world/environment/procedural_boulder.gd")

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
		_grass_field.world_bounds = _world_bounds  # Set bounds directly
		parent.add_child(_grass_field)
		print("[TerrainFeatures] Created grass field for biome: ", biome.biome_id)


## Update grass with player position
func update_grass_player_position(_delta: float) -> void:
	if _grass_field and _player_ref and is_instance_valid(_player_ref):
		_grass_field.update_player_position(_player_ref.global_position)


## Spawn obstacle boulders
func spawn_boulders(_biome: BiomeDefinition, parent: Node2D, count: int = 40) -> void:
	if not _enabled:
		return
	
	# Clear existing boulders
	clear_boulders()
	
	# Create boulder container
	if not _boulder_container:
		_boulder_container = Node2D.new()
		_boulder_container.name = "BoulderContainer"
		parent.add_child(_boulder_container)
	
	# Spawn boulders
	for i in range(count):
		var boulder = ProceduralBoulderScript.new()
		_boulder_container.add_child(boulder)
		
		# Try to find valid position
		var valid_pos := false
		var pos := Vector2.ZERO
		var attempts := 0
		
		while not valid_pos and attempts < 20:
			attempts += 1
			# Margin from edges (400px)
			var margin = 400.0
			var safe_rect = _world_bounds.grow(-margin)
			
			pos = Vector2(
				_rng.randf_range(safe_rect.position.x, safe_rect.end.x),
				_rng.randf_range(safe_rect.position.y, safe_rect.end.y)
			)
			
			# Check distance from center (Player Spawn: 800px radius safe zone)
			if pos.length() > 800.0:
				valid_pos = true
		
		# If we failed to find a spot after 20 tries, skip this boulder
		if not valid_pos:
			continue
			
		boulder.global_position = pos
		
		# Random size
		var size := _rng.randf_range(0.8, 1.5)
		boulder.scale = Vector2(size, size)
		
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
