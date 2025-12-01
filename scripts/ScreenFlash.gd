extends ColorRect
## HoloCure-style screen flash effects for level-up and damage feedback.
## Add this as a full-screen ColorRect in a high-layer CanvasLayer.

# Flash durations
const LEVEL_UP_DURATION := 0.15
const DAMAGE_DURATION := 0.1

# Flash colors
const LEVEL_UP_COLOR := Color(1.0, 1.0, 1.0, 0.6)  # White flash
const DAMAGE_COLOR := Color(1.0, 0.2, 0.2, 0.4)    # Red flash

var _tween: Tween = null

func _ready() -> void:
	# Start fully transparent
	color = Color(0, 0, 0, 0)
	# Make sure it doesn't block input
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Set anchors to full screen
	set_anchors_preset(Control.PRESET_FULL_RECT)

func flash_level_up() -> void:
	_flash(LEVEL_UP_COLOR, LEVEL_UP_DURATION)

func flash_damage() -> void:
	_flash(DAMAGE_COLOR, DAMAGE_DURATION)

func flash_custom(flash_color: Color, duration: float) -> void:
	_flash(flash_color, duration)

func _flash(flash_color: Color, duration: float) -> void:
	# Cancel any existing flash
	if _tween and _tween.is_running():
		_tween.kill()
	
	# Set flash color instantly
	color = flash_color
	
	# Create fade-out tween
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_EXPO)
	_tween.tween_property(self, "color:a", 0.0, duration)
