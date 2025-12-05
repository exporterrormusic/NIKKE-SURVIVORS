extends Area2D

@onready var visual = $SwordSlashVisual

var _hit_bodies: Array = []

# Critical hit settings
const BASE_CRIT_CHANCE := 0.15  # 15% base chance to crit
const CRIT_MULTIPLIER := 2.0  # 2x damage on crit
var base_damage := 2

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	visual.update_visual({
		"radius": 260.0,
		"arc_degrees": 90.0,
		"core_color": Color(0.95, 0.85, 1.0, 0.9),
		"edge_color": Color(1.0, 1.0, 1.0, 1.0),
		"glow_color": Color(0.7, 0.5, 0.9, 0.6),
		"fade": 1.0,
		"wipe_progress": 0.0,
		"sparkle_count": 8,
		"sparkle_seed": randi()
	})
	
	# Sweep animation - fast swing like Link to the Past
	var tween = create_tween()
	tween.tween_property(visual, "wipe_progress", 1.0, 0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	
	# Brief hold at full extension
	await get_tree().create_timer(0.04).timeout
	
	# Fade out
	var fade_tween = create_tween()
	fade_tween.tween_property(visual, "modulate:a", 0.0, 0.06)
	await fade_tween.finished
	
	queue_free()

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var direction = (mouse_pos - get_parent().global_position).normalized()
	position = direction * 30
	rotation = direction.angle()

func _on_body_entered(body):
	if body == get_parent():
		return
	if body in _hit_bodies:
		return
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	if body.has_method("take_damage"):
		# Roll for critical hit - base chance + shop bonus
		var crit_chance := BASE_CRIT_CHANCE
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_crit_chance"):
			crit_chance += player.get_crit_chance()
		var is_crit := randf() < crit_chance
		var damage := base_damage
		if is_crit:
			damage = int(base_damage * CRIT_MULTIPLIER)
		# Pass hit direction (slash direction) for knockback visual
		var hit_direction = Vector2.from_angle(rotation)
		body.take_damage(damage, is_crit, hit_direction)
		_hit_bodies.append(body)
