extends Control
## Generates a procedural starfield background.

const STAR_COUNT := 200
const COLORS := [Color(1, 1, 1), Color(0.8, 0.9, 1), Color(1, 1, 0.8), Color(0.8, 0.8, 1)]

var _stars: Array[Dictionary] = []

func _ready() -> void:
	for i in range(STAR_COUNT):
		_stars.append({
			"pos": Vector2(randf(), randf()), # UV coordinates 0-1
			"size": randf_range(1.0, 3.0),
			"color": COLORS[randi() % COLORS.size()] * randf_range(0.5, 1.0),
			"blink_speed": randf_range(0.5, 3.0),
			"time_offset": randf() * 100.0
		})

func _draw() -> void:
	var rect_size = get_rect().size
	var time = Time.get_ticks_msec() / 1000.0
	
	for star in _stars:
		var pos = star.pos * rect_size
		var alpha = 0.7 + 0.3 * sin(time * star.blink_speed + star.time_offset)
		var col = star.color
		col.a = alpha
		draw_rect(Rect2(pos, Vector2(star.size, star.size)), col)

func _process(_delta: float) -> void:
	queue_redraw()
