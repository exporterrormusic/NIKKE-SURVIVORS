extends Control

## Edge layer for the talent tree lanes (approved mockup
## docs/mockups/talent_tree_v3.html variant C3a). Edges are computed from the
## actual talent button rects so they always land on node borders:
## - Same-row dependency (root -> side mod): elbow split - stem out of the
##   root's right edge, vertical rail at the midpoint, stub into the mod's
##   left edge. No arrowheads (user choice).
## - Cross-row dependency (special -> burst, burst -> capstone): vertical line
##   down the left column WITH an arrowhead landing on the target's top edge.
## Edges light cyan when the prerequisite talent is owned.

const LINE_W := 4.0
const ARROW_HALF := 9.0
const ARROW_LEN := 12.0
const COLOR_DIM := Color(0.5, 0.55, 0.61, 0.45)
const COLOR_LIT := Color(0.208, 0.773, 0.949, 0.9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var tree = get_meta("tree_ref", null)
	var char_id: int = get_meta("char_id", -1)
	if tree == null or char_id < 0:
		return

	# Map talent id -> rect / data from the live buttons
	var rects := {}
	var talents := {}
	for btn in tree._talent_buttons:
		if not is_instance_valid(btn):
			continue
		var t: Dictionary = btn.get_meta("talent")
		rects[t["id"]] = Rect2(btn.position, btn.size)
		talents[t["id"]] = t

	var unlocked: Dictionary = tree.get_unlocked_for_char(char_id)

	for id in talents:
		var t: Dictionary = talents[id]
		var reqs: Array = t.get("requires", [])
		if reqs.is_empty():
			continue
		var src_id: String = reqs[0]
		if not rects.has(src_id):
			continue
		var src: Rect2 = rects[src_id]
		var dst: Rect2 = rects[id]
		var color := COLOR_LIT if unlocked.get(src_id, 0) > 0 else COLOR_DIM

		if int(t["row"]) == int(talents[src_id]["row"]):
			_draw_elbow_split(src, dst, color)
		else:
			_draw_vertical_gate(src, dst, color)


## Root right edge -> midpoint rail -> mod left edge. No arrowheads.
func _draw_elbow_split(src: Rect2, dst: Rect2, color: Color) -> void:
	var rail_x := (src.end.x + dst.position.x) * 0.5
	var sy := src.position.y + src.size.y * 0.5
	var dy := dst.position.y + dst.size.y * 0.5

	# Stem out of the root
	draw_rect(Rect2(src.end.x, sy - LINE_W * 0.5, rail_x - src.end.x + LINE_W * 0.5, LINE_W), color)
	# Vertical rail
	var rail_top := minf(sy, dy) - LINE_W * 0.5
	var rail_bottom := maxf(sy, dy) + LINE_W * 0.5
	draw_rect(Rect2(rail_x - LINE_W * 0.5, rail_top, LINE_W, rail_bottom - rail_top), color)
	# Stub into the mod
	draw_rect(Rect2(rail_x - LINE_W * 0.5, dy - LINE_W * 0.5, dst.position.x - rail_x + LINE_W * 0.5, LINE_W), color)


## Vertical line down the left column, arrowhead tip ON the target's top edge.
func _draw_vertical_gate(src: Rect2, dst: Rect2, color: Color) -> void:
	var x := src.position.x + src.size.x * 0.5
	var top := src.end.y
	var tip := dst.position.y
	draw_rect(Rect2(x - LINE_W * 0.5, top, LINE_W, tip - ARROW_LEN - top), color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - ARROW_HALF, tip - ARROW_LEN),
		Vector2(x + ARROW_HALF, tip - ARROW_LEN),
		Vector2(x, tip),
	]), color)
