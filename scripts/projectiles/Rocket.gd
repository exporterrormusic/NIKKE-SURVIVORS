extends Area2D

var velocity = Vector2.ZERO
var acceleration = 500
var max_speed = 1200
var player
var target_enemy = null
var last_target_pos = Vector2.ZERO
var time = 0.0

# Smoke trail settings - rockets have more intense trails
const SMOKE_INTERVAL := 0.025
const SMOKE_LIFETIME := 0.5
const SMOKE_START_SIZE := 5.0
const SMOKE_END_SIZE := 18.0
var _smoke_timer := 0.0
var _smoke_particles: Array = []
var _trail_color := Color(0.45, 0.45, 0.5, 0.7)  # Grey smoke
var _fire_color := Color(1.0, 0.6, 0.15, 0.9)  # Orange-yellow fire
var _light: PointLight2D = null

func _ready():
    add_to_group("projectiles")
    connect("body_entered", Callable(self, "_on_body_entered"))
    player = get_parent().get_node("Player")
    # Select initial target
    var closest_enemy = null
    var min_dist = INF
    for child in get_parent().get_children():
        if child is CharacterBody2D and child != player and child.has_method("take_damage"):
            var dist = global_position.distance_to(child.global_position)
            if dist < min_dist:
                min_dist = dist
                closest_enemy = child
    if closest_enemy:
        target_enemy = closest_enemy
        last_target_pos = closest_enemy.global_position
    else:
        last_target_pos = player.global_position  # fallback
    set_process(true)
    
    # Add dynamic point light - rockets are brighter
    _light = PointLight2D.new()
    _light.name = "RocketLight"
    _light.color = Color(1.0, 0.5, 0.15)  # Orange-red glow
    _light.energy = 1.0
    _light.texture = _create_light_texture()
    _light.texture_scale = 0.35
    _light.shadow_enabled = false
    add_child(_light)

func _create_light_texture() -> Texture2D:
    # Use cached texture for performance
    return TextureCache.get_light_texture_64()

func _process(delta):
    # Flicker the light intensely (every other frame)
    if _light and Engine.get_process_frames() % 2 == 0:
        _light.energy = 0.8 + randf() * 0.5
    
    # Update smoke trail
    _smoke_timer += delta
    if _smoke_timer >= SMOKE_INTERVAL:
        _smoke_timer = 0.0
        _spawn_smoke_particle()
    
    # Update existing smoke particles
    var i := 0
    while i < _smoke_particles.size():
        var p: Dictionary = _smoke_particles[i]
        p["age"] += delta
        if p["age"] >= SMOKE_LIFETIME:
            _smoke_particles.remove_at(i)
            continue
        # Smoke rises and spreads
        p["pos"] += Vector2(randf_range(-12, 12), randf_range(-25, -10)) * delta
        _smoke_particles[i] = p
        i += 1
    
    # Only redraw every other frame for performance
    if Engine.get_process_frames() % 2 == 0:
        queue_redraw()

func _spawn_smoke_particle():
    _smoke_particles.append({
        "pos": global_position,
        "age": 0.0,
        "size_offset": randf_range(-3, 3)
    })

func _draw():
    # Draw smoke trail (in local space)
    for p in _smoke_particles:
        var life_ratio: float = p["age"] / SMOKE_LIFETIME
        var alpha := (1.0 - life_ratio) * 0.6
        var size: float = lerp(SMOKE_START_SIZE, SMOKE_END_SIZE, life_ratio) + p["size_offset"]
        var local_pos: Vector2 = p["pos"] - global_position
        
        # Bright fire core (fades quickly)
        if life_ratio < 0.35:
            var fire_alpha := (1.0 - life_ratio / 0.35) * 0.8
            var fire_col := Color(_fire_color.r * 1.5, _fire_color.g * 1.5, _fire_color.b, fire_alpha)
            draw_circle(local_pos, size * 0.6, fire_col)
        
        # Smoke puff
        var smoke_col := Color(_trail_color.r, _trail_color.g, _trail_color.b, alpha)
        draw_circle(local_pos, size, smoke_col)

func _physics_process(delta):
    time += delta
    var target_pos = last_target_pos
    if target_enemy and is_instance_valid(target_enemy):
        target_pos = target_enemy.global_position
        last_target_pos = target_pos
    # Move towards target_pos
    acceleration = min(acceleration + 6000 * delta, 8000)
    var dir = (target_pos - global_position).normalized()
    velocity += dir * acceleration * delta
    if velocity.length() > max_speed:
        velocity = velocity.normalized() * max_speed
    position += velocity * delta
    rotation = velocity.angle()  # point towards movement direction
    if time > 3.0 or global_position.distance_to(target_pos) < 30:
        call_deferred("explode")
    if position.x < -100 or position.x > 2000 or position.y < -100 or position.y > 1200:
        call_deferred("queue_free")

func _on_body_entered(body):
    if body == player:
        return
    # Ignore other projectiles (rockets, missiles, etc.)
    if body.is_in_group("projectiles"):
        return
    # Skip charmed enemies (they're friendly now)
    if body.is_in_group("charmed_allies"):
        return
    if body.has_method("take_damage"):
        var hit_direction = velocity.normalized()
        body.take_damage(1, false, hit_direction)
    call_deferred("explode")

func explode():
    var explosion_scene = preload("res://scenes/effects/Explosion.tscn")
    var explosion = explosion_scene.instantiate()
    get_parent().add_child(explosion)
    explosion.global_position = global_position
    call_deferred("queue_free")