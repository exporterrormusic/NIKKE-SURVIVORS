class_name NikkeDamageLog
extends VBoxContainer
## Damage log row list (dark field register): severity-coded accent edge,
## timestamp, source, hit type, amount. Reads the DamageLog singleton on
## refresh() - no per-frame processing. Used by the pause overlay and the
## defeat report.

const UI := preload("res://scripts/ui/UITheme.gd")
const DamageLogScript := preload("res://scripts/autoload/DamageLog.gd")


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func refresh() -> void:
	for child in get_children():
		child.queue_free()

	var dl := DamageLogScript.get_instance()
	var entries: Array = dl.get_entries_reversed() if dl else []

	if entries.is_empty():
		var empty := Label.new()
		empty.text = "NO DAMAGE TAKEN"
		UI.style_subtitle_label(empty, 18, Color(1, 1, 1, 0.4))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(empty)
		return

	for entry in entries:
		add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> Control:
	var amount: int = entry.get("amount", 0)
	var accent := Color(0.353, 0.392, 0.439, 1.0)
	var amount_color := Color(0.667, 0.706, 0.753, 1.0)
	if amount >= 50:
		accent = UI.COLOR_DANGER
		amount_color = Color(1.0, 0.42, 0.38, 1.0)
	elif amount >= 20:
		accent = Color(0.91, 0.573, 0.247, 1.0)
		amount_color = Color(0.941, 0.663, 0.361, 1.0)
	elif amount >= 10:
		accent = Color(0.85, 0.78, 0.35, 1.0)
		amount_color = Color(0.95, 0.9, 0.5, 1.0)

	var row := PanelContainer.new()
	var style := UI.create_accent_edge_style(
		Color(0.078, 0.094, 0.122, 0.7), accent, SIDE_LEFT, 4)
	style.content_margin_left = 20
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", style)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var time_label := Label.new()
	time_label.text = DamageLogScript.format_time(entry)
	time_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	time_label.add_theme_font_size_override("font_size", 19)
	time_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	time_label.custom_minimum_size.x = 66
	hbox.add_child(time_label)

	var source_label := Label.new()
	source_label.text = str(entry.get("source", "Unknown"))
	source_label.add_theme_font_override("font", UI.FONT_BOLD)
	source_label.add_theme_font_size_override("font_size", 21)
	source_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_label.clip_text = true
	source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(source_label)

	var type_label := Label.new()
	type_label.text = "(%s)" % entry.get("type", "hit")
	type_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	type_label.add_theme_font_size_override("font_size", 18)
	type_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hbox.add_child(type_label)

	var amount_label := Label.new()
	amount_label.text = "-%d" % amount
	amount_label.add_theme_font_override("font", UI.FONT_BOLD)
	amount_label.add_theme_font_size_override("font_size", 22)
	amount_label.add_theme_color_override("font_color", amount_color)
	amount_label.custom_minimum_size.x = 66
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(amount_label)

	return row
