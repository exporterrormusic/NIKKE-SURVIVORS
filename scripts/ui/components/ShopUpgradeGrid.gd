extends Node
class_name ShopUpgradeGrid
## Right-side upgrade grid and unlock panel for ShopMenu.
## Builds upgrade cards in a grid, manages the unlock panel for locked characters,
## and provides buy/reset buttons with visual feedback.
##
## Usage: var grid = ShopUpgradeGrid.new()
##        grid.setup(upgrade_grid, upgrade_scroll, right_panel, unlock_panel, core_icon_factory)
##        grid.purchase_requested.connect(_on_purchase)
##        grid.reset_requested.connect(_on_reset)

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")
const GENERAL_FILTER := "GENERAL"
const CHARACTER_UNLOCK_COST := 3

signal purchase_requested(upgrade_id: String, cost: int)
signal reset_requested(category: String)

var _upgrade_grid: GridContainer
var _upgrade_scroll: ScrollContainer
var _right_panel: Panel
var _unlock_panel: Control

# Callable(icon_size: int) -> Control — factory for creating core icons
var _core_icon_factory: Callable


func setup(upgrade_grid: GridContainer, upgrade_scroll: ScrollContainer, right_panel: Panel, unlock_panel: Control, core_icon_factory: Callable) -> void:
	_upgrade_grid = upgrade_grid
	_upgrade_scroll = upgrade_scroll
	_right_panel = right_panel
	_unlock_panel = unlock_panel
	_core_icon_factory = core_icon_factory


func rebuild(filter: String, unlocked_characters: Array[String], upgrade_levels: Dictionary, cores_spent: Dictionary) -> void:
	# Clear grid
	for child in _upgrade_grid.get_children():
		child.queue_free()
	
	# Clear any existing reset buttons from the right panel
	if _right_panel:
		for child in _right_panel.get_children():
			if child.has_meta("is_reset_container"):
				child.queue_free()
	
	if filter == GENERAL_FILTER:
		_upgrade_scroll.visible = true
		_unlock_panel.visible = false
		_build_general_upgrades(upgrade_levels, cores_spent)
	else:
		var is_unlocked := filter in unlocked_characters
		if is_unlocked:
			_upgrade_scroll.visible = true
			_unlock_panel.visible = false
			_build_character_upgrades(filter, upgrade_levels, cores_spent)
		else:
			_upgrade_scroll.visible = false
			_unlock_panel.visible = true
			_update_unlock_panel(filter, cores_spent)


func update_unlock_panel(char_id: String, registry: CharacterRegistry, cores_spent: Dictionary) -> void:
	_update_unlock_panel(char_id, cores_spent)


# ─── Upgrade grid builders ──────────────────────────────────────────────

func _build_general_upgrades(upgrade_levels: Dictionary, cores_spent: Dictionary) -> void:
	for upgrade in ShopData.GENERAL_UPGRADES:
		var card := _create_upgrade_card(upgrade, "general", upgrade_levels, cores_spent)
		_upgrade_grid.add_child(card)
	
	_add_reset_button_to_content(GENERAL_FILTER.to_lower())


func _build_character_upgrades(char_id: String, upgrade_levels: Dictionary, cores_spent: Dictionary) -> void:
	if char_id in ShopData.CHARACTER_UPGRADES:
		var upgrades: Array = ShopData.CHARACTER_UPGRADES[char_id]
		for upgrade in upgrades:
			var card := _create_upgrade_card(upgrade, char_id, upgrade_levels, cores_spent)
			_upgrade_grid.add_child(card)
	else:
		var placeholder := Label.new()
		placeholder.text = "No upgrades available"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if UI.FONT_MEDIUM:
			placeholder.add_theme_font_override("font", UI.FONT_MEDIUM)
		placeholder.add_theme_font_size_override("font_size", 24)
		placeholder.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
		_upgrade_grid.add_child(placeholder)
	
	_add_reset_button_to_content(char_id)


func _create_upgrade_card(upgrade: Dictionary, category: String, upgrade_levels: Dictionary, cores_spent: Dictionary) -> Control:
	var upgrade_id: String = category + "_" + upgrade["id"]
	var current_level: int = upgrade_levels.get(upgrade_id, 0)
	var max_level: int = upgrade["max_level"]
	var is_maxed: bool = current_level >= max_level
	var cost: int = _calculate_upgrade_cost(upgrade["base_cost"], current_level)
	var can_afford: bool = GameManager.get_pristine_cores() >= cost
	
	# Use interactive card class for hover effects
	var card := _UpgradeCard.new()
	card.custom_minimum_size = Vector2(200, 560)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.setup(is_maxed)
	card.set_can_purchase(can_afford and not is_maxed)
	
	# Connect card click to purchase
	if not is_maxed:
		card.card_clicked.connect(_on_card_clicked.bind(upgrade_id, cost, card))
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 20
	vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)
	
	# Icon centered at top
	var icon_center := CenterContainer.new()
	icon_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_center)
	
	var icon := Label.new()
	icon.text = upgrade["icon"]
	icon.add_theme_font_size_override("font_size", 80)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(icon)
	
	# Name centered
	var name_label := Label.new()
	name_label.text = upgrade["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_BOLD:
		name_label.add_theme_font_override("font", UI.FONT_BOLD)
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_label)
	
	# Level indicator centered
	var level_label := Label.new()
	level_label.text = "Lv. %d / %d" % [current_level, max_level]
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_MEDIUM:
		level_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	level_label.add_theme_font_size_override("font_size", 28)
	level_label.add_theme_color_override("font_color", UI.COLOR_UNLOCKED if is_maxed else UI.TEXT_SECONDARY)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(level_label)
	
	# Description in a container that expands but clips overflow
	var desc_container := Control.new()
	desc_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_container.clip_contents = true
	desc_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_container)
	
	var desc_label := Label.new()
	desc_label.text = upgrade["desc"]
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if UI.FONT_MEDIUM:
		desc_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	
	var desc_len = upgrade["desc"].length()
	var font_size = 24
	if desc_len > 100:
		font_size = 18
	elif desc_len > 80:
		font_size = 20
	desc_label.add_theme_font_size_override("font_size", font_size)
	
	desc_label.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	desc_container.add_child(desc_label)
	
	# Buy button or maxed label - centered, always at bottom
	var btn_center := CenterContainer.new()
	btn_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(btn_center)
	
	if is_maxed:
		var maxed_label := Label.new()
		maxed_label.text = "MAXED"
		maxed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if UI.FONT_BOLD:
			maxed_label.add_theme_font_override("font", UI.FONT_BOLD)
		maxed_label.add_theme_font_size_override("font_size", 32)
		maxed_label.add_theme_color_override("font_color", UI.COLOR_UNLOCKED)
		maxed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_center.add_child(maxed_label)
	else:
		var buy_btn := _create_cost_button(cost, upgrade_id, can_afford, card)
		btn_center.add_child(buy_btn)
	
	return card


func _on_card_clicked(upgrade_id: String, cost: int, card: _UpgradeCard) -> void:
	purchase_requested.emit(upgrade_id, cost)
	# The parent handles the purchase; we flash the card when notified


func flash_card_purchased(card_ref: _UpgradeCard) -> void:
	if is_instance_valid(card_ref):
		card_ref.flash_purchased()


func flash_card_cant_afford(card_ref: _UpgradeCard) -> void:
	if is_instance_valid(card_ref):
		card_ref.flash_cant_afford()


# ─── Buy button ─────────────────────────────────────────────────────────

func _create_cost_button(cost: int, upgrade_id: String, can_afford: bool, parent_card: _UpgradeCard = null) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 72)
	btn.focus_mode = Control.FOCUS_NONE
	
	# Style: sci-fi container look matching the header
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()
	
	if can_afford:
		normal.bg_color = UI.SHOP_UNLOCK_AFFORD_BG
		normal.border_color = UI.SHOP_UNLOCK_AFFORD_BORDER
		hover.bg_color = UI.SHOP_UNLOCK_AFFORD_HOVER_BG
		hover.border_color = UI.SHOP_UNLOCK_AFFORD_HOVER_BORDER
		pressed.bg_color = UI.SHOP_UNLOCK_AFFORD_PRESSED_BG
		pressed.border_color = UI.SHOP_UNLOCK_AFFORD_PRESSED_BORDER
	else:
		normal.bg_color = UI.SHOP_UNLOCK_CANT_BG
		normal.border_color = UI.SHOP_UNLOCK_CANT_BORDER
		hover.bg_color = UI.SHOP_UNLOCK_CANT_HOVER_BG
		hover.border_color = UI.SHOP_UNLOCK_CANT_HOVER_BORDER
		pressed.bg_color = UI.SHOP_UNLOCK_CANT_BG
		pressed.border_color = UI.SHOP_UNLOCK_CANT_BORDER
	
	disabled.bg_color = UI.SHOP_UNLOCK_DISABLED_BG
	disabled.border_color = UI.SHOP_UNLOCK_DISABLED_BORDER
	
	for style in [normal, hover, pressed, disabled]:
		style.set_border_width_all(3)
		style.set_corner_radius_all(6)
		style.corner_detail = 2
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	
	# Button content: icon | divider | cost
	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(content)
	
	# Core icon section
	var icon_section := CenterContainer.new()
	icon_section.custom_minimum_size = Vector2(60, 0)
	icon_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_section)
	
	if _core_icon_factory.is_valid():
		var core_icon: Control = _core_icon_factory.call(44)
		core_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_section.add_child(core_icon)
	
	# Divider line
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(2, 48)
	divider.color = UI.SHOP_DIVIDER_AFFORD if can_afford else UI.SHOP_DIVIDER_CANT
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)
	
	# Cost section
	var cost_section := CenterContainer.new()
	cost_section.custom_minimum_size = Vector2(60, 0)
	cost_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cost_section)
	
	var cost_label := Label.new()
	cost_label.text = str(cost)
	if UI.FONT_BOLD:
		cost_label.add_theme_font_override("font", UI.FONT_BOLD)
	cost_label.add_theme_font_size_override("font_size", 36)
	cost_label.add_theme_color_override("font_color", UI.COLOR_CORE if can_afford else UI.COLOR_LOCKED)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_section.add_child(cost_label)
	
	btn.disabled = not can_afford
	
	# Connect with parent card for visual feedback
	btn.pressed.connect(_on_buy_button_pressed.bind(upgrade_id, cost, parent_card))
	
	# Flash red on click if can't afford
	if not can_afford and parent_card:
		btn.button_down.connect(flash_card_cant_afford.bind(parent_card))
	
	return btn


func _on_buy_button_pressed(upgrade_id: String, cost: int, parent_card: _UpgradeCard) -> void:
	purchase_requested.emit(upgrade_id, cost)


# ─── Unlock panel ───────────────────────────────────────────────────────

func _update_unlock_panel(char_id: String, cores_spent: Dictionary) -> void:
	var panel_btn := _unlock_panel as Button
	if not panel_btn:
		return
	
	var content: VBoxContainer = null
	for child in panel_btn.get_children():
		if child is VBoxContainer:
			content = child
			break
	if not content:
		return
	
	var char_name := _get_char_name(char_id)
	
	var unlock_label := content.get_node_or_null("UnlockLabel") as Label
	if unlock_label:
		unlock_label.text = char_name.to_upper() + " LOCKED"
	
	var cost := CHARACTER_UNLOCK_COST
	var can_afford: bool = GameManager.get_pristine_cores() >= cost
	
	# Update cost row
	var cost_row := content.get_node_or_null("CostRow") as HBoxContainer
	if cost_row:
		for child in cost_row.get_children():
			child.queue_free()
		
		if _core_icon_factory.is_valid():
			var core_icon: Control = _core_icon_factory.call(40)
			core_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cost_row.add_child(core_icon)
		
		var cost_label := Label.new()
		cost_label.text = "%d" % cost
		if UI.FONT_TITLE:
			cost_label.add_theme_font_override("font", UI.FONT_TITLE)
		cost_label.add_theme_font_size_override("font_size", 48)
		cost_label.add_theme_color_override("font_color", UI.COLOR_CORE)
		cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_row.add_child(cost_label)
	
	# Update hint text based on affordability
	var hint := content.get_node_or_null("ClickHint") as Label
	if hint:
		if can_afford:
			hint.text = "Click to Unlock"
			hint.add_theme_color_override("font_color", UI.SHOP_HINT_BRIGHT)
		else:
			hint.text = "Not Enough Cores"
			hint.add_theme_color_override("font_color", UI.SHOP_HINT_MUTED)
	
	# Enable/disable button
	panel_btn.disabled = not can_afford
	
	# Disconnect old signals and connect new
	for connection in panel_btn.pressed.get_connections():
		panel_btn.pressed.disconnect(connection["callable"])
	
	panel_btn.pressed.connect(_on_unlock_clicked.bind(char_id, cost))


func _on_unlock_clicked(char_id: String, cost: int) -> void:
	purchase_requested.emit(char_id + "_unlock", cost)


func _get_char_name(char_id: String) -> String:
	var registry := CharacterRegistry.get_instance()
	return registry.get_character_name(char_id)


# ─── Reset button ───────────────────────────────────────────────────────

func _add_reset_button_to_content(category: String) -> void:
	var reset_container := Control.new()
	reset_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	reset_container.offset_left = -90
	reset_container.offset_top = -90
	reset_container.offset_right = -20
	reset_container.offset_bottom = -20
	reset_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset_container.set_meta("is_reset_container", true)
	
	if _right_panel:
		_right_panel.add_child(reset_container)
	
	var reset_btn := Button.new()
	reset_btn.text = "↺"
	reset_btn.custom_minimum_size = Vector2(70, 70)
	reset_btn.size = Vector2(70, 70)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.tooltip_text = "Reset " + ("General" if category == "general" else category.capitalize()) + " upgrades and refund cores"
	reset_btn.add_theme_font_size_override("font_size", 36)
	reset_btn.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	
	var reset_normal := StyleBoxFlat.new()
	reset_normal.bg_color = UI.RESET_BTN_BG
	reset_normal.set_border_width_all(3)
	reset_normal.border_color = UI.RESET_BTN_BORDER
	reset_normal.set_corner_radius_all(10)
	reset_btn.add_theme_stylebox_override("normal", reset_normal)
	
	var reset_hover := StyleBoxFlat.new()
	reset_hover.bg_color = UI.RESET_BTN_HOVER_BG
	reset_hover.set_border_width_all(3)
	reset_hover.border_color = UI.RESET_BTN_HOVER_BORDER
	reset_hover.set_corner_radius_all(10)
	reset_btn.add_theme_stylebox_override("hover", reset_hover)
	
	var reset_pressed := StyleBoxFlat.new()
	reset_pressed.bg_color = UI.RESET_BTN_PRESSED_BG
	reset_pressed.set_border_width_all(3)
	reset_pressed.border_color = UI.RESET_BTN_PRESSED_BORDER
	reset_pressed.set_corner_radius_all(10)
	reset_btn.add_theme_stylebox_override("pressed", reset_pressed)
	
	reset_btn.pressed.connect(_on_reset_clicked.bind(category))
	reset_container.add_child(reset_btn)


func _on_reset_clicked(category: String) -> void:
	reset_requested.emit(category)


# ─── Utility ────────────────────────────────────────────────────────────

static func _calculate_upgrade_cost(base_cost: int, current_level: int) -> int:
	if current_level < 10:
		return base_cost + current_level
	else:
		var levels_past_10 := current_level - 10
		var doubling_cost := 11 * int(pow(2, levels_past_10))
		return doubling_cost


# ─── UPGRADE CARD (Inner class) - Interactive card with hover/flash effects ───

class _UpgradeCard extends Control:
	signal card_clicked
	
	const UI := preload("res://scripts/ui/UITheme.gd")
	
	var _is_maxed: bool = false
	var _is_hovered: bool = false
	var _flash_color: Color = Color.TRANSPARENT
	var _flash_time: float = 0.0
	var _flash_duration: float = 0.3
	var _can_purchase: bool = false
	
	func setup(is_maxed: bool) -> void:
		_is_maxed = is_maxed
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
	
	func set_can_purchase(can_purchase: bool) -> void:
		_can_purchase = can_purchase
	
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				if _is_maxed:
					return
				if not _can_purchase:
					flash_cant_afford()
					return
				emit_signal("card_clicked")
	
	func _process(delta: float) -> void:
		if _flash_time > 0.0:
			_flash_time -= delta
			queue_redraw()
	
	func _on_mouse_entered() -> void:
		_is_hovered = true
		queue_redraw()
	
	func _on_mouse_exited() -> void:
		_is_hovered = false
		queue_redraw()
	
	func flash_purchased() -> void:
		_flash_color = UI.SHOP_CARD_PURCHASED_BG
		_flash_time = _flash_duration
		queue_redraw()
	
	func flash_cant_afford() -> void:
		_flash_color = UI.SHOP_CARD_CANT_AFFORD_BG
		_flash_time = _flash_duration * 0.5
		queue_redraw()
	
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		
		var bg_color: Color = UI.SHOP_CARD_BG
		if _flash_time > 0.0:
			var flash_t: float = _flash_time / _flash_duration
			bg_color = UI.SHOP_CARD_BG.lerp(_flash_color, flash_t)
		elif _is_hovered:
			bg_color = UI.SHOP_CARD_HOVER_BG
		
		var border_color: Color
		if _is_maxed:
			border_color = UI.SHOP_CARD_MAXED_BORDER
		elif _is_hovered:
			border_color = UI.SHOP_CARD_HOVER_BORDER
		else:
			border_color = UI.SHOP_CARD_BORDER
		
		var corner_radius := 10.0
		_draw_rounded_rect(rect, bg_color, corner_radius)
		_draw_rounded_rect_outline(rect, border_color, corner_radius, 2.0)
		
		if _is_hovered and _flash_time <= 0.0:
			for i in range(3, 0, -1):
				var glow_alpha: float = 0.05 * (1.0 - float(i) / 3.0)
				var glow_rect := Rect2(rect.position - Vector2(i, i) * 2, rect.size + Vector2(i, i) * 4)
				_draw_rounded_rect(glow_rect, Color(UI.ORB_CARD_GLOW.r, UI.ORB_CARD_GLOW.g, UI.ORB_CARD_GLOW.b, glow_alpha), corner_radius + i * 2)
	
	func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
		var points := PackedVector2Array()
		var segments := 8
		
		for i in range(segments + 1):
			var angle := PI + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(radius, radius) + Vector2(cos(angle), sin(angle)) * radius)
		for i in range(segments + 1):
			var angle := -PI / 2.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(rect.size.x - radius, radius) + Vector2(cos(angle), sin(angle)) * radius)
		for i in range(segments + 1):
			var angle := 0.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius) + Vector2(cos(angle), sin(angle)) * radius)
		for i in range(segments + 1):
			var angle := PI / 2.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(radius, rect.size.y - radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		draw_colored_polygon(points, color)
	
	func _draw_rounded_rect_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
		var points := PackedVector2Array()
		var segments := 8
		
		for i in range(segments + 1):
			var angle := PI + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(radius, radius) + Vector2(cos(angle), sin(angle)) * radius)
		for i in range(segments + 1):
			var angle := -PI / 2.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(rect.size.x - radius, radius) + Vector2(cos(angle), sin(angle)) * radius)
		for i in range(segments + 1):
			var angle := 0.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius) + Vector2(cos(angle), sin(angle)) * radius)
		for i in range(segments + 1):
			var angle := PI / 2.0 + (PI / 2.0) * float(i) / float(segments)
			points.append(rect.position + Vector2(radius, rect.size.y - radius) + Vector2(cos(angle), sin(angle)) * radius)
		
		points.append(points[0])
		draw_polyline(points, color, width, true)
