extends Control
class_name ShopMenu
## Main Menu Shop - NIKKE "supply terminal" (light admin register, approved
## mockup docs/mockups/shop_v2.html). Left: tab rail + item list + reset;
## right: detail panel with current/next bonus and BUY / BUY x10 slabs.
## Permanent general stat upgrades purchased with Pristine Rapture Cores.
## Character unlocks live in the character select screen; character signature
## upgrades are in-run talents (TalentData row 2).
## Static chrome lives in ShopMenu.tscn; rows are data-driven from ShopData.

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")
const ShopListRowScript := preload("res://scripts/ui/components/ShopListRow.gd")
const NikkePopupScript := preload("res://scripts/ui/components/NikkePopup.gd")

signal back_requested

const GENERAL_FILTER := "GENERAL"

# Shop data persistence
var _unlocked_characters: Array[String] = []
var _upgrade_levels: Dictionary = {} # "upgrade_id" -> level
var _cores_spent: Dictionary = {} # "general" -> total cores spent

var _selected_index := 0
var _rows: Array = []  # of ShopListRow (typed via preload; class_name indexing lags)
var _active_popup: Control = null

@onready var _header_title: Label = %HeaderTitle
@onready var _header_sub: Label = %HeaderSub
@onready var _back_button: Button = %BackButton
@onready var _item_list: VBoxContainer = %ItemList
@onready var _reset_button: Button = %ResetButton
@onready var _detail_panel: Panel = %DetailPanel
@onready var _watermark: Label = %Watermark
@onready var _role_label: Label = %RoleLabel
@onready var _name_label: Label = %NameLabel
@onready var _desc_label: Label = %DescLabel
@onready var _lv_now: Label = %LvNow
@onready var _lv_arrow: Label = %LvArrow
@onready var _lv_next: Label = %LvNext
@onready var _cur_bonus: Label = %CurBonus
@onready var _next_bonus: Label = %NextBonus
@onready var _cost10_cap: Label = %Cost10Cap
@onready var _cost10_label: Label = %Cost10Label
@onready var _buy_button: Button = %BuyButton
@onready var _buy10_button: Button = %Buy10Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_load_shop_data()
	_style_chrome()
	_build_rows()

	_back_button.pressed.connect(func():
		UISounds.play_back()
		back_requested.emit()
	)
	_reset_button.pressed.connect(_on_reset_pressed)
	_buy_button.pressed.connect(func(): _buy_levels(1))
	_buy10_button.pressed.connect(func(): _buy_levels(10))
	if GameManager and not GameManager.core_count_changed.is_connected(_on_cores_changed):
		GameManager.core_count_changed.connect(_on_cores_changed)
	visibility_changed.connect(_on_visibility_changed)

	_select(0, false)
	call_deferred("_grab_initial_focus")


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		call_deferred("_grab_initial_focus")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if _active_popup:
			return  # NikkePopup closes itself
		get_viewport().set_input_as_handled()
		UISounds.play_back()
		back_requested.emit()


# =============================================================================
# CHROME / ROWS
# =============================================================================

func _style_chrome() -> void:
	UI.style_header_label(_header_title, 56, UI.ADMIN_TEXT)
	UI.style_subtitle_label(_header_sub, 17, UI.ADMIN_TEXT_DIM)

	_detail_panel.add_theme_stylebox_override("panel", UI.create_admin_card_style())

	_watermark.add_theme_font_size_override("font_size", 300)
	_watermark.add_theme_color_override("font_color", Color(UI.ADMIN_TEXT.r, UI.ADMIN_TEXT.g, UI.ADMIN_TEXT.b, 0.05))

	UI.style_subtitle_label(_role_label, 17, UI.ACCENT_CYAN_DEEP)
	_name_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_name_label.add_theme_font_size_override("font_size", 78)
	_name_label.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	_desc_label.add_theme_font_override("font", UI.FONT_MEDIUM)
	_desc_label.add_theme_font_size_override("font_size", 24)
	_desc_label.add_theme_color_override("font_color", Color(0.29, 0.31, 0.34, 1.0))

	_lv_now.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_lv_now.add_theme_font_size_override("font_size", 93)
	_lv_now.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	_lv_arrow.add_theme_font_size_override("font_size", 39)
	_lv_arrow.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)
	_lv_next.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_lv_next.add_theme_font_size_override("font_size", 57)
	_lv_next.add_theme_color_override("font_color", UI.ACCENT_CYAN_DEEP)

	for cell in [%CurCell, %NextCell, %Cost10Cell]:
		var caption: Label = cell.get_child(0)
		UI.style_subtitle_label(caption, 15, UI.ADMIN_TEXT_DIM)
		var value: Label = cell.get_child(1)
		value.add_theme_font_override("font", UI.FONT_BOLD)
		value.add_theme_font_size_override("font_size", 31)
		value.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	_next_bonus.add_theme_color_override("font_color", UI.ACCENT_CYAN_DEEP)

	for btn in [_buy_button, _buy10_button]:
		btn.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
		btn.add_theme_font_size_override("font_size", 28)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			btn.add_theme_color_override(state, Color.WHITE)
		btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.85))
		var corner := ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT
		btn.add_theme_stylebox_override("normal", UI.create_chamfer_card(UI.ACCENT_CYAN, Color(0, 0, 0, 0), 0, corner, 18.0))
		btn.add_theme_stylebox_override("hover", UI.create_chamfer_card(UI.ACCENT_CYAN_BRIGHT, Color(0, 0, 0, 0), 0, corner, 18.0))
		btn.add_theme_stylebox_override("pressed", UI.create_chamfer_card(UI.ACCENT_CYAN_DEEP, Color(0, 0, 0, 0), 0, corner, 18.0))
		btn.add_theme_stylebox_override("disabled", UI.create_chamfer_card(Color(0.714, 0.733, 0.761, 1.0), Color(0, 0, 0, 0), 0, corner, 18.0))
		btn.add_theme_stylebox_override("focus", UI.create_button_style_focus())

	_reset_button.add_theme_font_override("font", UI.FONT_BOLD)
	_reset_button.add_theme_font_size_override("font_size", 19)
	var reset_normal := StyleBoxFlat.new()
	reset_normal.bg_color = Color.WHITE
	reset_normal.border_color = Color(0.769, 0.153, 0.11, 1.0)
	reset_normal.set_border_width_all(1)
	reset_normal.set_corner_radius_all(0)
	var reset_hover := reset_normal.duplicate()
	reset_hover.bg_color = Color(0.992, 0.941, 0.937, 1.0)
	_reset_button.add_theme_stylebox_override("normal", reset_normal)
	_reset_button.add_theme_stylebox_override("hover", reset_hover)
	_reset_button.add_theme_stylebox_override("pressed", reset_hover)
	_reset_button.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_reset_button.add_theme_color_override(state, Color(0.769, 0.153, 0.11, 1.0))


func _build_rows() -> void:
	for child in _item_list.get_children():
		child.queue_free()
	_rows.clear()

	for i in ShopData.GENERAL_UPGRADES.size():
		var upgrade: Dictionary = ShopData.GENERAL_UPGRADES[i]
		var row = ShopListRowScript.new()
		row.glyph = upgrade["glyph"]
		row.glyph_tint = upgrade["tint"]
		row.item_name = upgrade["name"]
		row.pressed.connect(_select.bind(i))
		_item_list.add_child(row)
		_rows.append(row)
	call_deferred("_setup_focus_neighbors")


# =============================================================================
# SELECTION / DETAIL
# =============================================================================

func _select(index: int, animate: bool = true) -> void:
	if animate and index != _selected_index:
		UISounds.play_select()
	_selected_index = index
	for i in _rows.size():
		_rows[i].set_selected(i == index)
	_refresh()


func _refresh() -> void:
	var upgrade: Dictionary = ShopData.GENERAL_UPGRADES[_selected_index]
	var level := _get_level(upgrade)
	var max_level: int = upgrade["max_level"]
	var is_maxed := level >= max_level

	for i in _rows.size():
		_rows[i].set_level_text("LV %02d" % _get_level(ShopData.GENERAL_UPGRADES[i]))

	_watermark.text = upgrade["glyph"]
	_name_label.text = str(upgrade["name"]).to_upper()
	_desc_label.text = str(upgrade["desc"]) + ". Applies to every Nikke, every run."
	_lv_now.text = "LV %02d" % level
	_lv_arrow.visible = not is_maxed
	_lv_next.visible = not is_maxed
	_lv_next.text = "LV %02d" % (level + 1)
	_cur_bonus.text = ShopData.format_bonus(upgrade, level)
	_next_bonus.text = ShopData.format_bonus(upgrade, level + 1)

	var bulk_count := mini(10, max_level - level)
	_cost10_cap.text = "NEXT %d COST" % bulk_count
	_cost10_label.text = "◆ %d" % _bulk_cost(upgrade, bulk_count)

	if is_maxed:
		_buy_button.text = "MAXED"
		_buy_button.disabled = true
		_buy10_button.visible = false
		%Cost10Cell.visible = false
		%NextCell.visible = false
		return
	%Cost10Cell.visible = true
	%NextCell.visible = true

	var cores := GameManager.get_pristine_cores()
	var cost1 := _calculate_upgrade_cost(upgrade["base_cost"], level)
	var bulk := _bulk_cost(upgrade, bulk_count)
	_buy_button.text = "◆ %d   BUY" % cost1
	_buy_button.disabled = cores < cost1
	_buy10_button.visible = bulk_count > 1
	_buy10_button.text = "◆ %d   ×%d" % [bulk, bulk_count]
	_buy10_button.disabled = cores < bulk


func _get_level(upgrade: Dictionary) -> int:
	return _upgrade_levels.get("general_" + str(upgrade["id"]), 0)


func _bulk_cost(upgrade: Dictionary, count: int) -> int:
	var level := _get_level(upgrade)
	var total := 0
	for i in count:
		total += _calculate_upgrade_cost(upgrade["base_cost"], level + i)
	return total


func _on_cores_changed(_value: int) -> void:
	_refresh()


# =============================================================================
# PURCHASE / RESET
# =============================================================================

func _buy_levels(count: int) -> void:
	var upgrade: Dictionary = ShopData.GENERAL_UPGRADES[_selected_index]
	var level := _get_level(upgrade)
	count = mini(count, int(upgrade["max_level"]) - level)
	if count <= 0:
		return
	var total := _bulk_cost(upgrade, count)
	if not GameManager.spend_pristine_cores(total):
		UISounds.play_back()
		return

	UISounds.play_confirm()
	var upgrade_id := "general_" + str(upgrade["id"])
	_upgrade_levels[upgrade_id] = level + count
	_cores_spent[GENERAL_FILTER] = _cores_spent.get(GENERAL_FILTER, 0) + total
	_save_shop_data()
	_refresh()
	print("[ShopMenu] Purchased %s x%d for %d cores (now level %d)" % [upgrade_id, count, total, level + count])


func _on_reset_pressed() -> void:
	if _active_popup:
		return
	var refund: int = _cores_spent.get(GENERAL_FILTER, 0)
	if refund <= 0:
		UISounds.play_back()
		return

	UISounds.play_select()
	var popup := NikkePopupScript.create("Reset all upgrades?", "Pristine core refund")
	popup.add_text("Refund ◆ %d Pristine Cores and reset every upgrade to LV 00?\nRefunds are always penalty-free." % refund)
	popup.add_button("CANCEL", "secondary").pressed.connect(popup.close)
	popup.add_button("REFUND", "danger").pressed.connect(func():
		popup.close()
		_do_refund()
	)
	_active_popup = popup
	popup.closed.connect(func():
		_active_popup = null
		call_deferred("_grab_initial_focus")
	)
	popup.open(self)


func _do_refund() -> void:
	var refund: int = _cores_spent.get(GENERAL_FILTER, 0)
	GameManager.add_pristine_cores(refund)

	var keys_to_remove: Array[String] = []
	for upgrade_id in _upgrade_levels.keys():
		if upgrade_id.begins_with("general_"):
			keys_to_remove.append(upgrade_id)
	for key in keys_to_remove:
		_upgrade_levels.erase(key)
	_cores_spent.erase(GENERAL_FILTER)

	_save_shop_data()
	UISounds.play_confirm()
	_refresh()
	print("[ShopMenu] Refunded %d cores for general upgrades" % refund)


# =============================================================================
# FOCUS
# =============================================================================

func _grab_initial_focus() -> void:
	if is_visible_in_tree() and _selected_index < _rows.size():
		_rows[_selected_index].grab_focus()


func _setup_focus_neighbors() -> void:
	for i in _rows.size():
		var row: Button = _rows[i]
		if i > 0:
			row.focus_neighbor_top = row.get_path_to(_rows[i - 1])
		if i < _rows.size() - 1:
			row.focus_neighbor_bottom = row.get_path_to(_rows[i + 1])
		else:
			row.focus_neighbor_bottom = row.get_path_to(_reset_button)
		row.focus_neighbor_right = row.get_path_to(_buy_button)
	if not _rows.is_empty():
		_reset_button.focus_neighbor_top = _reset_button.get_path_to(_rows[_rows.size() - 1])
		_buy_button.focus_neighbor_left = _buy_button.get_path_to(_rows[0])
	_buy_button.focus_neighbor_right = _buy_button.get_path_to(_buy10_button)
	_buy10_button.focus_neighbor_left = _buy10_button.get_path_to(_buy_button)


# =============================================================================
# PERSISTENCE
# =============================================================================

func _load_shop_data() -> void:
	var data: Dictionary = SaveManager.load_section("shop")

	# Start with default unlocked characters
	_unlocked_characters.clear()
	for char_id in CharacterRegistry.DEFAULT_UNLOCKED:
		_unlocked_characters.append(char_id)

	if not data.is_empty():
		var saved_unlocked = data.get("characters", {}).get("unlocked", [])
		for char_id in saved_unlocked:
			if char_id not in _unlocked_characters:
				_unlocked_characters.append(char_id)

		var saved_upgrades = data.get("upgrades", {})
		if saved_upgrades is Dictionary:
			for key in saved_upgrades:
				_upgrade_levels[key] = saved_upgrades[key]

		var saved_cores = data.get("cores_spent", {})
		if saved_cores is Dictionary:
			for key in saved_cores:
				_cores_spent[key] = saved_cores[key]

	print("[ShopMenu] Loaded shop data: %d characters unlocked, %d upgrades" % [_unlocked_characters.size(), _upgrade_levels.size()])


func _save_shop_data() -> void:
	# Save unlocked characters (excluding defaults to save space)
	var extra_unlocked: Array = []
	for char_id in _unlocked_characters:
		if char_id not in CharacterRegistry.DEFAULT_UNLOCKED:
			extra_unlocked.append(char_id)

	var data := {
		"characters": {
			"unlocked": extra_unlocked
		},
		"upgrades": _upgrade_levels,
		"cores_spent": _cores_spent
	}

	var err := SaveManager.save_section("shop", data)
	if err == OK:
		invalidate_upgrade_cache()
	else:
		push_error("[ShopMenu] Failed to save shop data: %d" % err)


# =============================================================================
# STATIC API (used across gameplay code - keep signatures stable)
# =============================================================================

## Get total bonus for an upgrade type (for use by game systems)
static func get_upgrade_bonus(upgrade_type: String) -> float:
	var data := SaveManager.load_section("shop")
	if data.is_empty():
		return 0.0

	var level: int = data.get("upgrades", {}).get("general_" + upgrade_type, 0)

	match upgrade_type:
		"atk":
			return level * 0.25 # +25% per level
		"hp":
			return float(level) # +1 HP per level
		"speed":
			return level * 0.05 # +5% per level
		"crit":
			return level * 0.02 # +2% per level
		"pickup":
			return level * 0.10 # +10% per level
		"xp":
			return level * 0.05 # +5% per level

	return 0.0


## Check if a character is unlocked
static func is_character_unlocked(char_id: String) -> bool:
	if char_id in CharacterRegistry.DEFAULT_UNLOCKED:
		return true

	var data := SaveManager.load_section("shop")
	if data.is_empty():
		return false

	var unlocked = data.get("characters", {}).get("unlocked", [])
	return char_id in unlocked


## Persist a character unlock (called from the character select storefront).
## Preserves the rest of the shop save section.
static func unlock_character(char_id: String) -> bool:
	var data := SaveManager.load_section("shop")
	var chars: Dictionary = data.get("characters", {})
	var unlocked: Array = chars.get("unlocked", [])
	if char_id not in unlocked:
		unlocked.append(char_id)
	chars["unlocked"] = unlocked
	data["characters"] = chars
	return SaveManager.save_section("shop", data) == OK


## Check if a character-specific signature upgrade is active.
## Phase 3 rework: these are now run-only talents, so this reads the current
## run's talent tree instead of persistent shop purchases. The name is kept
## because ~30 call sites (projectiles, controllers) use it as the lookup API.
static func has_character_upgrade(char_id: String, upgrade_id: String) -> bool:
	var tree := TalentTree.instance
	if tree == null:
		return false

	var registry := CharacterRegistry.get_instance()
	if registry == null:
		return false

	var char_index: int = registry.get_character_index(char_id)
	if char_index < 0:
		return false

	return tree.get_talent_level(char_index, upgrade_id) > 0


## Kept for compatibility; talent state needs no cache invalidation
static func invalidate_upgrade_cache() -> void:
	pass


## Calculate upgrade cost - linear for first 10 levels, then doubles each level after
static func _calculate_upgrade_cost(base_cost: int, current_level: int) -> int:
	if current_level < 10:
		return base_cost + current_level
	else:
		var levels_past_10 := current_level - 10
		var doubling_cost := 11 * int(pow(2, levels_past_10))
		return doubling_cost
