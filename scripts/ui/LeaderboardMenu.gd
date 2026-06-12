extends Control
class_name LeaderboardMenu
## Leaderboards - NIKKE "operator gallery" (light admin register, approved
## mockup docs/mockups/leaderboard_v2.html variant E). Every operator gets a
## ranked record card (best run each, NO DATA grayed); clicking one shows the
## run in the always-visible detail pane (replaces the old stats popup).
## Static chrome lives in LeaderboardMenu.tscn; cards are data-driven.

signal back_requested

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")
const OperatorRecordCardScript := preload("res://scripts/ui/components/OperatorRecordCard.gd")

const CARD_SIZE := Vector2(297, 255)

# Per-character vertical face anchor for the card art band (portrait-sq crops
# put faces at slightly different heights). Higher = crop sits lower on the
# image. Tuned by eye against the live screen.
const FACE_FOCUS_DEFAULT := 0.38
const FACE_FOCUS_OVERRIDES := {
	"commander": 0.30, "wells": 0.30,
	"kilo": 0.46, "nayuta": 0.52, "rapunzel": 0.46, "marian": 0.46,
}

# Horizontal focus for the detail art strip — subjects that stand off-center
# in their burst art (window slides toward them so they center in the strip).
const DETAIL_FOCUS_X_DEFAULT := 0.5
const DETAIL_FOCUS_X_OVERRIDES := {
	"wells": 0.57, "cecil": 0.58,
}

var _records: Array = []   # ordered card data dictionaries
var _cards: Array = []     # OperatorRecordCard instances
var _selected_index := 0

@onready var _header_title: Label = %HeaderTitle
@onready var _header_sub: Label = %HeaderSub
@onready var _back_button: Button = %BackButton
@onready var _grid: GridContainer = %CardGrid
@onready var _empty_state: Label = %EmptyStateLabel
@onready var _detail_panel: Panel = %DetailPanel
# CoverArtRect (untyped: class_name indexing lags fresh files)
@onready var _detail_art = %DetailArt
@onready var _detail_name: Label = %DetailName
@onready var _detail_rank: Label = %DetailRank
@onready var _kv_list: VBoxContainer = %KvList
@onready var _no_data_label: Label = %NoDataLabel
@onready var _gf_band: PanelContainer = %GfBand
@onready var _gf_label: Label = %GfLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_style_chrome()
	_build_records()
	_build_cards()

	_back_button.pressed.connect(func():
		UISounds.play_back()
		back_requested.emit()
	)

	if _cards.is_empty():
		_empty_state.visible = true
		_detail_panel.visible = false
	else:
		_select(0, false)
	call_deferred("_grab_initial_focus")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		UISounds.play_back()
		back_requested.emit()
		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()


# =============================================================================
# CHROME
# =============================================================================

func _style_chrome() -> void:
	UI.style_header_label(_header_title, 56, UI.ADMIN_TEXT)
	UI.style_subtitle_label(_header_sub, 17, UI.ADMIN_TEXT_DIM)
	_detail_panel.add_theme_stylebox_override("panel", UI.create_admin_card_style())

	_detail_name.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_detail_name.add_theme_font_size_override("font_size", 44)
	_detail_name.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	UI.style_subtitle_label(_detail_rank, 14, UI.ACCENT_CYAN_DEEP)

	_empty_state.add_theme_font_override("font", UI.FONT_BOLD)
	_empty_state.add_theme_font_size_override("font_size", 27)
	_empty_state.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)
	_no_data_label.add_theme_font_override("font", UI.FONT_BOLD)
	_no_data_label.add_theme_font_size_override("font_size", 21)
	_no_data_label.add_theme_color_override("font_color", UI.ADMIN_TEXT_DIM)

	var band_style := StyleBoxFlat.new()
	band_style.bg_color = Color(0.91, 0.224, 0.18, 0.06)
	band_style.border_color = Color(0.91, 0.224, 0.18, 0.55)
	band_style.set_border_width_all(1)
	band_style.set_corner_radius_all(0)
	band_style.content_margin_top = 15
	band_style.content_margin_bottom = 15
	_gf_band.add_theme_stylebox_override("panel", band_style)
	_gf_label.add_theme_font_override("font", UI.FONT_BOLD)
	_gf_label.add_theme_font_size_override("font_size", 15)
	_gf_label.add_theme_color_override("font_color", Color(0.769, 0.153, 0.11, 1.0))


# =============================================================================
# DATA
# =============================================================================

func _build_records() -> void:
	_records.clear()
	var registry = CharacterRegistry.get_instance()
	if registry == null:
		return

	var entries: Array = []
	if GameManager and GameManager.has_method("get_leaderboard_entries"):
		entries = GameManager.get_leaderboard_entries(99)

	var entry_by_code: Dictionary = {}
	for entry in entries:
		entry_by_code[String(entry.get("code", ""))] = entry

	var ranked: Array = []
	var unranked: Array = []
	for char_id in registry.get_all_character_ids():
		var data = registry.get_character(char_id)
		var display_name: String = data.display_name if data else str(char_id).capitalize()
		var entry: Dictionary = entry_by_code.get(char_id, {})
		var record := {
			"code": char_id,
			"display_name": display_name,
			"score": int(entry.get("best_score", 0)),
			"wave": int(entry.get("best_wave", 0)),
			"difficulty": int(entry.get("best_difficulty", 1)),
			"goddess_fall": bool(entry.get("best_goddess_fall", false)),
			"timestamp": int(entry.get("timestamp", 0)),
		}
		if record["score"] > 0:
			ranked.append(record)
		else:
			unranked.append(record)

	ranked.sort_custom(func(a, b): return a["score"] > b["score"])
	_records = ranked + unranked


## Cards want the face-framed square crop; the big detail pane wants the
## dramatic burst art (top-biased by CoverArtRect so faces stay in frame).
const CARD_ART_PRIORITY := ["portrait-sq.png", "portrait.png", "burst.png"]
const DETAIL_ART_PRIORITY := ["burst.png", "portrait-sq.png", "portrait.png"]


func _resolve_art(code: String, priority: Array) -> Texture2D:
	var folder := code.replace("_", "-")
	for file in priority:
		var path := "res://assets/characters/%s/%s" % [folder, file]
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				return tex
	return null


# =============================================================================
# CARDS / SELECTION
# =============================================================================

func _build_cards() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()

	for i in _records.size():
		var record: Dictionary = _records[i]
		var card = OperatorRecordCardScript.new()
		card.custom_minimum_size = CARD_SIZE
		card.display_name = record["display_name"]
		card.rank = (i + 1) if record["score"] > 0 else 0
		card.best_score = record["score"]
		card.best_wave = record["wave"]
		card.best_difficulty = record["difficulty"]
		card.goddess_fall = record["goddess_fall"]
		card.art = _resolve_art(record["code"], CARD_ART_PRIORITY)
		card.face_focus = FACE_FOCUS_OVERRIDES.get(record["code"], FACE_FOCUS_DEFAULT)
		card.pressed.connect(_on_card_pressed.bind(i))
		_grid.add_child(card)
		_cards.append(card)
	call_deferred("_setup_focus_neighbors")


func _on_card_pressed(index: int) -> void:
	if index != _selected_index:
		UISounds.play_select()
	_select(index, true)


func _select(index: int, _animate: bool) -> void:
	_selected_index = index
	for i in _cards.size():
		_cards[i].set_selected(i == index)
	_refresh_detail()


func _refresh_detail() -> void:
	var record: Dictionary = _records[_selected_index]
	var has_data: bool = record["score"] > 0

	_detail_art.texture = _resolve_art(record["code"], DETAIL_ART_PRIORITY)
	_detail_art.focus_x = DETAIL_FOCUS_X_OVERRIDES.get(record["code"], DETAIL_FOCUS_X_DEFAULT)
	_detail_name.text = str(record["display_name"]).to_upper()
	# Long names (SNOW WHITE, COMMANDER) shrink to stay clear of the panel edge
	var name_length := _detail_name.text.length()
	var name_size := 44
	if name_length > 10:
		name_size = 30
	elif name_length > 7:
		name_size = 36
	_detail_name.add_theme_font_size_override("font_size", name_size)
	_detail_rank.text = ("RANK %02d // BEST SORTIE" % (_selected_index + 1)) if has_data else "UNRANKED"

	for child in _kv_list.get_children():
		child.queue_free()
	_no_data_label.visible = not has_data
	_gf_band.visible = has_data and record["goddess_fall"]
	if not has_data:
		return

	_add_kv_row("SCORE", _format_full_number(record["score"]))
	_add_kv_row("WAVE REACHED", str(record["wave"]))
	_add_kv_row("DIFFICULTY", "×%d" % record["difficulty"])
	_add_kv_row("DATE", _format_date(record["timestamp"]))


## Stacked caption-over-value block (narrow column beside the art strip)
func _add_kv_row(key: String, value: String) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var key_label := Label.new()
	key_label.text = key
	UI.style_subtitle_label(key_label, 13, UI.ADMIN_TEXT_DIM)
	block.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	value_label.add_theme_font_size_override("font_size", 34)
	value_label.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	block.add_child(value_label)

	_kv_list.add_child(block)

	var hairline := ColorRect.new()
	hairline.custom_minimum_size = Vector2(0, 1)
	hairline.color = UI.ADMIN_HAIRLINE
	hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kv_list.add_child(hairline)


# =============================================================================
# FOCUS
# =============================================================================

func _grab_initial_focus() -> void:
	if not _cards.is_empty():
		_cards[_selected_index].grab_focus()
	elif _back_button:
		_back_button.grab_focus()


func _setup_focus_neighbors() -> void:
	var cols := _grid.columns
	for i in _cards.size():
		var card: Button = _cards[i]
		var col := i % cols
		if col > 0:
			card.focus_neighbor_left = card.get_path_to(_cards[i - 1])
		if col < cols - 1 and i + 1 < _cards.size():
			card.focus_neighbor_right = card.get_path_to(_cards[i + 1])
		if i - cols >= 0:
			card.focus_neighbor_top = card.get_path_to(_cards[i - cols])
		else:
			card.focus_neighbor_top = card.get_path_to(_back_button)
		if i + cols < _cards.size():
			card.focus_neighbor_bottom = card.get_path_to(_cards[i + cols])
	if not _cards.is_empty():
		_back_button.focus_neighbor_bottom = _back_button.get_path_to(_cards[0])


# =============================================================================
# FORMATTING
# =============================================================================

func _format_full_number(value: int) -> String:
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return result


func _format_date(timestamp: int) -> String:
	if timestamp <= 0:
		return "--"
	var date := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d" % [date.year, date.month, date.day]
