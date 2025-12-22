extends Control
class_name BaseMenu
## Base class for all menu screens.
## Provides common functionality: back navigation, sound effects, focus management, scene transitions.
##
## Usage: Extend this class and override _setup_menu() for menu-specific setup.
## Set _back_scene to auto-navigate on back, or leave empty to just emit signal.

const UISounds := preload("res://scripts/ui/UISoundManager.gd")
const UI := preload("res://scripts/ui/UITheme.gd")

## Emitted when user requests to go back (ESC/B button)
signal back_requested

## Scene to navigate to when going back (set in subclass or leave empty for signal-only)
var _back_scene: String = ""

## Initial control to focus for controller support
var _initial_focus_control: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_menu()
	call_deferred("_grab_initial_focus")


## Override in subclass to set up menu-specific elements
func _setup_menu() -> void:
	pass


## Override to return the control that should receive initial focus
func _get_initial_focus_control() -> Control:
	return _initial_focus_control


func _grab_initial_focus() -> void:
	var ctrl := _get_initial_focus_control()
	if ctrl and is_instance_valid(ctrl):
		ctrl.grab_focus()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	
	if event.is_action_pressed("ui_cancel"):
		_on_back_requested()
		get_viewport().set_input_as_handled()


## Called when back is requested (ESC/B). Override for custom behavior.
func _on_back_requested() -> void:
	UISounds.play_back()
	back_requested.emit()
	
	if _back_scene != "":
		_navigate_to(_back_scene)


## Navigate to a scene with proper cleanup
func _navigate_to(scene_path: String) -> void:
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		push_warning("BaseMenu: Scene not found: %s" % scene_path)


## Helper to create styled buttons matching the game's visual style
func _create_menu_button(text: String, bg_color: Color = UI.BG_MID, border_color: Color = UI.BORDER_DEFAULT) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 45)
	btn.add_theme_font_size_override("font_size", 18)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.border_color = border_color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := normal.duplicate()
	hover.bg_color = bg_color.lightened(0.1)
	hover.set_border_width_all(3)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := normal.duplicate()
	pressed.bg_color = bg_color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	return btn


## Helper to play UI sounds
func _play_select_sound() -> void:
	UISounds.play_select()


func _play_back_sound() -> void:
	UISounds.play_back()
