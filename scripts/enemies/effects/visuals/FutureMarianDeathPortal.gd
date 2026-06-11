# Extracted from scripts/enemies/FutureMarian.gd (was runtime-compiled embedded source).
extends Node2D

var marian_ref: Node2D = null
var _time: float = 0.0
var _duration: float = 2.0
var _dissolve_start: float = 0.3  # When Marian starts dissolving
var _portal_close_start: float = 1.2  # When portal starts closing
var _original_scale: Vector2 = Vector2.ONE  # Store original scale

func _ready() -> void:
	z_index = 200
	# Capture original scale on ready
	if marian_ref and is_instance_valid(marian_ref):
		_original_scale = marian_ref.scale

func _process(delta: float) -> void:
	_time += delta
	
	# Dissolve Marian (fade out + shrink)
	if marian_ref and is_instance_valid(marian_ref):
		if _time > _dissolve_start:
			var dissolve_progress := clampf((_time - _dissolve_start) / 0.8, 0.0, 1.0)
			marian_ref.modulate.a = 1.0 - dissolve_progress
			# Shrink relative to original scale (1.0 down to 0.5)
			marian_ref.scale = _original_scale * (1.0 - dissolve_progress * 0.5)
			
			# Move Marian toward portal center
			marian_ref.global_position = lerp(marian_ref.global_position, global_position, delta * 3.0)
		
		# Queue free Marian when fully dissolved
		if _time > _dissolve_start + 0.9:
			marian_ref.queue_free()
			marian_ref = null
	
	if _time >= _duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := _time / _duration
	
	# Portal opens quickly, stays open, then closes
	var open_phase := clampf(progress * 4.0, 0.0, 1.0)  # Fast open
	var close_start := clampf((_time - _portal_close_start) / (_duration - _portal_close_start), 0.0, 1.0)
	
	var portal_scale := open_phase * (1.0 - close_start)
	var alpha := 1.0 - close_start * 0.8
	
	var portal_w := 100.0 * portal_scale
	var portal_h := 175.0 * portal_scale
	
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
		var px: float = cos(angle) * r
		var py: float = sin(angle) * r * (portal_h / max(portal_w, 0.001))
		draw_circle(Vector2(px, py), 3.0, Color(1.0, 0.8, 1.0, alpha * 0.7))

func _draw_wavy_oval(w: float, h: float, color: Color, wave: float) -> void:
	if w <= 0 or h <= 0: return
	var points := PackedVector2Array()
	for i in range(32):
		var angle := TAU * float(i) / 32.0
		var wave_mod := 1.0 + sin(angle * 4.0 + wave * 0.5) * 0.1
		points.append(Vector2(cos(angle) * w * wave_mod, sin(angle) * h * wave_mod))
	draw_colored_polygon(points, color)

func _draw_wavy_oval_ring(w: float, h: float, color: Color, wave: float, thickness: float) -> void:
	if w <= 0 or h <= 0: return
	var prev := Vector2.ZERO
	for i in range(33):
		var angle := TAU * float(i) / 32.0
		var wave_mod := 1.0 + sin(angle * 4.0 + wave * 0.5) * 0.1
		var pt := Vector2(cos(angle) * w * wave_mod, sin(angle) * h * wave_mod)
		if i > 0:
			draw_line(prev, pt, color, thickness)
		prev = pt
