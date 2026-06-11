# Extracted from scripts/characters/WellsController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0

func _ready() -> void:
    z_index = -1

func _process(delta: float) -> void:
    _time += delta
    queue_redraw()

func _draw() -> void:
    var pulse := sin(_time * 4.0) * 0.3 + 0.7
    var alpha := 0.5 * pulse
    
    # Pulsing red glow
    for i in range(4):
        var radius := 40.0 + float(i) * 20.0
        var color := Color(1.0, 0.15, 0.15, alpha * (1.0 - float(i) * 0.2))
        draw_arc(Vector2.ZERO, radius, 0, TAU, 24, color, 4.0)
    
    # Red energy particles orbiting
    for i in range(8):
        var angle := TAU * float(i) / 8.0 + _time * 2.5
        var dist := 50.0 + sin(_time * 3.0 + float(i)) * 15.0
        var pos := Vector2(cos(angle), sin(angle)) * dist
        draw_circle(pos, 5.0, Color(1.0, 0.2, 0.2, 0.7))
