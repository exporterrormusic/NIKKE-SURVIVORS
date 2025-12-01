extends Control
class_name TalentTree

## Talent Tree UI System - Clean container-based architecture
## Shows 3 character portraits, clicking opens their skill tree

signal talent_unlocked(character_id: int, talent_id: String)
signal tree_closed

# Preload portraits at class level to avoid runtime loading issues
var _portraits: Array[Texture2D] = []

# UI References
var _main_panel: PanelContainer = null
var _character_panel: VBoxContainer = null
var _tree_panel: VBoxContainer = null
var _current_character: int = -1

# Colors
const BG_COLOR := Color(0.02, 0.02, 0.04, 0.97)
const PANEL_BG := Color(0.06, 0.06, 0.09, 0.98)
const BORDER_COLOR := Color(0.7, 0.7, 0.75, 1.0)
const HOVER_BORDER := Color(1.0, 0.85, 0.2, 1.0)
const LOCKED_COLOR := Color(0.35, 0.35, 0.4, 1.0)
const UNLOCKED_COLOR := Color(0.3, 0.9, 0.4, 1.0)
const TITLE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const DESC_COLOR := Color(0.7, 0.7, 0.75, 1.0)

# Character data
const CHARACTER_NAMES: Array[String] = ["Scarlet", "Snow White", "Rapunzel"]
const PORTRAIT_PATHS: Array[String] = [
	"res://assets/characters/scarlet/portrait-sq.png",
	"res://assets/characters/snow-white/portrait-sq.png",
	"res://assets/characters/rapunzel/portrait-sq.png"
]

# Talent definitions - Simplified: 3 main abilities + 4 upgrades (2 per special/burst)
# Layout: UNLOCK (row 0) -> SPECIAL (row 1) -> BURST (row 2)
# Side upgrades: 2 for special (row 1, cols 0,2), 2 for burst (row 2, cols 0,2)
var TALENT_DATA := {
	0: [  # Scarlet - Melee DPS
		{"id": "unlock", "name": "Unlock Scarlet", "desc": "Add Scarlet to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "Melee warrior who loses 3% max HP per attack but deals high damage."},
		{"id": "special", "name": "Dash Slash", "desc": "Dash leaves a damaging wave", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Dash releases a piercing wave dealing 8 damage. 4s cooldown."},
		{"id": "special_cd", "name": "Quick Dash", "desc": "-1s special cooldown", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "-1s cooldown per level. At max: 1s cooldown."},
		{"id": "special_heal", "name": "Vampiric Slash", "desc": "Heals 5/15/25% max HP per hit", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Wave heals per enemy hit while still dealing damage."},
		{"id": "burst", "name": "Crimson Wave", "desc": "BURST: Devastating slash wave", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Costs 50% HP. Hits all enemies on screen. Teleports to last target."},
		{"id": "burst_execute", "name": "Execution", "desc": "Instantly kills non-elite, non-boss enemies", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Regular enemies die instantly. Elites/bosses take normal damage."},
		{"id": "burst_vuln", "name": "Expose Weakness", "desc": "Targets take 50% more damage", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Marked enemies take +50% damage from all sources."},
	],
	1: [  # Snow White - Ranged with Turret
		{"id": "unlock", "name": "Snow White", "desc": "Already in your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 0, "unlock": true, "default": true,
		 "tooltip": "Sniper with piercing shots. 7 ammo, 1.5s reload."},
		{"id": "special", "name": "Auto-Turret", "desc": "Deploy auto-targeting turrets", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Deploys turret with 4 missiles. 1 charge, 8s recharge."},
		{"id": "special_capacity", "name": "Ammo Cache", "desc": "+2 turret missile capacity", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "+2 missiles per turret. Max: 10 missiles."},
		{"id": "special_count", "name": "More Turrets", "desc": "+2 max turret charges", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "+2 charges per level. Max: 7 turrets."},
		{"id": "burst", "name": "Blizzard", "desc": "BURST: Freezing storm", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "90° ice beam dealing 50 damage. Massive range."},
		{"id": "burst_burn", "name": "Frostburn", "desc": "Burns enemies for 10/25/33% max HP/s", "col": 0, "row": 2, "requires": ["burst"], "max": 3, "cost": 1,
		 "tooltip": "3s burn. Elites/bosses take 4/8/12% instead."},
		{"id": "burst_gauge", "name": "Soul Harvest", "desc": "Kills during burst refill gauge", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Burst kills generate burst gauge for chaining."},
	],
	2: [  # Rapunzel - Support Healer
		{"id": "unlock", "name": "Unlock Rapunzel", "desc": "Add Rapunzel to your squad", "col": 1, "row": 0, "requires": [], "max": 1, "cost": 1, "unlock": true,
		 "tooltip": "Support with explosive missiles and healing abilities."},
		{"id": "special", "name": "Healing Cross", "desc": "Create a healing zone", "col": 1, "row": 1, "requires": ["unlock"], "max": 1, "cost": 1, "special": true,
		 "tooltip": "Heals 3% max HP/s for 9s. 10s cooldown."},
		{"id": "special_power", "name": "Rejuvenation", "desc": "Healing: 10/17.5/25% max HP/s", "col": 0, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Increases healing power dramatically."},
		{"id": "special_size", "name": "Expanding Aura", "desc": "Zone size/duration +50/150/300%", "col": 2, "row": 1, "requires": ["special"], "max": 3, "cost": 1,
		 "tooltip": "Larger radius and longer duration."},
		{"id": "burst", "name": "Golden Hair", "desc": "BURST: Massive heal + stun", "col": 1, "row": 2, "requires": ["special"], "max": 1, "cost": 1, "burst": true,
		 "tooltip": "Full heal + 4s stun on all enemies."},
		{"id": "burst_stun", "name": "Stunning Beauty", "desc": "Stun duration increased to 8s", "col": 0, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Doubles stun from 4s to 8s."},
		{"id": "burst_invuln", "name": "Divine Protection", "desc": "8 seconds of invincibility", "col": 2, "row": 2, "requires": ["burst"], "max": 1, "cost": 1,
		 "tooltip": "Grants 8s invincibility on burst."},
	]
}

# Tooltip UI reference
var _tooltip: PanelContainer = null

# Player's unlocked talents
var _unlocked_talents: Dictionary = {0: {}, 1: {}, 2: {}}
var _skill_points: int = 0
var _talent_buttons: Array = []
var _lines_control: Control = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Ensure TalentTree is rendered above all other UI
	z_index = 100
	
	# Preload all portraits
	for path in PORTRAIT_PATHS:
		var tex = load(path)
		_portraits.append(tex)
	
	_build_ui()
	visible = false
	_apply_default_talents()

func _build_ui() -> void:
	# Full screen dark overlay
	var overlay := ColorRect.new()
	overlay.color = BG_COLOR
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# Main centered container - above the overlay
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	# Main panel with border
	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(1000, 700)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.border_color = BORDER_COLOR
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(20)
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_main_panel)
	
	# Content container (switches between character select and tree view)
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_panel.add_child(content)
	
	# Character selection panel
	_character_panel = VBoxContainer.new()
	_character_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_character_panel.add_theme_constant_override("separation", 20)
	content.add_child(_character_panel)
	_build_character_panel()
	
	# Tree panel (hidden initially)
	_tree_panel = VBoxContainer.new()
	_tree_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tree_panel.add_theme_constant_override("separation", 15)
	_tree_panel.visible = false
	content.add_child(_tree_panel)
	
	# Create tooltip (added last so it renders on top)
	_create_tooltip()

func _build_character_panel() -> void:
	# Title
	var title := Label.new()
	title.text = "TALENT TREES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	_character_panel.add_child(title)
	
	# Skill points
	var points := Label.new()
	points.name = "SkillPoints"
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_font_size_override("font_size", 24)
	points.add_theme_color_override("font_color", HOVER_BORDER)
	_character_panel.add_child(points)
	
	# Spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	_character_panel.add_child(spacer1)
	
	# Character cards row
	var cards_row := HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", 40)
	_character_panel.add_child(cards_row)
	
	for i in range(3):
		var card := _create_character_card(i)
		cards_row.add_child(card)
	
	# Spacer
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_panel.add_child(spacer2)
	
	# Close button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_character_panel.add_child(btn_row)
	
	var close_btn := Button.new()
	close_btn.text = "✕ CLOSE"
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.custom_minimum_size = Vector2(160, 50)
	close_btn.pressed.connect(_on_close)
	_style_button(close_btn)
	btn_row.add_child(close_btn)

func _create_character_card(char_id: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 380)
	
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.04, 0.04, 0.06, 1.0)
	card_style.border_color = BORDER_COLOR
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(10)
	card_style.set_content_margin_all(15)
	card.add_theme_stylebox_override("panel", card_style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)
	
	# Portrait container
	var portrait_container := CenterContainer.new()
	vbox.add_child(portrait_container)
	
	var portrait_panel := PanelContainer.new()
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.02, 0.02, 0.03, 1.0)
	portrait_style.border_color = BORDER_COLOR
	portrait_style.set_border_width_all(2)
	portrait_style.set_corner_radius_all(8)
	portrait_panel.add_theme_stylebox_override("panel", portrait_style)
	portrait_container.add_child(portrait_panel)
	
	var portrait_rect := TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(180, 180)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if char_id < _portraits.size() and _portraits[char_id] != null:
		portrait_rect.texture = _portraits[char_id]
	portrait_panel.add_child(portrait_rect)
	
	# Character name
	var name_label := Label.new()
	name_label.text = CHARACTER_NAMES[char_id]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", TITLE_COLOR)
	vbox.add_child(name_label)
	
	# Unlock count
	var count_label := Label.new()
	count_label.name = "CountLabel"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 16)
	count_label.add_theme_color_override("font_color", DESC_COLOR)
	vbox.add_child(count_label)
	_update_card_count(count_label, char_id)
	
	# Status
	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(status_label)
	_update_card_status(status_label, char_id)
	
	# Click button (overlay)
	var click_btn := Button.new()
	click_btn.text = "View Talents"
	click_btn.add_theme_font_size_override("font_size", 18)
	click_btn.custom_minimum_size = Vector2(0, 40)
	click_btn.pressed.connect(_on_character_selected.bind(char_id))
	_style_button(click_btn)
	vbox.add_child(click_btn)
	
	return card

func _update_card_count(label: Label, char_id: int) -> void:
	var char_talents: Dictionary = _unlocked_talents.get(char_id, {})
	var unlocked: int = char_talents.size()
	var talent_list: Array = TALENT_DATA[char_id]
	var total: int = talent_list.size()
	label.text = "%d / %d Talents Unlocked" % [unlocked, total]
	label.add_theme_color_override("font_color", UNLOCKED_COLOR if unlocked == total else DESC_COLOR)

func _update_card_status(label: Label, char_id: int) -> void:
	if char_id == 1:  # Snow White always unlocked
		label.text = "★ AVAILABLE"
		label.add_theme_color_override("font_color", UNLOCKED_COLOR)
	elif _unlocked_talents.get(char_id, {}).has("unlock"):
		label.text = "★ UNLOCKED"
		label.add_theme_color_override("font_color", UNLOCKED_COLOR)
	else:
		label.text = "🔒 LOCKED"
		label.add_theme_color_override("font_color", LOCKED_COLOR)

func _style_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	normal.border_color = BORDER_COLOR
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.12, 0.12, 0.18, 1.0)
	hover.border_color = HOVER_BORDER
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

func _on_character_selected(char_id: int) -> void:
	_current_character = char_id
	_character_panel.visible = false
	_tree_panel.visible = true
	_build_tree_view(char_id)

func _build_tree_view(char_id: int) -> void:
	# Clear previous
	for child in _tree_panel.get_children():
		child.queue_free()
	_talent_buttons.clear()
	_lines_control = null
	
	# Title bar with character name
	var title_bar := HBoxContainer.new()
	title_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tree_panel.add_child(title_bar)
	
	var title := Label.new()
	title.text = CHARACTER_NAMES[char_id] + " - TALENTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title_bar.add_child(title)
	
	# Skill points
	var points := Label.new()
	points.name = "TreeSkillPoints"
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_font_size_override("font_size", 22)
	points.add_theme_color_override("font_color", HOVER_BORDER)
	points.text = "Skill Points: %d" % _skill_points
	_tree_panel.add_child(points)
	
	# Tree container panel (holds lines and nodes)
	var tree_panel := PanelContainer.new()
	tree_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tree_panel.custom_minimum_size = Vector2(720, 440)
	var tree_style := StyleBoxFlat.new()
	tree_style.bg_color = Color(0.03, 0.03, 0.05, 1.0)
	tree_style.border_color = Color(0.5, 0.5, 0.55, 1.0)
	tree_style.set_border_width_all(2)
	tree_style.set_corner_radius_all(8)
	tree_style.set_content_margin_all(10)
	tree_panel.add_theme_stylebox_override("panel", tree_style)
	_tree_panel.add_child(tree_panel)
	
	var tree_holder := Control.new()
	tree_holder.custom_minimum_size = Vector2(700, 420)
	tree_panel.add_child(tree_holder)
	
	# Lines layer (behind nodes) - uses custom drawing
	_lines_control = Control.new()
	_lines_control.name = "Lines"
	_lines_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines_control.set_script(preload("res://scripts/TalentTreeLines.gd"))
	# Set meta AFTER script is applied to ensure it's not cleared
	_lines_control.set_meta("tree_ref", self)
	_lines_control.set_meta("char_id", char_id)
	tree_holder.add_child(_lines_control)
	
	# Create talent nodes in a grid
	var talents: Array = TALENT_DATA[char_id]
	var node_width: float = 180.0
	var node_height: float = 90.0
	var h_spacing: float = 230.0
	var v_spacing: float = 105.0
	var grid_width: float = 3.0 * h_spacing
	var start_x: float = (700.0 - grid_width) / 2.0 + (h_spacing - node_width) / 2.0
	
	for talent in talents:
		var col: int = talent["col"]
		var row: int = talent["row"]
		var node := _create_talent_button(talent, char_id)
		node.position = Vector2(start_x + col * h_spacing, row * v_spacing + 5)
		node.size = Vector2(node_width, node_height)
		tree_holder.add_child(node)
		_talent_buttons.append(node)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_panel.add_child(spacer)
	
	# Back button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tree_panel.add_child(btn_row)
	
	var back_btn := Button.new()
	back_btn.text = "← BACK"
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.custom_minimum_size = Vector2(160, 50)
	back_btn.pressed.connect(_on_back_to_characters)
	_style_button(back_btn)
	btn_row.add_child(back_btn)

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
		_show_tooltip(talent, btn)
	)
	btn.mouse_exited.connect(func(): 
		btn.set_meta("hovered", false)
		btn.queue_redraw()
		_hide_tooltip()
	)
	return btn

func _create_tooltip() -> void:
	# Create tooltip panel - NOT using anchors so it sizes to content
	_tooltip = PanelContainer.new()
	_tooltip.name = "Tooltip"
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 200  # Above everything
	_tooltip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tooltip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.02, 0.02, 0.04, 0.98)
	tooltip_style.border_color = Color(1.0, 0.85, 0.2, 1.0)  # Golden border
	tooltip_style.set_border_width_all(2)
	tooltip_style.set_corner_radius_all(8)
	tooltip_style.set_content_margin_all(12)
	tooltip_style.shadow_color = Color(0, 0, 0, 0.5)
	tooltip_style.shadow_size = 4
	_tooltip.add_theme_stylebox_override("panel", tooltip_style)
	
	var vbox := VBoxContainer.new()
	vbox.name = "TooltipVBox"
	vbox.add_theme_constant_override("separation", 6)
	_tooltip.add_child(vbox)
	
	# Title label
	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))  # Golden title
	vbox.add_child(title_label)
	
	# Short description
	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # White
	vbox.add_child(desc_label)
	
	# Separator
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 2)
	vbox.add_child(separator)
	
	# Detailed tooltip text - use Label instead of RichTextLabel for proper sizing
	var tooltip_label := Label.new()
	tooltip_label.name = "TooltipLabel"
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.custom_minimum_size = Vector2(250, 0)
	tooltip_label.add_theme_font_size_override("font_size", 12)
	tooltip_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1.0))  # Slightly dimmer white
	vbox.add_child(tooltip_label)
	
	add_child(_tooltip)

func _show_tooltip(talent: Dictionary, btn: Button) -> void:
	if _tooltip == null:
		return
	
	# Update tooltip content
	var title_label: Label = _tooltip.get_node_or_null("TooltipVBox/TitleLabel")
	var desc_label: Label = _tooltip.get_node_or_null("TooltipVBox/DescLabel")
	var tooltip_label: Label = _tooltip.get_node_or_null("TooltipVBox/TooltipLabel")
	
	if title_label:
		title_label.text = talent["name"]
	
	if desc_label:
		desc_label.text = talent["desc"]
	
	if tooltip_label:
		var full_description: String = talent.get("tooltip", "")
		tooltip_label.text = full_description
	
	# Reset size so it recalculates
	_tooltip.size = Vector2.ZERO
	
	# Position tooltip near the button
	var btn_global_pos := btn.global_position
	var btn_size := btn.size
	
	# Make visible first
	_tooltip.visible = true
	
	# Position to the right of the button by default
	var tooltip_pos := Vector2(btn_global_pos.x + btn_size.x + 10, btn_global_pos.y)
	
	# Wait one frame for size to update
	await get_tree().process_frame
	
	var tooltip_size := _tooltip.size
	var viewport_size := get_viewport_rect().size
	
	# If tooltip would go off the right edge, position it to the left of the button
	if tooltip_pos.x + tooltip_size.x > viewport_size.x - 20:
		tooltip_pos.x = btn_global_pos.x - tooltip_size.x - 10
	
	# If tooltip would go off the bottom edge, move it up
	if tooltip_pos.y + tooltip_size.y > viewport_size.y - 20:
		tooltip_pos.y = viewport_size.y - tooltip_size.y - 20
	
	# Make sure it doesn't go off the top
	if tooltip_pos.y < 20:
		tooltip_pos.y = 20
	
	_tooltip.global_position = tooltip_pos

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false

func _draw_talent_button(btn: Button) -> void:
	var talent: Dictionary = btn.get_meta("talent")
	var char_id: int = btn.get_meta("char_id")
	var hovered: bool = btn.get_meta("hovered", false)
	
	var talent_id: String = talent["id"]
	var current_level: int = _unlocked_talents.get(char_id, {}).get(talent_id, 0)
	var max_level: int = talent["max"]
	var is_unlocked := current_level > 0
	var is_maxed := current_level >= max_level
	var can_unlock := _can_unlock_talent(char_id, talent)
	
	# Colors - default for regular talents
	var bg_color := Color(0.08, 0.08, 0.1, 1.0)  # Dark gray when locked
	var border_color := LOCKED_COLOR
	
	# Determine talent type
	var is_special: bool = talent.get("special", false)
	var is_burst: bool = talent.get("burst", false)
	var is_unlock: bool = talent.get("unlock", false)
	
	# Set colors based on state and type
	if is_burst:
		# Red/Crimson for burst
		if is_maxed:
			bg_color = Color(0.6, 0.15, 0.15, 1.0)  # Bright red
			border_color = Color(1.0, 0.4, 0.4, 1.0)
		elif is_unlocked:
			bg_color = Color(0.45, 0.1, 0.1, 1.0)  # Medium red
			border_color = Color(0.9, 0.3, 0.3, 1.0)
		else:
			bg_color = Color(0.15, 0.05, 0.05, 1.0)  # Dark red
	elif is_special:
		# Yellow/Gold for special
		if is_maxed:
			bg_color = Color(0.5, 0.4, 0.1, 1.0)  # Bright gold
			border_color = Color(1.0, 0.85, 0.3, 1.0)
		elif is_unlocked:
			bg_color = Color(0.4, 0.3, 0.08, 1.0)  # Medium gold
			border_color = Color(0.9, 0.75, 0.25, 1.0)
		else:
			bg_color = Color(0.12, 0.1, 0.03, 1.0)  # Dark gold
	elif is_unlock:
		# White/Silver for character unlock
		if is_maxed:
			bg_color = Color(0.35, 0.35, 0.4, 1.0)  # Bright silver
			border_color = Color(0.9, 0.9, 1.0, 1.0)
		elif is_unlocked:
			bg_color = Color(0.25, 0.25, 0.3, 1.0)  # Medium silver
			border_color = Color(0.8, 0.8, 0.9, 1.0)
		else:
			bg_color = Color(0.1, 0.1, 0.12, 1.0)  # Dark
	else:
		# Green for regular upgrades
		if is_maxed:
			bg_color = Color(0.15, 0.4, 0.15, 1.0)  # Bright green
			border_color = UNLOCKED_COLOR
		elif is_unlocked:
			bg_color = Color(0.1, 0.25, 0.1, 1.0)  # Medium green
			border_color = Color(0.6, 0.8, 0.3, 1.0)
		elif can_unlock:
			border_color = HOVER_BORDER if hovered else BORDER_COLOR
			if hovered:
				bg_color = Color(0.12, 0.12, 0.15, 1.0)
	
	# Draw background
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	btn.draw_style_box(style, Rect2(Vector2.ZERO, btn.size))
	
	# Text
	var font := btn.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	
	var name_text: String = talent["name"]
	var name_color := TITLE_COLOR if (is_unlocked or can_unlock) else LOCKED_COLOR
	var name_size := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var name_x := (btn.size.x - name_size.x) / 2.0
	btn.draw_string(font, Vector2(name_x, 32), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_color)
	
	# Level
	var level_text := "%d / %d" % [current_level, max_level]
	var level_color := UNLOCKED_COLOR if is_maxed else (DESC_COLOR if is_unlocked else LOCKED_COLOR)
	var level_size := font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var level_x := (btn.size.x - level_size.x) / 2.0
	btn.draw_string(font, Vector2(level_x, 56), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, level_color)
	
	# Cost
	if not is_maxed and can_unlock:
		var cost_text := "Cost: %d" % talent["cost"]
		var cost_size := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var cost_x := (btn.size.x - cost_size.x) / 2.0
		btn.draw_string(font, Vector2(cost_x, 78), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HOVER_BORDER)

func _can_unlock_talent(char_id: int, talent: Dictionary) -> bool:
	var talent_id: String = talent["id"]
	
	print("[TalentTree] Checking can unlock: char=%d, talent=%s" % [char_id, talent_id])
	print("[TalentTree] Skill points: %d, cost: %d" % [_skill_points, talent["cost"]])
	
	if _skill_points < talent["cost"]:
		print("[TalentTree] BLOCKED: Not enough skill points")
		return false
	
	var current_level: int = _unlocked_talents.get(char_id, {}).get(talent_id, 0)
	print("[TalentTree] Current level: %d, max: %d" % [current_level, talent["max"]])
	if current_level >= talent["max"]:
		print("[TalentTree] BLOCKED: Already at max level")
		return false
	
	var requires: Array = talent.get("requires", [])
	print("[TalentTree] Requires: %s" % [requires])
	print("[TalentTree] Unlocked talents for char %d: %s" % [char_id, _unlocked_talents.get(char_id, {})])
	for req_id in requires:
		var req_level: int = _unlocked_talents.get(char_id, {}).get(req_id, 0)
		print("[TalentTree] Requirement '%s' level: %d" % [req_id, req_level])
		if req_level <= 0:
			print("[TalentTree] BLOCKED: Missing requirement '%s'" % req_id)
			return false
	
	print("[TalentTree] CAN UNLOCK!")
	return true

func _on_talent_clicked(btn: Button) -> void:
	var talent: Dictionary = btn.get_meta("talent")
	var char_id: int = btn.get_meta("char_id")
	
	print("[TalentTree] CLICK on talent: char=%d, id=%s" % [char_id, talent["id"]])
	
	if not _can_unlock_talent(char_id, talent):
		print("[TalentTree] Cannot unlock - blocked")
		return
	
	var talent_id: String = talent["id"]
	if not _unlocked_talents.has(char_id):
		_unlocked_talents[char_id] = {}
	
	var current_level: int = _unlocked_talents[char_id].get(talent_id, 0)
	_unlocked_talents[char_id][talent_id] = current_level + 1
	_skill_points -= talent["cost"]
	
	print("[TalentTree] UNLOCKED %s! New state: %s" % [talent_id, _unlocked_talents[char_id]])
	
	emit_signal("talent_unlocked", char_id, talent_id)
	
	# Refresh the tree UI to show updated state
	_refresh_tree()
	
	# Only close if no skill points remaining
	if _skill_points <= 0:
		_on_close()

func _refresh_tree() -> void:
	var points := _tree_panel.get_node_or_null("TreeSkillPoints")
	if points:
		points.text = "Skill Points: %d" % _skill_points
	
	for btn in _talent_buttons:
		if is_instance_valid(btn):
			btn.queue_redraw()
	
	# Redraw lines
	if _lines_control:
		_lines_control.queue_redraw()

func _on_back_to_characters() -> void:
	_tree_panel.visible = false
	_character_panel.visible = true
	_current_character = -1
	_refresh_character_cards()

func _refresh_character_cards() -> void:
	var cards_row := _character_panel.get_child(3) if _character_panel.get_child_count() > 3 else null
	if not cards_row:
		return
	
	for i in range(cards_row.get_child_count()):
		var card: PanelContainer = cards_row.get_child(i)
		var vbox := card.get_child(0) as VBoxContainer
		if vbox:
			var count_label := vbox.get_node_or_null("CountLabel")
			if count_label:
				_update_card_count(count_label, i)
			var status_label := vbox.get_node_or_null("StatusLabel")
			if status_label:
				_update_card_status(status_label, i)
	
	var char_points := _character_panel.get_node_or_null("SkillPoints")
	if char_points:
		char_points.text = "Skill Points: %d" % _skill_points

func _on_close() -> void:
	visible = false
	emit_signal("tree_closed")

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event.is_action_pressed("ui_cancel"):
		if _tree_panel.visible:
			_on_back_to_characters()
		else:
			_on_close()
		get_viewport().set_input_as_handled()

# Public API
func show_tree() -> void:
	visible = true
	_character_panel.visible = true
	_tree_panel.visible = false
	_refresh_character_cards()

func add_skill_points(amount: int) -> void:
	_skill_points += amount
	_refresh_character_cards()

func get_skill_points() -> int:
	return _skill_points

func get_talent_level(char_id: int, talent_id: String) -> int:
	return _unlocked_talents.get(char_id, {}).get(talent_id, 0)

func is_talent_unlocked(char_id: int, talent_id: String) -> bool:
	return get_talent_level(char_id, talent_id) > 0

func get_unlocked_talents() -> Dictionary:
	return _unlocked_talents.duplicate(true)

func set_unlocked_talents(data: Dictionary) -> void:
	_unlocked_talents = data.duplicate(true)

# Helper methods for TalentTreeLines drawing
func get_talent_data(char_id: int) -> Array:
	return TALENT_DATA.get(char_id, [])

func get_unlocked_for_char(char_id: int) -> Dictionary:
	return _unlocked_talents.get(char_id, {})

func _apply_default_talents() -> void:
	for char_id in range(3):
		var talents: Array = TALENT_DATA[char_id]
		for talent in talents:
			if talent.get("default", false):
				if not _unlocked_talents.has(char_id):
					_unlocked_talents[char_id] = {}
				var talent_id: String = talent["id"]
				if not _unlocked_talents[char_id].has(talent_id):
					_unlocked_talents[char_id][talent_id] = 1
