extends Node
class_name EffectPool
## Object pool for frequently spawned visual effects.
## Reduces allocations during combat by reusing effect nodes.
##
## Usage:
##   # Get pool instance (create if not exists)
##   var pool = EffectPool.get_instance()
##   
##   # Spawn a pooled damage number
##   pool.spawn_damage_number(parent, position, value, is_crit)
##   
##   # Spawn a pooled hit spark
##   pool.spawn_hit_spark(parent, position, spark_type, direction)

# Pool sizes (pre-warmed at startup)
const DAMAGE_NUMBER_POOL_SIZE := 50
const HIT_SPARK_POOL_SIZE := 30

# Singleton instance
static var _instance: EffectPool = null

# Pools
var _damage_number_pool: Array[FloatingDamageNumber] = []
var _hit_spark_pool: Array[HitSpark] = []

# Container for inactive pooled objects
var _pool_container: Node = null


static func get_instance() -> EffectPool:
	if _instance == null:
		_instance = EffectPool.new()
		_instance.name = "EffectPool"
		# Add to tree at root level so it persists
		if Engine.get_main_loop():
			var root = Engine.get_main_loop().root
			if root:
				root.call_deferred("add_child", _instance)
	return _instance


func _ready() -> void:
	# Create container for pooled objects
	_pool_container = Node.new()
	_pool_container.name = "PooledEffects"
	add_child(_pool_container)
	
	# Pre-warm pools
	_prewarm_damage_numbers()
	_prewarm_hit_sparks()
	print("[EffectPool] Initialized with %d damage numbers, %d hit sparks" % [
		DAMAGE_NUMBER_POOL_SIZE, HIT_SPARK_POOL_SIZE
	])


func _prewarm_damage_numbers() -> void:
	for i in range(DAMAGE_NUMBER_POOL_SIZE):
		var num := FloatingDamageNumber.new()
		num.visible = false
		num.set_process(false)
		_pool_container.add_child(num)
		_damage_number_pool.append(num)


func _prewarm_hit_sparks() -> void:
	for i in range(HIT_SPARK_POOL_SIZE):
		var spark := HitSpark.new()
		spark.visible = false
		spark.set_process(false)
		_pool_container.add_child(spark)
		_hit_spark_pool.append(spark)


# =============================================================================
# DAMAGE NUMBERS
# =============================================================================

func spawn_damage_number(parent: Node, pos: Vector2, value: int, type: FloatingDamageNumber.NumberType = FloatingDamageNumber.NumberType.DAMAGE) -> FloatingDamageNumber:
	var num: FloatingDamageNumber = _get_pooled_damage_number()
	
	if num == null:
		# Pool exhausted, create new (will be freed normally)
		num = FloatingDamageNumber.new()
		num.setup(value, type)
		num.global_position = pos
		parent.add_child(num)
		return num
	
	# Reset and configure pooled number
	_reset_damage_number(num, value, type, pos)
	
	# Reparent to target parent
	if num.get_parent() != parent:
		num.get_parent().remove_child(num)
		parent.add_child(num)
	
	return num


func _get_pooled_damage_number() -> FloatingDamageNumber:
	for num in _damage_number_pool:
		if not num.visible:
			return num
	return null


func _reset_damage_number(num: FloatingDamageNumber, value: int, type: FloatingDamageNumber.NumberType, pos: Vector2) -> void:
	num.setup(value, type)
	num.global_position = pos
	num.visible = true
	num.modulate.a = 1.0
	num.scale = Vector2.ONE
	num.set_process(true)
	# Reset internal state
	num._elapsed = 0.0
	num._velocity = Vector2(randf_range(-20, 20), -FloatingDamageNumber.FLOAT_SPEED)


func return_damage_number(num: FloatingDamageNumber) -> void:
	## Called when damage number animation completes - returns to pool
	if num in _damage_number_pool:
		num.visible = false
		num.set_process(false)
		# Reparent back to pool container
		if num.get_parent() != _pool_container:
			num.get_parent().remove_child(num)
			_pool_container.add_child(num)


# =============================================================================
# HIT SPARKS
# =============================================================================

func spawn_hit_spark(parent: Node, pos: Vector2, type: HitSpark.SparkType = HitSpark.SparkType.NORMAL, direction: Vector2 = Vector2.RIGHT) -> HitSpark:
	var spark: HitSpark = _get_pooled_hit_spark()
	
	if spark == null:
		# Pool exhausted, create new (will be freed normally)
		spark = HitSpark.new()
		spark.spark_type = type
		spark.direction = direction
		spark.global_position = pos
		parent.add_child(spark)
		return spark
	
	# Reset and configure pooled spark
	_reset_hit_spark(spark, type, direction, pos)
	
	# Reparent to target parent
	if spark.get_parent() != parent:
		spark.get_parent().remove_child(spark)
		parent.add_child(spark)
	
	return spark


func _get_pooled_hit_spark() -> HitSpark:
	for spark in _hit_spark_pool:
		if not spark.visible:
			return spark
	return null


func _reset_hit_spark(spark: HitSpark, type: HitSpark.SparkType, direction: Vector2, pos: Vector2) -> void:
	spark.spark_type = type
	spark.direction = direction
	spark.global_position = pos
	spark.visible = true
	spark.modulate.a = 1.0
	spark.scale = Vector2.ONE
	spark.rotation = randf() * TAU
	spark.set_process(true)
	# Reset internal state
	spark._lifetime = 0.0
	spark._scale_anim = 0.0


func return_hit_spark(spark: HitSpark) -> void:
	## Called when hit spark animation completes - returns to pool
	if spark in _hit_spark_pool:
		spark.visible = false
		spark.set_process(false)
		# Reparent back to pool container
		if spark.get_parent() != _pool_container:
			spark.get_parent().remove_child(spark)
			_pool_container.add_child(spark)


# =============================================================================
# CONVENIENCE STATIC METHODS
# =============================================================================

static func damage(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return get_instance().spawn_damage_number(parent, pos, value, FloatingDamageNumber.NumberType.DAMAGE)


static func critical(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return get_instance().spawn_damage_number(parent, pos, value, FloatingDamageNumber.NumberType.CRITICAL)


static func heal(parent: Node, pos: Vector2, value: int) -> FloatingDamageNumber:
	return get_instance().spawn_damage_number(parent, pos, value, FloatingDamageNumber.NumberType.HEAL)


static func spark_normal(parent: Node, pos: Vector2, direction: Vector2 = Vector2.RIGHT) -> HitSpark:
	return get_instance().spawn_hit_spark(parent, pos, HitSpark.SparkType.NORMAL, direction)


static func spark_critical(parent: Node, pos: Vector2, direction: Vector2 = Vector2.RIGHT) -> HitSpark:
	return get_instance().spawn_hit_spark(parent, pos, HitSpark.SparkType.CRITICAL, direction)


static func spark_player_hit(parent: Node, pos: Vector2, direction: Vector2 = Vector2.RIGHT) -> HitSpark:
	return get_instance().spawn_hit_spark(parent, pos, HitSpark.SparkType.PLAYER_HIT, direction)
