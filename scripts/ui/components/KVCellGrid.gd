class_name KVCellGrid
extends GridContainer
## Telemetry cell grid (dark field register): caption-over-value cells with
## hairline separators, oblique numerals. Used by the pause telemetry panel
## and the results report. Call set_cells() with [{ "k": ..., "v": ... }].

const UI := preload("res://scripts/ui/UITheme.gd")

@export var value_size: int = 39

var _cells: Array = []


func _ready() -> void:
	add_theme_constant_override("h_separation", 0)
	add_theme_constant_override("v_separation", 0)
	if not _cells.is_empty():
		_rebuild()


func set_cells(cells: Array) -> void:
	_cells = cells
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		var box := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Color(0.5, 0.55, 0.61, 0.22)
		style.set_border_width_all(0)
		if (i + 1) % columns != 0:
			style.border_width_right = 1
		if i < _cells.size() - columns:
			style.border_width_bottom = 1
		style.set_content_margin_all(0)
		style.content_margin_top = 16
		style.content_margin_bottom = 20
		box.add_theme_stylebox_override("panel", style)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(col)

		var k := Label.new()
		k.text = str(cell.get("k", ""))
		UI.style_subtitle_label(k, 15, Color(1, 1, 1, 0.55))
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(k)

		var v := Label.new()
		v.text = str(cell.get("v", ""))
		v.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
		v.add_theme_font_size_override("font_size", value_size)
		v.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(v)
