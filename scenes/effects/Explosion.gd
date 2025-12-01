extends Area2D

var time = 0.0

func _ready():
    connect("body_entered", Callable(self, "_on_body_entered"))
    for body in get_overlapping_bodies():
        if body != get_parent().get_node("Player") and body.has_method("take_damage"):
            var hit_direction = (body.global_position - global_position).normalized()
            body.take_damage(1, false, hit_direction)
    modulate.a = 1.0
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.2)
    await tween.finished
    queue_free()

func _process(delta):
    time += delta
    $Sprite2D.material.set_shader_parameter("time", time)

func _on_body_entered(body):
    if body != get_parent().get_node("Player") and body.has_method("take_damage"):
        var hit_direction = (body.global_position - global_position).normalized()
        body.take_damage(20, false, hit_direction)