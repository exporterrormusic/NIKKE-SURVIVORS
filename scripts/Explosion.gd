extends Area2D

var time = 0.0
var _light: PointLight2D = null

func _ready():
    connect("body_entered", Callable(self, "_on_body_entered"))
    for body in get_overlapping_bodies():
        if body != get_parent().get_node("Player") and body.has_method("take_damage"):
            # Skip charmed enemies (they're friendly now)
            if body.is_in_group("charmed_allies"):
                continue
            var hit_direction = (body.global_position - global_position).normalized()
            body.take_damage(1, false, hit_direction)
    modulate.a = 1.0
    
    # Add bright explosion light
    _light = PointLight2D.new()
    _light.name = "ExplosionLight"
    _light.color = Color(1.0, 0.7, 0.3)  # Warm orange
    _light.energy = 2.5  # Very bright initially
    _light.texture = _create_light_texture()
    _light.texture_scale = 0.8  # Large radius
    _light.shadow_enabled = false
    add_child(_light)
    
    var tween = create_tween()
    tween.set_parallel(true)
    tween.tween_property(self, "modulate:a", 0.0, 0.2)
    tween.tween_property(_light, "energy", 0.0, 0.25)  # Light fades with explosion
    await tween.finished
    queue_free()

func _create_light_texture() -> Texture2D:
    # Use cached texture for performance
    return TextureCache.get_light_texture_64()

func _process(delta):
    time += delta
    $Sprite2D.material.set_shader_parameter("time", time)

func _on_body_entered(body):
    if body != get_parent().get_node("Player") and body.has_method("take_damage"):
        # Skip charmed enemies (they're friendly now)
        if body.is_in_group("charmed_allies"):
            return
        var hit_direction = (body.global_position - global_position).normalized()
        body.take_damage(1, false, hit_direction)