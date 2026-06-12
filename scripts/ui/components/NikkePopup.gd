class_name NikkePopup
extends Control
## Standard NIKKE dialog: white admin-register card on a dark scrim.
## Header pair (oblique title + letter-spaced subtitle), hairline, content
## slot, bottom button row. Closes on ESC or scrim click.
##
## Usage:
##   var popup := NikkePopup.create("Quit Game?", "Confirm exit")
##   popup.add_text("Are you sure?")
##   popup.add_button("CANCEL", "secondary").pressed.connect(popup.close)
##   popup.add_button("QUIT", "danger").pressed.connect(func(): get_tree().quit())
##   popup.open(self)

const UI := preload("res://scripts/ui/UITheme.gd")

signal closed

var title_text: String = ""
var subtitle_text: String = ""
var card_min_size := Vector2(640, 0):
	set(value):
		card_min_size = value
		if _card:
			_card.custom_minimum_size = value

var _card: PanelContainer = null
var _content_box: VBoxContainer = null
var _button_row: HBoxContainer = null
var _first_button: Button = null


static func create(title: String, subtitle: String = "") -> NikkePopup:
	var popup := NikkePopup.new()
	popup.title_text = title
	popup.subtitle_text = subtitle
	popup._build_ui()
	return popup


func _ready() -> void:
	if _content_box == null:
		_build_ui()
	# Entrance: snappy fade + slide (needs to be in-tree for tweens)
	modulate.a = 0.0
	var start_y := _card.position.y
	_card.position.y = start_y + UI.SLIDE_DISTANCE * 0.5
	var tween := create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 1.0, UI.SLIDE_DURATION)
	tween.tween_property(_card, "position:y", start_y, UI.SLIDE_DURATION)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = UI.BG_OVERLAY
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	var card := PanelContainer.new()
	_card = card
	card.custom_minimum_size = card_min_size
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.add_theme_stylebox_override("panel", UI.create_popup_card_style())
	add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	UI.style_header_label(title, 38, UI.ADMIN_TEXT)
	vbox.add_child(title)

	if subtitle_text != "":
		var sub := Label.new()
		sub.text = subtitle_text
		UI.style_subtitle_label(sub, 12, UI.ADMIN_TEXT_DIM)
		vbox.add_child(sub)

	var hairline := ColorRect.new()
	hairline.color = UI.ADMIN_HAIRLINE
	hairline.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(hairline)

	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 12)
	_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_box)

	_button_row = HBoxContainer.new()
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_row.add_theme_constant_override("separation", 20)
	vbox.add_child(_button_row)


func open(parent: Node) -> void:
	parent.add_child(self)
	if _first_button:
		_first_button.grab_focus.call_deferred()


func close() -> void:
	closed.emit()
	queue_free()


func add_text(body: String) -> Label:
	var label := Label.new()
	label.text = body
	label.add_theme_font_override("font", UI.FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Autowrap labels MUST have a pinned width: without one the minimum height
	# is computed against zero width (one word per line), ballooning the card
	# into a screen-tall blank sliver.
	label.custom_minimum_size.x = card_min_size.x - 80
	_content_box.add_child(label)
	return label


func add_content(control: Control) -> void:
	_content_box.add_child(control)


## kind: "primary" (cyan CTA), "secondary" (light), "danger" (red)
func add_button(label: String, kind: String = "secondary") -> Button:
	var btn := Button.new()
	btn.text = label.to_upper()
	btn.custom_minimum_size = Vector2(160, 48)
	btn.add_theme_font_override("font", UI.FONT_BOLD)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_stylebox_override("focus", UI.create_button_style_focus())

	match kind:
		"primary":
			btn.add_theme_stylebox_override("normal", UI.create_cta_style_normal())
			btn.add_theme_stylebox_override("hover", UI.create_cta_style_hover())
			btn.add_theme_stylebox_override("pressed", UI.create_cta_style_pressed())
			_set_button_font_color(btn, Color.WHITE)
		"danger":
			btn.add_theme_stylebox_override("normal", UI.create_danger_cta_style_normal())
			var hover := UI.create_danger_cta_style_normal()
			hover.bg_color = hover.bg_color.lightened(0.12)
			btn.add_theme_stylebox_override("hover", hover)
			btn.add_theme_stylebox_override("pressed", UI.create_danger_cta_style_normal())
			_set_button_font_color(btn, Color.WHITE)
		_:
			btn.add_theme_stylebox_override("normal", UI.create_secondary_cta_style_normal())
			btn.add_theme_stylebox_override("hover", UI.create_secondary_cta_style_hover())
			btn.add_theme_stylebox_override("pressed", UI.create_secondary_cta_style_normal())
			_set_button_font_color(btn, UI.ADMIN_TEXT)

	_button_row.add_child(btn)
	if _first_button == null:
		_first_button = btn
	return btn


## Buttons inherit white focus/hover font colors from the default theme,
## which is unreadable on light card buttons - pin every state.
static func _set_button_font_color(btn: Button, color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color"]:
		btn.add_theme_color_override(state, color)
	btn.add_theme_color_override("font_disabled_color", Color(color.r, color.g, color.b, 0.4))


## Convenience: a secondary button that just closes the popup.
func add_close_button(label: String = "CLOSE") -> Button:
	var btn := add_button(label, "secondary")
	btn.pressed.connect(close)
	return btn


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
