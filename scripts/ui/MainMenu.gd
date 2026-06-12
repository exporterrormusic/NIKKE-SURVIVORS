extends Control
class_name MainMenu
## Main menu screen - NIKKE lobby layout (V1-A, see docs/UI_REDESIGN_NIKKE.md).
## Layout lives in MainMenu.tscn; this script only wires signals, popups,
## focus navigation, and the clean-mode toggle.

const UI := preload("res://scripts/ui/UITheme.gd")
const NikkePopupScript := preload("res://scripts/ui/components/NikkePopup.gd")

signal play_selected
signal achievements_selected
signal settings_selected
signal leaderboards_selected
signal shop_selected

const VERSION_TEXT := "v0.2B"
const SERIAL_TEXT := "SOV-2026 // ARK SYS %s"

@onready var _logo: TextureRect = %GameLogo
@onready var _greebles: Control = %Greebles
@onready var _left_column: Control = %LeftColumn
@onready var _shop_button: Button = %ShopButton
@onready var _leaderboards_button: Button = %LeaderboardsButton
@onready var _achievements_button: Button = %AchievementsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _play_button: Button = %PlayButton
@onready var _quit_button: Button = %QuitButton
@onready var _top_strip: HBoxContainer = %TopRightStrip
@onready var _notice_button: Button = %NoticeButton
@onready var _core_pill: Button = %CorePill

var _active_popup: Control = null
var _notice_read: bool = false

# Clean Mode (Shift+Q): 0 = all visible, 1 = logo only, 2 = menu only, 3 = art only
var _clean_mode_state: int = 0


func _ready() -> void:
	_greebles.set("serial_text", SERIAL_TEXT % VERSION_TEXT.to_upper())
	call_deferred("_align_greebles_to_logo")

	_connect_buttons()
	_setup_focus_navigation()

	# If we are the root scene (loaded via change_scene), register with MenuManager
	if MenuManager and get_tree().current_scene == self:
		call_deferred("_register_with_manager")

	call_deferred("_grab_initial_focus")
	visibility_changed.connect(_on_visibility_changed)


func _register_with_manager() -> void:
	MenuManager.register_root_main_menu(self)


## The logo PNG has transparent padding, so the drawn art is narrower than the
## TextureRect. Measure the texture's opaque bounds and match the greeble strip
## (barcode + serial) to the visible logo width.
func _align_greebles_to_logo() -> void:
	var tex: Texture2D = _logo.texture
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	var used := img.get_used_rect()
	if used.size.x <= 0:
		return

	# Map texture-space opaque rect into the TextureRect's drawn rect
	# (stretch_mode = keep aspect centered)
	var tex_size := Vector2(tex.get_width(), tex.get_height())
	var draw_scale := minf(_logo.size.x / tex_size.x, _logo.size.y / tex_size.y)
	var drawn_origin: Vector2 = _logo.position + (_logo.size - tex_size * draw_scale) * 0.5
	var left := drawn_origin.x + used.position.x * draw_scale
	var width := used.size.x * draw_scale

	_greebles.position.x = left
	_greebles.size.x = width
	_greebles.queue_redraw()


func _connect_buttons() -> void:
	_play_button.pressed.connect(_on_menu_pressed.bind(play_selected))
	_shop_button.pressed.connect(_on_menu_pressed.bind(shop_selected))
	_leaderboards_button.pressed.connect(_on_menu_pressed.bind(leaderboards_selected))
	_achievements_button.pressed.connect(_on_menu_pressed.bind(achievements_selected))
	_settings_button.pressed.connect(_on_menu_pressed.bind(settings_selected))
	_core_pill.pressed.connect(_on_menu_pressed.bind(shop_selected))
	_notice_button.pressed.connect(_show_patch_notes)
	_quit_button.pressed.connect(_show_quit_confirmation)


func _on_menu_pressed(menu_signal: Signal) -> void:
	AudioManager.play_ui_select()
	menu_signal.emit()


func _setup_focus_navigation() -> void:
	var left_chain: Array[Button] = [
		_shop_button, _leaderboards_button, _achievements_button, _settings_button
	]
	for i in left_chain.size():
		var btn := left_chain[i]
		btn.focus_neighbor_top = left_chain[wrapi(i - 1, 0, left_chain.size())].get_path()
		btn.focus_neighbor_bottom = left_chain[wrapi(i + 1, 0, left_chain.size())].get_path()
		btn.focus_neighbor_right = _play_button.get_path()

	_play_button.focus_neighbor_left = _shop_button.get_path()
	_play_button.focus_neighbor_bottom = _quit_button.get_path()
	_play_button.focus_neighbor_top = _notice_button.get_path()
	_quit_button.focus_neighbor_top = _play_button.get_path()
	_quit_button.focus_neighbor_left = _settings_button.get_path()
	_notice_button.focus_neighbor_bottom = _play_button.get_path()
	_notice_button.focus_neighbor_right = _core_pill.get_path()
	_core_pill.focus_neighbor_left = _notice_button.get_path()
	_core_pill.focus_neighbor_bottom = _play_button.get_path()


func _grab_initial_focus() -> void:
	if is_visible_in_tree() and _active_popup == null:
		_play_button.grab_focus()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		call_deferred("_grab_initial_focus")


# =============================================================================
# POPUPS
# =============================================================================

func _open_popup(popup: Control) -> void:
	_active_popup = popup
	popup.closed.connect(func():
		_active_popup = null
		call_deferred("_grab_initial_focus")
	)
	popup.open(self)


func _show_patch_notes() -> void:
	if _active_popup:
		return
	AudioManager.play_ui_select()

	_notice_read = true
	if _notice_button.has_method("set_dot_visible"):
		_notice_button.set_dot_visible(false)

	var popup := NikkePopupScript.create("Patch Notes", "Latest updates // %s" % VERSION_TEXT)
	popup.card_min_size = Vector2(720, 560)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var content := Label.new()
	content.text = _load_patch_notes()
	content.add_theme_font_override("font", UI.FONT_MEDIUM)
	content.add_theme_font_size_override("font_size", 16)
	content.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	popup.add_content(scroll)

	popup.add_close_button()
	_open_popup(popup)


func _load_patch_notes() -> String:
	var file := FileAccess.open(ScenePaths.PATCH_NOTES, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		if not text.is_empty():
			return text
	return "No patch notes available."


func _show_quit_confirmation() -> void:
	if _active_popup:
		return
	AudioManager.play_ui_back()

	var popup := NikkePopupScript.create("Quit Game?", "Confirm exit // commander")
	popup.add_text("Leave the battlefield and return to your desktop?")
	popup.add_button("CANCEL", "secondary").pressed.connect(popup.close)
	popup.add_button("QUIT", "danger").pressed.connect(func(): get_tree().quit())
	_open_popup(popup)


# =============================================================================
# INPUT / CLEAN MODE
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# Clean Mode Shortcut (Shift + Q)
	if event is InputEventKey and event.pressed and event.keycode == KEY_Q and event.shift_pressed:
		_cycle_clean_mode()
		get_viewport().set_input_as_handled()
		return

	# Popups consume their own input (NikkePopup handles ui_cancel)
	if _active_popup:
		return

	if event.is_action_pressed("ui_cancel"):
		_show_quit_confirmation()
		get_viewport().set_input_as_handled()


func _cycle_clean_mode() -> void:
	_clean_mode_state = (_clean_mode_state + 1) % 4
	var show_menu := _clean_mode_state == 0 or _clean_mode_state == 2
	var show_logo := _clean_mode_state == 0 or _clean_mode_state == 1

	_left_column.visible = show_menu
	_play_button.visible = show_menu
	_quit_button.visible = show_menu
	_top_strip.visible = show_menu
	_logo.visible = show_logo
	_greebles.visible = show_logo
