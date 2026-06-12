class_name ChamferStyleBox
extends StyleBox
## Sharp-cornered rect with one 45-degree chamfered (cut) corner - the NIKKE
## signature card shape. Optionally draws a border and an accent bar on the
## left edge. Created via UITheme.create_chamfer_card().

enum ChamferCorner { TOP_LEFT, TOP_RIGHT, BOTTOM_RIGHT, BOTTOM_LEFT }

@export var bg_color := Color(0.11, 0.129, 0.165, 1.0)
@export var border_color := Color(0, 0, 0, 0)
@export var border_width := 0
@export var chamfer := 12.0
@export var chamfer_corner := ChamferCorner.BOTTOM_RIGHT
@export var accent_color := Color(0, 0, 0, 0)
@export var accent_width := 0.0


func _build_polygon(rect: Rect2, inset: float) -> PackedVector2Array:
	var r := rect.grow(-inset)
	var c := maxf(chamfer - inset, 0.0)
	var tl := r.position
	var tr := Vector2(r.end.x, r.position.y)
	var br := r.end
	var bl := Vector2(r.position.x, r.end.y)
	var pts := PackedVector2Array()
	match chamfer_corner:
		ChamferCorner.TOP_LEFT:
			pts.append(tl + Vector2(c, 0))
			pts.append(tr)
			pts.append(br)
			pts.append(bl)
			pts.append(tl + Vector2(0, c))
		ChamferCorner.TOP_RIGHT:
			pts.append(tl)
			pts.append(tr - Vector2(c, 0))
			pts.append(tr + Vector2(0, c))
			pts.append(br)
			pts.append(bl)
		ChamferCorner.BOTTOM_RIGHT:
			pts.append(tl)
			pts.append(tr)
			pts.append(br - Vector2(0, c))
			pts.append(br - Vector2(c, 0))
			pts.append(bl)
		ChamferCorner.BOTTOM_LEFT:
			pts.append(tl)
			pts.append(tr)
			pts.append(br)
			pts.append(bl + Vector2(c, 0))
			pts.append(bl - Vector2(0, c))
	return pts


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if border_width > 0 and border_color.a > 0.0:
		RenderingServer.canvas_item_add_polygon(
			to_canvas_item, _build_polygon(rect, 0.0), PackedColorArray([border_color])
		)
		RenderingServer.canvas_item_add_polygon(
			to_canvas_item, _build_polygon(rect, float(border_width)), PackedColorArray([bg_color])
		)
	else:
		RenderingServer.canvas_item_add_polygon(
			to_canvas_item, _build_polygon(rect, 0.0), PackedColorArray([bg_color])
		)
	if accent_width > 0.0 and accent_color.a > 0.0:
		RenderingServer.canvas_item_add_rect(
			to_canvas_item,
			Rect2(rect.position, Vector2(accent_width, rect.size.y)),
			accent_color
		)
