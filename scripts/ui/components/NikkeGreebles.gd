class_name NikkeGreebles
extends Control
## Decorative NIKKE-style margin greebles: barcode, fake serial number,
## plus-sign registration marks, and dot grid. Low-contrast, purely
## decorative - drop into menu corners/margins and pick the modes.
## Deterministic (seeded) so layouts don't shimmer between opens.

@export var show_barcode := true
@export var show_serial := true
@export var serial_text := "SOV-2026 // ARK SYS v2.4"
@export var show_plus_marks := false
@export var show_dot_grid := false
@export var tint := Color(1.0, 1.0, 1.0, 0.3)
@export var rng_seed := 7
@export var barcode_height := 16.0
@export var serial_font_size := 11
@export var dot_spacing := 24.0
@export var plus_size := 5.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	# Barcode and serial share one row spanning the full control width:
	# [|||||||||||||||||]  SOV-2026 // ...
	var font: Font = UITheme.FONT_MEDIUM
	var text_w := 0.0
	if show_serial:
		text_w = font.get_string_size(
			serial_text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, serial_font_size
		).x
	if show_barcode:
		var bar_span := size.x
		if show_serial:
			bar_span = maxf(size.x - text_w - 12.0, 24.0)
		_draw_barcode(bar_span)
	if show_serial:
		_draw_serial(font, size.x - text_w)
	if show_plus_marks:
		_draw_plus_marks()
	if show_dot_grid:
		_draw_dot_grid()


func _draw_barcode(span: float) -> void:
	# Simple LCG so bar pattern is stable per seed
	var state := rng_seed * 2654435761
	var x := 0.0
	while x < span:
		state = int(state * 1103515245 + 12345) & 0x7FFFFFFF
		var bar_w := 1.0 + float(state % 4)
		state = int(state * 1103515245 + 12345) & 0x7FFFFFFF
		var gap := 2.0 + float(state % 4)
		draw_rect(Rect2(x, 0, bar_w, barcode_height), tint)
		x += bar_w + gap


func _draw_serial(font: Font, x: float) -> void:
	# Baseline vertically centered against the barcode
	var baseline := barcode_height * 0.5 + 4.0
	draw_string(font, Vector2(x, baseline), serial_text.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, serial_font_size, tint)


func _draw_plus_marks() -> void:
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		draw_line(corner + Vector2(-plus_size, 0), corner + Vector2(plus_size, 0), tint, 1.0)
		draw_line(corner + Vector2(0, -plus_size), corner + Vector2(0, plus_size), tint, 1.0)


func _draw_dot_grid() -> void:
	var dot_tint := Color(tint.r, tint.g, tint.b, tint.a * 0.6)
	var y := dot_spacing * 0.5
	while y < size.y:
		var x := dot_spacing * 0.5
		while x < size.x:
			draw_rect(Rect2(x, y, 1.5, 1.5), dot_tint)
			x += dot_spacing
		y += dot_spacing
