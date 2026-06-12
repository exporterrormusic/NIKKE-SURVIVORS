extends Control
class_name PristineCoreContainer
## Pristine Rapture Core counter (dark field register, approved HUD mockup
## docs/mockups/hud_v2.html): red corner-bracket chip with the drawn core orb
## and oblique numerals. Used by the in-game HUD (bottom-right).
##
## Usage: var display = PristineCoreContainer.new()
##        parent.add_child(display)
##        display.update_count(5)

const UI := preload("res://scripts/ui/UITheme.gd")

const CONTAINER_WIDTH := 150.0
const CONTAINER_HEIGHT := 64.0
const BRACKET_SIZE := 24.0
const BRACKET_WIDTH := 3.0

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
	content.offset_left = 18
	content.offset_right = -21
	content.add_theme_constant_override("separation", 15)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(content)

	# Core icon (left)
	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(36, 36)
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(icon_container)

	_core_icon = PristineCoreIcon.new()
	_core_icon.custom_minimum_size = Vector2(36, 36)
	_core_icon.size = Vector2(36, 36)
	icon_container.add_child(_core_icon)

	# Count (right)
	_count_label = Label.new()
	_count_label.text = "0"
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_count_label.add_theme_font_size_override("font_size", 33)
	_count_label.add_theme_color_override("font_color", Color(1.0, 0.706, 0.682, 1.0))
	_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 2)
	_count_label.size_flags_vertical = Control.SIZE_FILL
	content.add_child(_count_label)


func _draw() -> void:
	var w := size.x
	var h := size.y

	# Collection flash intensifies the brackets briefly
	var flash_intensity: float = _flash_time / 0.5 if _flash_time > 0 else 0.0
	var bracket_color := Color(0.91, 0.224, 0.18, 0.8 + flash_intensity * 0.2)
	if flash_intensity > 0:
		bracket_color = bracket_color.lightened(flash_intensity * 0.4)

	# Flat dark chip
	draw_rect(Rect2(0, 0, w, h), Color(0.039, 0.051, 0.071, 0.5))

	# Red corner brackets (top-left + bottom-right)
	var s := minf(BRACKET_SIZE, minf(w, h) * 0.5)
	draw_rect(Rect2(0, 0, s, BRACKET_WIDTH), bracket_color)
	draw_rect(Rect2(0, 0, BRACKET_WIDTH, s), bracket_color)
	draw_rect(Rect2(w - s, h - BRACKET_WIDTH, s, BRACKET_WIDTH), bracket_color)
	draw_rect(Rect2(w - BRACKET_WIDTH, h - s, BRACKET_WIDTH, s), bracket_color)


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
