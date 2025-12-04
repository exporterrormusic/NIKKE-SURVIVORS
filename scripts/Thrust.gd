extends Area2D

@onready var visual = $SwordBeamVisual
@onready var collision = $CollisionShape2D

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	visual.update_visual({
		"active_length": 0.0,
		"beam_width": 18.0,
		"color": Color(0.39, 1.0, 0.78, 0.95),
		"fade": 1.0,
		"activation": 1.0,
		"lifetime_ratio": 0.0,
		"seed": randi(),
		"time": 0.0
	})
	var tween = create_tween()
	tween.tween_property(self, "beam_length", 300.0, 0.1)
	await tween.finished
	await get_tree().create_timer(0.25).timeout
	var tween2 = create_tween()
	tween2.tween_property(self, "beam_length", 0.0, 0.05)
	await tween2.finished
	queue_free()

var beam_length: float = 0.0:
	set(value):
		beam_length = value
		visual.update_visual({
			"active_length": beam_length,
			"beam_width": 18.0,
			"color": Color(0.39, 1.0, 0.78, 0.95),
			"fade": 1.0,
			"activation": 1.0,
			"lifetime_ratio": 0.0,
			"seed": randi(),
			"time": Time.get_time_dict_from_system()["second"] as float
		})

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var direction = (mouse_pos - get_parent().global_position).normalized()
	position = direction * 50
	rotation = direction.angle()

func _on_body_entered(body):
	if body == get_parent():
		return
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	if body.has_method("take_damage"):
		var hit_direction = Vector2.from_angle(rotation)
		body.take_damage(5, false, hit_direction)
