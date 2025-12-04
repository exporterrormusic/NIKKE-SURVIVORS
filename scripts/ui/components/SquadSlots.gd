extends Control
class_name SquadSlots
## 3 squad member slots on the right side. Click filled slot to remove.

signal slot_cleared(index: int)
signal squad_complete

const SLOT_SPACING := 16

var _slots: Array[Panel] = []
var _squad: Array[String] = ["", "", ""]
var _registry: RefCounted = null

func _ready() -> void:
	_load_registry()
	_build_ui()

func _load_registry() -> void:
	_registry = CharacterRegistry.get_instance()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)
	
	var title := Label.new()
	title.text = "SQUAD"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 36
	vbox.add_child(title)
	
	var slots_container := VBoxContainer.new()
	slots_container.add_theme_constant_override("separation", SLOT_SPACING)
	slots_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(slots_container)
	
	for i in 3:
		var slot := _create_slot(i)
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slots_container.add_child(slot)
		_slots.append(slot)

func _create_slot(index: int) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(0, 140)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	
	# Portrait fills entire slot
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(portrait)
	
	# Empty placeholder "?"
	var empty_lbl := Label.new()
	empty_lbl.name = "EmptyLabel"
	empty_lbl.text = "?"
	empty_lbl.add_theme_font_size_override("font_size", 56)
	empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 0.5))
	empty_lbl.set_anchors_preset(Control.PRESET_CENTER)
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(empty_lbl)
	
	# Badge overlay at top
	var badge_bg := ColorRect.new()
	badge_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	badge_bg.anchor_bottom = 0.18
	badge_bg.color = Color(0.0, 0.0, 0.0, 0.7)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(badge_bg)
	
	var badge := Label.new()
	badge.name = "Badge"
	badge.text = "★ MAIN" if index == 0 else "SUPPORT %d" % index
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if index == 0 else Color(0.6, 0.5, 1.0))
	badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_bg.add_child(badge)
	
	# Name bar overlay at bottom
	var name_bar := ColorRect.new()
	name_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_bar.anchor_top = 0.86
	name_bar.color = Color(0.0, 0.0, 0.0, 0.85)
	name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(name_bar)
	
	var name_lbl := Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = "EMPTY"
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_lbl.offset_left = 4
	name_lbl.offset_right = -4
	name_lbl.offset_top = 2
	name_lbl.offset_bottom = -2
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bar.add_child(name_lbl)
	
	# White border overlay on TOP of everything
	var border_overlay := Panel.new()
	border_overlay.name = "BorderOverlay"
	border_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	border_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)  # Transparent background
	border_style.border_color = Color(0.95, 0.95, 0.98, 1.0)
	border_style.set_border_width_all(3)
	border_style.set_corner_radius_all(10)
	border_overlay.add_theme_stylebox_override("panel", border_style)
	slot.add_child(border_overlay)
	
	_update_slot_style(slot, false)
	slot.gui_input.connect(_on_slot_input.bind(index))
	return slot

func _update_slot_style(slot: Panel, filled: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.9) if filled else Color(0.06, 0.06, 0.1, 0.8)
	style.set_corner_radius_all(10)
	slot.add_theme_stylebox_override("panel", style)

func add_character(char_id: String) -> bool:
	# Find first empty slot
	for i in 3:
		if _squad[i] == "":
			_squad[i] = char_id
			_update_slot_visual(i)
			_check_complete()
			return true
	return false

func remove_character(index: int) -> void:
	if index < 0 or index >= 3:
		return
	_squad[index] = ""
	_update_slot_visual(index)
	slot_cleared.emit(index)

func remove_character_by_id(char_id: String) -> void:
	for i in 3:
		if _squad[i] == char_id:
			remove_character(i)
			return

func has_character(char_id: String) -> bool:
	return char_id in _squad

func is_complete() -> bool:
	for id in _squad:
		if id == "":
			return false
	return true

func get_squad() -> Array[String]:
	return _squad.duplicate()

func clear() -> void:
	for i in 3:
		_squad[i] = ""
		_update_slot_visual(i)

func _update_slot_visual(index: int) -> void:
	var slot := _slots[index]
	var char_id := _squad[index]
	var filled := char_id != ""
	
	var portrait: TextureRect = slot.find_child("Portrait", true, false)
	var name_lbl: Label = slot.find_child("NameLabel", true, false)
	var empty_lbl: Label = slot.find_child("EmptyLabel", true, false)
	
	if filled and _registry:
		var data = _registry.get_character(char_id)
		if data:
			if portrait:
				portrait.texture = data.get_portrait()
			if name_lbl:
				name_lbl.text = data.display_name
				name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	else:
		if portrait:
			portrait.texture = null
		if name_lbl:
			name_lbl.text = "EMPTY"
			name_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	
	if empty_lbl:
		empty_lbl.visible = not filled
	
	_update_slot_style(slot, filled)
	
	# Animate
	var tween := create_tween()
	tween.tween_property(slot, "scale", Vector2(1.05, 1.05), 0.08)
	tween.tween_property(slot, "scale", Vector2.ONE, 0.08)

func _check_complete() -> void:
	if is_complete():
		squad_complete.emit()

func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _squad[index] != "":
			remove_character(index)
