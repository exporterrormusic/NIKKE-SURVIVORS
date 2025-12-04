extends Area2D

@export var damage:int = 999
@export var lifespan: float = 0.5
@export var owner_node: Node = null

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	# Auto-free after lifespan
	call_deferred("_start_life_timer")

func _start_life_timer():
	await get_tree().create_timer(lifespan).timeout
	queue_free()

func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return
	if body == owner_node:
		return
	# Skip charmed enemies (they're friendly now)
	if body.is_in_group("charmed_allies"):
		return
	if not body.has_method("take_damage"):
		return
	# Inflict damage
	body.take_damage(damage)
