extends CanvasLayer
class_name IntroScreen
## Self-contained intro/disclaimer screen with walking character animation.
## Created by MenuManager and emits dismissed when the user can proceed.

signal dismissed

# Inline colors (avoids UITheme preload cascade)
const _COLOR_TEXT_MUTED := Color(0.592, 0.6, 0.694, 1.0)
const _COLOR_TEXT_SECONDARY := Color(0.784, 0.792, 0.878, 1.0)
const _COLOR_TEXT_DISABLED := Color(0.4, 0.42, 0.45, 1.0)
const _COLOR_CHAR_PORTRAIT := Color(1, 1, 1, 0.95)
const INTRO_MIN_DISPLAY_TIME_MS := 3000

var _root_control: Control = null
var _continue_label: Label = null
var _resources_ready: bool = false
var _intro_start_time: int = 0

# Walking character (process-based animation, survives main thread hiccups)
var _loading_character: AnimatedSprite2D = null
var _placeholder_node: Control = null
var _walk_speed: float = 150.0
var _walk_end_x: float = 0.0
var _bob_time: float = 0.0
var _bob_base_y: float = 0.0
var _selected_sprite_path: String = ""


# --- Public API ---

func start(sprite_path: String) -> void:
	## Build the intro UI and begin walking animation.
	## Called by MenuManager after adding this node to the tree.
	_selected_sprite_path = sprite_path
	_build_ui()
	_add_placeholder_character()
	_try_load_sprite()


func set_resources_ready() -> void:
	## Called by MenuManager when all menu resources are loaded.
	## Updates the continue label so the user knows they can proceed.
	_resources_ready = true
	if _continue_label and is_instance_valid(_continue_label):
		_continue_label.text = "Click anywhere to continue"
		_continue_label.add_theme_color_override("font_color", _COLOR_TEXT_SECONDARY)


# --- UI Building ---

func _build_ui() -> void:
	name = "IntroLayer"
	layer = 100

	_root_control = Control.new()
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.name = "IntroScreen"
	_root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root_control)

	# Black background that receives input
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_intro_bg_input)
	_root_control.add_child(bg)

	# Center container for text
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -500
	center.offset_right = 500
	center.offset_top = -150
	center.offset_bottom = 150
	center.add_theme_constant_override("separation", 20)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(center)

	# Title
	var title := Label.new()
	title.text = "DISCLAIMER"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", _COLOR_TEXT_MUTED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(title)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	center.add_child(spacer)

	# Disclaimer lines
	var lines := [
		"This is an unofficial, fan-made game based on Goddess of Victory: NIKKE.",
		"It is not affiliated with, endorsed by, or sponsored by ShiftUp or any official partners.",
		"All trademarks and characters belong to their respective owners."
	]
	for line_text in lines:
		var line := Label.new()
		line.text = line_text
		line.add_theme_font_size_override("font_size", 22)
		line.add_theme_color_override("font_color", _COLOR_TEXT_SECONDARY)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(line)

	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 30
	center.add_child(spacer2)

	# Continue instruction — starts as "Loading..."
	_continue_label = Label.new()
	_continue_label.text = "Loading..."
	_continue_label.add_theme_font_size_override("font_size", 16)
	_continue_label.add_theme_color_override("font_color", _COLOR_TEXT_DISABLED)
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_continue_label)

	_intro_start_time = Time.get_ticks_msec()
	set_process(true)


# --- Walking Character ---

func _add_placeholder_character() -> void:
	if not _root_control or not is_instance_valid(_root_control):
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_bob_base_y = viewport_size.y - 60
	_walk_end_x = viewport_size.x + 100.0

	var placeholder := ColorRect.new()
	placeholder.size = Vector2(32, 48)
	placeholder.color = _COLOR_CHAR_PORTRAIT
	placeholder.position = Vector2(-50.0, _bob_base_y - 24)
	placeholder.name = "PlaceholderCharacter"
	_root_control.add_child(placeholder)
	_placeholder_node = placeholder


func _try_load_sprite() -> void:
	var status := ResourceLoader.load_threaded_get_status(_selected_sprite_path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_upgrade_to_animated_character()
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		call_deferred("_try_load_sprite")


func _upgrade_to_animated_character() -> void:
	if not _root_control or not is_instance_valid(_root_control):
		return

	var current_x: float = -50.0
	if _placeholder_node and is_instance_valid(_placeholder_node):
		current_x = _placeholder_node.position.x
		_placeholder_node.queue_free()
		_placeholder_node = null

	var sprite_sheet: Texture2D = ResourceLoader.load_threaded_get(_selected_sprite_path) as Texture2D
	if not sprite_sheet:
		return

	# Sprite sheet config: 3 columns, 4 rows (down/left/right/up), row 2 = walking right
	var columns: int = 3
	var rows: int = 4
	var fps: float = 6.0

	var texture_size: Vector2 = sprite_sheet.get_size()
	var frame_width := int(texture_size.x / columns)
	var frame_height := int(texture_size.y / rows)

	var frames := SpriteFrames.new()
	frames.add_animation("right")
	frames.set_animation_speed("right", fps)
	frames.set_animation_loop("right", true)

	for col in range(columns):
		var atlas := AtlasTexture.new()
		atlas.atlas = sprite_sheet
		atlas.region = Rect2(col * frame_width, 2 * frame_height, frame_width, frame_height)
		frames.add_frame("right", atlas)

	_loading_character = AnimatedSprite2D.new()
	_loading_character.sprite_frames = frames
	# Frame-height-relative scale: walking loader renders ~160px tall for both
	# pixel-art (64px) and high-res (640px) sheets
	var loader_scale := 160.0 / float(frame_height)
	_loading_character.scale = Vector2(loader_scale, loader_scale)
	if loader_scale >= 1.0:
		_loading_character.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_loading_character.animation = "right"
	_loading_character.play("right")
	_loading_character.modulate = _COLOR_CHAR_PORTRAIT

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_bob_base_y = viewport_size.y - 60
	_walk_end_x = viewport_size.x + 100.0
	_loading_character.position = Vector2(current_x, _bob_base_y)
	_root_control.add_child(_loading_character)


func _process(delta: float) -> void:
	# Animate the walking character using _process (survives main thread hiccups)
	if _loading_character and is_instance_valid(_loading_character):
		_loading_character.position.x += _walk_speed * delta
		_bob_time += delta * 8.0
		_loading_character.position.y = _bob_base_y + sin(_bob_time) * 3.0
		if _loading_character.position.x > _walk_end_x:
			_loading_character.position.x = -50.0
	elif _placeholder_node and is_instance_valid(_placeholder_node):
		_placeholder_node.position.x += _walk_speed * delta
		_bob_time += delta * 8.0
		_placeholder_node.position.y = _bob_base_y - 24 + sin(_bob_time) * 3.0
		if _placeholder_node.position.x > _walk_end_x:
			_placeholder_node.position.x = -50.0


# --- Input Handling ---

func _input(event: InputEvent) -> void:
	# Handle intro screen dismissal with any key/button
	if not _root_control or not is_instance_valid(_root_control):
		return

	var is_key: bool = event is InputEventKey
	var is_mouse: bool = event is InputEventMouseButton
	var _is_joypad: bool = event is InputEventJoypadButton

	if is_key or is_mouse:
		get_viewport().set_input_as_handled()

		if not _resources_ready:
			return

		var elapsed: int = Time.get_ticks_msec() - _intro_start_time
		if elapsed < INTRO_MIN_DISPLAY_TIME_MS:
			return

		var is_pressed: bool = false
		if is_key:
			is_pressed = (event as InputEventKey).pressed
		elif is_mouse:
			is_pressed = (event as InputEventMouseButton).pressed

		if is_pressed:
			_dismiss()


func _on_intro_bg_input(event: InputEvent) -> void:
	# Handle mouse button events on the background
	if not event is InputEventMouseButton:
		return

	get_viewport().set_input_as_handled()

	if not _resources_ready:
		return

	var elapsed := Time.get_ticks_msec() - _intro_start_time
	if elapsed < INTRO_MIN_DISPLAY_TIME_MS:
		return

	if event.pressed:
		_dismiss()


func _dismiss() -> void:
	emit_signal("dismissed")
