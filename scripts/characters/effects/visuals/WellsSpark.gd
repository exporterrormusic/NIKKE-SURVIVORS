# Extracted from scripts/characters/WellsController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0
var _sparks: Array = []

func _ready() -> void:
    z_index = 300
    # Generate random sparks
    for i in range(12):
        _sparks.append({
            "dir": Vector2(randf_range(-1.0, 1.0), randf_range(-1.5, -0.3)).normalized(),
            "speed": randf_range(80.0, 200.0),
            "life": randf_range(0.3, 0.6),
            "pos": Vector2.ZERO
        })

func _process(delta: float) -> void:
    _time += delta
    for spark in _sparks:
        spark.pos += spark.dir * spark.speed * delta
    if _time >= 0.7:
        queue_free()
        return
    queue_redraw()

func _draw() -> void:
    for spark in _sparks:
        var age: float = float(_time) / float(spark.life)
        if age > 1.0:
            continue
        var alpha: float = 1.0 - age
        # Yellow-orange sparks
        var color: Color = Color(1.0, 0.8 - age * 0.4, 0.2, alpha)
        draw_circle(spark.pos, 2.0 + (1.0 - age) * 2.0, color)
        # Spark trail
        var trail: Vector2 = spark.pos - spark.dir * 8.0
        draw_line(trail, spark.pos, Color(1.0, 0.9, 0.4, alpha * 0.5), 1.5)
