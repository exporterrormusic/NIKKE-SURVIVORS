class_name OperatorChip
extends PanelContainer
## Small "OPERATOR // <name>" chip with portrait (top-right strips of the
## character & mission select screens). Display-only.

const UI := preload("res://scripts/ui/UITheme.gd")

## Light admin-register variant: white card (dark glass otherwise)
@export var light_register := false

var _portrait: TextureRect = null
var _name_label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if light_register:
		add_theme_stylebox_override("panel", UI.create_admin_card_style())
	else:
		var glass := UI.create_glass_style(0.55)
		glass.border_color = Color(1.0, 1.0, 1.0, 0.22)
		glass.set_border_width_all(UI.BORDER_THIN)
		add_theme_stylebox_override("panel", glass)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	var pad_l := Control.new()
	pad_l.custom_minimum_size.x = 2
	row.add_child(pad_l)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(45, 45)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	row.add_child(_portrait)

	var text_col := VBoxContainer.new()
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.add_theme_constant_override("separation", 0)
	row.add_child(text_col)

	var caption := Label.new()
	caption.text = "NIKKE"
	caption.add_theme_font_override("font", UI.FONT_MEDIUM)
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color",
		UI.ADMIN_TEXT_DIM if light_register else Color(1, 1, 1, 0.6))
	text_col.add_child(caption)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", UI.FONT_BOLD)
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color",
		UI.ADMIN_TEXT if light_register else UI.TEXT_PRIMARY)
	text_col.add_child(_name_label)

	var pad_r := Control.new()
	pad_r.custom_minimum_size.x = 8
	row.add_child(pad_r)


func set_operator(display_name: String, portrait: Texture2D) -> void:
	if _name_label:
		_name_label.text = display_name.to_upper()
	if _portrait:
		_portrait.texture = portrait
