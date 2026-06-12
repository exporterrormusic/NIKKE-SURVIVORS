extends Control
class_name AchievementsMenu
## Achievements - NIKKE "commendations" screen (light admin register, approved
## mockup docs/mockups/achievements_v3.html variant W2). Left: category rail
## (GENERAL + one row per operator, portrait + n/m count + completion
## underbar). Right: white card with ghost burst art behind the medal rows
## (~22% strength), oblique category title, ALL/COMPLETE/INCOMPLETE filter.
## Static chrome lives in AchievementsMenu.tscn; rows are data-driven.

signal back_requested

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")
const AchievementRailRowScript := preload("res://scripts/ui/components/AchievementRailRow.gd")
const AchievementRowScript := preload("res://scripts/ui/components/AchievementRow.gd")
const ShopMenuScript := preload("res://scripts/ui/ShopMenu.gd")

const GENERAL_FILTER := "GENERAL"
const FILTERS := ["ALL", "COMPLETE", "INCOMPLETE"]

var _registry: CharacterRegistry = null
var _achievements: Array[Dictionary] = []
var _selected_category: String = GENERAL_FILTER
var _completion_filter: String = "ALL"
var _rail_rows: Dictionary = {}      # category code -> AchievementRailRow
var _rail_order: Array[String] = []
var _filter_group := ButtonGroup.new()
var _focus_in_content := false

@onready var _header_title: Label = %HeaderTitle
@onready var _header_sub: Label = %HeaderSub
@onready var _back_button: Button = %BackButton
@onready var _rail_list: VBoxContainer = %RailList
@onready var _content_panel: Panel = %ContentPanel
@onready var _ghost_art = %GhostArt  # CoverArtRect (untyped: indexing lag)
@onready var _ghost_fade: TextureRect = %GhostFade
@onready var _cat_title: Label = %CatTitle
@onready var _cat_sub: Label = %CatSub
@onready var _filter_buttons: Dictionary = {
	"ALL": %FilterAll, "COMPLETE": %FilterComplete, "INCOMPLETE": %FilterIncomplete,
}
@onready var _ach_scroll: ScrollContainer = %AchScroll
@onready var _ach_list: VBoxContainer = %AchList
@onready var _empty_label: Label = %EmptyLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_registry = CharacterRegistry.get_instance()

	_load_achievements()
	_style_chrome()
	_build_rail()
	_setup_filters()

	_back_button.pressed.connect(func():
		UISounds.play_back()
		back_requested.emit()
	)

	_select_category(GENERAL_FILTER)
	call_deferred("_grab_initial_focus")


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		UISounds.play_back()
		# Two-stage back: content focus returns to the rail first
		if _focus_in_content:
			_focus_in_content = false
			_grab_initial_focus()
		else:
			back_requested.emit()


# =============================================================================
# DATA
# =============================================================================

func _load_achievements() -> void:
	_achievements = []
	if has_node("/root/AchievementManager"):
		var manager = get_node("/root/AchievementManager")
		for ach in manager.get_all_achievements():
			_achievements.append(ach)


func _filtered_for(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for achievement in _achievements:
		var ach_category: String = achievement.get("category", GENERAL_FILTER)
		if category == GENERAL_FILTER:
			if ach_category == GENERAL_FILTER:
				result.append(achievement)
		elif ach_category.to_lower() == category.to_lower():
			result.append(achievement)
	return result


func _counts_for(category: String) -> Vector2i:
	var filtered := _filtered_for(category)
	var unlocked := 0
	for achievement in filtered:
		if achievement.get("unlocked", false):
			unlocked += 1
	return Vector2i(unlocked, filtered.size())


# =============================================================================
# CHROME / RAIL / FILTERS
# =============================================================================

func _style_chrome() -> void:
	UI.style_header_label(_header_title, 56, UI.ADMIN_TEXT)
	UI.style_subtitle_label(_header_sub, 17, UI.ADMIN_TEXT_DIM)
	_content_panel.add_theme_stylebox_override("panel", UI.create_admin_card_style())

	_cat_title.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_cat_title.add_theme_font_size_override("font_size", 45)
	_cat_title.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	UI.style_subtitle_label(_cat_sub, 16, UI.ADMIN_TEXT_DIM)

	_empty_label.add_theme_font_override("font", UI.FONT_BOLD)
	_empty_label.add_theme_font_size_override("font_size", 24)
	_empty_label.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)


func _build_rail() -> void:
	for child in _rail_list.get_children():
		child.queue_free()
	_rail_rows.clear()
	_rail_order.clear()

	_add_rail_row(GENERAL_FILTER, "GENERAL", null, false)

	if _registry == null:
		return
	for char_id in _registry.get_all_character_ids():
		var data = _registry.get_character(char_id)
		var display_name: String = data.display_name if data else str(char_id).capitalize()
		var portrait: Texture2D = null
		var portrait_path := "res://assets/characters/%s/portrait-sq.png" % char_id.replace("_", "-")
		if ResourceLoader.exists(portrait_path):
			portrait = load(portrait_path)
		var is_locked := not ShopMenuScript.is_character_unlocked(char_id)
		_add_rail_row(char_id, display_name, portrait, is_locked)

	_refresh_rail_counts()
	call_deferred("_setup_rail_focus")


func _add_rail_row(code: String, display_name: String, portrait: Texture2D, is_locked: bool) -> void:
	var row = AchievementRailRowScript.new()
	row.category_name = display_name
	row.portrait = portrait
	row.is_locked = is_locked
	row.pressed.connect(_on_rail_pressed.bind(code))
	_rail_list.add_child(row)
	_rail_rows[code] = row
	_rail_order.append(code)


func _refresh_rail_counts() -> void:
	for code in _rail_rows:
		var counts := _counts_for(code)
		_rail_rows[code].set_counts(counts.x, counts.y)


func _setup_filters() -> void:
	for filter_name in FILTERS:
		var btn: Button = _filter_buttons[filter_name]
		btn.button_group = _filter_group
		btn.custom_minimum_size.y = 57
		btn.add_theme_font_override("font", UI.FONT_BOLD)
		btn.add_theme_font_size_override("font_size", 18)
		var idle := StyleBoxFlat.new()
		idle.bg_color = Color.WHITE
		idle.border_color = Color(0.784, 0.804, 0.827, 1.0)
		idle.set_border_width_all(1)
		idle.set_corner_radius_all(0)
		var selected_style := StyleBoxFlat.new()
		selected_style.bg_color = UI.ADMIN_TEXT
		selected_style.set_corner_radius_all(0)
		var hover := idle.duplicate()
		hover.border_color = UI.ACCENT_CYAN_DEEP
		btn.add_theme_stylebox_override("normal", idle)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", selected_style)
		btn.add_theme_stylebox_override("hover_pressed", selected_style)
		btn.add_theme_stylebox_override("focus", UI.create_button_style_focus())
		btn.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", UI.ADMIN_TEXT)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		btn.add_theme_color_override("font_focus_color", UI.ADMIN_TEXT_DIM)
		btn.pressed.connect(_on_filter_pressed.bind(filter_name))


func _on_filter_pressed(filter_name: String) -> void:
	UISounds.play_select()
	_completion_filter = filter_name
	_focus_in_content = true
	_rebuild_list()


func _on_rail_pressed(code: String) -> void:
	if code != _selected_category:
		UISounds.play_select()
	_focus_in_content = false
	_select_category(code)


# =============================================================================
# CONTENT
# =============================================================================

func _select_category(code: String) -> void:
	_selected_category = code
	for rail_code in _rail_rows:
		_rail_rows[rail_code].set_selected(rail_code == code)

	# Ghost burst art behind the list (GENERAL has no operator art)
	if code == GENERAL_FILTER:
		_ghost_art.visible = false
		_ghost_fade.visible = false
	else:
		var burst_path := "res://assets/characters/%s/burst.png" % code.replace("_", "-")
		if ResourceLoader.exists(burst_path):
			_ghost_art.texture = load(burst_path)
			_ghost_art.visible = true
			_ghost_fade.visible = true
		else:
			_ghost_art.visible = false
			_ghost_fade.visible = false

	var display := "GENERAL"
	if code != GENERAL_FILTER and _registry:
		var data = _registry.get_character(code)
		if data:
			display = str(data.display_name).to_upper()
	_cat_title.text = display

	_rebuild_list()


func _rebuild_list() -> void:
	for child in _ach_list.get_children():
		child.queue_free()

	var counts := _counts_for(_selected_category)
	_cat_sub.text = "%d OF %d COMMENDATIONS EARNED" % [counts.x, counts.y]

	var filtered := _filtered_for(_selected_category)
	if _completion_filter == "COMPLETE":
		filtered = filtered.filter(func(a): return a.get("unlocked", false))
	elif _completion_filter == "INCOMPLETE":
		filtered = filtered.filter(func(a): return not a.get("unlocked", false))

	# Unlocked first, then by progress percentage
	filtered.sort_custom(func(a, b):
		if a.unlocked != b.unlocked:
			return a.unlocked
		var prog_a: float = float(a.progress) / float(max(a.target, 1))
		var prog_b: float = float(b.progress) / float(max(b.target, 1))
		return prog_a > prog_b
	)

	_empty_label.visible = filtered.is_empty()

	for achievement in filtered:
		var row = AchievementRowScript.new()
		row.title = achievement.get("title", "")
		row.description = achievement.get("desc", "")
		row.unlocked = achievement.get("unlocked", false)
		row.progress = achievement.get("progress", 0)
		row.target = achievement.get("target", 1)
		row.focus_entered.connect(func(): _focus_in_content = true)
		_ach_list.add_child(row)

	if _ach_scroll:
		_ach_scroll.set_deferred("scroll_vertical", 0)


# =============================================================================
# FOCUS
# =============================================================================

func _grab_initial_focus() -> void:
	if not _rail_order.is_empty():
		var row = _rail_rows.get(_selected_category, _rail_rows[_rail_order[0]])
		row.grab_focus()


func _setup_rail_focus() -> void:
	for i in _rail_order.size():
		var row: Button = _rail_rows[_rail_order[i]]
		if i > 0:
			row.focus_neighbor_top = row.get_path_to(_rail_rows[_rail_order[i - 1]])
		if i < _rail_order.size() - 1:
			row.focus_neighbor_bottom = row.get_path_to(_rail_rows[_rail_order[i + 1]])
		row.focus_neighbor_right = row.get_path_to(_filter_buttons["ALL"])
