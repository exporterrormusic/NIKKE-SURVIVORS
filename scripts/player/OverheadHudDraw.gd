@tool
extends Node

## Static drawing utilities for PlayerOverheadHud.
## All methods take a CanvasItem to draw on + position/color parameters.

static func draw_bar(canvas: CanvasItem, rect: Rect2, cur: float, max_val: float, bg: Color, fill: Color, border: Color, bw: float) -> void:
	var cm := maxf(0.0001, max_val)
	canvas.draw_rect(rect, bg, true)
	var r := clampf(cur / cm, 0.0, 1.0)
	if r > 0.0: canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x * r, rect.size.y)), fill, true)
	canvas.draw_rect(rect, border, false, bw)

static func draw_bar_text(canvas: CanvasItem, text: String, cp: Vector2, fs: int) -> void:
	var font := ThemeDB.fallback_font
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var dp := Vector2(cp.x - ts.x * 0.5, cp.y + ts.y * 0.35)
	var sh := Color(0, 0, 0, 0.8)
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]: canvas.draw_string(font, dp + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
	canvas.draw_string(font, dp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

static func draw_rounded_rect(canvas: CanvasItem, rect: Rect2, rad: float, color: Color) -> void:
	var pts := get_rounded_rect_points(rect, rad)
	if pts.size() >= 3: canvas.draw_colored_polygon(pts, color)

static func draw_rounded_rect_outline(canvas: CanvasItem, rect: Rect2, rad: float, color: Color, w: float) -> void:
	var pts := get_rounded_rect_points(rect, rad)
	if pts.size() >= 3: pts.append(pts[0]); canvas.draw_polyline(pts, color, w)

static func get_rounded_rect_points(rect: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array(); var segs := 6
	var l := rect.position.x; var r := rect.position.x + rect.size.x
	var t := rect.position.y; var b := rect.position.y + rect.size.y
	var r2 := minf(rad, minf(rect.size.x, rect.size.y) * 0.5)
	for i in range(segs + 1): var a := PI + (PI / 2.0) * float(i) / float(segs); pts.append(Vector2(l + r2 + cos(a) * r2, t + r2 + sin(a) * r2))
	for i in range(segs + 1): var a := -PI / 2.0 + (PI / 2.0) * float(i) / float(segs); pts.append(Vector2(r - r2 + cos(a) * r2, t + r2 + sin(a) * r2))
	for i in range(segs + 1): var a := 0.0 + (PI / 2.0) * float(i) / float(segs); pts.append(Vector2(r - r2 + cos(a) * r2, b - r2 + sin(a) * r2))
	for i in range(segs + 1): var a := PI / 2.0 + (PI / 2.0) * float(i) / float(segs); pts.append(Vector2(l + r2 + cos(a) * r2, b - r2 + sin(a) * r2))
	return pts

static func draw_pie_slice_smooth(canvas: CanvasItem, center: Vector2, clip: Rect2, sa: float, ea: float, color: Color, cr: float) -> void:
	var pts := PackedVector2Array(); pts.append(center)
	var ar := absf(ea - sa); var segs := maxi(32, int(64.0 * ar / TAU)); var rad := clip.size.length(); var step := (ea - sa) / float(segs)
	for i in range(segs + 1): var a := sa + step * float(i); pts.append(center + Vector2(cos(a), sin(a)) * rad)
	var clipped := Geometry2D.intersect_polygons(pts, get_rounded_rect_points(clip, cr))
	for p in clipped: if p.size() >= 3: canvas.draw_colored_polygon(p, color)

# ─── Icon drawing helpers ─────────────────────────────────────────────

static func draw_lock_icon(canvas: CanvasItem, center: Vector2) -> void:
	var lc := Color(0.95, 0.95, 0.95, 0.95); var sc := Color(0.8, 0.8, 0.8, 0.95)
	canvas.draw_rect(Rect2(center + Vector2(-6, -1), Vector2(12, 10)), lc, true)
	canvas.draw_circle(center + Vector2(0, 2), 2.0, Color(0.2, 0.1, 0.1, 1.0))
	canvas.draw_line(center + Vector2(0, 3), center + Vector2(0, 6), Color(0.2, 0.1, 0.1, 1.0), 2.0)
	canvas.draw_arc(center, 6.0, PI, TAU, 12, sc, 2.5)

static func draw_sword_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	canvas.draw_line(center + Vector2(0, -12), center + Vector2(0, 3.6), color, 3.0)
	canvas.draw_line(center + Vector2(-4.5, 1.2), center + Vector2(4.5, 1.2), color, 3.0)
	canvas.draw_line(center + Vector2(0, 3.6), center + Vector2(0, 7.2), color, 2.4)

static func draw_clock_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	var g := Color(1.0, 0.85, 0.3, color.a); var r := 10.0
	var pts := PackedVector2Array()
	for i in range(24): pts.append(center + Vector2(cos(TAU*i/24.0-PI/2), sin(TAU*i/24.0-PI/2)) * r)
	canvas.draw_polyline(pts, g, 2.0); canvas.draw_line(pts[pts.size()-1], pts[0], g, 2.0)
	canvas.draw_circle(center, r-2, Color(color.r*0.7, color.g*0.7, color.b*0.7, color.a))
	canvas.draw_circle(center, r-3, color)
	for i in range(4): var a := TAU*i/4.0-PI/2; canvas.draw_line(center+Vector2(cos(a),sin(a))*(r-4), center+Vector2(cos(a),sin(a))*(r-2), g, 1.5)
	canvas.draw_line(center, center+Vector2(cos(-PI/3), sin(-PI/3))*5, color, 2)
	canvas.draw_line(center, center+Vector2(cos(-PI/2), sin(-PI/2))*7, color, 1.5)
	canvas.draw_circle(center, 1.5, g)

static func draw_turret_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	var br := 8.0; var bl := 10.0; var bw := 2.5; var acc := Color(color.r*0.7, color.g*0.7, color.b*0.7, color.a)
	var h := PackedVector2Array()
	for i in range(6): h.append(center + Vector2(cos(TAU*i/6.0-PI/6), sin(TAU*i/6.0-PI/6))*br)
	canvas.draw_colored_polygon(h, acc); var ih := PackedVector2Array()
	for i in range(6): ih.append(center + Vector2(cos(TAU*i/6.0-PI/6), sin(TAU*i/6.0-PI/6))*(br-2))
	canvas.draw_colored_polygon(ih, color); canvas.draw_circle(center, 3, acc); canvas.draw_circle(center, 2, color)
	var md := Vector2(0.7, -0.7).normalized()
	canvas.draw_line(center+md*3, center+md*bl, color, bw+1); canvas.draw_line(center+md*3, center+md*bl, acc, bw-0.5)
	var p := Vector2(-md.y, md.x); canvas.draw_line(center+p*4, center+p*4+md*bl*0.7, color, bw); canvas.draw_line(center-p*4, center-p*4+md*bl*0.7, color, bw)

static func draw_cross_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	canvas.draw_line(center+Vector2(0,-10), center+Vector2(0,10), color, 5)
	canvas.draw_line(center+Vector2(-10,0), center+Vector2(10,0), color, 5)

static func draw_shotgun_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	var acc := Color(color.r*0.75, color.g*0.75, color.b*0.75, color.a)
	var sp := PackedVector2Array([center+Vector2(-3,-5), center+Vector2(3,-5), center+Vector2(3,7), center+Vector2(-3,7)])
	canvas.draw_colored_polygon(sp, acc)
	canvas.draw_colored_polygon(PackedVector2Array([center+Vector2(-3,3), center+Vector2(3,3), center+Vector2(3,7), center+Vector2(-3,7)]), Color(0.85,0.65,0.3,color.a))
	for a in [-0.4, -0.15, 0.0, 0.15, 0.4]: var d := Vector2(sin(a), -cos(a)); canvas.draw_line(center+Vector2(0,-6), center+Vector2(0,-6)+d*8, color, 1.5)

static func draw_mind_control_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	var acc := Color(color.r*0.7, color.g*0.7, color.b*0.7, color.a)
	var ep := PackedVector2Array(); var segs := 16
	for i in range(segs+1): var t := float(i)/float(segs); ep.append(center+Vector2(lerpf(-7,7,t), -4*(1.0-pow(2.0*t-1.0,2.0))))
	for i in range(segs, -1, -1): var t := float(i)/float(segs); ep.append(center+Vector2(lerpf(-7,7,t), 4*(1.0-pow(2.0*t-1.0,2.0))))
	canvas.draw_colored_polygon(ep, acc)
	canvas.draw_circle(center, 5, Color(0.8,0.5,1.0,color.a)); canvas.draw_circle(center, 2.5, Color(0.1,0.05,0.15,color.a))
	canvas.draw_circle(center+Vector2(-1.5,-1.5), 1, Color(1,1,1,0.6))

static func draw_horse_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	var acc := Color(color.r*0.7, color.g*0.7, color.b*0.7, color.a)
	var hp := PackedVector2Array([center+Vector2(8,-2), center+Vector2(6,-6), center+Vector2(2,-8), center+Vector2(-2,-10), center+Vector2(-4,-6), center+Vector2(-6,-2), center+Vector2(-8,4), center+Vector2(-4,8), center+Vector2(2,6), center+Vector2(6,2)])
	canvas.draw_colored_polygon(hp, color)
	canvas.draw_circle(center+Vector2(0,-4), 2, acc); canvas.draw_circle(center+Vector2(0,-4), 1, Color(0.1,0.1,0.1,color.a))
	canvas.draw_circle(center+Vector2(6,0), 1, acc)
	var mc := Color(color.r*1.2, color.g*1.1, color.b, color.a)
	canvas.draw_line(center+Vector2(-2,-8), center+Vector2(-6,-4), mc, 1.5); canvas.draw_line(center+Vector2(-4,-6), center+Vector2(-7,-1), mc, 1.5); canvas.draw_line(center+Vector2(-5,-4), center+Vector2(-8,2), mc, 1.5)

static func draw_drone_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	var acc := Color(color.r*0.7, color.g*0.7, color.b*0.7, color.a); var blue := Color(0.3, 0.7, 1.0, color.a)
	canvas.draw_circle(center, 7, color); canvas.draw_circle(center, 5, acc)
	canvas.draw_circle(center, 2.5, Color(0.2,0.5,0.9,color.a)); canvas.draw_circle(center+Vector2(-0.5,-0.5), 1, Color(1,1,1,0.7))
	for i in range(4): var a := i*PI*0.5+PI*0.25; var s := center+Vector2(cos(a),sin(a))*6; var e := center+Vector2(cos(a),sin(a))*11; canvas.draw_line(s, e, color, 2); canvas.draw_circle(e, 2.5, acc)
	canvas.draw_line(center+Vector2(0,-7), center+Vector2(0,-11), color, 1.5); canvas.draw_circle(center+Vector2(0,-11), 1.5, blue)

static func draw_clone_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	var acc := Color(color.r*0.7, color.g*0.7, color.b*0.7, color.a); var purple := Color(0.7, 0.4, 1.0, color.a)
	var o := Vector2(4,-2)
	canvas.draw_circle(center+o+Vector2(0,-6), 3, acc); canvas.draw_line(center+o+Vector2(0,-3), center+o+Vector2(0,4), acc, 2.5)
	canvas.draw_line(center+o+Vector2(-4,0), center+o+Vector2(4,0), acc, 2); canvas.draw_line(center+o+Vector2(0,4), center+o+Vector2(-3,10), acc, 2); canvas.draw_line(center+o+Vector2(0,4), center+o+Vector2(3,10), acc, 2)
	var mo := Vector2(-2,1)
	canvas.draw_circle(center+mo+Vector2(0,-6), 3.5, purple); canvas.draw_line(center+mo+Vector2(0,-3), center+mo+Vector2(0,4), purple, 3)
	canvas.draw_line(center+mo+Vector2(-5,0), center+mo+Vector2(5,0), purple, 2.5); canvas.draw_line(center+mo+Vector2(0,4), center+mo+Vector2(-3,10), purple, 2.5); canvas.draw_line(center+mo+Vector2(0,4), center+mo+Vector2(3,10), purple, 2.5)

static func draw_hourglass_icon(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	var c2 := color.lightened(0.2)
	var tp := PackedVector2Array([center+Vector2(-5,-6), center+Vector2(5,-6), center]); var bp := PackedVector2Array([center, center+Vector2(5,6), center+Vector2(-5,6)])
	canvas.draw_colored_polygon(tp, color); canvas.draw_colored_polygon(bp, color)
	canvas.draw_polyline(tp, c2, 1.5); canvas.draw_polyline(bp, c2, 1.5)

static func get_special_ready_color(char_index: int, cooldown_progress: float) -> Color:
	## Returns the ready color for a character's special ability indicator
	## cooldown_progress near 0 = dim/darker, near 1.0 = full brightness
	var dim := clampf(cooldown_progress * 0.3 + 0.7, 0.7, 1.0)
	match char_index:
		0:  return Color(0.4 * dim, 0.6 * dim, 1.0 * dim, 1.0)  # Snow White - blue
		1:  return Color(1.0 * dim, 0.4 * dim, 0.3 * dim, 1.0)  # Scarlet - red
		2:  return Color(1.0 * dim, 0.85 * dim, 0.4 * dim, 1.0) # Rapunzel - gold
		3:  return Color(0.7 * dim, 0.4 * dim, 1.0 * dim, 1.0)  # Nayuta - purple
		4:  return Color(0.3 * dim, 0.85 * dim, 0.95 * dim, 1.0) # Commander - cyan
		5:  return Color(0.95 * dim, 0.5 * dim, 0.7 * dim, 1.0) # Marian - pink
		6:  return Color(0.5 * dim, 0.9 * dim, 0.5 * dim, 1.0)  # Crown - green
		7:  return Color(1.0 * dim, 0.7 * dim, 0.2 * dim, 1.0)  # Sin - orange
		8:  return Color(0.3 * dim, 0.7 * dim, 1.0 * dim, 1.0)  # Cecil - sky blue
		9:  return Color(0.8 * dim, 0.5 * dim, 1.0 * dim, 1.0)  # Wells - lavender
		10: return Color(0.6 * dim, 0.9 * dim, 1.0 * dim, 1.0)  # Kilo - light blue
		_:  return Color(0.7 * dim, 0.8 * dim, 1.0 * dim, 1.0)  # default

static func draw_level_up_arrow_icon(canvas: CanvasItem, center: Vector2) -> void:
	var ic := Color(0.15, 0.1, 0.02, 1.0); var hl := Color(1, 1, 0.9, 0.8)
	var ct := center+Vector2(0,-6.4); var cl := center+Vector2(-7,-1.6); var cr := center+Vector2(7,-1.6)
	canvas.draw_line(cl, ct, ic, 5); canvas.draw_line(ct, cr, ic, 5); canvas.draw_line(cl, ct, hl, 3); canvas.draw_line(ct, cr, hl, 3)
	var sr := Rect2(center.x-2.5, center.y-0.8, 5, 7.2); canvas.draw_rect(sr, ic, true); canvas.draw_rect(sr.grow(-1), hl, true)
