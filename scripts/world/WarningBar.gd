extends Control
class_name WarningBar

## Thin semi-transparent red warning bar with hexagon sci-fi pattern
## Features cyberpunk scanline animation for opening/closing

var _pulse_timer := 0.0
var _pulse_duration := 2.0
var _time := 0.0
var _warning_text := "WARNING"

# Animation states
var _anim_state := 0  # 0=hidden, 1=animating in, 2=showing, 3=animating out
var _anim_progress := 0.0
const ANIM_DURATION := 0.4

const BAR_COLOR := Color(0.85, 0.1, 0.08, 0.75)
const BAR_HEIGHT := 200.0
const HEX_SIZE := 16.0
const PULSE_SPEED := 8.0
const SCANLINE_COUNT := 12

func set_warning_text(text: String) -> void:
	_warning_text = text

func _ready() -> void:
	# Span full viewport width, positioned at middle third
	_update_size()
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _update_size() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	position = Vector2(0, (viewport_size.y - BAR_HEIGHT) / 2.0)
	size = Vector2(viewport_size.x, BAR_HEIGHT)

func _draw() -> void:
	if _anim_state == 0:
		return
	
	_update_size()
	
	# Calculate animation alpha and scanline effect
	var anim_alpha := 1.0
	var scanline_intensity := 0.0
	
	if _anim_state == 1:  # Animating in
		anim_alpha = _anim_progress
		scanline_intensity = 1.0 - _anim_progress
	elif _anim_state == 3:  # Animating out
		anim_alpha = 1.0 - _anim_progress
		scanline_intensity = _anim_progress
	
	# Calculate pulse (faster, more visible)
	var pulse := (sin(_time * PULSE_SPEED) + 1.0) * 0.5
	var alpha := (0.5 + pulse * 0.3) * anim_alpha
	
	# Draw scanline reveal/hide effect
	if scanline_intensity > 0:
		_draw_scanline_effect(scanline_intensity, anim_alpha)
	
	# Draw main bar background (with clip based on animation)
	var bar_color := Color(BAR_COLOR.r, BAR_COLOR.g, BAR_COLOR.b, alpha)
	
	if _anim_state == 1 or _anim_state == 3:
		# Draw in strips that reveal/hide
		_draw_animated_bar(bar_color, anim_alpha, scanline_intensity)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), bar_color)
	
	# Draw hexagon pattern overlay (only when mostly visible)
	if anim_alpha > 0.3:
		_draw_hex_pattern(alpha * 0.5 * anim_alpha)
	
	# Draw glowing edges
	var edge_alpha := alpha * 0.9
	var edge_color := Color(1.0, 0.2, 0.15, edge_alpha)
	draw_rect(Rect2(0, 0, size.x, 4), edge_color)
	draw_rect(Rect2(0, size.y - 4, size.x, 4), edge_color)
	
	# Gradient fade at edges (left and right)
	var fade_width := 60.0
	for i in range(int(fade_width)):
		var t := float(i) / fade_width
		var fade_color := Color(0, 0, 0, (1.0 - t) * alpha * 0.5)
		draw_line(Vector2(i, 0), Vector2(i, size.y), fade_color, 1.0)
		draw_line(Vector2(size.x - i, 0), Vector2(size.x - i, size.y), fade_color, 1.0)
	
	# Draw warning text in center (only when mostly visible)
	if anim_alpha > 0.5:
		_draw_warning_text(pulse, alpha)

func _draw_scanline_effect(intensity: float, alpha: float) -> void:
	# Cyberpunk scanline effect during transition
	var scanline_color := Color(1.0, 0.3, 0.2, intensity * alpha * 0.8)
	var glow_color := Color(1.0, 0.1, 0.05, intensity * alpha * 0.4)
	
	for i in range(SCANLINE_COUNT):
		var y_base := (float(i) / SCANLINE_COUNT) * size.y
		var wave := sin(_time * 15.0 + float(i) * 0.8) * 3.0
		var y := y_base + wave
		
		# Flickering scanlines
		var flicker := (sin(_time * 30.0 + float(i) * 2.3) + 1.0) * 0.5
		if flicker > 0.3:
			# Glow behind
			draw_line(Vector2(0, y), Vector2(size.x, y), glow_color, 6.0)
			# Sharp scanline
			draw_line(Vector2(0, y), Vector2(size.x, y), scanline_color, 2.0)
	
	# Horizontal glitch bars
	var glitch_count := int(intensity * 5)
	for i in range(glitch_count):
		var glitch_y := fmod(_time * 200.0 + float(i) * 50.0, size.y)
		var glitch_width := randf_range(50.0, 150.0) * intensity
		var glitch_x := fmod(_time * 100.0 * (float(i) + 1.0), size.x)
		var glitch_color := Color(1.0, 0.2, 0.1, intensity * 0.6)
		draw_rect(Rect2(glitch_x, glitch_y, glitch_width, 3.0), glitch_color)

func _draw_animated_bar(bar_color: Color, anim_alpha: float, scanline_intensity: float) -> void:
	# Draw bar in horizontal strips that slide in from edges
	var strip_height := size.y / SCANLINE_COUNT
	
	# Determine if we're animating in or out
	var is_animating_out := (_anim_state == 3)
	
	for i in range(SCANLINE_COUNT):
		var y := float(i) * strip_height
		# Use anim_alpha for strip reveal/hide animation
		var strip_progress := clampf(anim_alpha * 1.5 - float(i) * 0.05, 0.0, 1.0)
		
		if strip_progress > 0:
			# Strips slide in from alternating sides
			# On animate out, reverse the direction
			var from_left := (i % 2 == 0)
			if is_animating_out:
				from_left = not from_left  # Reverse direction on exit
			
			var strip_width := size.x * strip_progress
			var x := 0.0 if from_left else (size.x - strip_width)
			
			# Add slight offset based on animation
			var offset := sin(_time * 10.0 + float(i)) * 5.0 * scanline_intensity
			
			var strip_color := bar_color
			# Edge strips glow more
			if i == 0 or i == SCANLINE_COUNT - 1:
				strip_color = bar_color.lightened(0.2)
			
			draw_rect(Rect2(x + offset, y, strip_width, strip_height + 1), strip_color)

func _draw_hex_pattern(alpha: float) -> void:
	var hex_color := Color(1.0, 0.3, 0.2, alpha)
	var hex_w := HEX_SIZE * 1.5
	var hex_h := HEX_SIZE * 0.866  # sqrt(3)/2
	
	# Calculate rows to stay within bar bounds with padding
	var padding := 20.0
	var usable_height := size.y - padding * 2
	var rows := int(usable_height / (hex_h * 2))
	var cols := int(size.x / hex_w) + 2
	var start_y := padding + hex_h  # Start after top padding
	
	for row in range(rows):
		for col in range(cols):
			var offset_x := (hex_w * 0.75) if (row % 2 == 1) else 0.0
			var cx := col * hex_w * 1.5 + offset_x - fmod(_time * 20.0, hex_w * 1.5)
			var cy := start_y + row * hex_h * 2
			
			# Skip if outside vertical bounds
			if cy < padding or cy > size.y - padding:
				continue
			
			if cx > -HEX_SIZE and cx < size.x + HEX_SIZE:
				_draw_hexagon(Vector2(cx, cy), HEX_SIZE * 0.4, hex_color)

func _draw_hexagon(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := PI / 6.0 + i * PI / 3.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	
	# Draw outline only for subtle effect
	for i in range(6):
		var next := (i + 1) % 6
		draw_line(points[i], points[next], color, 1.5)

func _draw_warning_text(pulse: float, alpha: float) -> void:
	var text := "⚠ " + _warning_text + " ⚠"
	var font := ThemeDB.fallback_font
	var font_size := 90
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2.0, (size.y + text_size.y) / 2.0 - 20)
	
	# Glow behind text
	var glow_color := Color(0.0, 0.0, 0.0, alpha * 0.7)
	for offset in [Vector2(-3, -3), Vector2(3, -3), Vector2(-3, 3), Vector2(3, 3), Vector2(0, 4)]:
		draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glow_color)
	
	# Main text with pulse
	var text_brightness := 0.85 + pulse * 0.15
	var text_color := Color(text_brightness, text_brightness, text_brightness, min(1.0, alpha + 0.4))
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

func _process(delta: float) -> void:
	if _anim_state == 0:
		return
	
	_time += delta
	
	# Handle animation states
	if _anim_state == 1:  # Animating in
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_progress = 1.0
			_anim_state = 2  # Now showing
		queue_redraw()
	elif _anim_state == 2:  # Showing (pulsing)
		_pulse_timer -= delta
		queue_redraw()
		if _pulse_timer <= ANIM_DURATION:
			# Start animating out
			_anim_state = 3
			_anim_progress = 0.0
	elif _anim_state == 3:  # Animating out
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_state = 0
			visible = false
		queue_redraw()

func start_pulse(duration: float) -> void:
	_pulse_duration = duration
	_pulse_timer = duration
	_time = 0.0
	_anim_state = 1  # Start animating in
	_anim_progress = 0.0
	visible = true
	queue_redraw()
