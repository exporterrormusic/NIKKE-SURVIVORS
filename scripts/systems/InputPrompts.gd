extends Node
## Input prompts manager - provides device-aware button prompt text.
## Automatically detects when user switches between keyboard/mouse and controller.

signal input_device_changed(is_controller: bool)

var is_controller: bool = false
var _last_input_type: String = "keyboard"

# Keyboard/mouse prompt labels
const KEYBOARD_PROMPTS := {
	"attack": "LMB",
	"thrust": "RMB",
	"dash": "Shift",
	"burst": "Q",
	"next_character": "Scroll Up",
	"prev_character": "Scroll Down",
	"ui_cancel": "Esc",
	"move_up": "W",
	"move_down": "S",
	"move_left": "A",
	"move_right": "D",
}

# Controller prompt labels (Xbox-style, works for most controllers)
const CONTROLLER_PROMPTS := {
	"attack": "[RT]",
	"thrust": "[LT]",
	"dash": "[A]",
	"burst": "[Y]",
	"next_character": "[RB]",
	"prev_character": "[LB]",
	"ui_cancel": "[Start]",
	"move_up": "[L↑]",
	"move_down": "[L↓]",
	"move_left": "[L←]",
	"move_right": "[L→]",
}

# PlayStation alternative labels
const PLAYSTATION_PROMPTS := {
	"attack": "[R2]",
	"thrust": "[L2]",
	"dash": "[X]",
	"burst": "[△]",
	"next_character": "[R1]",
	"prev_character": "[L1]",
	"ui_cancel": "[Options]",
}

func _ready() -> void:
	# Default to keyboard
	is_controller = false
	_last_input_type = "keyboard"
	emit_signal("input_device_changed", is_controller)

func _input(event: InputEvent) -> void:
	# Only detect if we absolutely need to, otherwise assume mouse/key
	pass

## Get the display prompt for an action based on current input device
func get_prompt(action: String) -> String:
	if is_controller:
		return CONTROLLER_PROMPTS.get(action, "[?]")
	return KEYBOARD_PROMPTS.get(action, "?")

## Get a specific prompt style (for UI that shows both)
func get_keyboard_prompt(action: String) -> String:
	return KEYBOARD_PROMPTS.get(action, "?")

func get_controller_prompt(action: String) -> String:
	return CONTROLLER_PROMPTS.get(action, "[?]")

## Check if any controller is connected
func has_controller() -> bool:
	return Input.get_connected_joypads().size() > 0
