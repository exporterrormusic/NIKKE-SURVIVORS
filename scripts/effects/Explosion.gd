extends Area2D

var time = 0.0
var _light: PointLight2D = null
var _damaged_bodies: Array = []  # Track who we've already damaged
var owner_node: Node = null  # Track who spawned this explosion for killer_source
var killer_source_override: String = ""  # Override killer_source if set

# Performance: disable explosion lights (less impactful since they're short-lived)
const ENABLE_EXPLOSION_LIGHTS := false

func _ready():
    connect("body_entered", Callable(self, "_on_body_entered"))
    # Damage all bodies currently overlapping
    for body in get_overlapping_bodies():
        _try_damage_body(body)
    modulate.a = 1.0
    
    # Explosion lights are short-lived but still add up - optional
    if ENABLE_EXPLOSION_LIGHTS:
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
    if _light:
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
    _try_damage_body(body)

func _try_damage_body(body) -> void:
    # Skip if already damaged this body
    if body in _damaged_bodies:
        return
    if body == get_parent().get_node_or_null("Player"):
        return
    if not body.has_method("take_damage"):
        return
    # Skip charmed enemies (they're friendly now)
    if body.is_in_group("charmed_allies"):
        return
    _damaged_bodies.append(body)
    var hit_direction = (body.global_position - global_position).normalized()
    # Determine killer source - use override if set, otherwise check owner type
    var killer_source := "player"
    if killer_source_override != "":
        killer_source = killer_source_override
    elif is_instance_valid(owner_node) and (owner_node is NayutaClone or owner_node is SummonedAlly):
        killer_source = "summon"
    body.take_damage(1, false, hit_direction, false, killer_source)