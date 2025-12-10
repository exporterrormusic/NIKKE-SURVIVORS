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
var _redraw_frame := 0

func initialize(radius: float, duration: float, delay: float, color: Color) -> void:
	_max_radius = radius
	_duration = duration
	_delay = delay
	_color = color
	_ring_width = radius * 0.1

func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat

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
	
	# Throttle redraws to every other frame
	_redraw_frame += 1
	if _redraw_frame % 2 == 0:
		queue_redraw()

func _draw() -> void:
	if not _started:
		return
	
	var t := _timer / _duration
	var current_radius := _max_radius * t
	var alpha := (1.0 - t) * _color.a
	var draw_color := Color(_color.r, _color.g, _color.b, alpha)
	var width := _ring_width * (1.0 - t * 0.5)  # Ring gets thinner as it expands
	
	# Draw ring as arc (full circle) - reduced segments for performance
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 24, draw_color, width, true)
