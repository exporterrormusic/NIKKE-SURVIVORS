# Extracted from scripts/enemies/EnemySpawner.gd (was runtime-compiled embedded
# source with colors injected via string composition; now plain vars).
extends Node2D

var ring_base_color := Color(1.0, 0.1, 0.0) # Super boss: Color(0.8, 0.0, 0.2)
var core_base_color := Color(1.0, 0.5, 0.2) # Super boss: Color(1.0, 0.2, 0.4)

var _time := 0.0
var _max_radius := 2000.0
var _duration := 1.5

func _ready() -> void:
	# Screen flash
	var flash := ColorRect.new()
	flash.name = "Flash"
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = ring_base_color
	flash.color.a = 0.8
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	canvas.add_child(flash)

	# Camera shake
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(1.0)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

	# Fade out flash
	var flash_node := get_node_or_null("CanvasLayer/Flash")
	if flash_node:
		var fade_t := clampf(_time / _duration, 0.0, 1.0)
		flash_node.color.a = 0.8 * (1.0 - fade_t)

	if _time >= _duration:
		queue_free()

func _draw() -> void:
	var t := clampf(_time / _duration, 0.0, 1.0)
	var radius := _max_radius * ease(t, 0.3)
	var alpha := 1.0 - t

	# Expanding ring
	var ring_color := ring_base_color
	ring_color.a = alpha * 0.8
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, ring_color, 30.0 * (1.0 - t) + 5.0)

	# Inner glow
	var core_color := core_base_color
	core_color.a = alpha * 0.6
	for i in range(5):
		var r := radius * (0.2 + i * 0.15) * (1.0 - t * 0.5)
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, core_color, 20.0 * (1.0 - t))
