extends Panel
class_name DamageLogPanel
## Displays recent damage events in a scrollable list.
## Matches the style of StatsPanel for visual consistency.
## Only rebuilds when refresh() is called (no per-frame processing).

const UI := preload("res://scripts/ui/UITheme.gd")
const DamageLogScript := preload("res://scripts/autoload/DamageLog.gd")

var _title_label: Label = null
var _content: VBoxContainer = null
var _scroll: ScrollContainer = null
var _is_embedded: bool = false

func set_embedded(value: bool) -> void:
	_is_embedded = value

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# Apply panel style (matches StatsPanel)
	if _is_embedded:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.08, 0.12, 0.98)
		style.border_color = Color(0.5, 0.5, 0.6, 0.8)
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
		add_theme_stylebox_override("panel", style)
	
	# Clear existing children if rebuilding
	for child in get_children():
		child.queue_free()
	
	custom_minimum_size = Vector2(400, 520)
	
	# Main container
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# Title
	_title_label = Label.new()
	_title_label.text = "DAMAGE LOG"
	_title_label.add_theme_font_override("font", UI.FONT_TITLE)
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4)) # Red tint for damage
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)
	
	# Divider
	var divider := ColorRect.new()
	divider.color = UI.DIVIDER_SUBTLE
	divider.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(divider)
	
	# Scroll container for entries
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)
	
	# Content container for damage entries
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)

## Refresh the display from DamageLog singleton.
func refresh() -> void:
	if not _content:
		return
	
	# Clear existing content
	for child in _content.get_children():
		child.queue_free()
	
	# Get entries (newest first)
	var dl := DamageLogScript.get_instance()
	var entries: Array = dl.get_entries_reversed() if dl else []
	
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No damage taken"
		empty_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(empty_label)
		return
	
	# Create entry for each damage event
	for entry in entries:
		var row := _create_damage_entry(entry)
		_content.add_child(row)

func _create_damage_entry(entry: Dictionary) -> Control:
	var container := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.08, 0.08, 0.9) # Slight red tint
	panel_style.border_color = Color(0.5, 0.3, 0.3, 0.6)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(8)
	container.add_theme_stylebox_override("panel", panel_style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	container.add_child(hbox)
	
	# Time stamp
	var time_label := Label.new()
	var dl := DamageLogScript.get_instance()
	if dl:
		time_label.text = DamageLogScript.format_time(entry)
	else:
		time_label.text = "0:00"
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
	time_label.custom_minimum_size.x = 50
	hbox.add_child(time_label)
	
	# Source name
	var source_label := Label.new()
	source_label.text = entry.get("source", "Unknown")
	source_label.add_theme_font_size_override("font_size", 16)
	source_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_label.clip_text = true
	source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(source_label)
	
	# Damage type
	var type_label := Label.new()
	type_label.text = "(%s)" % entry.get("type", "hit")
	type_label.add_theme_font_size_override("font_size", 14)
	type_label.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	hbox.add_child(type_label)
	
	# Damage amount (color-coded)
	var amount: int = entry.get("amount", 0)
	var amount_label := Label.new()
	amount_label.text = "-%d" % amount
	amount_label.add_theme_font_size_override("font_size", 18)
	
	# Color code by severity
	var color := Color(0.8, 0.8, 0.8) # Minor (gray)
	if amount >= 50:
		color = Color(1.0, 0.3, 0.3) # Severe (red)
	elif amount >= 20:
		color = Color(1.0, 0.7, 0.3) # Moderate (orange)
	elif amount >= 10:
		color = Color(1.0, 1.0, 0.5) # Notable (yellow)
	
	amount_label.add_theme_color_override("font_color", color)
	amount_label.custom_minimum_size.x = 60
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(amount_label)
	
	return container
