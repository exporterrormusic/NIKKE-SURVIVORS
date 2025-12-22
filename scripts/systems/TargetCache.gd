extends Node
class_name TargetCache

## Centralized cache for enemy and ally targeting.
## Prevents expensive get_nodes_in_group() calls every frame by caching results.
## Updated once per frame maximum, shared across all entities.

# Cache refresh intervals (in seconds) - balance between freshness and performance
const CACHE_INTERVAL := 0.2  # 200ms for main combat groups (enemies, player)
const CACHE_INTERVAL_SLOW := 0.5  # 500ms for non-critical groups (boulders, shields)

# Cached arrays
static var _enemies: Array = []
static var _charmed_allies: Array = []
static var _nayuta_clones: Array = []
static var _shielder_shields: Array = []
static var _summoned_allies: Array = []
static var _boulders: Array = []
static var _player: Node2D = null

# Cache timing
static var _last_cache_frame: int = -1
static var _cache_timer: float = 0.0
static var _slow_cache_timer: float = 0.0

# Tree reference (set once per scene)
static var _tree: SceneTree = null

## Clean up all cached references to prevent dangling references on exit
static func cleanup() -> void:
	_enemies.clear()
	_charmed_allies.clear()
	_nayuta_clones.clear()
	_shielder_shields.clear()
	_summoned_allies.clear()
	_boulders.clear()
	_player = null
	_tree = null
	_last_cache_frame = -1
	_cache_timer = 0.0
	_slow_cache_timer = 0.0
	print("[TargetCache] Cleanup complete")


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
	_slow_cache_timer += delta
	
	if _cache_timer >= CACHE_INTERVAL or _last_cache_frame < 0:
		_cache_timer = 0.0
		_last_cache_frame = current_frame
		_refresh_cache_fast()
	
	if _slow_cache_timer >= CACHE_INTERVAL_SLOW:
		_slow_cache_timer = 0.0
		_refresh_cache_slow()


static func _refresh_cache_fast() -> void:
	"""Refresh high-priority combat groups."""
	if not _ensure_tree():
		return
	
	# Critical combat groups - updated frequently
	_enemies = _tree.get_nodes_in_group("enemies")
	_charmed_allies = _tree.get_nodes_in_group("charmed_allies")
	_summoned_allies = _tree.get_nodes_in_group("summoned_allies")
	
	# Cache player reference
	var players := _tree.get_nodes_in_group("player")
	_player = players[0] as Node2D if not players.is_empty() else null


static func _refresh_cache_slow() -> void:
	"""Refresh low-priority groups less frequently."""
	if not _ensure_tree():
		return
	
	# Non-critical groups - updated less often
	_nayuta_clones = _tree.get_nodes_in_group("nayuta_clones")
	_shielder_shields = _tree.get_nodes_in_group("shielder_shields")
	_boulders = _tree.get_nodes_in_group("boulders")


static func get_enemies() -> Array:
	"""Returns cached enemy list. Auto-refreshes if stale."""
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache_fast()
		_last_cache_frame = current_frame
	return _enemies


static func get_charmed_allies() -> Array:
	"""Returns cached charmed allies list."""
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache_fast()
		_last_cache_frame = current_frame
	return _charmed_allies


static func get_nayuta_clones() -> Array:
	"""Returns cached Nayuta clones list."""
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache_fast()
		_last_cache_frame = current_frame
	return _nayuta_clones


static func get_shielder_shields() -> Array:
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache_fast()
		_last_cache_frame = current_frame
	return _shielder_shields

static func get_summoned_allies() -> Array:
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache_fast()
		_last_cache_frame = current_frame
	return _summoned_allies

static func get_boulders() -> Array:
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache_slow()
		_last_cache_frame = current_frame
	return _boulders


static func get_player() -> Node2D:
	"""Returns cached player reference."""
	var current_frame := Engine.get_process_frames()
	if current_frame != _last_cache_frame:
		_refresh_cache_fast()
		_last_cache_frame = current_frame
	return _player


static func get_nearest_enemy(from_position: Vector2, max_range: float = INF) -> Node2D:
	"""Find the nearest valid enemy to a position."""
	var enemies := get_enemies()
	var nearest: Node2D = null
	var min_dist_sq := max_range * max_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		# Skip dying enemies? (Optional)
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
			
		var dist_sq = from_position.distance_squared_to(enemy.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			nearest = enemy
			
	return nearest
