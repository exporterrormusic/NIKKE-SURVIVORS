extends Node
## UI management singleton - handles themes, input prompts, and menu coordination.
## Consolidates: UITheme + InputPrompts + (eventually) MenuManager logic.

# --- Signals ---
signal input_device_changed(is_controller: bool)
signal menu_opened(menu_name: String)
signal menu_closed(menu_name: String)
signal menu_changed(menu_name: String)

# --- Menu Stack ---
var _menu_stack: Array[Control] = []
var _current_menu: Control = null

# --- Theme Colors (Mapped from UITheme) ---
const ACCENT_PRIMARY := Color(0.95, 0.95, 0.98, 1.0)
const ACCENT_SECONDARY := Color(1.0, 0.714, 0.15, 1.0) # Gold
const COLOR_DANGER := Color(1.0, 0.34, 0.34, 1.0)
const COLOR_SUCCESS := Color(0.29, 0.87, 0.5, 1.0)

const BG_DEEP := Color(0.04, 0.055, 0.08, 1.0)
const BG_MID := Color(0.082, 0.11, 0.157, 1.0)
const BG_LIGHT := Color(0.118, 0.157, 0.212, 1.0)

const TEXT_PRIMARY := Color(0.94, 0.96, 0.97, 1.0)
const TEXT_SECONDARY := Color(0.784, 0.792, 0.878, 1.0)
const TEXT_MUTED := Color(0.592, 0.6, 0.694, 1.0)

# --- Input State ---
var is_controller: bool = false

# Keyboard/mouse prompt labels
const KEYBOARD_PROMPTS := {
	"attack": "LMB",
	"thrust": "RMB",
	"dash": "Shift",
	"burst": "Q",
	"ui_cancel": "Esc",
	"move_up": "W",
	"move_down": "S",
	"move_left": "A",
	"move_right": "D",
}

# Controller prompt labels
const CONTROLLER_PROMPTS := {
	"attack": "[RT]",
	"thrust": "[LT]",
	"dash": "[A]",
	"burst": "[Y]",
	"ui_cancel": "[Start]",
	"move_up": "[L↑]",
	"move_down": "[L↓]",
	"move_left": "[L←]",
	"move_right": "[L→]",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input_detection()
	print("[UIManager] Initialized")


func _setup_input_detection() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	print("[UIManager] Controller %s: %d" % ["connected" if connected else "disconnected", device])


func _input(event: InputEvent) -> void:
	# Track input type for UI hints
	var was_controller = is_controller
	
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		is_controller = true
	elif event is InputEventKey or event is InputEventMouseButton:
		is_controller = false
		
	if was_controller != is_controller:
		input_device_changed.emit(is_controller)


# --- Input Prompts API ---

func get_prompt(action: String) -> String:
	if is_controller:
		return CONTROLLER_PROMPTS.get(action, "[?]")
	return KEYBOARD_PROMPTS.get(action, "?")


# --- Menu Navigation ---

func push_menu(menu: Control) -> void:
	if _current_menu:
		_current_menu.hide()
		_menu_stack.append(_current_menu)
	
	_current_menu = menu
	_current_menu.show()
	menu_changed.emit(menu.name)
	EventBus.menu_opened.emit(menu.name)


func pop_menu() -> Control:
	var popped := _current_menu
	
	if _menu_stack.size() > 0:
		_current_menu = _menu_stack.pop_back()
		_current_menu.show()
		menu_changed.emit(_current_menu.name)
	else:
		_current_menu = null
	
	if popped:
		popped.hide()
		EventBus.menu_closed.emit(popped.name)
	
	return popped


func get_current_menu() -> Control:
	return _current_menu


# --- Style Factory (from UITheme) ---

func create_panel_style(bg_color: Color = BG_MID, border_color: Color = Color(0.3, 0.35, 0.45, 0.8)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(0)
	return style
