extends Control
class_name PristineCoreContainer
## Sci-fi danger container for Pristine Rapture Core display.
## Extracted from ShopMenu.gd for reusability.
##
## Usage: var display = PristineCoreContainer.new()
##        parent.add_child(display)
##        display.get_count_label().text = "5"

const UI := preload("res://scripts/ui/UITheme.gd")

const CONTAINER_WIDTH := 200.0
const CONTAINER_HEIGHT := 75.0
const BORDER_THICKNESS := 3.0
const CORNER_CUT := 10.0

var _core_icon: Control = null
var _count_label: Label = null
var _glow_time: float = 0.0
var _flash_time: float = 0.0 # Time remaining for collection flash


func _init() -> void:
	custom_minimum_size = Vector2(CONTAINER_WIDTH, CONTAINER_HEIGHT)


func _ready() -> void:
	_build_container()


func _process(delta: float) -> void:
	_glow_time += delta
	if _flash_time > 0:
		_flash_time -= delta
	queue_redraw()


func get_core_icon() -> Control:
	return _core_icon


func get_count_label() -> Label:
	return _count_label


func update_count(value: int) -> void:
	if _count_label:
		_count_label.text = str(value)


## Briefly intensify the glow (used by the in-game counter on core pickup)
func flash_collected() -> void:
	_flash_time = 0.5


func _build_container() -> void:
	# Main content HBox
	var content := HBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 16
	content.offset_right = -16
	content.offset_top = 18
	content.offset_bottom = -8
	content.add_theme_constant_override("separation", 0)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(content)
	
	# Core icon section (left side)
	var icon_section := CenterContainer.new()
	icon_section.custom_minimum_size = Vector2(50, 0)
	content.add_child(icon_section)
	
	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(40, 40)
	icon_section.add_child(icon_container)
	
	_core_icon = PristineCoreIcon.new()
	_core_icon.custom_minimum_size = Vector2(40, 40)
	_core_icon.size = Vector2(40, 40)
	icon_container.add_child(_core_icon)
	
	# Vertical divider space
	var divider_space := Control.new()
	divider_space.custom_minimum_size = Vector2(16, 0)
	content.add_child(divider_space)
	
	# Count section (right side)
	var count_section := CenterContainer.new()
	count_section.custom_minimum_size = Vector2(60, 0)
	count_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(count_section)
	
	_count_label = Label.new()
	_count_label.text = "0"
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_override("font", UI.FONT_TITLE)
	_count_label.add_theme_font_size_override("font_size", 36)
	_count_label.add_theme_color_override("font_color", UI.SHOP_CORE_TEXT)
	_count_label.add_theme_color_override("font_outline_color", UI.SHOP_COUNT_OUTLINE)
	_count_label.add_theme_constant_override("outline_size", 2)
	count_section.add_child(_count_label)


func _draw() -> void:
	var w := size.x
	var h := size.y

	# Pulsing glow effect (intensified during collection flash)
	var flash_intensity: float = _flash_time / 0.5 if _flash_time > 0 else 0.0
	var glow_pulse: float = 0.5 + 0.2 * sin(_glow_time * 2.5) + flash_intensity * 0.6

	# Draw outer glow
	var glow_layers := 6 + int(flash_intensity * 4)
	for i in range(glow_layers, 0, -1):
		var glow_alpha: float = glow_pulse * 0.08 * (1.0 - float(i) / float(glow_layers)) + flash_intensity * 0.15
		var offset: float = float(i) * (2.0 + flash_intensity * 2.0)
		var glow_rect := Rect2(-offset, -offset, w + offset * 2, h + offset * 2)
		draw_rect(glow_rect, Color(UI.SHOP_CORE_GLOW.r, UI.SHOP_CORE_GLOW.g + flash_intensity * 0.3, UI.SHOP_CORE_GLOW.b, glow_alpha))
	
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
	draw_colored_polygon(bg_points, UI.SHOP_CORE_BG)
	
	# Draw border
	for i in range(bg_points.size()):
		var p1: Vector2 = bg_points[i]
		var p2: Vector2 = bg_points[(i + 1) % bg_points.size()]
		draw_line(p1, p2, UI.SHOP_CORE_BORDER, BORDER_THICKNESS, true)
	
	# Draw vertical divider line
	var divider_x := w * 0.42
	var divider_top := 16.0
	var divider_bottom := h - 8.0
	draw_line(Vector2(divider_x, divider_top), Vector2(divider_x, divider_bottom), UI.SHOP_CORE_DIVIDER, 1.5)
	
	# Draw "PRISTINE CORE" title at top
	var title_text := "PRISTINE CORE"
	var title_size := 10
	var title_width: float = UI.FONT_TITLE.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var title_x: float = (w - title_width) / 2.0
	draw_string(UI.FONT_TITLE, Vector2(title_x, 12), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, UI.RESET_TITLE)
	
	# Draw subtle scan lines for tech effect
	var scan_alpha: float = 0.03 + 0.02 * sin(_glow_time * 5.0)
	for y_line in range(0, int(h), 4):
		draw_line(Vector2(CORNER_CUT, y_line), Vector2(w - CORNER_CUT, y_line),
				 Color(UI.RESET_SCAN_LINE.r, UI.RESET_SCAN_LINE.g, UI.RESET_SCAN_LINE.b, scan_alpha), 1.0)


# === PRISTINE CORE ICON ===
class PristineCoreIcon extends Control:
	const UI := preload("res://scripts/ui/UITheme.gd")
	
	func _draw() -> void:
		var center: Vector2 = size / 2.0
		var radius: float = minf(size.x, size.y) / 2.0 - 2.0
		
		# Outer glow
		for i in range(8, 0, -1):
			var glow_alpha: float = 0.15 * (1.0 - float(i) / 8.0)
			var glow_radius: float = radius + float(i) * 2.0
			draw_circle(center, glow_radius, Color(UI.ORB_DANGER_GLOW.r, UI.ORB_DANGER_GLOW.g, UI.ORB_DANGER_GLOW.b, glow_alpha))
		
		# Main sphere gradient
		var segments: int = 32
		for i in range(segments, 0, -1):
			var t: float = float(i) / float(segments)
			var r: float = radius * t
			var color := Color(0.6 + 0.4 * (1.0 - t), 0.1 + 0.2 * (1.0 - t), 0.1 + 0.1 * (1.0 - t))
			draw_circle(center, r, color)
		
		# Inner glowing core
		var core_radius: float = radius * 0.5
		for i in range(16, 0, -1):
			var t: float = float(i) / 16.0
			var r: float = core_radius * t
			var alpha: float = 0.8 * (1.0 - t * 0.5)
			draw_circle(center, r, Color(UI.ORB_DANGER_RING.r, UI.ORB_DANGER_RING.g, UI.ORB_DANGER_RING.b, alpha))
		
		# Hot center
		draw_circle(center, radius * 0.15, UI.ORB_DANGER_CENTER)
		
		# Specular highlight
		var highlight_offset: Vector2 = Vector2(-radius * 0.25, -radius * 0.25)
		var highlight_radius: float = radius * 0.2
		draw_circle(center + highlight_offset, highlight_radius, UI.ORB_DANGER_HIGHLIGHT)
		draw_circle(center + highlight_offset, highlight_radius * 0.5, UI.ORB_DANGER_HIGHLIGHT_CORE)
