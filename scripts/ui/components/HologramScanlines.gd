extends Control
## Hologram scanline overlay effect with animated sweep - red/danger themed

const UI := preload("res://scripts/ui/UITheme.gd")

var _time: float = 0.0
var _scanline_spacing: float = 3.0
var _sweep_speed: float = 80.0  # pixels per second
var _sweep_height: float = 120.0  # Big visible sweep


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
	
	# Draw horizontal scanlines (subtle red tint)
	var scanline_color := UI.VFX_SCANLINE
	var y := 0.0
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), scanline_color, 1.0)
		y += _scanline_spacing
	
	# Animated bright sweep (top to bottom)
	# Start fully above the visible area so it enters smoothly
	var total_travel := h + _sweep_height * 2  # Full sweep height above and below
	var sweep_y := fmod(_time * _sweep_speed, total_travel) - _sweep_height
	
	# Draw gradient sweep (vertical, top to bottom)
	var sweep_segments := 30
	for i in range(sweep_segments):
		var seg_start := sweep_y + (float(i) / sweep_segments) * _sweep_height
		var seg_size := _sweep_height / sweep_segments
		
		# Skip if completely out of bounds
		if seg_start + seg_size < 0 or seg_start > h:
			continue
		
		# Fade in and out across the sweep (sine curve)
		var t := float(i) / float(sweep_segments - 1)
		var alpha := sin(t * PI) * 0.3  # Peak in middle, stronger visibility
		
		var sweep_color := Color(UI.VFX_SCANLINE_SWEEP.r, UI.VFX_SCANLINE_SWEEP.g, UI.VFX_SCANLINE_SWEEP.b, alpha)
		draw_rect(Rect2(0, seg_start, w, seg_size + 1), sweep_color)
	
	# Add subtle edge glow lines (red themed)
	var edge_color := UI.VFX_SCANLINE_EDGE
	draw_line(Vector2(0, 0), Vector2(w, 0), edge_color, 1.0)
	draw_line(Vector2(0, h - 1), Vector2(w, h - 1), edge_color, 1.0)
