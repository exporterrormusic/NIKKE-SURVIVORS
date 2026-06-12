class_name NikkeCardButton
extends Button
## NIKKE lobby-vocabulary card button: a ~6-degree skewed parallelogram card.
## Styles (from the NIKKE reference vocabulary, see docs/UI_REDESIGN_NIKKE.md):
##   "blue"       - blue gradient + white text (primary feature, e.g. SHOP)
##   "dark"       - charcoal glass + cyan-tinted text (secondary features)
##   "dark_red"   - charcoal red glass (QUIT/destructive)
##   "white_blue" - white card + blue text (utility chips, e.g. NOTICE)
##   "white_ark"  - frosted white + dark chip icon (THE main entry, e.g. PLAY)

const UI := preload("res://scripts/ui/UITheme.gd")
const MainMenuIconScript := preload("res://scripts/ui/components/MainMenuIcon.gd")

const SKEW := Vector2(0.105, 0.0)  # ~6 degree lean

@export var card_style: String = "dark"
@export var title_text: String = ""
@export var subtitle_text: String = ""
@export var icon_type: String = ""
@export var show_dot: bool = false
@export var title_size: int = 26
@export var icon_size: int = 30

var _dot: Panel = null
var _title_label: Label = null


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)

	_apply_styles()
	_build_content()
	_build_dot()

	mouse_entered.connect(func(): UI.apply_hover_effect(self))
	mouse_exited.connect(func(): UI.remove_hover_effect(self))
	button_down.connect(func(): UI.apply_press_effect(self))


func set_dot_visible(value: bool) -> void:
	show_dot = value
	if _dot:
		_dot.visible = value


func _palette() -> Dictionary:
	match card_style:
		"blue":
			return {
				"bg": Color(0.18, 0.66, 0.91, 1.0),
				"bg_hover": UI.ACCENT_CYAN_BRIGHT,
				"border": Color(0.08, 0.40, 0.62, 1.0),
				"border_width": 0, "bottom_edge": 3,
				"title": Color.WHITE, "subtitle": Color(1, 1, 1, 0.8),
				"icon": Color.WHITE,
			}
		"dark_red":
			return {
				"bg": Color(0.12, 0.06, 0.06, 0.92),
				"bg_hover": Color(0.2, 0.09, 0.09, 0.95),
				"border": Color(0.91, 0.224, 0.18, 0.45),
				"border_width": 1, "bottom_edge": 0,
				"title": Color(1.0, 0.7, 0.68, 1.0), "subtitle": Color(1.0, 0.7, 0.68, 0.7),
				"icon": Color(1.0, 0.55, 0.52, 1.0),
			}
		"white_blue":
			return {
				"bg": Color(0.97, 0.985, 1.0, 1.0),
				"bg_hover": Color.WHITE,
				"border": Color(0.78, 0.86, 0.93, 1.0),
				"border_width": 0, "bottom_edge": 0,
				"title": UI.ACCENT_CYAN_DEEP, "subtitle": UI.ADMIN_TEXT_DIM,
				"icon": UI.ACCENT_CYAN_DEEP,
			}
		"white_ark":
			return {
				"bg": Color(0.95, 0.96, 0.97, 0.94),
				"bg_hover": Color(1.0, 1.0, 1.0, 0.97),
				"border": Color(1, 1, 1, 0.0),
				"border_width": 0, "bottom_edge": 0,
				"title": UI.ADMIN_TEXT, "subtitle": Color(0.35, 0.38, 0.42, 1.0),
				"icon": Color.WHITE,
			}
		_:  # "dark"
			return {
				"bg": Color(0.075, 0.09, 0.115, 0.92),
				"bg_hover": Color(0.115, 0.14, 0.175, 0.95),
				"border": Color(0.35, 0.63, 0.78, 0.35),
				"border_width": 1, "bottom_edge": 0,
				"title": Color(0.81, 0.91, 0.96, 1.0), "subtitle": Color(0.81, 0.91, 0.96, 0.6),
				"icon": UI.ACCENT_CYAN,
			}


func _make_card_box(bg: Color, p: Dictionary) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(0)
	style.skew = SKEW
	style.border_color = p["border"]
	style.set_border_width_all(p["border_width"])
	if p["bottom_edge"] > 0:
		style.border_width_bottom = p["bottom_edge"]
	style.shadow_color = UI.SHADOW_COLOR
	style.shadow_size = UI.SHADOW_SIZE
	style.shadow_offset = UI.SHADOW_OFFSET
	style.set_content_margin_all(0)
	return style


func _apply_styles() -> void:
	var p := _palette()
	var normal := _make_card_box(p["bg"], p)
	var hover := _make_card_box(p["bg_hover"], p)
	var pressed := _make_card_box(p["bg"].darkened(0.12), p)
	pressed.shadow_size = 0

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.skew = SKEW
	focus.border_color = UI.ACCENT_SECONDARY
	focus.set_border_width_all(UI.BORDER_NORMAL)
	focus.set_corner_radius_all(0)

	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("hover_pressed", pressed)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("focus", focus)


func _build_content() -> void:
	var p := _palette()

	var row := HBoxContainer.new()
	row.name = "Content"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 26
	row.offset_right = -20
	row.offset_top = 6
	row.offset_bottom = -6
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	if icon_type != "":
		var icon_holder: Control
		if card_style == "white_ark":
			# Dark chip behind the icon (the "Ark" treatment)
			var chip := Panel.new()
			var chip_style := StyleBoxFlat.new()
			chip_style.bg_color = Color(0.08, 0.095, 0.12, 1.0)
			chip_style.set_corner_radius_all(UI.CORNER_TILE)
			chip.add_theme_stylebox_override("panel", chip_style)
			chip.custom_minimum_size = Vector2(icon_size + 28, icon_size + 28)
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon: Control = MainMenuIconScript.new()
			icon.set("icon_type", icon_type)
			icon.set("base_color", p["icon"])
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			chip.add_child(icon)
			icon_holder = chip
		else:
			var icon: Control = MainMenuIconScript.new()
			icon.set("icon_type", icon_type)
			icon.set("base_color", p["icon"])
			icon.custom_minimum_size = Vector2(icon_size, icon_size)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon_holder = icon
		icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon_holder)

	var text_box := VBoxContainer.new()
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 0)
	text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)

	_title_label = Label.new()
	_title_label.text = title_text.to_upper()
	if card_style == "white_ark":
		_title_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	else:
		_title_label.add_theme_font_override("font", UI.FONT_BOLD)
	_title_label.add_theme_font_size_override("font_size", title_size)
	_title_label.add_theme_color_override("font_color", p["title"])
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_title_label)

	if subtitle_text != "":
		var sub := Label.new()
		sub.text = subtitle_text
		UI.style_subtitle_label(sub, max(10, title_size / 3), p["subtitle"])
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_box.add_child(sub)


func _build_dot() -> void:
	_dot = Panel.new()
	_dot.name = "NotificationDot"
	var style := StyleBoxFlat.new()
	style.bg_color = UI.COLOR_DANGER
	style.set_corner_radius_all(9)  # circle - sanctioned exception
	style.border_color = Color(1, 1, 1, 0.85)
	style.set_border_width_all(2)
	_dot.add_theme_stylebox_override("panel", style)
	_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dot.offset_left = -8
	_dot.offset_top = -8
	_dot.offset_right = 8
	_dot.offset_bottom = 8
	_dot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dot.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.visible = show_dot
	add_child(_dot)
