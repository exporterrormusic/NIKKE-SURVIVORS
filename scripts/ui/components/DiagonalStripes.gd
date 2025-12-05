extends Control
## Animated diagonal warning stripes effect - red/danger themed

var _time: float = 0.0
var _stripe_width: float = 400.0  # Very thick stripes (5x of 80)
var _scroll_speed: float = 60.0  # pixels per second


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var rect_size := size
	var w := rect_size.x
	var h := rect_size.y
	
	if w <= 0 or h <= 0:
		return
	
	# Colors for warning stripes - red/black danger theme
	var color_a := Color(1.0, 0.2, 0.15, 0.18)  # Red
	var color_b := Color(0.0, 0.0, 0.0, 0.12)   # Dark/transparent
	
	# Calculate stripe offset for animation (scrolling right)
	var offset := fmod(_time * _scroll_speed, _stripe_width * 2.0)
	
	# Angle offset - use height * 0.7 for a nice ~35 degree tilt
	var angle_offset := h * 0.7
	
	# Draw diagonal stripes - tilted
	var stripe_count := int((w + angle_offset * 2) / _stripe_width) + 6
	
	for i in range(stripe_count):
		var x := (i * _stripe_width) - angle_offset - _stripe_width * 3 + offset
		var color := color_a if i % 2 == 0 else color_b
		
		# Draw a diagonal stripe as a polygon (parallelogram)
		var points := PackedVector2Array([
			Vector2(x, h),
			Vector2(x + _stripe_width, h),
			Vector2(x + _stripe_width + angle_offset, 0),
			Vector2(x + angle_offset, 0)
		])
		
		draw_colored_polygon(points, color)
