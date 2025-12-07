extends Node
class_name TargetCache

## Centralized cache for enemy and ally targeting.
## Prevents expensive get_nodes_in_group() calls every frame by caching results.
## Updated once per frame maximum, shared across all entities.

# Cache refresh interval (in seconds) - balance between freshness and performance
const CACHE_INTERVAL := 0.1  # 100ms = 10 updates per second

# Cached arrays
static var _enemies: Array = []
static var _charmed_allies: Array = []
static var _nayuta_clones: Array = []
static var _player: Node2D = null

# Cache timing
static var _last_cache_frame: int = -1
static var _cache_timer: float = 0.0

# Tree reference (set once per scene)
static var _tree: SceneTree = null


static func _ensure_tree() -> bool:
	if _tree == null or not is_instance_valid(_tree):
		if Engine.get_main_loop() is SceneTree:
			_tree = Engine.get_main_loop() as SceneTree
	return _tree != null


static func refresh_if_needed(delta: float = 0.0) -> void:
	"""Call this once per frame from a manager, or it auto-refreshes on access."""
	var current_frame := Engine.get_process_frames()
	if current_frame == _last_cache_frame:
		return  # Already updated this frame
	
	_cache_timer += delta
	if _cache_timer < CACHE_INTERVAL and _last_cache_frame >= 0:
		return  # Not time yet
	
	_cache_timer = 0.0
	_last_cache_frame = current_frame
	_refresh_cache()


static func _refresh_cache() -> void:
	if not _ensure_tree():
		return
	
	# Update all cached arrays
	_enemies = _tree.get_nodes_in_group("enemies")
	_charmed_allies = _tree.get_nodes_in_group("charmed_allies")
	_nayuta_clones = _tree.get_nodes_in_group("nayuta_clones")
	
	# Cache player reference
	var players := _tree.get_nodes_in_group("player")
	_player = players[0] as Node2D if not players.is_empty() else null


static func get_enemies() -> Array:
	"""Returns cached enemy list. Auto-refreshes if stale."""
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache()
		_last_cache_frame = current_frame
	return _enemies


static func get_charmed_allies() -> Array:
	"""Returns cached charmed allies list."""
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache()
		_last_cache_frame = current_frame
	return _charmed_allies


static func get_nayuta_clones() -> Array:
	"""Returns cached Nayuta clones list."""
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache()
		_last_cache_frame = current_frame
	return _nayuta_clones


static func get_player() -> Node2D:
	"""Returns cached player reference."""
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache()
		_last_cache_frame = current_frame
	return _player


static func get_nearest_enemy(from_position: Vector2, max_range: float = INF) -> Node2D:
	"""Find the nearest valid enemy to a position."""
	var enemies := get_enemies()
	var nearest: Node2D = null
	var nearest_dist := max_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if enemy.get("hp") != null and enemy.get("hp") <= 0:
			continue
		
		var dist := from_position.distance_to((enemy as Node2D).global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy as Node2D
	
	return nearest


static func get_enemies_in_range(from_position: Vector2, range_radius: float) -> Array:
	"""Get all enemies within a radius. Returns array of Node2D."""
	var enemies := get_enemies()
	var result: Array = []
	var range_sq := range_radius * range_radius
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if enemy.get("hp") != null and enemy.get("hp") <= 0:
			continue
		
		var dist_sq := from_position.distance_squared_to((enemy as Node2D).global_position)
		if dist_sq <= range_sq:
			result.append(enemy)
	
	return result


static func clear_cache() -> void:
	"""Clear all caches. Call when changing scenes."""
	_enemies.clear()
	_charmed_allies.clear()
	_nayuta_clones.clear()
	_player = null
	_last_cache_frame = -1
	_cache_timer = 0.0
	_tree = null
