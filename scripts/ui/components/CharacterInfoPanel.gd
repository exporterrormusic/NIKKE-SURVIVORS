extends Panel
class_name CharacterInfoPanel
## Shows character stats, special attack, and burst info when hovering.

var _char_data: Resource = null

var _portrait: TextureRect
var _portrait_container: Control
var _name_lbl: Label
var _desc_lbl: Label
var _stats_box: VBoxContainer
var _special_title: Label
var _special_desc: Label
var _burst_title: Label
var _burst_desc: Label

func _ready() -> void:
	_build_ui()
	_apply_style()

func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.97)
	style.border_color = Color(0.95, 0.95, 0.98, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 4
	add_theme_stylebox_override("panel", style)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 28)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(hbox)
	
	# Left: Portrait + name + description
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 260
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)
	
	# Portrait container with clipping and border
	_portrait_container = Control.new()
	_portrait_container.custom_minimum_size = Vector2(160, 160)
	_portrait_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_portrait_container.visible = false  # Hidden until character is hovered
	left.add_child(_portrait_container)
	
	# Clip panel for rounded corners
	var clip_panel := Panel.new()
	clip_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_panel.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	var clip_style := StyleBoxFlat.new()
	clip_style.bg_color = Color(0.08, 0.08, 0.12)
	clip_style.set_corner_radius_all(12)
	clip_panel.add_theme_stylebox_override("panel", clip_style)
	_portrait_container.add_child(clip_panel)
	
	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	clip_panel.add_child(_portrait)
	
	# White border overlay on top
	var portrait_border := Panel.new()
	portrait_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.border_color = Color(0.95, 0.95, 0.98, 1.0)
	border_style.set_border_width_all(3)
	border_style.set_corner_radius_all(12)
	portrait_border.add_theme_stylebox_override("panel", border_style)
	_portrait_container.add_child(portrait_border)
	
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 20)
	_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.clip_text = true
	_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(_name_lbl)
	
	_desc_lbl = Label.new()
	_desc_lbl.add_theme_font_size_override("font_size", 12)
	_desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(_desc_lbl)
	
	# Divider
	var div1 := VSeparator.new()
	div1.custom_minimum_size.x = 3
	hbox.add_child(div1)
	
	# Middle: Stats
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 8)
	_stats_box.custom_minimum_size.x = 200
	_stats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_stats_box)
	
	var stats_title := Label.new()
	stats_title.text = "STATS"
	stats_title.add_theme_font_size_override("font_size", 20)
	stats_title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_box.add_child(stats_title)
	
	# Divider
	var div2 := VSeparator.new()
	div2.custom_minimum_size.x = 3
	hbox.add_child(div2)
	
	# Right: Special + Burst (two columns)
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 24)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	
	# Special column
	var special_col := VBoxContainer.new()
	special_col.add_theme_constant_override("separation", 8)
	special_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(special_col)
	
	_special_title = Label.new()
	_special_title.add_theme_font_size_override("font_size", 18)
	_special_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	special_col.add_child(_special_title)
	
	var special_sep := HSeparator.new()
	special_col.add_child(special_sep)
	
	_special_desc = Label.new()
	_special_desc.add_theme_font_size_override("font_size", 13)
	_special_desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	_special_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_special_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	special_col.add_child(_special_desc)
	
	# Burst column
	var burst_col := VBoxContainer.new()
	burst_col.add_theme_constant_override("separation", 8)
	burst_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(burst_col)
	
	_burst_title = Label.new()
	_burst_title.add_theme_font_size_override("font_size", 18)
	_burst_title.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0))
	burst_col.add_child(_burst_title)
	
	var burst_sep := HSeparator.new()
	burst_col.add_child(burst_sep)
	
	_burst_desc = Label.new()
	_burst_desc.add_theme_font_size_override("font_size", 13)
	_burst_desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	_burst_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_burst_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	burst_col.add_child(_burst_desc)

func set_character(data: Resource) -> void:
	_char_data = data
	if not data:
		_clear()
		return
	
	_portrait_container.visible = true
	_portrait.texture = data.get_portrait()
	_name_lbl.text = data.display_name
	_desc_lbl.text = data.description if data.description else ""
	
	# Stats
	for child in _stats_box.get_children():
		if child is HBoxContainer:
			child.queue_free()
	
	_add_stat("HP", data.base_hp, 20, Color(0.4, 0.9, 0.5))
	_add_stat("ATK", int(data.base_damage), 50, Color(1.0, 0.5, 0.4))
	_add_stat("SPD", int(data.move_speed), 500, Color(0.5, 0.7, 1.0))
	var crit_val: int = int(data.crit_chance * 100) if data.get("crit_chance") else 5
	_add_stat("CRIT", crit_val, 100, Color(1.0, 0.85, 0.3))
	
	# Special
	_special_title.text = "SPECIAL: " + (data.special_name if data.special_name else "None")
	_special_desc.text = data.special_description if data.special_description else ""
	
	# Burst
	_burst_title.text = "BURST: " + (data.burst_name if data.burst_name else "Unknown")
	_burst_desc.text = data.burst_description if data.burst_description else ""

func _add_stat(stat_name: String, value: int, max_val: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var lbl := Label.new()
	lbl.text = stat_name
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	lbl.custom_minimum_size.x = 50
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	
	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(100, 0)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.12, 0.16)
	bg_style.set_corner_radius_all(6)
	bg_style.border_color = Color(0.3, 0.3, 0.35)
	bg_style.set_border_width_all(1)
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	row.add_child(bar_bg)
	
	var fill := ColorRect.new()
	fill.color = color
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(float(value) / float(max_val), 0.08, 1.0)
	fill.offset_left = 3
	fill.offset_right = -3
	fill.offset_top = 3
	fill.offset_bottom = -3
	bar_bg.add_child(fill)
	
	# Value label inside the bar
	var val_lbl := Label.new()
	val_lbl.text = str(value)
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	val_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_bg.add_child(val_lbl)
	
	_stats_box.add_child(row)

func _clear() -> void:
	_portrait_container.visible = false
	_portrait.texture = null
	_name_lbl.text = "Hover a Character"
	_desc_lbl.text = ""
	_special_title.text = "SPECIAL:"
	_special_desc.text = ""
	_burst_title.text = "BURST:"
	_burst_desc.text = ""
