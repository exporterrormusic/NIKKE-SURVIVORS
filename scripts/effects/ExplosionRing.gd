extends Node2D
class_name ExplosionRing

## Expanding ring for explosion effect

var _max_radius := 150.0
var _duration := 0.5
var _delay := 0.0
var _color := Color(1.0, 0.3, 0.1, 0.8)
var _timer := 0.0
var _started := false
var _ring_width := 8.0

func initialize(radius: float, duration: float, delay: float, color: Color) -> void:
	_max_radius = radius
	_duration = duration
	_delay = delay
	_color = color
	_ring_width = radius * 0.1

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	# Handle delay
	if _delay > 0:
		_delay -= delta
		return
	
	if not _started:
		_started = true
	
	_timer += delta
	
	if _timer >= _duration:
		queue_free()
		return
	
	queue_redraw()

func _draw() -> void:
	if not _started:
		return
	
	var t := _timer / _duration
	var current_radius := _max_radius * t
	var alpha := (1.0 - t) * _color.a
	var draw_color := Color(_color.r, _color.g, _color.b, alpha)
	var width := _ring_width * (1.0 - t * 0.5)  # Ring gets thinner as it expands
	
	# Draw ring as arc (full circle)
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 64, draw_color, width, true)
