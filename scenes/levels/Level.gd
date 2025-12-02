extends Node2D

const MAP_DEFINITIONS_DIR := "res://resources/maps/"
const DEFAULT_MAP_ID := &"emerald_fields"

var current_map_definition: MapDefinition = null
var enemy_spawn_timer: Timer = null
var world_bounds: Rect2 = Rect2()
var _combat_juice: Node = null

@onready var environment: Node2D = $Environment
@onready var map_selector: Control = $CanvasLayer/MapSelector

func _ready():
	set_process_input(true)
	_load_map_definition(DEFAULT_MAP_ID)
	_setup_combat_juice()
	_setup_environment()
	_setup_enemy_spawning()
	_connect_map_selector()

func _setup_combat_juice() -> void:
	# Create CombatJuice system
	var CombatJuiceScript = load("res://scripts/CombatJuice.gd")
	if CombatJuiceScript:
		_combat_juice = Node.new()
		_combat_juice.set_script(CombatJuiceScript)
		_combat_juice.name = "CombatJuice"
		add_child(_combat_juice)
		
		# Register camera - use call_deferred to ensure Player is ready
		call_deferred("_register_combat_juice_camera")
		
		# Add chromatic aberration overlay to CanvasLayer
		var canvas_layer = get_node_or_null("ScreenFlashLayer")
		if canvas_layer and _combat_juice.has_method("get_chromatic_overlay"):
			var overlay = _combat_juice.get_chromatic_overlay()
			if overlay:
				canvas_layer.add_child(overlay)

func _register_combat_juice_camera() -> void:
	var player = get_node_or_null("Player")
	if player:
		var camera = player.get_node_or_null("Camera2D")
		if camera and _combat_juice and _combat_juice.has_method("register_camera"):
			_combat_juice.register_camera(camera)
			print("[Level] Camera registered with CombatJuice")
		else:
			push_warning("[Level] Could not register camera - camera: ", camera, " combat_juice: ", _combat_juice)
	else:
		push_warning("[Level] Player not found for camera registration")

func _load_map_definition(map_id: StringName) -> void:
	var map_path := MAP_DEFINITIONS_DIR + String(map_id) + ".tres"
	if ResourceLoader.exists(map_path):
		current_map_definition = load(map_path)
		print("[Level] Loaded map: ", current_map_definition.display_name)
	else:
		push_warning("[Level] Map not found: ", map_path)
		# Fallback to default bounds
		world_bounds = Rect2(Vector2(-1920, -1080), Vector2(3840, 2160))

func _setup_environment() -> void:
	if current_map_definition:
		# Set world bounds from map definition
		world_bounds = current_map_definition.get_world_bounds()
		if environment and environment.has_method("set_world_bounds"):
			environment.set_world_bounds(world_bounds)
		
		# Initialize environment with map settings
		if environment and environment.has_method("initialize_environment"):
			var env_seed = current_map_definition.environment_seed if current_map_definition.environment_seed != 0 else randi()
			environment.initialize_environment(env_seed, current_map_definition.biome_id, current_map_definition.time_of_day_id)
	else:
		# Fallback bounds if no map loaded
		world_bounds = Rect2(Vector2(-1920, -1080), Vector2(3840, 2160))
		if environment and environment.has_method("set_world_bounds"):
			environment.set_world_bounds(world_bounds)
	
	# Register player with environment for grass interaction
	var player = $Player
	if player and environment and environment.has_method("register_player"):
		environment.register_player(player)

var current_wave: int = 0
var enemies_in_wave: int = 0
var wave_timer: Timer = null

func _setup_enemy_spawning() -> void:
	enemy_spawn_timer = Timer.new()
	add_child(enemy_spawn_timer)
	enemy_spawn_timer.wait_time = 0.5  # Faster spawning within waves
	enemy_spawn_timer.connect("timeout", Callable(self, "spawn_enemy"))
	
	wave_timer = Timer.new()
	add_child(wave_timer)
	wave_timer.wait_time = 10.0  # New wave every 10 seconds
	wave_timer.connect("timeout", Callable(self, "start_new_wave"))
	wave_timer.start()
	
	start_new_wave()

@onready var wave_display: Label = $CanvasLayer/WaveDisplay

func start_new_wave() -> void:
	current_wave += 1
	enemies_in_wave = current_wave * 3  # More enemies per wave
	print("[Level] Starting wave ", current_wave, " with ", enemies_in_wave, " enemies")
	
	if wave_display:
		wave_display.text = "Wave: " + str(current_wave)
	
	if enemy_spawn_timer:
		enemy_spawn_timer.start()

func spawn_enemy():
	if enemies_in_wave <= 0:
		if enemy_spawn_timer:
			enemy_spawn_timer.stop()
		return
	
	var enemy_scene = preload("res://scenes/characters/Enemy.tscn")
	var enemy = enemy_scene.instantiate()
	add_child(enemy)
	enemy.position = random_world_edge_position()
	
	enemies_in_wave -= 1
	
	# If this was the last enemy in the wave, stop the timer
	if enemies_in_wave <= 0:
		if enemy_spawn_timer:
			enemy_spawn_timer.stop()

func random_world_edge_position() -> Vector2:
	# Spawn enemies at the edges of the world bounds, not just screen
	var bounds = world_bounds
	var side = randi() % 4
	var pos = Vector2()
	
	match side:
		0:  # top
			pos = Vector2(randf_range(bounds.position.x, bounds.position.x + bounds.size.x), bounds.position.y - 50)
		1:  # right
			pos = Vector2(bounds.position.x + bounds.size.x + 50, randf_range(bounds.position.y, bounds.position.y + bounds.size.y))
		2:  # bottom
			pos = Vector2(randf_range(bounds.position.x, bounds.position.x + bounds.size.x), bounds.position.y + bounds.size.y + 50)
		3:  # left
			pos = Vector2(bounds.position.x - 50, randf_range(bounds.position.y, bounds.position.y + bounds.size.y))
	
	return pos

func _connect_map_selector() -> void:
	if map_selector:
		map_selector.connect("map_selected", Callable(self, "_on_map_selected"))
		map_selector.connect("time_selected", Callable(self, "_on_time_selected"))

func _on_map_selected(map_id: StringName) -> void:
	_load_map_definition(map_id)
	_setup_environment()
	# Clear existing enemies when changing maps
	for child in get_children():
		if child.is_in_group("enemies") or child.name.begins_with("Enemy"):
			child.queue_free()
	# Remove old central structure
	if has_node("CentralStructure"):
		get_node("CentralStructure").queue_free()
	# Add new central structure
	var central_structure = preload("res://scenes/world/CentralStructure.tscn").instantiate()
	central_structure.name = "CentralStructure"
	central_structure.position = world_bounds.get_center()
	add_child(central_structure)
	# Force environment refresh
	if environment and environment.has_method("set_environment"):
		var env_seed = current_map_definition.environment_seed if current_map_definition and current_map_definition.environment_seed != 0 else randi()
		environment.set_environment(current_map_definition.biome_id, current_map_definition.time_of_day_id, env_seed)
	# Recreate boundary walls
	_create_boundary_walls()
	# Reset wave system
	current_wave = 0
	enemies_in_wave = 0
	start_new_wave()

func _on_time_selected(time_id: StringName) -> void:
	if environment and environment.has_method("set_time_of_day"):
		environment.set_time_of_day(time_id)

func _create_boundary_walls() -> void:
	# Clear existing boundary walls
	for child in get_children():
		if child.name.begins_with("Boundary"):
			child.queue_free()
	
	# Create simple colored boundary markers
	var bounds = world_bounds
	var marker_size = 200.0
	
	# Corner markers
	var corners = [
		Vector2(bounds.position.x, bounds.position.y), # Top-left
		Vector2(bounds.position.x + bounds.size.x, bounds.position.y), # Top-right  
		Vector2(bounds.position.x, bounds.position.y + bounds.size.y), # Bottom-left
		Vector2(bounds.position.x + bounds.size.x, bounds.position.y + bounds.size.y) # Bottom-right
	]
	
	var colors = [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW]
	
	for i in range(4):
		var marker = ColorRect.new()
		marker.name = "Boundary" + str(i)
		marker.color = colors[i]
		marker.size = Vector2(marker_size, marker_size)
		marker.position = corners[i] - Vector2(marker_size/2, marker_size/2)
		add_child(marker)

# Allow toggling map selector with a key (for testing)
func _input(event):
	if event.is_action_pressed("ui_cancel"):  # ESC key
		if map_selector:
			map_selector.visible = !map_selector.visible