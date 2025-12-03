extends Button
class_name MainMenuOptionButton
## Styled button for main menu options with icon support.
## Uses UITheme for consistent NIKKE + Holocure hybrid styling.

const UI := preload("res://scripts/ui/UITheme.gd")

@export var option_id: String = "PLAY"
@export var icon_type: String = "play"
@export var label_text: String = "PLAY"
@export var accent_color: Color = Color(0.0, 0.83, 1.0, 1.0)  # UI.ACCENT_PRIMARY
@export var play_option: bool = false  # Special styling for the main "Play" button
@export var danger_option: bool = false  # Red styling for quit/cancel

var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_pressed: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _icon: Node = null
var _label: Label = null
var _hover_tween: Tween = null
var _is_selected: bool = false

func _ready() -> void:
	var content := get_node_or_null("Content")
	if content:
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon = content.get_node_or_null("Icon")
		_label = content.get_node_or_null("Label") as Label
		if _icon:
			_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _label:
			_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	flat = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	toggle_mode = false
	disabled = false
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text = ""
	
	# Set pivot for scale animations
	pivot_offset = size / 2.0
	
	_setup_styles()
	_update_visuals(false)
	
	if _label:
		_label.text = label_text
	if _icon and _icon.has_method("set_base_color"):
		_icon.set("icon_type", icon_type)
		_icon.call("set_base_color", _get_icon_color(false, false))
		_icon.call("set_selected", false)
	
	# Connect hover signals for bouncy effect
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	resized.connect(_on_resized)


func _on_resized() -> void:
	pivot_offset = size / 2.0


func _on_mouse_entered() -> void:
	if not _is_selected:
		_hover_tween = UI.apply_hover_effect(self, _hover_tween)


func _on_mouse_exited() -> void:
	if not _is_selected:
		_hover_tween = UI.remove_hover_effect(self, _hover_tween)


func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_visuals(selected)
	if _icon and _icon.has_method("set_selected"):
		_icon.call("set_selected", selected and not play_option)
	
	# Reset scale when selected changes
	if selected:
		scale = Vector2.ONE
		if _hover_tween:
			_hover_tween.kill()


func set_accent_color(color: Color) -> void:
	accent_color = color
	_update_visuals(_is_selected)


func _setup_styles() -> void:
	if play_option:
		# Primary action button - bright cyan
		_style_normal = UI.create_primary_button_style_normal()
		_style_hover = UI.create_primary_button_style_hover()
		_style_pressed = UI.create_button_style_pressed()
		_style_selected = UI.create_primary_button_style_hover()
	elif danger_option:
		# Danger button - red tinted
		_style_normal = UI.create_danger_button_style()
		_style_hover = _create_danger_hover_style()
		_style_pressed = UI.create_button_style_pressed()
		_style_selected = _style_hover
	else:
		# Standard button
		_style_normal = UI.create_button_style_normal()
		_style_hover = UI.create_button_style_hover()
		_style_pressed = UI.create_button_style_pressed()
		_style_selected = UI.create_button_style_selected()
	
	_apply_styles(_style_normal, _style_hover, _style_pressed)


func _create_danger_hover_style() -> StyleBoxFlat:
	var style := UI.create_panel_style(
		Color(0.35, 0.1, 0.1, 1.0),
		UI.COLOR_DANGER,
		UI.BORDER_THICK,
		UI.CORNER_MEDIUM,
		true
	)
	style.shadow_color = Color(1.0, 0.3, 0.3, 0.4)
	style.shadow_size = 6
	return style


func _update_visuals(selected: bool) -> void:
	if selected:
		_apply_styles(_style_selected, _style_selected, _style_pressed)
	else:
		_apply_styles(_style_normal, _style_hover, _style_pressed)
	
	_update_label_color(selected)
	_update_icon_color(selected)


func _update_label_color(selected: bool) -> void:
	if not _label:
		return
	
	var color: Color
	if play_option:
		color = UI.TEXT_DARK
	elif danger_option:
		color = UI.COLOR_DANGER if not selected else UI.TEXT_PRIMARY
	elif selected:
		color = UI.ACCENT_PRIMARY
	else:
		color = accent_color
	
	_label.add_theme_color_override("font_color", color)


func _update_icon_color(selected: bool) -> void:
	if not _icon or not _icon.has_method("set_base_color"):
		return
	_icon.call("set_base_color", _get_icon_color(selected, is_hovered()))


func _get_icon_color(selected: bool, hovered: bool) -> Color:
	if play_option:
		return UI.TEXT_DARK
	if danger_option:
		return UI.COLOR_DANGER
	if selected:
		return UI.ACCENT_PRIMARY
	if hovered:
		return UI.TEXT_PRIMARY
	return accent_color


func _apply_styles(normal: StyleBoxFlat, hover: StyleBoxFlat, pressed_style: StyleBoxFlat) -> void:
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", normal)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("hover_pressed", pressed_style)
