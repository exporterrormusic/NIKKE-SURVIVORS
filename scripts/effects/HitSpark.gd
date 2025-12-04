extends Node2D
class_name HitSpark

## Anime-style hit spark effect - spawns at point of impact
## Shows brief star/slash burst then fades

enum SparkType { NORMAL, CRITICAL, PLAYER_HIT }

var spark_type: SparkType = SparkType.NORMAL
var direction: Vector2 = Vector2.RIGHT  # Direction the hit came FROM

# Animation
var _lifetime: float = 0.0
var _max_lifetime: float = 0.25  # Longer duration for visibility
var _scale_anim: float = 0.0

# Visual properties per type - vivid colors that get brightness-boosted for bloom
const NORMAL_COLOR := Color(1.0, 0.95, 0.5, 1.0)  # Yellow-gold
const CRITICAL_COLOR := Color(1.0, 0.6, 0.2, 1.0)  # Orange
const PLAYER_HIT_COLOR := Color(1.0, 0.3, 0.3, 1.0)  # Red

# Brightness multiplier for bloom effect
const BLOOM_BOOST := 1.5

const SPARK_SIZE := 35.0  # Bigger sparks
const LINE_COUNT := 6  # More spark lines

func _ready() -> void:
	z_index = 50
	set_process(true)
	# Random rotation for variety
	rotation = randf() * TAU

func _process(delta: float) -> void:
	_lifetime += delta
	
	# Scale animation: quick pop then shrink
	var t = _lifetime / _max_lifetime
	if t < 0.3:
		_scale_anim = ease(t / 0.3, 0.2)  # Quick expand
	else:
		_scale_anim = 1.0 - ease((t - 0.3) / 0.7, 2.0)  # Slow shrink
	
	queue_redraw()
	
	if _lifetime >= _max_lifetime:
		queue_free()

func _draw() -> void:
	var color: Color
	var size_mult: float = 1.0
	
	match spark_type:
		SparkType.NORMAL:
			color = NORMAL_COLOR
			size_mult = 1.0
		SparkType.CRITICAL:
			color = CRITICAL_COLOR
			size_mult = 2.0  # Much bigger for crits
		SparkType.PLAYER_HIT:
			color = PLAYER_HIT_COLOR
			size_mult = 1.8  # Bigger for player hits
	
	var alpha = 1.0 - (_lifetime / _max_lifetime)
	# Apply bloom boost to RGB while keeping alpha separate
	var bloom_color = Color(color.r * BLOOM_BOOST, color.g * BLOOM_BOOST, color.b * BLOOM_BOOST, alpha)
	
	var current_size = SPARK_SIZE * _scale_anim * size_mult
	
	# Draw star burst pattern
	for i in range(LINE_COUNT):
		var angle = (TAU / LINE_COUNT) * i
		var line_dir = Vector2.from_angle(angle)
		
		# Main line - THICKER
		var line_end = line_dir * current_size
		draw_line(Vector2.ZERO, line_end, bloom_color, 4.0 * _scale_anim, true)
		
		# Secondary shorter lines between main lines
		var secondary_angle = angle + (TAU / LINE_COUNT) * 0.5
		var secondary_dir = Vector2.from_angle(secondary_angle)
		var secondary_end = secondary_dir * current_size * 0.5
		draw_line(Vector2.ZERO, secondary_end, bloom_color, 2.5 * _scale_anim, true)
	
	# Center glow circle
	var glow_color = bloom_color
	glow_color.a = alpha * 0.6
	draw_circle(Vector2.ZERO, current_size * 0.3, glow_color)
	
	# Bright center - boost white for bloom
	var center_color = Color(BLOOM_BOOST, BLOOM_BOOST, BLOOM_BOOST, alpha)
	draw_circle(Vector2.ZERO, current_size * 0.15, center_color)

# ============ STATIC SPAWNERS ============

static func spawn_normal(parent: Node, pos: Vector2, hit_direction: Vector2 = Vector2.RIGHT) -> HitSpark:
	var spark = HitSpark.new()
	spark.spark_type = SparkType.NORMAL
	spark.direction = hit_direction
	spark.global_position = pos
	parent.add_child(spark)
	return spark

static func spawn_critical(parent: Node, pos: Vector2, hit_direction: Vector2 = Vector2.RIGHT) -> HitSpark:
	var spark = HitSpark.new()
	spark.spark_type = SparkType.CRITICAL
	spark.direction = hit_direction
	spark.global_position = pos
	parent.add_child(spark)
	return spark

static func spawn_player_hit(parent: Node, pos: Vector2, hit_direction: Vector2 = Vector2.RIGHT) -> HitSpark:
	var spark = HitSpark.new()
	spark.spark_type = SparkType.PLAYER_HIT
	spark.direction = hit_direction
	spark.global_position = pos
	parent.add_child(spark)
	return spark
