class_name DiagonalArtStrip
extends Control
## Angled parallelogram art strip (main-menu venetian language): character art
## clipped to a slanted quad with glowing edge lines and a soft top/bottom
## vignette. The WHOLE strip animates: slides in from off-screen right, then
## drifts slowly left-right forever. Used by the character select screen.

@export var slant_ratio := 0.22          # top-left inset as fraction of width
@export var edge_band_color := Color(1.0, 1.0, 1.0, 1.0)
@export var edge_band_width := 12.5      # solid band hiding the aliased art edge
@export var drift_amplitude := 24.0      # px each side of rest position
@export var drift_period := 30.0         # seconds for a full there-and-back
@export var entrance_offset := 1290.0    # px to the right of rest position
@export var entrance_time := 0.55
@export var exit_time := 0.16

var _texture: Texture2D = null
var _drift_t := 0.0
var _drifting := false
var _anim_tween: Tween = null

## All motion happens through this drawn offset, NOT node position - node
## transforms can snap to whole pixels which makes slow drift jitter, while
## drawn vertices rasterize at sub-pixel precision and stay smooth.
var offset_x := 0.0:
	set(value):
		offset_x = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_art(texture: Texture2D) -> void:
	_texture = texture
	queue_redraw()


## Slide in from off-screen right, then begin the perpetual drift.
func play_entrance() -> void:
	_kill_anim()
	_drifting = false
	offset_x = entrance_offset
	_anim_tween = create_tween()
	_anim_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_anim_tween.tween_property(self, "offset_x", drift_amplitude, entrance_time)
	_anim_tween.tween_callback(_start_drift)


## Quick exit right, swap the art, slide back in (<0.4s total).
func swap_art(texture: Texture2D) -> void:
	_kill_anim()
	_drifting = false
	_anim_tween = create_tween()
	_anim_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_anim_tween.tween_property(self, "offset_x", entrance_offset, exit_time)
	_anim_tween.tween_callback(set_art.bind(texture))
	_anim_tween.set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(self, "offset_x", drift_amplitude, 0.3)
	_anim_tween.tween_callback(_start_drift)


func _start_drift() -> void:
	# cos starts at +amplitude and eases left first - matches the entrance pose
	_drift_t = 0.0
	_drifting = true


func _kill_anim() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()


func _process(delta: float) -> void:
	if _drifting:
		_drift_t += delta
		offset_x = cos(_drift_t * TAU / drift_period) * drift_amplitude


func _polygon_x(edge_left: bool, f: float) -> float:
	# f: 0 = top, 1 = bottom. Quad: (sW,0) (W,0) (W-sW,H) (0,H)
	var s := slant_ratio * size.x
	if edge_left:
		return s * (1.0 - f)
	return size.x - s * f


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return
	# Sub-pixel-smooth motion: all geometry shifts by the animated offset
	draw_set_transform(Vector2(offset_x, 0.0))
	var s := slant_ratio * w
	var quad := PackedVector2Array([
		Vector2(s, 0), Vector2(w, 0), Vector2(w - s, h), Vector2(0, h)
	])

	# Art with object-fit:cover UV mapping
	if _texture:
		var tw := float(_texture.get_width())
		var th := float(_texture.get_height())
		var cover_scale := maxf(w / tw, h / th)
		var uv_w := (w / cover_scale) / tw
		var uv_h := (h / cover_scale) / th
		var u0 := (1.0 - uv_w) * 0.5
		var v0 := (1.0 - uv_h) * 0.5
		var uvs := PackedVector2Array()
		for p in quad:
			uvs.append(Vector2(u0 + (p.x / w) * uv_w, v0 + (p.y / h) * uv_h))
		draw_colored_polygon(quad, Color(0.92, 0.92, 0.95, 1.0), uvs, _texture)

	# Vignette: dark fade at top 30% and bottom 28%, following the slant
	_draw_vignette_slice(0.0, 0.3, Color(0.08, 0.094, 0.118, 0.22), Color(0.08, 0.094, 0.118, 0.0))
	_draw_vignette_slice(0.72, 1.0, Color(0.08, 0.094, 0.118, 0.0), Color(0.08, 0.094, 0.118, 0.3))

	# Smooth white bands along both slant edges - hide the polygon's aliased border
	_draw_edge_band(true)
	_draw_edge_band(false)


func _draw_vignette_slice(f0: float, f1: float, top_col: Color, bottom_col: Color) -> void:
	var h := size.y
	var pts := PackedVector2Array([
		Vector2(_polygon_x(true, f0), f0 * h), Vector2(_polygon_x(false, f0), f0 * h),
		Vector2(_polygon_x(false, f1), f1 * h), Vector2(_polygon_x(true, f1), f1 * h)
	])
	var cols := PackedColorArray([top_col, top_col, bottom_col, bottom_col])
	draw_polygon(pts, cols)


func _draw_edge_band(left_edge: bool) -> void:
	# Antialiased thick line: smooth edges, unlike draw_colored_polygon.
	# Overshoot top/bottom (extrapolated along the slant) so the flat line
	# caps stay outside the visible strip.
	var h := size.y
	var over := edge_band_width / h
	draw_line(
		Vector2(_polygon_x(left_edge, -over), -edge_band_width),
		Vector2(_polygon_x(left_edge, 1.0 + over), h + edge_band_width),
		edge_band_color, edge_band_width, true
	)
