extends Control

## HoloCure-style Upgrade Shop
## Dark cards with white borders, yellow glow on hover, clean pixel-art aesthetic

signal upgrade_chosen(option_id)

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

@export var option_a: String = ""
@export var option_b: String = ""
@export var option_c: String = ""
@export var icon_a: Texture2D
@export var icon_b: Texture2D
@export var icon_c: Texture2D

var selected_option = -1
var selected_text = ""
var debug_centering: bool = false  # Kept for Player.gd compatibility

# Sizing - balanced for good readability (scaled 1.3x)
const CARD_WIDTH := 754.0   # 580 * 1.3
const CARD_HEIGHT := 156.0  # 120 * 1.3
const ICON_SIZE := 125      # 96 * 1.3
const BORDER_WIDTH := 4.0
const CORNER_RADIUS := 10
const CARD_SPACING := 18    # 14 * 1.3
const TEXT_PADDING := 26    # 20 * 1.3

var _cards: Array[Control] = []
var _hover_states: Array[bool] = [false, false, false]
var _hover_tweens: Dictionary = {}

func _ready():
	# Setup dark overlay background
	$ColorRect.color = UI.BG_OVERLAY
	$ColorRect.visible = true
	
	# Style the title
	var title = get_node_or_null("Center/VBoxContainer/Title")
	if title:
		title.add_theme_font_size_override("font_size", 54)  # 42 * 1.3
		title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	
	call_deferred("setup_options")

func setup_options():
	var btn1 = get_node_or_null("Center/VBoxContainer/OptionButton1")
	var btn2 = get_node_or_null("Center/VBoxContainer/OptionButton2")
	var btn3 = get_node_or_null("Center/VBoxContainer/OptionButton3")
	if btn1 == null or btn2 == null or btn3 == null:
		call_deferred("setup_options")
		return
	
	var vbox = get_node_or_null("Center/VBoxContainer")
	if vbox:
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", CARD_SPACING)
	
	var buttons = [btn1, btn2, btn3]
	var options = [option_a, option_b, option_c]
	var icons = [icon_a, icon_b, icon_c]
	
	for i in range(3):
		_setup_card(buttons[i], options[i], icons[i], i)

func _setup_card(button: Button, text: String, icon: Texture2D, index: int):
	# Clear default button content - we'll draw custom
	button.text = ""
	button.icon = null
	button.flat = true
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	
	# Center the button's pivot for scaling
	button.pivot_offset = Vector2(CARD_WIDTH / 2, CARD_HEIGHT / 2)
	
	# Store data in metadata
	var headline = text
	var description = ""
	if text.find(":") != -1:
		var parts = text.split(":", false, 2)
		headline = parts[0].strip_edges().to_upper()
		description = parts[1].strip_edges() if parts.size() > 1 else ""
	
	button.set_meta("headline", headline)
	button.set_meta("description", description)
	button.set_meta("index", index)
	
	# Process icon
	if icon and icon.get_image():
		var img = icon.get_image().duplicate()
		var aspect = img.get_width() / max(1.0, img.get_height())
		var target_w = int(ICON_SIZE * aspect)
		img.resize(target_w, ICON_SIZE, Image.INTERPOLATE_NEAREST)
		button.set_meta("icon", ImageTexture.create_from_image(img))
	elif icon:
		button.set_meta("icon", icon)
	else:
		button.set_meta("icon", null)
	
	_cards.append(button)
	
	# Connect signals
	if not button.pressed.is_connected(_on_option_selected):
		button.pressed.connect(_on_option_selected.bind(index))
	if not button.mouse_entered.is_connected(_on_card_hover):
		button.mouse_entered.connect(_on_card_hover.bind(index))
	if not button.mouse_exited.is_connected(_on_card_unhover):
		button.mouse_exited.connect(_on_card_unhover.bind(index))
	if not button.draw.is_connected(_on_card_draw):
		button.draw.connect(_on_card_draw.bind(button))
	
	button.queue_redraw()

func _on_card_draw(button: Button):
	var index: int = button.get_meta("index", 0)
	var hovered: bool = _hover_states[index]
	var headline: String = button.get_meta("headline", "")
	var description: String = button.get_meta("description", "")
	var icon: Texture2D = button.get_meta("icon", null)
	
	var rect := Rect2(Vector2.ZERO, button.size)
	var bg_color := UI.CHAR_HOVER if hovered else UI.CHAR_NORMAL
	var border_color := UI.TALENT_HOVER_BORDER if hovered else UI.ACCENT_PRIMARY
	var border_w := BORDER_WIDTH + (1 if hovered else 0)
	
	# Draw background with rounded corners
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(int(border_w))
	style.set_corner_radius_all(CORNER_RADIUS)
	button.draw_style_box(style, rect)
	
	# Icon area
	var icon_area_width := ICON_SIZE + TEXT_PADDING * 2
	var icon_x := TEXT_PADDING
	var icon_y := (button.size.y - ICON_SIZE) / 2
	
	# Draw icon
	if icon:
		var icon_rect := Rect2(icon_x, icon_y, ICON_SIZE, ICON_SIZE)
		button.draw_texture_rect(icon, icon_rect, false)
	
	# Draw divider line
	var divider_x := icon_area_width
	var divider_top := 16.0
	var divider_bottom := button.size.y - 16.0
	button.draw_line(
		Vector2(divider_x, divider_top),
		Vector2(divider_x, divider_bottom),
		UI.ENTRY_SEPARATOR, 2.0
	)
	
	# Text area
	var text_x := divider_x + TEXT_PADDING
	var text_width := button.size.x - text_x - TEXT_PADDING
	
	# Get font
	var font := button.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	
	# Draw headline
	var headline_size := 28  # 22 * 1.3
	var headline_y := button.size.y / 2 - 4
	if description != "":
		headline_y = button.size.y / 2 - 18
	button.draw_string(font, Vector2(text_x, headline_y), headline, HORIZONTAL_ALIGNMENT_LEFT, text_width, headline_size, UI.TEXT_PRIMARY)
	
	# Draw description
	if description != "":
		var desc_size := 20  # 16 * 1.3
		var desc_y := button.size.y / 2 + 20
		button.draw_string(font, Vector2(text_x, desc_y), description, HORIZONTAL_ALIGNMENT_LEFT, text_width, desc_size, UI.TEXT_SECONDARY)

func _on_card_hover(index: int):
	_hover_states[index] = true
	var button := _cards[index]
	
	# Cancel existing tween
	if _hover_tweens.has(index) and is_instance_valid(_hover_tweens[index]):
		_hover_tweens[index].kill()
	
	# Scale up animation from center
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "scale", Vector2(1.04, 1.04), 0.12)
	_hover_tweens[index] = tween
	
	button.queue_redraw()

func _on_card_unhover(index: int):
	_hover_states[index] = false
	var button := _cards[index]
	
	# Cancel existing tween
	if _hover_tweens.has(index) and is_instance_valid(_hover_tweens[index]):
		_hover_tweens[index].kill()
	
	# Scale back animation
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(button, "scale", Vector2.ONE, 0.08)
	_hover_tweens[index] = tween
	
	button.queue_redraw()

func _on_option_selected(option_id: int):
	UISounds.play_confirm()
	selected_option = option_id
	selected_text = [option_a, option_b, option_c][option_id]
	emit_signal("upgrade_chosen", selected_text)
	queue_free()
