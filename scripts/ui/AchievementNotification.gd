extends CanvasLayer
class_name AchievementNotification

## Achievement unlock notification popup.
## Shows a toast-style notification when an achievement is unlocked.
## Auto-hides after a few seconds.

const UI := preload("res://scripts/ui/UITheme.gd")

const DISPLAY_TIME := 4.0
const SLIDE_TIME := 0.3

var _panel: PanelContainer = null
var _title_label: Label = null
var _desc_label: Label = null
var _tween: Tween = null
var _queue: Array[Dictionary] = []
var _showing: bool = false


func _ready() -> void:
	layer = 200  # Above everything
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Connect to AchievementManager signal
	if has_node("/root/AchievementManager"):
		var manager = get_node("/root/AchievementManager")
		if not manager.achievement_unlocked.is_connected(_on_achievement_unlocked):
			manager.achievement_unlocked.connect(_on_achievement_unlocked)
	
	_build_ui()


func _build_ui() -> void:
	# Main panel - positioned at top center, starts off-screen
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.offset_left = -200
	_panel.offset_right = 200
	_panel.offset_top = -120  # Start off-screen
	_panel.offset_bottom = 0
	
	var style := StyleBoxFlat.new()
	style.bg_color = UI.ENTRY_BG
	style.set_border_width_all(3)
	style.border_color = UI.ACCENT_SECONDARY
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	
	# Content VBox
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)
	
	# Achievement icon + title row
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(title_row)
	
	# Trophy icon
	var icon_label := Label.new()
	icon_label.text = "🏆"
	icon_label.add_theme_font_size_override("font_size", 28)
	title_row.add_child(icon_label)
	
	# Title
	_title_label = Label.new()
	_title_label.text = "ACHIEVEMENT UNLOCKED"
	_title_label.add_theme_font_override("font", UI.FONT_TITLE)
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)
	title_row.add_child(_title_label)
	
	# Description
	_desc_label = Label.new()
	_desc_label.text = ""
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	_desc_label.add_theme_font_size_override("font_size", 18)
	_desc_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	vbox.add_child(_desc_label)
	
	# Start hidden
	_panel.visible = false


func _on_achievement_unlocked(_achievement_id: String, data: Dictionary) -> void:
	_queue.append(data)
	_process_queue()


func _process_queue() -> void:
	if _showing or _queue.is_empty():
		return
	
	var data: Dictionary = _queue.pop_front()
	_show_notification(data)


func _show_notification(data: Dictionary) -> void:
	_showing = true
	
	# Set content
	var title: String = data.get("title", "Achievement Unlocked")
	_desc_label.text = title
	
	# Slide in from top
	_panel.visible = true
	_panel.offset_top = -120
	
	if _tween and _tween.is_valid():
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_panel, "offset_top", 20, SLIDE_TIME)
	_tween.tween_interval(DISPLAY_TIME)
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "offset_top", -120, SLIDE_TIME)
	_tween.tween_callback(_on_hide_complete)


func _on_hide_complete() -> void:
	_panel.visible = false
	_showing = false
	_process_queue()


## Manually show an achievement notification
func show_achievement(title: String) -> void:
	_on_achievement_unlocked("", {"title": title})
