extends Control
class_name StageSelector
## Holocure-style stage selector with fixed stages, preview, and animated start button.

signal stage_confirmed(stage_id: String)
signal back_requested

var _selected_stage_id: String = "stage_1"
var _stage_cards: Array[Control] = []

var _preview_rect: TextureRect
var _stage_name_lbl: Label
var _modifier_lbl: Label
var _start_btn: Button
var _start_tween: Tween

func _ready() -> void:
	_build_ui()
	_select_first_unlocked()
	_start_pulse_animation()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

func _select_first_unlocked() -> void:
	# Select the first unlocked stage
	for stage in StageRegistry.STAGES:
		if GameState.is_stage_unlocked(stage.id):
			_selected_stage_id = stage.id
			break
	_update_selection()

func _build_ui() -> void:
	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.add_theme_constant_override("separation", 24)
	add_child(main)
	
	# Left: Stage selection list
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = 240
	main.add_child(left)
	
	var stages_title := Label.new()
	stages_title.text = "SELECT STAGE"
	stages_title.add_theme_font_size_override("font_size", 20)
	stages_title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	left.add_child(stages_title)
	
	for stage in StageRegistry.STAGES:
		var card := _create_stage_card(stage)
		left.add_child(card)
		_stage_cards.append(card)
	
	# Center: Preview
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 12)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(center)
	
	var preview_panel := Panel.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	preview_style.border_color = Color(0.4, 0.45, 0.55, 0.8)
	preview_style.set_border_width_all(3)
	preview_style.set_corner_radius_all(10)
	preview_panel.add_theme_stylebox_override("panel", preview_style)
	center.add_child(preview_panel)
	
	_preview_rect = TextureRect.new()
	_preview_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_rect.offset_left = 8
	_preview_rect.offset_right = -8
	_preview_rect.offset_top = 8
	_preview_rect.offset_bottom = -8
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_panel.add_child(_preview_rect)
	
	_stage_name_lbl = Label.new()
	_stage_name_lbl.add_theme_font_size_override("font_size", 28)
	_stage_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	_stage_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_stage_name_lbl)
	
	_modifier_lbl = Label.new()
	_modifier_lbl.add_theme_font_size_override("font_size", 14)
	_modifier_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_modifier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_modifier_lbl)
	
	# Right: Start button
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.custom_minimum_size.x = 180
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(right)
	
	_start_btn = Button.new()
	_start_btn.text = "MISSION\nSTART"
	_start_btn.custom_minimum_size = Vector2(160, 100)
	_start_btn.add_theme_font_size_override("font_size", 24)
	_apply_start_button_style()
	_start_btn.pressed.connect(_on_start_pressed)
	right.add_child(_start_btn)
	
	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(160, 50)
	_apply_back_button_style(back_btn)
	back_btn.pressed.connect(func(): back_requested.emit())
	right.add_child(back_btn)

func _create_stage_card(stage: Dictionary) -> Control:
	var is_unlocked: bool = GameState.is_stage_unlocked(stage.id)
	var is_cleared: bool = stage.id in GameState.stages_cleared
	
	var card := Panel.new()
	card.custom_minimum_size = Vector2(220, 70)
	card.set_meta("stage_id", stage.id)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 0.95) if is_unlocked else Color(0.06, 0.06, 0.08, 0.9)
	style.border_color = Color(0.35, 0.4, 0.5, 0.8) if is_unlocked else Color(0.2, 0.2, 0.25, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_right = -12
	vbox.offset_top = 8
	vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)
	
	# Stage number + name row
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	vbox.add_child(name_row)
	
	var stage_num := Label.new()
	stage_num.text = stage.id.replace("stage_", "").to_upper()
	stage_num.add_theme_font_size_override("font_size", 14)
	stage_num.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75) if is_unlocked else Color(0.35, 0.35, 0.4))
	name_row.add_child(stage_num)
	
	var stage_name := Label.new()
	stage_name.text = stage.name if is_unlocked else "???"
	stage_name.add_theme_font_size_override("font_size", 18)
	stage_name.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98) if is_unlocked else Color(0.4, 0.4, 0.45))
	name_row.add_child(stage_name)
	
	# Cleared indicator
	if is_cleared:
		var cleared_lbl := Label.new()
		cleared_lbl.text = "✓"
		cleared_lbl.add_theme_font_size_override("font_size", 18)
		cleared_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		name_row.add_child(cleared_lbl)
	
	# Modifier description
	var modifier_text := _get_modifier_text(stage)
	var modifier_lbl := Label.new()
	modifier_lbl.text = modifier_text if is_unlocked else "Clear previous stage to unlock"
	modifier_lbl.add_theme_font_size_override("font_size", 12)
	modifier_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7) if is_unlocked else Color(0.3, 0.3, 0.35))
	vbox.add_child(modifier_lbl)
	
	# Lock overlay for locked stages
	if not is_unlocked:
		var lock_overlay := ColorRect.new()
		lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_overlay.color = Color(0, 0, 0, 0.3)
		lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lock_overlay)
		
		var lock_icon := Label.new()
		lock_icon.text = "🔒"
		lock_icon.add_theme_font_size_override("font_size", 24)
		lock_icon.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		lock_icon.offset_left = -40
		lock_icon.offset_right = -12
		card.add_child(lock_icon)
	else:
		# Make clickable
		card.gui_input.connect(_on_card_input.bind(stage.id))
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	return card

func _get_modifier_text(stage: Dictionary) -> String:
	var rules: Dictionary = stage.get("spawn_rules", {})
	var parts: Array[String] = []
	
	var time_str := "Day" if stage.time == "day" else "Night"
	parts.append(time_str)
	
	if rules.get("elite_only", false):
		parts.append("Elite Enemies Only")
	if rules.get("endless", false):
		parts.append("Endless Mode")
	if parts.size() == 1:
		parts.append("Standard Mode")
	
	return " • ".join(parts)

func _on_card_input(event: InputEvent, stage_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected_stage_id = stage_id
		_update_selection()

func _update_selection() -> void:
	# Update card visuals
	for card in _stage_cards:
		var card_stage_id: String = card.get_meta("stage_id")
		var is_selected := card_stage_id == _selected_stage_id
		var is_unlocked: bool = GameState.is_stage_unlocked(card_stage_id)
		
		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		if is_selected and is_unlocked:
			style.border_color = Color(0.95, 0.95, 0.98)
			style.set_border_width_all(3)
			style.bg_color = Color(0.15, 0.18, 0.24, 1.0)
		elif is_unlocked:
			style.border_color = Color(0.35, 0.4, 0.5, 0.8)
			style.set_border_width_all(2)
			style.bg_color = Color(0.1, 0.1, 0.14, 0.95)
	
	_update_preview()

func _update_preview() -> void:
	var stage: Dictionary = StageRegistry.get_stage(_selected_stage_id)
	if stage.is_empty():
		return
	
	_stage_name_lbl.text = stage.name
	_modifier_lbl.text = _get_modifier_text(stage)
	
	# Stage-specific preview images
	var preview_map := {
		"stage_1": "res://assets/backgrounds/forest.jpg",
		"stage_2": "res://assets/backgrounds/snow-night.jpg",
		"stage_3": "res://assets/backgrounds/rapturefield2.jpg",
	}
	
	var preview_path: String = preview_map.get(_selected_stage_id, "")
	if preview_path != "" and ResourceLoader.exists(preview_path):
		_preview_rect.texture = load(preview_path)
	else:
		_preview_rect.texture = null

func _apply_start_button_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.7, 0.4, 1.0)
	normal.border_color = Color(0.4, 1.0, 0.6)
	normal.set_border_width_all(4)
	normal.set_corner_radius_all(12)
	normal.shadow_color = Color(0.2, 0.8, 0.4, 0.4)
	normal.shadow_size = 8
	_start_btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.8, 0.5, 1.0)
	hover.border_color = Color(0.5, 1.0, 0.7)
	hover.set_border_width_all(4)
	hover.set_corner_radius_all(12)
	hover.shadow_size = 12
	_start_btn.add_theme_stylebox_override("hover", hover)
	
	_start_btn.add_theme_color_override("font_color", Color.WHITE)

func _apply_back_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.12, 0.16, 0.95)
	normal.border_color = Color(0.4, 0.4, 0.5, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

func _start_pulse_animation() -> void:
	if _start_tween:
		_start_tween.kill()
	_start_tween = create_tween().set_loops()
	_start_tween.tween_property(_start_btn, "scale", Vector2(1.03, 1.03), 0.6).set_trans(Tween.TRANS_SINE)
	_start_tween.tween_property(_start_btn, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

func _on_start_pressed() -> void:
	stage_confirmed.emit(_selected_stage_id)
