extends Node2D
class_name SparkleEffect

var duration: float = 4.0

func _ready() -> void:
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	duration -= delta
	if duration <= 0:
		queue_free()
		return
	# Only redraw every other frame for performance
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()

func _draw() -> void:
	var alpha = clampf(duration / 4.0, 0.0, 1.0)
	# Reduce sparkle count from 16 to 8 for performance
	for i in 8:
		var angle = i * PI / 4 + Time.get_ticks_msec() * 0.008
		var pos = Vector2(cos(angle), sin(angle)) * 40
		var sparkle_color = Color(1.0, 1.0, 0.0, alpha * 1.2)
		var size = 6 + sin(Time.get_ticks_msec() * 0.03 + i * 0.5) * 4
		draw_circle(pos, size, sparkle_color)