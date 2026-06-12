class_name OperatorRecordCard
extends Button
## Ranked operator card for the leaderboard gallery: burst art, rank numeral
## overlay, GODDESS chip, name + best score + wave line. Grayed "NO DATA"
## state for operators without a recorded run. Yellow accent when selected.

const UI := preload("res://scripts/ui/UITheme.gd")

const ART_HEIGHT := 144.0
const CHAMFER := 18.0

var display_name := ""
var rank := 0            # 1-based; 0 = unranked
var best_score := 0
var best_wave := 0
var best_difficulty := 1
var goddess_fall := false
var art: Texture2D = null
## Vertical point of the art (0 = top, 1 = bottom) kept centered in the band.
## Cards use the face-framed portrait-sq, where faces sit just above center.
var face_focus := 0.38

var _selected := false


func _ready() -> void:
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Flat transparent button; all visuals are drawn
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed"]:
		add_theme_stylebox_override(state, empty)
	add_theme_stylebox_override("focus", UI.create_button_style_focus())
	resized.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_selected(selected: bool) -> void:
	_selected = selected
	queue_redraw()


func _chamfer_polygon(rect_size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, 0), Vector2(rect_size.x, 0),
		Vector2(rect_size.x, rect_size.y - CHAMFER),
		Vector2(rect_size.x - CHAMFER, rect_size.y),
		Vector2(0, rect_size.y),
	])


func _draw() -> void:
	var w := size.x
	var h := size.y
	var has_data := best_score > 0

	# Card body (white, bottom-right chamfer)
	draw_colored_polygon(_chamfer_polygon(size), Color.WHITE)

	# Burst art, cover-fit into the top band
	if art:
		var tw := float(art.get_width())
		var th := float(art.get_height())
		var cover_scale := maxf(w / tw, ART_HEIGHT / th)
		var uv_w := (w / cover_scale) / tw
		var uv_h := (ART_HEIGHT / cover_scale) / th
		var u0 := (1.0 - uv_w) * 0.5
		# Keep the face line centered in the visible slice, clamped to bounds
		var v0 := clampf(face_focus - uv_h * 0.5, 0.0, 1.0 - uv_h)
		var quad := PackedVector2Array([
			Vector2(0, 0), Vector2(w, 0), Vector2(w, ART_HEIGHT), Vector2(0, ART_HEIGHT)
		])
		var uvs := PackedVector2Array([
			Vector2(u0, v0), Vector2(u0 + uv_w, v0),
			Vector2(u0 + uv_w, v0 + uv_h), Vector2(u0, v0 + uv_h)
		])
		var tint := Color(0.95, 0.95, 0.97, 1.0) if has_data else Color(0.32, 0.33, 0.36, 1.0)
		draw_colored_polygon(quad, tint, uvs, art)
	else:
		draw_rect(Rect2(0, 0, w, ART_HEIGHT), Color(0.102, 0.129, 0.169, 1.0))

	var font_oblique: Font = UI.FONT_TITLE_OBLIQUE
	var font_bold: Font = UI.FONT_BOLD

	# Rank numeral overlay (top-left, white with shadow)
	var rank_text := "%02d" % rank if has_data else "--"
	draw_string(font_oblique, Vector2(14, 44), rank_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color(0, 0, 0, 0.55))
	draw_string(font_oblique, Vector2(12, 42), rank_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color.WHITE)

	# GODDESS chip (top-right)
	if has_data and goddess_fall:
		var chip_w := 36.0
		var chip_h := 28.0
		var chip_pos := Vector2(w - chip_w - 9, 9)
		draw_colored_polygon(PackedVector2Array([
			chip_pos, chip_pos + Vector2(chip_w, 0),
			chip_pos + Vector2(chip_w, chip_h - 8), chip_pos + Vector2(chip_w - 8, chip_h),
			chip_pos + Vector2(0, chip_h),
		]), UI.COLOR_DANGER)
		draw_string(font_bold, chip_pos + Vector2(9, 21), "☠",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)

	# Text block
	var text_color := UI.ADMIN_TEXT if has_data else UI.ADMIN_TEXT_DIM
	draw_string(font_bold, Vector2(17, ART_HEIGHT + 27), display_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, w - 30, 18, text_color)
	if has_data:
		draw_string(font_oblique, Vector2(17, ART_HEIGHT + 63), _format_score(best_score),
			HORIZONTAL_ALIGNMENT_LEFT, w - 30, 32, UI.ADMIN_TEXT)
		draw_string(font_bold, Vector2(17, ART_HEIGHT + 87), "×%d · WAVE %d" % [best_difficulty, best_wave],
			HORIZONTAL_ALIGNMENT_LEFT, w - 30, 15, UI.ACCENT_CYAN_DEEP)
	else:
		draw_string(font_bold, Vector2(17, ART_HEIGHT + 58), "NO DATA",
			HORIZONTAL_ALIGNMENT_LEFT, w - 30, 20, UI.ADMIN_TEXT_DIM)

	# Selection: yellow accent bar + outline
	if _selected:
		draw_rect(Rect2(0, 0, 6, h), UI.ACCENT_SECONDARY)
		draw_rect(Rect2(Vector2.ZERO, size), UI.ACCENT_SECONDARY, false, 3.0)
	elif is_hovered():
		draw_rect(Rect2(Vector2.ZERO, size), UI.ACCENT_CYAN, false, 1.0)


static func _format_score(value: int) -> String:
	# Abbreviate with ~3 significant digits: 102K, 11.3M, 1.23B
	if value >= 1000000000:
		var billions := float(value) / 1000000000.0
		return ("%dB" % int(billions)) if billions >= 100 else \
			(("%.1fB" % billions) if billions >= 10 else ("%.2fB" % billions))
	elif value >= 1000000:
		var millions := float(value) / 1000000.0
		return ("%dM" % int(millions)) if millions >= 100 else \
			(("%.1fM" % millions) if millions >= 10 else ("%.2fM" % millions))
	elif value >= 1000:
		var thousands := float(value) / 1000.0
		return ("%dK" % int(thousands)) if thousands >= 100 else \
			(("%.1fK" % thousands) if thousands >= 10 else ("%.2fK" % thousands))
	return str(value)
