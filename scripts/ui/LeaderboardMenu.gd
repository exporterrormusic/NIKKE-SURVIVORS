extends Control
class_name LeaderboardMenu
## Leaderboard menu showing top survival runs per character.
## Displays player scores, waves survived, and character portraits.

signal back_requested

const UI := preload("res://scripts/ui/UITheme.gd")

const MAX_VISIBLE_ENTRIES := 10
const ENTRIES_PER_COLUMN := 5

@onready var _left_column: VBoxContainer = %LeftColumn
@onready var _right_column: VBoxContainer = %RightColumn
@onready var _columns_scroll: ScrollContainer = %ColumnsScroll
@onready var _empty_state_label: Label = %EmptyStateLabel
@onready var _total_score_label: Label = %TotalScoreLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_process_unhandled_input(true)
	
	_update_static_labels()
	_refresh_entries()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_handle_escape()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_escape()
		accept_event()


func _handle_escape() -> void:
	var viewport := get_viewport()
	if viewport:
		viewport.set_input_as_handled()
	emit_signal("back_requested")


func _update_static_labels() -> void:
	if _total_score_label:
		_total_score_label.visible = false


func _refresh_entries() -> void:
	_clear_columns()
	
	# Get leaderboard data from GameState
	var entries: Array = _get_leaderboard_entries()
	
	_update_total_score_label()
	
	if entries.is_empty():
		if _empty_state_label:
			_empty_state_label.visible = true
		return
	
	if _empty_state_label:
		_empty_state_label.visible = false
	
	var left_entries := entries.slice(0, ENTRIES_PER_COLUMN)
	var right_entries: Array = []
	if entries.size() > ENTRIES_PER_COLUMN:
		right_entries = entries.slice(ENTRIES_PER_COLUMN, entries.size())
	
	var rank := 1
	for entry in left_entries:
		var control := _create_entry_control(entry, rank, true)
		_left_column.add_child(control)
		rank += 1
	
	for entry in right_entries:
		var control := _create_entry_control(entry, rank, false)
		_right_column.add_child(control)
		rank += 1
	
	if _columns_scroll:
		_columns_scroll.set_v_scroll(0)


func _get_leaderboard_entries() -> Array:
	# Get leaderboard data from GameState
	var entries: Array = []
	
	if GameState and GameState.has_method("get_leaderboard_entries"):
		entries = GameState.get_leaderboard_entries(MAX_VISIBLE_ENTRIES)
	
	return entries


func _update_total_score_label() -> void:
	if not _total_score_label:
		return
	
	var total_score := 0
	if GameState and GameState.has_method("get_total_score"):
		total_score = GameState.get_total_score()
	
	_total_score_label.text = "Total Score: %s" % _format_number(total_score)


func _format_number(value: int) -> String:
	# Abbreviate large numbers with 3 significant digits: 102K, 11.3M, 1.23B, etc.
	if value >= 1000000000:  # Billions
		var billions := float(value) / 1000000000.0
		if billions >= 100:
			return "%dB" % int(billions)
		elif billions >= 10:
			return "%.1fB" % billions
		else:
			return "%.2fB" % billions
	elif value >= 1000000:  # Millions
		var millions := float(value) / 1000000.0
		if millions >= 100:
			return "%dM" % int(millions)
		elif millions >= 10:
			return "%.1fM" % millions
		else:
			return "%.2fM" % millions
	elif value >= 1000:  # Thousands
		var thousands := float(value) / 1000.0
		if thousands >= 100:
			return "%dK" % int(thousands)
		elif thousands >= 10:
			return "%.1fK" % thousands
		else:
			return "%.2fK" % thousands
	else:
		return str(value)


func _format_full_number(value: int) -> String:
	# Format number with comma separators: 1,234,567
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return result


func _clear_columns() -> void:
	if _left_column:
		for child in _left_column.get_children():
			child.queue_free()
	if _right_column:
		for child in _right_column.get_children():
			child.queue_free()


func _create_entry_control(entry: Dictionary, rank: int, is_left_column: bool = true) -> Control:
	var wrapper := MarginContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Add outer padding - left margin for left column, right margin for right column
	wrapper.add_theme_constant_override("margin_left", 16 if is_left_column else 0)
	wrapper.add_theme_constant_override("margin_right", 16 if not is_left_column else 0)
	wrapper.add_theme_constant_override("margin_top", 10)
	wrapper.add_theme_constant_override("margin_bottom", 10)
	
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 120)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_entry_stylebox(rank == 1))
	wrapper.add_child(panel)
	
	var layout := HBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(layout)
	
	# Rank block
	var rank_block := _create_rank_block(rank)
	layout.add_child(rank_block)
	layout.add_child(_create_separator())
	
	# Portrait block
	var portrait_block := _create_portrait_block(entry)
	layout.add_child(portrait_block)
	layout.add_child(_create_separator())
	
	# Name block
	var name_block := _create_name_block(entry)
	layout.add_child(name_block)
	layout.add_child(_create_separator())
	
	# Score block
	var score_block := _create_score_block(entry)
	layout.add_child(score_block)
	layout.add_child(_create_separator())
	
	# Wave block
	var wave_block := _create_wave_block(entry)
	layout.add_child(wave_block)
	
	return wrapper


func _create_rank_block(rank: int) -> Control:
	var container := MarginContainer.new()
	container.custom_minimum_size = Vector2(70, 0)
	container.add_theme_constant_override("margin_left", 12)
	container.add_theme_constant_override("margin_right", 8)
	container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var label := Label.new()
	label.text = "#%d" % rank
	label.add_theme_font_override("font", UI.FONT_TITLE)
	label.add_theme_font_size_override("font_size", 40)
	if rank >= 100:
		label.add_theme_font_size_override("font_size", 28)
	elif rank >= 10:
		label.add_theme_font_size_override("font_size", 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.modulate = UI.RANK_GOLD if rank <= 3 else UI.TEXT_PRIMARY
	container.add_child(label)
	
	return container


func _create_portrait_block(entry: Dictionary) -> Control:
	var container := MarginContainer.new()
	container.custom_minimum_size = Vector2(100, 0)
	container.add_theme_constant_override("margin_top", 10)
	container.add_theme_constant_override("margin_bottom", 10)
	container.add_theme_constant_override("margin_left", 8)
	container.add_theme_constant_override("margin_right", 8)
	
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(96, 96)
	panel.add_theme_stylebox_override("panel", _make_portrait_stylebox())
	container.add_child(panel)
	
	var texture_rect := TextureRect.new()
	texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture_rect.texture = _resolve_entry_portrait(entry)
	panel.add_child(texture_rect)
	
	# Fallback initial if no portrait
	if texture_rect.texture == null:
		var fallback := Label.new()
		fallback.text = _get_initial(entry)
		fallback.add_theme_font_override("font", UI.FONT_BOLD)
		fallback.add_theme_font_size_override("font_size", 44)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fallback.size_flags_vertical = Control.SIZE_EXPAND_FILL
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(fallback)
	
	return container


func _create_name_block(entry: Dictionary) -> Control:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", 12)
	wrapper.add_theme_constant_override("margin_right", 12)
	wrapper.add_theme_constant_override("margin_top", 12)
	wrapper.add_theme_constant_override("margin_bottom", 12)
	wrapper.custom_minimum_size = Vector2(200, 0)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_stretch_ratio = 2.0
	
	var name_label := Label.new()
	var display_name: String = String(entry.get("display_name", ""))
	name_label.text = display_name
	name_label.add_theme_font_override("font", UI.FONT_BOLD)
	
	# Scale font size based on name length to prevent clipping
	var font_size := 42
	if display_name.length() > 16:
		font_size = 28
	elif display_name.length() > 12:
		font_size = 34
	elif display_name.length() > 8:
		font_size = 38
	
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = false
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(name_label)
	
	return wrapper


func _create_score_block(entry: Dictionary) -> Control:
	var wrapper := MarginContainer.new()
	wrapper.custom_minimum_size = Vector2(160, 0)
	wrapper.add_theme_constant_override("margin_left", 12)
	wrapper.add_theme_constant_override("margin_right", 12)
	wrapper.add_theme_constant_override("margin_top", 12)
	wrapper.add_theme_constant_override("margin_bottom", 12)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(container)
	
	var label := Label.new()
	label.text = "SCORE"
	label.add_theme_font_override("font", UI.FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = UI.TEXT_SECONDARY
	container.add_child(label)
	
	var value_label := Label.new()
	var best_score := int(entry.get("best_score", 0))
	if best_score > 0:
		value_label.text = _format_number(best_score)
		value_label.tooltip_text = _format_full_number(best_score)
		value_label.modulate = UI.TEXT_PRIMARY
	else:
		value_label.text = "NO DATA"
		value_label.modulate = UI.TEXT_MUTED
	value_label.add_theme_font_override("font", UI.FONT_TITLE)
	value_label.add_theme_font_size_override("font_size", 40)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_PASS  # Enable tooltip
	container.add_child(value_label)
	
	return wrapper


func _create_wave_block(entry: Dictionary) -> Control:
	var wrapper := MarginContainer.new()
	wrapper.custom_minimum_size = Vector2(140, 0)
	wrapper.add_theme_constant_override("margin_left", 12)
	wrapper.add_theme_constant_override("margin_right", 16)
	wrapper.add_theme_constant_override("margin_top", 12)
	wrapper.add_theme_constant_override("margin_bottom", 12)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(container)
	
	var label := Label.new()
	label.text = "WAVE"
	label.add_theme_font_override("font", UI.FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = UI.TEXT_SECONDARY
	container.add_child(label)
	
	# HBox for wave value and goddess fall badge
	var value_hbox := HBoxContainer.new()
	value_hbox.add_theme_constant_override("separation", 6)
	value_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(value_hbox)
	
	var value_label := Label.new()
	var best_wave := int(entry.get("best_wave", 0))
	var best_difficulty := int(entry.get("best_difficulty", 1))
	var goddess_fall: bool = entry.get("best_goddess_fall", false)
	
	if best_wave > 0:
		# Format: "difficulty-wave" (e.g., "5-12" for difficulty 5, wave 12)
		value_label.text = "%d-%d" % [best_difficulty, best_wave]
		value_label.tooltip_text = "Difficulty %d, Wave %d" % [best_difficulty, best_wave]
		value_label.modulate = UI.RANK_GREEN_TINT
	else:
		value_label.text = "--"
		value_label.modulate = UI.TEXT_MUTED
	value_label.add_theme_font_override("font", UI.FONT_TITLE)
	value_label.add_theme_font_size_override("font_size", 40)  # Same as score
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_PASS  # Enable tooltip
	value_hbox.add_child(value_label)
	
# Add wing badge for Goddess Fall runs
	if goddess_fall and best_wave > 0:
		var wing_label := Label.new()
		wing_label.text = "🫅"  # Wing emoji for Goddess Fall
		wing_label.add_theme_font_size_override("font_size", 28)
		wing_label.tooltip_text = "Goddess Fall"
		wing_label.modulate = UI.RANK_GOLD_TINT
		wing_label.mouse_filter = Control.MOUSE_FILTER_PASS
		value_hbox.add_child(wing_label)
	
	return wrapper


func _create_separator() -> Control:
	var separator := ColorRect.new()
	separator.color = UI.ENTRY_SEPARATOR
	separator.custom_minimum_size = Vector2(2, 80)
	separator.size_flags_vertical = Control.SIZE_EXPAND_FILL
	separator.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return separator


func _make_entry_stylebox(is_top_rank: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.ENTRY_BG.lightened(0.06) if is_top_rank else UI.ENTRY_BG
	style.border_color = UI.ACCENT_PRIMARY if is_top_rank else UI.ENTRY_BORDER
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _make_portrait_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP.darkened(0.2)
	style.border_color = UI.ACCENT_PRIMARY
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _get_initial(entry: Dictionary) -> String:
	var display_name := String(entry.get("display_name", ""))
	if display_name.length() > 0:
		return display_name.substr(0, 1).to_upper()
	var code := String(entry.get("code", ""))
	if code.length() > 0:
		return code.substr(0, 1).to_upper()
	return "?"


func _resolve_entry_portrait(entry: Dictionary) -> Texture2D:
	# First check if portrait is directly provided
	var raw_portrait: Variant = entry.get("portrait")
	if raw_portrait is Texture2D:
		return raw_portrait as Texture2D
	
	# Try to load from character assets
	var code := String(entry.get("code", "")).strip_edges()
	if code.is_empty():
		return null
	

	# Normalize code - replace underscores with hyphens for folder lookup
	var folder_code := code.replace("_", "-")
	# Try different path patterns - prioritize portrait-sq.png since some chars only have that
	var paths := [
		"res://assets/characters/%s/portrait-sq.png" % folder_code,
		"res://assets/characters/%s/portrait.png" % folder_code,
]
	
	for path in paths:
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				return tex
	
	return null