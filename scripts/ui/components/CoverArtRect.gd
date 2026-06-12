class_name CoverArtRect
extends Control
## Cover-fit art with a controllable vertical focus point — unlike
## TextureRect's KEEP_ASPECT_COVERED (which always center-crops), this keeps
## the chosen fraction of the image (e.g. the face line of a tall burst art)
## inside the visible crop. Optional NIKKE bottom-right chamfer.

@export var texture: Texture2D = null:
	set(value):
		texture = value
		queue_redraw()
## Vertical point of the image (0 = top, 1 = bottom) to keep centered in view.
## Burst art faces live around 0.15-0.25.
@export_range(0.0, 1.0) var focus_y := 0.2:
	set(value):
		focus_y = value
		queue_redraw()
## Horizontal point of the image (0 = left, 1 = right) to keep centered —
## for subjects that stand off-center in their art.
@export_range(0.0, 1.0) var focus_x := 0.5:
	set(value):
		focus_x = value
		queue_redraw()
## Extra zoom past cover-fit. >1 tightens the crop around focus_y — needed to
## center faces that sit near the top of the image, where panning alone
## clamps against the image edge.
@export_range(1.0, 3.0) var zoom := 1.0:
	set(value):
		zoom = value
		queue_redraw()
@export var chamfer := 24.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return

	var quad := PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0),
		Vector2(w, h - chamfer), Vector2(w - chamfer, h),
		Vector2(0, h),
	]) if chamfer > 0.0 else PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)
	])

	if texture == null:
		draw_colored_polygon(quad, Color(0.102, 0.129, 0.169, 1.0))
		return

	var tw := float(texture.get_width())
	var th := float(texture.get_height())
	var cover_scale := maxf(w / tw, h / th) * zoom
	var uv_w := (w / cover_scale) / tw
	var uv_h := (h / cover_scale) / th
	# Keep the focus point centered in the crop, clamped to the image bounds
	var u0 := clampf(focus_x - uv_w * 0.5, 0.0, 1.0 - uv_w)
	var v0 := clampf(focus_y - uv_h * 0.5, 0.0, 1.0 - uv_h)
	var uvs := PackedVector2Array()
	for p in quad:
		uvs.append(Vector2(u0 + (p.x / w) * uv_w, v0 + (p.y / h) * uv_h))
	draw_colored_polygon(quad, Color.WHITE, uvs, texture)
