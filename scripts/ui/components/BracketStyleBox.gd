class_name BracketStyleBox
extends StyleBox
## NIKKE target-box panel (approved HUD mockup docs/mockups/hud_v2.html):
## translucent dark fill with two corner brackets - top-left and bottom-right.
## Used across the in-game HUD (player cluster, minimap, cores, music, boss bar).

@export var bg_color := Color(0.039, 0.051, 0.071, 0.5)
@export var bracket_color := Color(1, 1, 1, 0.75)
@export var bracket_size := 24.0
@export var bracket_width := 3.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if bg_color.a > 0.0:
		RenderingServer.canvas_item_add_rect(to_canvas_item, rect, bg_color)
	if bracket_color.a <= 0.0 or bracket_width <= 0.0:
		return
	var s := minf(bracket_size, minf(rect.size.x, rect.size.y) * 0.5)
	var w := bracket_width
	# Top-left bracket
	RenderingServer.canvas_item_add_rect(to_canvas_item,
		Rect2(rect.position, Vector2(s, w)), bracket_color)
	RenderingServer.canvas_item_add_rect(to_canvas_item,
		Rect2(rect.position, Vector2(w, s)), bracket_color)
	# Bottom-right bracket
	RenderingServer.canvas_item_add_rect(to_canvas_item,
		Rect2(rect.end - Vector2(s, w), Vector2(s, w)), bracket_color)
	RenderingServer.canvas_item_add_rect(to_canvas_item,
		Rect2(rect.end - Vector2(w, s), Vector2(w, s)), bracket_color)
