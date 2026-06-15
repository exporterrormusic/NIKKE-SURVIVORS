extends Control
class_name TalentTree

## Talent Tree - NIKKE in-run overlay (dark field register, approved mockup
## docs/mockups/talent_tree_v3.html variant C3a). Shows the run character's
## tree. Opens on level up (and TAB).
##
## Layout: ability lanes - SPECIAL and BURST roots in a left column, their two
## mods stacked to the right connected by elbow split edges (no arrowheads);
## vertical gate edges down the left column (special -> burst -> capstone)
## carry arrowheads. Signature talent (no prerequisite) sits bottom-right.
## Nodes use the HUD bracket vocabulary; edges light cyan when the
## prerequisite is owned.

signal talent_unlocked(character_id: int, talent_id: String)
signal tree_closed

## The run's tree instance (set while a run is active). Used by
## ShopMenu.has_character_upgrade so gameplay code can query talent state.
static var instance: TalentTree = null

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")
const TalentData = preload("res://scripts/ui/TalentData.gd")

var TALENT_DATA := TalentData.TALENT_DATA

# Character data - loaded from CharacterRegistry
var CHARACTER_NAMES: Array[String] = []
var _character_registry = null
var _game_state = null

# The run's selected character (registry index)
var _run_character: int = 0 # Default: Snow White

# UI references
var _header_sub: Label = null
var _sp_value: Label = null
var _stats_panel: PanelContainer = null
var _tree_panel: Control = null # Tree holder (nodes + lines live here)
var _player_ref: Node = null # Reference to player for stats
var _char_label: Label = null
var _level_label: Label = null
var _portrait: TextureRect = null
var _stat_rows: Dictionary = {} # row name -> {"value": Label, "bonus": Label}
var _hidden_ui: Array = [] # HUD layers/controls hidden while the tree is open

# Player's unlocked talents (run-only, reset every run)
var _unlocked_talents: Dictionary = {0: {}, 1: {}, 2: {}, 3: {}, 4: {}, 5: {}, 6: {}, 7: {}, 8: {}, 9: {}, 10: {}}
var _skill_points: int = 0: set = set_skill_points
var _talent_buttons: Array = []
var _lines_control: Control = null

# Three trees per character, tab-swapped. Opens on the Default (attack) tree.
const TREE_TABS := [["attack", "ATTACK"], ["skill", "SKILL"], ["burst", "BURST"]]
var _active_tree: String = "attack"
var _tab_buttons: Dictionary = {}

# Open/close fade
var _anim_state := 0 # 0=hidden, 1=animating in, 2=showing, 3=animating out
var _anim_progress := 0.0
const ANIM_DURATION := 0.3
var _pending_unpause := false

# Preview mode: opened from the character-select screen as a read-only,
# centered modal. No pause, no HUD hiding, no skill-point spending — it just
# renders the unit's tree for browsing. Set via configure_preview() BEFORE the
# node enters the scene tree.
var _preview_mode := false
var _preview_char := -1

# ============================================================================
# Node geometry (mockup 1280x720 values x1.5 for the 1920x1080 viewport)
# ============================================================================
const ROOT_X := 36.0
const ROOT_W := 420.0
const MOD_X := 663.0
const MOD_W := 525.0
const NODE_H := 126.0
# Vertical layout compressed to fit the tree box below the tab band (box is
# 720px tall: y234..954). Content spans y9..711 with balanced 9px padding.
const SPECIAL_ROOT_Y := 78.0
const SPECIAL_MOD_YS := [9.0, 147.0]
const BURST_ROOT_Y := 366.0
const BURST_MOD_YS := [297.0, 435.0]
const SIG_Y := 585.0


func _ready() -> void:
	# A preview must not clobber the run's live tree instance (gameplay queries
	# read the static `instance`).
	if not _preview_mode:
		instance = self
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Ensure TalentTree is rendered above all other UI
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS # Process during pause

	_load_character_data()
	if _preview_mode and _preview_char >= 0:
		_run_character = _preview_char
	_apply_start_unlocked()
	if _preview_mode:
		_build_preview_ui()
	else:
		_build_ui()
	visible = false


## Pre-unlock talents flagged "start_unlocked" (e.g. a character's basic attack,
## which is always available and acts as the root prerequisite for its tree).
func _apply_start_unlocked() -> void:
	for char_id in TALENT_DATA:
		for talent in TALENT_DATA[char_id]:
			if talent.get("start_unlocked", false):
				if not _unlocked_talents.has(char_id):
					_unlocked_talents[char_id] = {}
				_unlocked_talents[char_id][talent["id"]] = 1


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _load_character_data() -> void:
	_character_registry = CharacterRegistry.get_instance()

	var game_state_node = get_node_or_null("/root/GameManager")
	if game_state_node:
		_game_state = game_state_node
		_run_character = _game_state.player_character_index

	if _character_registry:
		var char_ids: Array = _character_registry.get_all_character_ids()
		for id in char_ids:
			var char_data = _character_registry.get_character(id)
			if char_data:
				CHARACTER_NAMES.append(char_data.display_name)
	else:
		CHARACTER_NAMES = ["Snow White", "Scarlet", "Rapunzel", "Nayuta", "Commander", "Marian", "Crown", "Kilo", "Cecil", "Sin", "Wells"]


# ============================================================================
# CHROME
# ============================================================================

func _build_ui() -> void:
	# Full screen dim
	var dim := ColorRect.new()
	dim.color = Color(0.027, 0.039, 0.055, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Header (top-left)
	var title := Label.new()
	title.text = "TALENTS"
	title.position = Vector2(81, 39)
	title.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	title.add_theme_font_size_override("font_size", 63)
	title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	add_child(title)

	_header_sub = Label.new()
	_header_sub.text = "NIKKE // OPERATIVE"
	_header_sub.position = Vector2(84, 117)
	UI.style_subtitle_label(_header_sub, 16, Color(1, 1, 1, 0.65))
	add_child(_header_sub)

	var bar := ColorRect.new()
	bar.color = UI.ACCENT_CYAN
	bar.position = Vector2(84, 150)
	bar.size = Vector2(81, 4)
	add_child(bar)

	# Skill points chip (top-right)
	var sp_chip := PanelContainer.new()
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(1.0, 0.824, 0.247, 0.12)
	chip_style.border_color = UI.ACCENT_SECONDARY
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(0)
	chip_style.content_margin_left = 30
	chip_style.content_margin_right = 30
	chip_style.content_margin_top = 12
	chip_style.content_margin_bottom = 12
	sp_chip.add_theme_stylebox_override("panel", chip_style)
	sp_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sp_chip.position = Vector2(-360, 51)
	sp_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(sp_chip)
	sp_chip.offset_left = -360
	sp_chip.offset_top = 51
	sp_chip.offset_right = -81

	var sp_col := VBoxContainer.new()
	sp_col.add_theme_constant_override("separation", 0)
	sp_chip.add_child(sp_col)

	var sp_cap := Label.new()
	sp_cap.text = "SKILL POINTS"
	UI.style_subtitle_label(sp_cap, 14, UI.ACCENT_SECONDARY)
	sp_col.add_child(sp_cap)

	_sp_value = Label.new()
	_sp_value.text = "0"
	_sp_value.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_sp_value.add_theme_font_size_override("font_size", 39)
	_sp_value.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)
	sp_col.add_child(_sp_value)

	# Stats panel (left)
	_stats_panel = _build_stats_panel()
	add_child(_stats_panel)

	# Tree panel (right)
	var treewrap := PanelContainer.new()
	var wrap_style := StyleBoxFlat.new()
	wrap_style.bg_color = Color(0.039, 0.051, 0.071, 0.55)
	wrap_style.border_color = Color(1, 1, 1, 0.12)
	wrap_style.set_border_width_all(1)
	wrap_style.set_corner_radius_all(0)
	wrap_style.set_content_margin_all(0)
	treewrap.add_theme_stylebox_override("panel", wrap_style)
	treewrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	treewrap.offset_left = 594
	treewrap.offset_top = 234
	treewrap.offset_right = -81
	treewrap.offset_bottom = -126
	add_child(treewrap)

	_tree_panel = Control.new()
	_tree_panel.name = "TreeHolder"
	treewrap.add_child(_tree_panel)
	_build_tree_view(_run_character)

	# Tab bar (ATTACK / SKILL / BURST) seated on the tree box's top edge
	_build_tab_bar()

	# Close chip (bottom-right, plain rect - no chamfer on close buttons)
	var close_btn := Button.new()
	close_btn.text = ""
	close_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	close_btn.offset_left = -291
	close_btn.offset_top = -96
	close_btn.offset_right = -81
	close_btn.offset_bottom = -39
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = Color(0.078, 0.094, 0.122, 0.86)
	close_normal.border_color = Color(1, 1, 1, 0.18)
	close_normal.set_border_width_all(1)
	close_normal.set_corner_radius_all(0)
	var close_hover := close_normal.duplicate()
	close_hover.border_color = UI.ACCENT_CYAN
	close_btn.add_theme_stylebox_override("normal", close_normal)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_stylebox_override("pressed", close_hover)
	close_btn.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	close_btn.pressed.connect(_on_close)
	add_child(close_btn)

	var close_row := HBoxContainer.new()
	close_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_row.offset_left = 33
	close_row.offset_right = -33
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	close_row.add_theme_constant_override("separation", 15)
	close_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close_btn.add_child(close_row)

	var close_label := Label.new()
	close_label.text = "CLOSE"
	close_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	close_label.add_theme_font_size_override("font_size", 26)
	close_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	close_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	close_label.size_flags_vertical = Control.SIZE_FILL
	close_row.add_child(close_label)

	var close_hint := Label.new()
	close_hint.text = "ESC"
	UI.style_subtitle_label(close_hint, 15, Color(1, 1, 1, 0.45))
	close_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	close_hint.size_flags_vertical = Control.SIZE_FILL
	close_row.add_child(close_hint)


# ============================================================================
# PREVIEW WINDOW (character-select read-only modal)
# ============================================================================

## Compact, centered modal: dark scrim + a single window card holding the
## header, the ATTACK/SKILL/BURST tab band, and the tree box. No stats panel
## and no skill-point chrome — purely a browse view of the unit's tree, styled
## to match the in-run overlay (dark register, cyan-accented tabs).
func _build_preview_ui() -> void:
	const BOX_W := 1245.0
	const BOX_H := 720.0
	const TAB_H := 54.0

	# This overlay is added to the menu at runtime, where full-rect anchors can
	# resolve to a zero-size rect for a frame (collapsing the scrim and
	# mis-centering the window). Pin it to the viewport explicitly.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	position = Vector2.ZERO

	# Dim scrim — click anywhere outside the card to dismiss.
	var scrim := ColorRect.new()
	scrim.color = Color(0.012, 0.02, 0.031, 0.78)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_on_close()
	)
	add_child(scrim)

	# Center the window card on screen (robust to runtime resize timing).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.043, 0.055, 0.075, 0.99)
	card_style.border_color = Color(1, 1, 1, 0.16)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(0)
	card_style.content_margin_left = 36
	card_style.content_margin_right = 36
	card_style.content_margin_top = 30
	card_style.content_margin_bottom = 30
	card_style.shadow_color = Color(0, 0, 0, 0.55)
	card_style.shadow_size = 28
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	card.add_child(outer)

	# --- Header: title block (left) + close (right) ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	outer.add_child(header)

	var titlecol := VBoxContainer.new()
	titlecol.add_theme_constant_override("separation", 2)
	titlecol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titlecol)

	var title := Label.new()
	title.text = "TALENTS"
	title.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	titlecol.add_child(title)

	var char_name: String = CHARACTER_NAMES[_run_character] if _run_character >= 0 and _run_character < CHARACTER_NAMES.size() else "OPERATIVE"
	_header_sub = Label.new()
	_header_sub.text = "NIKKE // %s" % char_name.to_upper()
	UI.style_subtitle_label(_header_sub, 15, Color(1, 1, 1, 0.65))
	titlecol.add_child(_header_sub)

	var close_btn := Button.new()
	close_btn.text = "✕  CLOSE"
	close_btn.custom_minimum_size = Vector2(160, 52)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	close_btn.add_theme_font_size_override("font_size", 22)
	var c_normal := StyleBoxFlat.new()
	c_normal.bg_color = Color(0.078, 0.094, 0.122, 0.86)
	c_normal.border_color = Color(1, 1, 1, 0.18)
	c_normal.set_border_width_all(1)
	c_normal.set_corner_radius_all(0)
	var c_hover := c_normal.duplicate()
	c_hover.border_color = UI.ACCENT_CYAN
	close_btn.add_theme_stylebox_override("normal", c_normal)
	close_btn.add_theme_stylebox_override("hover", c_hover)
	close_btn.add_theme_stylebox_override("pressed", c_hover)
	close_btn.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		close_btn.add_theme_color_override(st, UI.TEXT_PRIMARY)
	close_btn.pressed.connect(_on_close.bind(false))
	header.add_child(close_btn)

	# --- Tabs + tree, flush together (mirrors the in-run overlay) ---
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	outer.add_child(stack)

	var bar := HBoxContainer.new()
	bar.name = "TabBar"
	bar.custom_minimum_size = Vector2(BOX_W, TAB_H)
	bar.add_theme_constant_override("separation", 0)
	stack.add_child(bar)

	var group := ButtonGroup.new()
	_tab_buttons.clear()
	for tab in TREE_TABS:
		var key: String = tab[0]
		var btn := Button.new()
		btn.text = tab[1]
		btn.toggle_mode = true
		btn.button_group = group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
		btn.add_theme_font_size_override("font_size", 28)
		_style_tab_button(btn)
		btn.pressed.connect(_on_tab_selected.bind(key))
		bar.add_child(btn)
		_tab_buttons[key] = btn
	_update_tab_visuals()

	# Tree box (fixed size; nodes are absolutely positioned inside _tree_panel).
	var box := Control.new()
	box.custom_minimum_size = Vector2(BOX_W, BOX_H)
	box.clip_contents = true
	stack.add_child(box)

	var box_bg := Panel.new()
	box_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	box_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.039, 0.051, 0.071, 0.55)
	box_style.border_color = Color(1, 1, 1, 0.12)
	box_style.set_border_width_all(1)
	box_style.set_corner_radius_all(0)
	box_bg.add_theme_stylebox_override("panel", box_style)
	box.add_child(box_bg)

	_tree_panel = Control.new()
	_tree_panel.name = "TreeHolder"
	_tree_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(_tree_panel)
	_build_tree_view(_run_character)


# ============================================================================
# STATS PANEL
# ============================================================================

func _build_stats_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.063, 0.078, 0.102, 0.86)
	style.border_color = Color(1, 1, 1, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", style)
	# Left-anchored column: right edge is an absolute 531px, NOT viewport-relative
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 81
	panel.offset_top = 180
	panel.offset_right = 531
	panel.offset_bottom = -126

	var vbox := VBoxContainer.new()
	vbox.name = "StatsVBox"
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	var cap := Label.new()
	cap.text = "FIELD STATUS"
	UI.style_subtitle_label(cap, 15, Color(1, 1, 1, 0.55))
	vbox.add_child(cap)

	var cap_gap := Control.new()
	cap_gap.custom_minimum_size.y = 18
	vbox.add_child(cap_gap)

	# Operator header: portrait + name + level
	var ophead := HBoxContainer.new()
	ophead.add_theme_constant_override("separation", 20)
	vbox.add_child(ophead)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.custom_minimum_size = Vector2(84, 84)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.clip_contents = true
	ophead.add_child(_portrait)

	var name_col := VBoxContainer.new()
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	name_col.add_theme_constant_override("separation", 2)
	ophead.add_child(name_col)

	_char_label = Label.new()
	_char_label.name = "CharLabel"
	_char_label.text = "OPERATIVE"
	_char_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_char_label.add_theme_font_size_override("font_size", 36)
	_char_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	name_col.add_child(_char_label)

	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.text = "LV 1"
	UI.style_subtitle_label(_level_label, 15, UI.ACCENT_SECONDARY)
	name_col.add_child(_level_label)

	var head_gap := Control.new()
	head_gap.custom_minimum_size.y = 12
	vbox.add_child(head_gap)

	for row_def in [["AtkRow", "ATK"], ["HpRow", "HP"], ["BurstRow", "BURST GEN"], ["SpeedRow", "SPEED"], ["CritRow", "CRIT RATE"]]:
		vbox.add_child(_create_stat_row(row_def[0], row_def[1]))

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(filler)

	return panel


func _create_stat_row(row_name: String, label_text: String) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.name = row_name
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0, 0, 0, 0)
	row_style.border_color = Color(0.5, 0.55, 0.61, 0.18)
	row_style.set_border_width_all(0)
	row_style.border_width_bottom = 1
	row_style.content_margin_top = 14
	row_style.content_margin_bottom = 14
	row_panel.add_theme_stylebox_override("panel", row_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row_panel.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	UI.style_subtitle_label(name_label, 15, Color(1, 1, 1, 0.6))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = "-"
	value_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	value_label.add_theme_font_size_override("font_size", 33)
	value_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	row.add_child(value_label)

	var bonus_label := Label.new()
	bonus_label.name = "Bonus"
	bonus_label.text = ""
	bonus_label.add_theme_font_override("font", UI.FONT_BOLD)
	bonus_label.add_theme_font_size_override("font_size", 18)
	bonus_label.add_theme_color_override("font_color", UI.COLOR_SUCCESS)
	bonus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bonus_label.size_flags_vertical = Control.SIZE_FILL
	row.add_child(bonus_label)

	# Direct references - no node-path lookups at update time
	_stat_rows[row_name] = {"value": value_label, "bonus": bonus_label}

	return row_panel


func _update_stats_panel(char_id: int = -1) -> void:
	if _stats_panel == null:
		return

	# Stats always show the run's character
	var display_char: int = char_id if char_id >= 0 else _run_character

	var char_name: String = CHARACTER_NAMES[display_char] if display_char >= 0 and display_char < CHARACTER_NAMES.size() else "Current"
	_set_char_label(char_name)
	if _header_sub:
		_header_sub.text = "NIKKE // %s" % char_name.to_upper()

	var current_level: int = 1
	var display_damage: int = 1
	var display_hp: int = 10
	var display_speed: int = 400
	var display_crit: float = 0.2
	var burst_rate: float = 1.0

	if _player_ref and is_instance_valid(_player_ref) and "level" in _player_ref:
		current_level = _player_ref.level

	if _character_registry:
		var char_data = _character_registry.get_character_by_index(display_char)
		if char_data:
			display_damage = int(char_data.base_damage)
			display_hp = char_data.base_hp
			display_speed = int(char_data.base_speed)
			display_crit = char_data.crit_chance if "crit_chance" in char_data else 0.2

			var weapon_type := _get_weapon_type_for_index(display_char)
			burst_rate = BurstConfig.get_rate(weapon_type)

			if _portrait and char_data.has_method("get_portrait"):
				_portrait.texture = char_data.get_portrait()

	if _level_label:
		_level_label.text = "LV %d" % current_level

	# Apply level damage multiplier (25% per level) to ATK display
	var level_damage_mult := 1.0 + (current_level - 1) * 0.25
	var scaled_damage := int(display_damage * level_damage_mult)

	# Get shop bonuses for display (not applied, just shown)
	var atk_bonus: float = 0.0
	var hp_bonus: int = 0
	var speed_bonus: float = 0.0
	var crit_bonus: float = 0.0

	if ShopMenu:
		atk_bonus = ShopMenu.get_upgrade_bonus("atk") # +25% per level
		hp_bonus = int(ShopMenu.get_upgrade_bonus("hp")) # +1 per level
		speed_bonus = ShopMenu.get_upgrade_bonus("speed") # +5% per level
		crit_bonus = ShopMenu.get_upgrade_bonus("crit") # +2% per level

	# Apply Scarlet's Low HP Bonus if applicable
	if display_char == 1 and _player_ref and _player_ref.has_method("get_low_hp_damage_multiplier"):
		var low_hp_mult: float = _player_ref.get_low_hp_damage_multiplier()
		if low_hp_mult > 1.0:
			_set_stat_value("AtkRow", str(int(scaled_damage * low_hp_mult)), "+%d%%" % int((low_hp_mult - 1.0) * 100))
		else:
			_set_stat_value("AtkRow", str(scaled_damage), "+%d%%" % int(atk_bonus * 100) if atk_bonus > 0 else "")
	else:
		_set_stat_value("AtkRow", str(scaled_damage), "+%d%%" % int(atk_bonus * 100) if atk_bonus > 0 else "")

	_set_stat_value("HpRow", str(display_hp), "+%d" % hp_bonus if hp_bonus > 0 else "")
	_set_stat_value("BurstRow", "%.1f%%" % burst_rate if burst_rate < 1.0 else "%.0f%%" % burst_rate)
	@warning_ignore("integer_division")
	_set_stat_value("SpeedRow", str(display_speed / 10), "+%d%%" % int(speed_bonus * 100) if speed_bonus > 0 else "")
	_set_stat_value("CritRow", "%.0f%%" % (display_crit * 100.0), "+%d%%" % int(crit_bonus * 100) if crit_bonus > 0 else "")


func _set_char_label(char_name: String) -> void:
	if _char_label != null:
		_char_label.text = char_name.to_upper()


func _set_stat_value(row_name: String, value: String, bonus: String = "") -> void:
	var row: Dictionary = _stat_rows.get(row_name, {})
	if row.is_empty():
		return
	row["value"].text = value
	row["bonus"].text = bonus


func _get_weapon_type_for_index(char_index: int) -> String:
	# Canonical weapon key for BurstConfig lookup (CharacterData.weapon_kind)
	if _character_registry:
		var char_data = _character_registry.get_character_by_index(char_index)
		if char_data and char_data.weapon_kind != "":
			return char_data.weapon_kind
	return "smg"


# ============================================================================
# TREE (C3a ability lanes)
# ============================================================================

## Slot position for a talent given its TalentData col/row.
## Rows 0/1: col 1 = lane root (left column), col 0 = top mod, col 2 = bottom mod.
## Row 2: col 2 = capstone (bottom-left, may be gated), col 0 = signature (bottom-right).
func _slot_rect(talent: Dictionary) -> Rect2:
	var col: int = talent["col"]
	var row: int = talent["row"]
	if row == 2:
		if col == 2:
			return Rect2(ROOT_X, SIG_Y, ROOT_W, NODE_H)
		return Rect2(MOD_X, SIG_Y, MOD_W, NODE_H)
	var mod_ys: Array = SPECIAL_MOD_YS if row == 0 else BURST_MOD_YS
	var root_y: float = SPECIAL_ROOT_Y if row == 0 else BURST_ROOT_Y
	match col:
		1: return Rect2(ROOT_X, root_y, ROOT_W, NODE_H)
		0: return Rect2(MOD_X, mod_ys[0], MOD_W, NODE_H)
		_: return Rect2(MOD_X, mod_ys[1], MOD_W, NODE_H)


func _build_tree_view(char_id: int) -> void:
	for child in _tree_panel.get_children():
		child.queue_free()
	_talent_buttons.clear()
	_lines_control = null

	# Lines layer (behind nodes) - uses custom drawing
	_lines_control = Control.new()
	_lines_control.name = "Lines"
	_lines_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines_control.set_script(preload("res://scripts/ui/TalentTreeLines.gd"))
	# Set meta AFTER script is applied to ensure it's not cleared
	_lines_control.set_meta("tree_ref", self)
	_lines_control.set_meta("char_id", char_id)
	_tree_panel.add_child(_lines_control)

	var talents: Array = TALENT_DATA[char_id]
	for talent in talents:
		if String(talent.get("tree", "skill")) != _active_tree:
			continue
		var node := _create_talent_button(talent, char_id)
		var rect := _slot_rect(talent)
		node.position = rect.position
		node.size = rect.size
		_tree_panel.add_child(node)
		_talent_buttons.append(node)


# ============================================================================
# TAB BAR (ATTACK / SKILL / BURST)
# ============================================================================

func _build_tab_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TabBar"
	bar.anchor_left = 0.0
	bar.anchor_top = 0.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 0.0
	bar.offset_left = 594
	bar.offset_top = 180
	bar.offset_right = -81
	bar.offset_bottom = 234
	bar.add_theme_constant_override("separation", 0)
	add_child(bar)

	var group := ButtonGroup.new()
	_tab_buttons.clear()
	for tab in TREE_TABS:
		var key: String = tab[0]
		var btn := Button.new()
		btn.text = tab[1]
		btn.toggle_mode = true
		btn.button_group = group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
		btn.add_theme_font_size_override("font_size", 28)
		_style_tab_button(btn)
		btn.pressed.connect(_on_tab_selected.bind(key))
		bar.add_child(btn)
		_tab_buttons[key] = btn
	_update_tab_visuals()


func _style_tab_button(btn: Button) -> void:
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0.078, 0.098, 0.129, 0.92)
	idle.set_corner_radius_all(0)
	idle.set_content_margin_all(10)
	idle.border_color = Color(1, 1, 1, 0.13)
	idle.border_width_right = 1
	var hover := idle.duplicate()
	hover.bg_color = Color(0.110, 0.137, 0.180, 0.95)
	var active := StyleBoxFlat.new()
	active.bg_color = Color(0.031, 0.043, 0.059, 0.95)
	active.set_corner_radius_all(0)
	active.set_content_margin_all(10)
	active.border_color = UI.ACCENT_CYAN
	active.border_width_bottom = 4
	btn.add_theme_stylebox_override("normal", idle)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", active)
	btn.add_theme_stylebox_override("hover_pressed", active)
	btn.add_theme_stylebox_override("focus", idle)
	btn.add_theme_color_override("font_color", Color(0.592, 0.627, 0.675, 1.0))
	btn.add_theme_color_override("font_hover_color", UI.TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", UI.ACCENT_CYAN)
	btn.add_theme_color_override("font_hover_pressed_color", UI.ACCENT_CYAN)


func _on_tab_selected(tree_key: String) -> void:
	if tree_key == _active_tree:
		_update_tab_visuals()
		return
	_active_tree = tree_key
	UISounds.play_confirm()
	_update_tab_visuals()
	_build_tree_view(_run_character)
	_refresh_tree()


func _update_tab_visuals() -> void:
	for key in _tab_buttons:
		var btn: Button = _tab_buttons[key]
		btn.set_pressed_no_signal(String(key) == _active_tree)


func _create_talent_button(talent: Dictionary, char_id: int) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.set_meta("talent", talent)
	btn.set_meta("char_id", char_id)
	btn.pressed.connect(_on_talent_clicked.bind(btn))
	btn.draw.connect(_draw_talent_button.bind(btn))
	btn.mouse_entered.connect(func():
		btn.set_meta("hovered", true)
		btn.queue_redraw()
	)
	btn.mouse_exited.connect(func():
		btn.set_meta("hovered", false)
		btn.queue_redraw()
	)
	return btn


func _draw_talent_button(btn: Button) -> void:
	var talent: Dictionary = btn.get_meta("talent")
	var char_id: int = btn.get_meta("char_id")
	var hovered: bool = btn.get_meta("hovered", false)

	var talent_id: String = talent["id"]
	var current_level: int = _unlocked_talents.get(char_id, {}).get(talent_id, 0)
	var max_level: int = talent["max"]
	var is_unlocked := current_level > 0
	var is_maxed := current_level >= max_level
	var can_unlock := _can_unlock_talent_quiet(char_id, talent)
	# Preview is a catalog: render every node at full readability (light "available"
	# style) rather than dimming unaffordable ones, since nothing is purchasable.
	if _preview_mode:
		can_unlock = not is_maxed
	var is_locked := not is_unlocked and not can_unlock

	# State palette (user spec): available = light grey, unavailable = dark
	# grey, bought = cyan. Yellow brackets on hover for affordable nodes.
	var bg_color := Color(0.18, 0.20, 0.23, 0.6)        # unavailable: dark grey
	var bracket_color := Color(1, 1, 1, 0.3)
	var bracket_size := 21.0
	var text_alpha := 0.55
	if is_unlocked: # bought (including maxed)
		bg_color = Color(0.122, 0.561, 0.878, 0.22)
		bracket_color = UI.ACCENT_CYAN
		bracket_size = 27.0
		text_alpha = 1.0
	elif can_unlock: # available: light grey
		bg_color = Color(0.62, 0.66, 0.71, 0.28)
		bracket_color = Color(1, 1, 1, 0.9)
		text_alpha = 1.0
		if hovered:
			bracket_color = UI.ACCENT_SECONDARY
			bracket_size = 30.0
			bg_color = Color(0.68, 0.72, 0.77, 0.34)

	var w := btn.size.x
	var h := btn.size.y

	# Flat fill + corner brackets (top-left / bottom-right)
	btn.draw_rect(Rect2(0, 0, w, h), bg_color)
	var bw := 3.0
	btn.draw_rect(Rect2(0, 0, bracket_size, bw), bracket_color)
	btn.draw_rect(Rect2(0, 0, bw, bracket_size), bracket_color)
	btn.draw_rect(Rect2(w - bracket_size, h - bw, bracket_size, bw), bracket_color)
	btn.draw_rect(Rect2(w - bw, h - bracket_size, bw, bracket_size), bracket_color)

	# Name (oblique). Burst abilities are prefixed with their slot, the real
	# ability name stays as-is (no invented flavor names in descs).
	var name_text := str(talent["name"]).to_upper()
	if talent.get("burst", false):
		name_text = "BURST: " + name_text
	var name_color := UI.ACCENT_CYAN if is_unlocked else UI.TEXT_PRIMARY
	name_color.a = text_alpha
	btn.draw_string(UI.FONT_TITLE_OBLIQUE, Vector2(20, 36), name_text,
		HORIZONTAL_ALIGNMENT_LEFT, w - 110, 24, name_color)

	# Short description + full detail (tooltip text integrated into the entry)
	var desc_text := str(talent["desc"])
	if desc_text != "":
		var desc_color := Color(1, 1, 1, 0.8 * text_alpha)
		btn.draw_string(UI.FONT_BOLD, Vector2(20, 58), desc_text,
			HORIZONTAL_ALIGNMENT_LEFT, w - 40, 15, desc_color)

	var detail: String = talent.get("tooltip", "")
	if detail != "":
		var detail_color := Color(1, 1, 1, 0.55 * text_alpha)
		# Multi-rank nodes reserve the bottom strip for pips
		var max_lines := 2 if max_level > 1 else 3
		btn.draw_multiline_string(UI.FONT_MEDIUM, Vector2(20, 79), detail,
			HORIZONTAL_ALIGNMENT_LEFT, w - 40, 13, max_lines, detail_color)

	# Cost chip (top-right); hidden once maxed
	if not is_maxed:
		var cost_text := "%d SP" % talent["cost"]
		var cost_color := UI.ACCENT_SECONDARY if not is_locked else Color(0.541, 0.565, 0.6, 1.0)
		var cost_w := UI.FONT_BOLD.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var chip_rect := Rect2(w - cost_w - 32, 12, cost_w + 20, 26)
		btn.draw_rect(chip_rect, Color(0.039, 0.051, 0.071, 0.8))
		btn.draw_rect(chip_rect, Color(cost_color.r, cost_color.g, cost_color.b, 0.5 * text_alpha), false, 1.0)
		btn.draw_string(UI.FONT_BOLD, chip_rect.position + Vector2(10, 19), cost_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(cost_color.r, cost_color.g, cost_color.b, text_alpha))

	# Level pips (multi-rank talents)
	if max_level > 1:
		for i in max_level:
			var pip_color := UI.ACCENT_CYAN if i < current_level else Color(1, 1, 1, 0.18)
			btn.draw_rect(Rect2(20 + i * 30, h - 18, 21, 7), pip_color)

	# State tag (bottom-right)
	if is_maxed:
		btn.draw_string(UI.FONT_BOLD, Vector2(w - 62, h - 11), "MAX",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.ACCENT_CYAN)
	elif is_unlocked and max_level == 1:
		btn.draw_string(UI.FONT_BOLD, Vector2(w - 84, h - 11), "ACTIVE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.ACCENT_CYAN)
	elif _is_pinnacle(talent) and not _pinnacle_ready(char_id, talent):
		# Pinnacle locked: tell the player they must finish the rest of the tree.
		btn.draw_string(UI.FONT_BOLD, Vector2(w - 232, h - 11), "MAX ALL OTHER SKILLS TO UNLOCK",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.ACCENT_SECONDARY)


# ============================================================================
# UNLOCK LOGIC
# ============================================================================

func _can_unlock_talent_quiet(char_id: int, talent: Dictionary) -> bool:
	if _skill_points < talent["cost"]:
		return false
	var current_level: int = _unlocked_talents.get(char_id, {}).get(talent["id"], 0)
	if current_level >= int(talent["max"]):
		return false
	for req_id in talent.get("requires", []):
		if _unlocked_talents.get(char_id, {}).get(req_id, 0) <= 0:
			return false
	# Pinnacle (the bottom-right node of each tree): only unlockable once every
	# OTHER talent in the same tree is fully maxed.
	if _is_pinnacle(talent) and not _pinnacle_ready(char_id, talent):
		return false
	return true


## The bottom-right node in each tree (col 0, row 2 = the SIG slot) is its "pinnacle".
func _is_pinnacle(talent: Dictionary) -> bool:
	return int(talent.get("col", -1)) == 0 and int(talent.get("row", -1)) == 2


## True when every non-pinnacle talent in the pinnacle's tree is at its max level.
func _pinnacle_ready(char_id: int, pinnacle: Dictionary) -> bool:
	var tree: String = String(pinnacle.get("tree", ""))
	var levels: Dictionary = _unlocked_talents.get(char_id, {})
	for t in TALENT_DATA.get(char_id, []):
		if String(t.get("tree", "")) != tree:
			continue
		if t["id"] == pinnacle["id"]:
			continue
		if int(levels.get(t["id"], 0)) < int(t["max"]):
			return false
	return true


func _can_unlock_talent(char_id: int, talent: Dictionary) -> bool:
	return _can_unlock_talent_quiet(char_id, talent)


func _on_talent_clicked(btn: Button) -> void:
	if _preview_mode:
		return  # Read-only browse view — nothing is purchasable.
	var talent: Dictionary = btn.get_meta("talent")
	var char_id: int = btn.get_meta("char_id")

	if not _can_unlock_talent(char_id, talent):
		return

	var talent_id: String = talent["id"]
	if not _unlocked_talents.has(char_id):
		_unlocked_talents[char_id] = {}

	var current_level: int = _unlocked_talents[char_id].get(talent_id, 0)
	_unlocked_talents[char_id][talent_id] = current_level + 1
	self._skill_points -= talent["cost"]

	UISounds.play_confirm()

	print("[TalentTree] UNLOCKED %s! New state: %s" % [talent_id, _unlocked_talents[char_id]])

	# Track skill purchase for achievement
	if has_node("/root/AchievementManager"):
		get_node("/root/AchievementManager").on_skill_purchased(char_id, talent_id)

	emit_signal("talent_unlocked", char_id, talent_id)

	_refresh_tree()

	# Only close if no skill points remaining - with delay for player to prepare
	if _skill_points <= 0:
		_on_close(true) # true = with delay before unpause


func _refresh_tree() -> void:
	if _sp_value:
		_sp_value.text = str(_skill_points)

	for btn in _talent_buttons:
		if is_instance_valid(btn):
			btn.queue_redraw()

	if _lines_control:
		_lines_control.queue_redraw()

	# Update stats (talents may modify player stats)
	_update_stats_panel()


# ============================================================================
# OPEN / CLOSE
# ============================================================================

func _process(delta: float) -> void:
	if _anim_state == 0:
		return

	if _anim_state == 1: # Fading in
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_progress = 1.0
			_anim_state = 2
		modulate.a = _anim_progress
	elif _anim_state == 3: # Fading out
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_progress = 1.0
			_finish_close()
		else:
			modulate.a = 1.0 - _anim_progress


func _finish_close() -> void:
	_anim_state = 0
	visible = false
	modulate.a = 1.0
	if not _preview_mode:
		_restore_game_hud()
		# Always unpause on close to resume gameplay
		_pending_unpause = false
		get_tree().paused = false
	emit_signal("tree_closed")


## The overlay replaces the in-game HUD entirely (same rule as the pause
## menu). The tree itself lives INSIDE the HUD CanvasLayer (99), so its
## visible siblings are hidden individually; every other positive-layer
## CanvasLayer is hidden whole. The exact set is restored on close.
func _hide_game_hud() -> void:
	if not _hidden_ui.is_empty():
		return
	var parent_layer := get_parent()
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == self:
			continue
		if node is CanvasLayer and not node is ParallaxBackground:
			if node == parent_layer:
				for sibling in node.get_children():
					if sibling != self and sibling is CanvasItem and sibling.visible:
						_hidden_ui.append(sibling)
						sibling.visible = false
				continue
			if node.visible and node.layer >= 0:
				_hidden_ui.append(node)
				node.visible = false
			continue
		for child in node.get_children():
			stack.append(child)


func _restore_game_hud() -> void:
	for ui_node in _hidden_ui:
		if is_instance_valid(ui_node):
			ui_node.visible = true
	_hidden_ui.clear()


func _on_close(with_delay: bool = false) -> void:
	UISounds.play_back()
	_anim_state = 3
	_anim_progress = 0.0
	_pending_unpause = with_delay


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		_on_close()
		get_viewport().set_input_as_handled()


# ============================================================================
# PUBLIC API
# ============================================================================

## Configure this tree as a read-only preview for the given registry index.
## MUST be called BEFORE the node enters the scene tree (before add_child) so
## _ready() skips the run-only wiring and renders the right character.
func configure_preview(char_index: int) -> void:
	_preview_mode = true
	_preview_char = char_index


## Show as a read-only preview (character-select screen): fade in only — no
## pause, no HUD hiding, no skill-point spending.
func show_preview() -> void:
	visible = true
	modulate.a = 0.0
	_anim_state = 1
	_anim_progress = 0.0
	_refresh_tree()
	_update_stats_panel()


func show_tree(player: Node = null) -> void:
	if player != null:
		_player_ref = player
	else:
		# Try to find player automatically
		_player_ref = get_tree().get_first_node_in_group("player")
		if _player_ref == null:
			_player_ref = get_node_or_null("/root/Level/Player")

	# Hide the in-game HUD while the tree is open (same rule as pause)
	_hide_game_hud()

	# Start open fade
	visible = true
	modulate.a = 0.0
	_anim_state = 1
	_anim_progress = 0.0

	# Pause the game (and timers)
	get_tree().paused = true
	_pending_unpause = true

	_refresh_tree()
	_update_stats_panel()


func add_skill_points(amount: int) -> void:
	self.set_skill_points(_skill_points + amount)
	_refresh_tree()


func get_skill_points() -> int:
	return _skill_points


func get_talent_level(char_id: int, talent_id: String) -> int:
	return _unlocked_talents.get(char_id, {}).get(talent_id, 0)


func is_talent_unlocked(char_id: int, talent_id: String) -> bool:
	return get_talent_level(char_id, talent_id) > 0


func get_unlocked_talents() -> Dictionary:
	return _unlocked_talents.duplicate(true)


# Helper methods for TalentTreeLines drawing
func get_talent_data(char_id: int) -> Array:
	return TALENT_DATA.get(char_id, [])


func get_unlocked_for_char(char_id: int) -> Dictionary:
	return _unlocked_talents.get(char_id, {})


func set_skill_points(amount: int) -> void:
	_skill_points = amount
	if _sp_value:
		_sp_value.text = str(_skill_points)
