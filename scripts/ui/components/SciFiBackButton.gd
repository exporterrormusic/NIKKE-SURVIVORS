extends Button
class_name SciFiBackButton
## Modular sci-fi styled back button with cut corners and hover glow.
## Replaces duplicate _BackButtonContainer inner classes in menus.
## 
## Usage: var back_btn = SciFiBackButton.new()
##        back_btn.pressed.connect(your_callback)
##        parent.add_child(back_btn)

const UI := preload("res://scripts/ui/UITheme.gd")

const CONTAINER_WIDTH := 200.0
const CONTAINER_HEIGHT := 75.0
const BORDER_THICKNESS := 3.0
const CORNER_CUT := 10.0

var _glow_time: float = 0.0
var _is_hovered: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(CONTAINER_WIDTH, CONTAINER_HEIGHT)
	focus_mode = Control.FOCUS_ALL # Enable controller focus
	mouse_entered.connect(func(): _is_hovered = true; queue_redraw())
	mouse_exited.connect(func(): _is_hovered = false; queue_redraw())
	# Also highlight on focus (for controller navigation)
	focus_entered.connect(func(): _is_hovered = true; queue_redraw())
	focus_exited.connect(func(): _is_hovered = false; queue_redraw())


func _ready() -> void:
	_build_content()
	# Remove default focus style to prevent white box
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _process(delta: float) -> void:
	_glow_time += delta
	if _is_hovered:
		queue_redraw()


func _build_content() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	center.add_child(hbox)
	
	var arrow := Label.new()
	arrow.text = "<<"
	arrow.add_theme_font_size_override("font_size", 32)
	arrow.add_theme_color_override("font_color", UI.BTN_BACK_BORDER)
	hbox.add_child(arrow)
	
	var label := Label.new()
	label.text = "BACK"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_TITLE:
		label.add_theme_font_override("font", UI.FONT_TITLE)
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	hbox.add_child(label)


func _draw() -> void:
	var w := size.x
	var h := size.y
	
	# Define colors based on state
	var bg_color := UI.BTN_BACK_BG
	var border_color := UI.BTN_BACK_BORDER
	
	if _is_hovered:
		bg_color = UI.BTN_BACK_HOVER_BG
		border_color = UI.BTN_BACK_HOVER_BORDER
	
	if button_pressed:
		bg_color = bg_color.darkened(0.2)
	
	# Draw background with cut corners
	var bg_points := PackedVector2Array([
		Vector2(CORNER_CUT, 0),
		Vector2(w - CORNER_CUT, 0),
		Vector2(w, CORNER_CUT),
		Vector2(w, h - CORNER_CUT),
		Vector2(w - CORNER_CUT, h),
		Vector2(CORNER_CUT, h),
		Vector2(0, h - CORNER_CUT),
		Vector2(0, CORNER_CUT)
	])
	draw_colored_polygon(bg_points, bg_color)
	
	# Draw border
	for i in range(bg_points.size()):
		var p1: Vector2 = bg_points[i]
		var p2: Vector2 = bg_points[(i + 1) % bg_points.size()]
		draw_line(p1, p2, border_color, BORDER_THICKNESS, true)
	
	# Tech decoration lines
	var line_alpha: float = 0.3
	if _is_hovered:
		line_alpha = 0.6 + 0.2 * sin(_glow_time * 8.0)
	
	var deco_color := border_color
	deco_color.a = line_alpha
	
	draw_line(Vector2(CORNER_CUT + 5, 5), Vector2(CORNER_CUT + 30, 5), deco_color, 2.0)
	draw_line(Vector2(w - CORNER_CUT - 30, h - 5), Vector2(w - CORNER_CUT - 5, h - 5), deco_color, 2.0)
