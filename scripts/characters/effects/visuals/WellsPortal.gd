# Extracted from scripts/characters/WellsController.gd (was runtime-compiled embedded source).
extends Node2D

var _time: float = 0.0
var _duration: float = 2.5

func _ready() -> void:
    z_index = 200

func _process(delta: float) -> void:
    _time += delta
    if _time >= _duration:
        queue_free()
        return
    queue_redraw()

func _draw() -> void:
    var progress := _time / _duration
    var open_phase := clampf(progress * 2.0, 0.0, 1.0)  # Portal opens in first half
    var close_phase := clampf((progress - 0.7) / 0.3, 0.0, 1.0)  # Closes in last 30%
    
    var alpha := 1.0 - close_phase
    var portal_w := 100.0 * open_phase * (1.0 - close_phase * 0.5)
    var portal_h := 175.0 * open_phase * (1.0 - close_phase * 0.5)
    
    # Shimmering distortion effect - wavy oval portal
    var wave_offset := sin(_time * 8.0) * 5.0
    
    # Outer glow
    for i in range(5):
        var glow_alpha := alpha * 0.15 * (1.0 - float(i) * 0.15)
        var extra := float(i) * 8.0
        _draw_wavy_oval(portal_w + extra, portal_h + extra, Color(0.6, 0.2, 0.9, glow_alpha), wave_offset)
    
    # Portal core (darker center)
    _draw_wavy_oval(portal_w * 0.8, portal_h * 0.8, Color(0.1, 0.0, 0.2, alpha * 0.9), wave_offset)
    
    # Edge ring
    _draw_wavy_oval_ring(portal_w, portal_h, Color(0.9, 0.4, 1.0, alpha), wave_offset, 4.0)
    
    # Inner shimmer particles
    for i in range(8):
        var angle := TAU * float(i) / 8.0 + _time * 3.0
        var r := portal_w * 0.6 * (0.7 + sin(_time * 5.0 + float(i)) * 0.3)
        var px := cos(angle) * r
        var py := sin(angle) * r * (portal_h / portal_w)
        draw_circle(Vector2(px, py), 3.02, Color(1.0, 0.8, 1.0, alpha * 0.7))

func _draw_wavy_oval(w: float, h: float, color: Color, wave: float) -> void:
    var points := PackedVector2Array()
    for i in range(32):
        var angle := TAU * float(i) / 32.0
        var wave_mod := 1.0 + sin(angle * 4.0 + wave * 0.5) * 0.1
        points.append(Vector2(cos(angle) * w * wave_mod, sin(angle) * h * wave_mod))
    draw_colored_polygon(points, color)

func _draw_wavy_oval_ring(w: float, h: float, color: Color, wave: float, thickness: float) -> void:
    var prev := Vector2.ZERO
    for i in range(33):
        var angle := TAU * float(i) / 32.0
        var wave_mod := 1.0 + sin(angle * 4.0 + wave * 0.5) * 0.1
        var pt := Vector2(cos(angle) * w * wave_mod, sin(angle) * h * wave_mod)
        if i > 0:
            draw_line(prev, pt, color, thickness)
        prev = pt
