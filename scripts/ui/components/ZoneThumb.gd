class_name ZoneThumb
extends Control
## Skewed parallelogram zone thumbnail for the mission-select carousel:
## cover-fit preview art, dark name band, yellow border when selected.
## Geometry matches the NIKKE card skew (~6 degrees).

signal pressed

const UI := preload("res://scripts/ui/UITheme.gd")
const SKEW_RATIO := 0.105  # tan(6 deg), same lean as NikkeCardButton
const BAND_HEIGHT := 27.0

var map_name := ""
var map_subtitle := ""
var texture: Texture2D = null

var selected := false:
	set(value):
		selected = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit()
		accept_event()


func _quad_x(edge_left: bool, f: float) -> float:
	# f: 0 = top, 1 = bottom. Quad: (s,0) (W,0) (W-s,H) (0,H)
	var s := SKEW_RATIO * size.y
	if edge_left:
		return s * (1.0 - f)
	return size.x - s * f


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return
	var s := SKEW_RATIO * h
	var quad := PackedVector2Array([
		Vector2(s, 0), Vector2(w, 0), Vector2(w - s, h), Vector2(0, h)
	])

	# Preview art, cover-fit, dimmed unless selected
	if texture:
		var tw := float(texture.get_width())
		var th := float(texture.get_height())
		var cover_scale := maxf(w / tw, h / th)
		var uv_w := (w / cover_scale) / tw
		var uv_h := (h / cover_scale) / th
		var u0 := (1.0 - uv_w) * 0.5
		var v0 := (1.0 - uv_h) * 0.5
		var uvs := PackedVector2Array()
		for p in quad:
			uvs.append(Vector2(u0 + (p.x / w) * uv_w, v0 + (p.y / h) * uv_h))
		var tint := Color(0.95, 0.95, 0.97, 1.0) if selected else Color(0.62, 0.62, 0.66, 1.0)
		draw_colored_polygon(quad, tint, uvs, texture)
	else:
		draw_colored_polygon(quad, Color(0.063, 0.078, 0.102, 1.0))

	# Name band along the bottom, following the slant
	var f0 := (h - BAND_HEIGHT) / h
	var band := PackedVector2Array([
		Vector2(_quad_x(true, f0), f0 * h), Vector2(_quad_x(false, f0), f0 * h),
		Vector2(_quad_x(false, 1.0), h), Vector2(_quad_x(true, 1.0), h)
	])
	draw_polygon(band, PackedColorArray([Color(0.04, 0.05, 0.07, 0.78)]))

	var font: Font = UI.FONT_BOLD
	var text_x := _quad_x(true, 1.0) + 14.0
	var text_y := h - BAND_HEIGHT * 0.5 + 5.0
	var max_w := _quad_x(false, f0) - text_x - 10.0
	var name_text := map_name.to_upper()
	draw_string(font, Vector2(text_x, text_y), name_text,
		HORIZONTAL_ALIGNMENT_LEFT, max_w, 13, Color(1, 1, 1, 0.95))
	var name_w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	if name_w + 40.0 < max_w:
		draw_string(font, Vector2(text_x + name_w + 9.0, text_y), map_subtitle.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, max_w - name_w - 9.0, 11, UI.ACCENT_CYAN)

	# Border: yellow when selected, faint hairline otherwise
	var outline := quad.duplicate()
	outline.append(quad[0])
	if selected:
		draw_polyline(outline, UI.ACCENT_SECONDARY, 3.0, true)
	else:
		draw_polyline(outline, Color(1, 1, 1, 0.25), 1.0, true)
