class_name CorePillButton
extends Button
## Compact Pristine Core counter pill (NIKKE currency-bar style):
## red core diamond + count + cyan "+" shop shortcut. Auto-syncs with
## GameManager.core_count_changed.

const UI := preload("res://scripts/ui/UITheme.gd")

## Light admin-register variant: white pill with charcoal text (dark glass otherwise)
@export var light_register := false
## Show the cyan "+" shop shortcut (hide on the shop screen itself)
@export var show_plus := true

var _count_label: Label = null


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "Pristine Rapture Cores - open Shop"

	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	if light_register:
		normal = UI.create_admin_card_style()
		hover = UI.create_admin_card_style()
		hover.border_color = UI.ACCENT_CYAN
		hover.set_border_width_all(UI.BORDER_THIN)
	else:
		normal = UI.create_glass_style(0.55)
		hover = UI.create_glass_style(0.7)
		hover.border_color = UI.ACCENT_CYAN
		hover.set_border_width_all(UI.BORDER_THIN)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", normal)
	add_theme_stylebox_override("focus", UI.create_button_style_focus())

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -14
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var gem := Label.new()
	gem.text = "◆"
	gem.add_theme_font_size_override("font_size", 18)
	gem.add_theme_color_override("font_color", UI.COLOR_CORE)
	row.add_child(gem)

	_count_label = Label.new()
	_count_label.add_theme_font_override("font", UI.FONT_BOLD)
	_count_label.add_theme_font_size_override("font_size", 19)
	_count_label.add_theme_color_override("font_color",
		UI.ADMIN_TEXT if light_register else UI.TEXT_PRIMARY)
	row.add_child(_count_label)

	if show_plus:
		var plus := Label.new()
		plus.text = "+"
		plus.add_theme_font_override("font", UI.FONT_BOLD)
		plus.add_theme_font_size_override("font_size", 22)
		plus.add_theme_color_override("font_color", UI.ACCENT_CYAN)
		row.add_child(plus)

	if GameManager:
		_update_count(GameManager.get_pristine_cores())
		if not GameManager.core_count_changed.is_connected(_update_count):
			GameManager.core_count_changed.connect(_update_count)


func _update_count(value: int) -> void:
	if _count_label:
		_count_label.text = str(value)
