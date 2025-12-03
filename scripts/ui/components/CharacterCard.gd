extends Control
class_name CharacterCard
## A selectable card showing a character's portrait and name.
## Used in the character selection menu.

signal pressed(card: CharacterCard)
signal hovered(card: CharacterCard)

@export var character_name: String = ""
@export var portrait_texture: Texture2D
@export var is_random: bool = false
@export var is_locked: bool = false

const NORMAL_BG := Color(0.12, 0.12, 0.16, 0.95)
const HOVER_BG := Color(0.18, 0.18, 0.24, 0.98)
const SELECTED_BG := Color(0.26, 0.26, 0.34, 1.0)
const BORDER_NORMAL := Color(0.4, 0.4, 0.5, 0.8)
const BORDER_SELECTED := Color(0.7, 0.8, 1.0, 1.0)
const LOCKED_TINT := Color(0.4, 0.4, 0.4, 1.0)

var _character_data: CharacterData = null
var _is_selected: bool = false
var _is_hovered: bool = false

@onready var _background: Panel = $Background
@onready var _portrait: TextureRect = $Background/Portrait
@onready var _name_label: Label = $Background/NameLabel
@onready var _random_label: Label = $Background/RandomLabel
@onready var _lock_overlay: ColorRect = $Background/LockOverlay

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	_update_visuals()


func configure(display_name: String, texture: Texture2D, random: bool = false, data: CharacterData = null) -> void:
	character_name = display_name
	portrait_texture = texture
	is_random = random
	_character_data = data
	
	if data:
		is_locked = not data.is_unlocked
	else:
		is_locked = false
	
	if is_inside_tree():
		_update_visuals()


func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_visuals()


func get_character_data() -> CharacterData:
	return _character_data


func _update_visuals() -> void:
	if not is_inside_tree():
		return
	
	# Update portrait
	if _portrait:
		if is_random:
			_portrait.texture = null
		else:
			_portrait.texture = portrait_texture
		_portrait.modulate = LOCKED_TINT if is_locked else Color.WHITE
	
	# Update name label
	if _name_label:
		_name_label.text = character_name
		_name_label.visible = not is_random
	
	# Update random label
	if _random_label:
		_random_label.visible = is_random
	
	# Update lock overlay
	if _lock_overlay:
		_lock_overlay.visible = is_locked
	
	# Update background style
	_update_background_style()


func _update_background_style() -> void:
	if not _background:
		return
	
	var bg_color := NORMAL_BG
	var border_color := BORDER_NORMAL
	
	if _is_selected:
		bg_color = SELECTED_BG
		border_color = BORDER_SELECTED
	elif _is_hovered:
		bg_color = HOVER_BG
	
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_border_width_all(2)
	style.border_color = border_color
	style.set_corner_radius_all(4)
	_background.add_theme_stylebox_override("panel", style)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_update_background_style()
	emit_signal("hovered", self)


func _on_mouse_exited() -> void:
	_is_hovered = false
	_update_background_style()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if not is_locked:
				emit_signal("pressed", self)
			accept_event()
