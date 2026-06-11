extends Control
class_name TalentTree

## Talent Tree UI System - Clean container-based architecture
## Shows the run character's skill tree. Opens on level up (and TAB).

signal talent_unlocked(character_id: int, talent_id: String)
signal tree_closed

## The run's tree instance (set while a run is active). Used by
## ShopMenu.has_character_upgrade so gameplay code can query talent state.
static var instance: TalentTree = null

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

# UI References
var _main_panel: PanelContainer = null
var _tree_panel: VBoxContainer = null

# Character data - loaded from CharacterRegistry
var CHARACTER_NAMES: Array[String] = []
var _character_registry = null
var _game_state = null

# The run's selected character (registry index)
var _run_character: int = 0 # Default: Snow White

const TalentData = preload("res://scripts/ui/TalentData.gd")
var TALENT_DATA := TalentData.TALENT_DATA

# Tooltip UI reference
var _tooltip: PanelContainer = null

# Stats panel reference
var _stats_panel: PanelContainer = null
var _player_ref: Node = null # Reference to player for stats

# Player's unlocked talents (run-only, reset every run)
var _unlocked_talents: Dictionary = {0: {}, 1: {}, 2: {}, 3: {}, 4: {}, 5: {}, 6: {}, 7: {}, 8: {}, 9: {}, 10: {}}
var _skill_points: int = 0: set = set_skill_points
var _talent_buttons: Array = []
var _lines_control: Control = null

# Animation state for scanline effect
var _scanline_overlay: Control = null
var _anim_state := 0 # 0=hidden, 1=animating in, 2=showing, 3=animating out
var _anim_progress := 0.0
var _anim_time := 0.0
const ANIM_DURATION := 0.5
var _pending_unpause := false

func _ready() -> void:
	instance = self
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Ensure TalentTree is rendered above all other UI
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS # Process during pause

	# Load character data from registry
	_load_character_data()

	_build_ui()
	_build_scanline_overlay()
	visible = false

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _load_character_data() -> void:
	# Get registry using class_name directly
	_character_registry = CharacterRegistry.get_instance()

	# Get GameManager (it's an autoload singleton)
	var game_state_node = get_node_or_null("/root/GameManager")
	if game_state_node:
		_game_state = game_state_node
		_run_character = _game_state.player_character_index

	# Load character names from registry
	if _character_registry:
		var char_ids: Array = _character_registry.get_all_character_ids()
		for id in char_ids:
			var char_data = _character_registry.get_character(id)
			if char_data:
				CHARACTER_NAMES.append(char_data.display_name)
	else:
		# Fallback if registry not available
		CHARACTER_NAMES = ["Snow White", "Scarlet", "Rapunzel", "Nayuta", "Commander", "Marian", "Crown", "Kilo", "Cecil", "Sin", "Wells"]

func _build_ui() -> void:
	# Full screen dark overlay
	var overlay := ColorRect.new()
	overlay.color = UI.BG_OVERLAY
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# Main centered container - above the overlay
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	# Outer HBox to hold stats panel + main panel
	var outer_hbox := HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", 15)
	center.add_child(outer_hbox)
	
	# Stats panel on the left (HoloCure style)
	_stats_panel = _build_stats_panel()
	outer_hbox.add_child(_stats_panel)
	
	# Main panel with border
	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(820, 700)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI.BG_DEEP
	panel_style.border_color = UI.ACCENT_PRIMARY_DIM
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(15)
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	outer_hbox.add_child(_main_panel)
	
	# Content container
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_panel.add_child(content)

	# Tree panel - built directly for the run's character
	_tree_panel = VBoxContainer.new()
	_tree_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tree_panel.add_theme_constant_override("separation", 15)
	content.add_child(_tree_panel)
	_build_tree_view(_run_character)

	# Create tooltip (added last so it renders on top)
	_create_tooltip()

func _build_scanline_overlay() -> void:
	# Create scanline overlay for cyberpunk animation effect - positioned over the main panel
	_scanline_overlay = Control.new()
	_scanline_overlay.name = "ScanlineOverlay"
	_scanline_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scanline_overlay.z_index = 200
	_scanline_overlay.visible = false
	_scanline_overlay.clip_contents = true # Clip to bounds
	add_child(_scanline_overlay)
	_scanline_overlay.draw.connect(_draw_scanline_overlay)

func _draw_scanline_overlay() -> void:
	if _anim_state == 0 or _anim_state == 2:
		return
	
	# Draw relative to overlay size (which matches main panel)
	var panel_size := _scanline_overlay.size
	var intensity := 0.0
	
	if _anim_state == 1: # Animating in
		intensity = 1.0 - _anim_progress
	elif _anim_state == 3: # Animating out
		intensity = _anim_progress
	
	# Fine scanline effect - more detail as requested
	var scanline_count := 40 # More scanlines for finer detail
	var scanline_color := Color(0.3, 0.8, 1.0, intensity * 0.5)
	var glow_color := Color(0.2, 0.6, 0.9, intensity * 0.25)
	
	for i in range(scanline_count):
		var y_base := (float(i) / scanline_count) * panel_size.y
		var wave := sin(_anim_time * 15.0 + float(i) * 0.5) * 2.0
		var y := y_base + wave
		
		# Flickering scanlines - faster, finer
		var flicker := (sin(_anim_time * 30.0 + float(i) * 1.8) + 1.0) * 0.5
		if flicker > 0.3:
			_scanline_overlay.draw_line(Vector2(0, y), Vector2(panel_size.x, y), glow_color, 4.0)
			_scanline_overlay.draw_line(Vector2(0, y), Vector2(panel_size.x, y), scanline_color, 1.0)
	
	# Digital noise pixels - small glitchy squares
	var pixel_count := int(intensity * 30)
	for i in range(pixel_count):
		var px := fmod(_anim_time * 80.0 * (float(i) + 1.0) + float(i) * 23.0, panel_size.x)
		var py := fmod(_anim_time * 60.0 * (float(i) + 0.5) + float(i) * 37.0, panel_size.y)
		var pixel_size := randf_range(2.0, 6.0) * intensity
		var pixel_color := Color(0.4, 0.9, 1.0, intensity * 0.6)
		_scanline_overlay.draw_rect(Rect2(px, py, pixel_size, pixel_size), pixel_color)
	
	# Horizontal glitch bars - smaller, more subtle
	var glitch_count := int(intensity * 4)
	for i in range(glitch_count):
		var glitch_y := fmod(_anim_time * 200.0 + float(i) * 80.0, panel_size.y)
		var glitch_width := randf_range(40.0, 120.0) * intensity
		var glitch_x := fmod(_anim_time * 150.0 * (float(i) + 1.0), panel_size.x)
		var glitch_color := Color(0.3, 0.9, 1.0, intensity * 0.4)
		_scanline_overlay.draw_rect(Rect2(glitch_x, glitch_y, glitch_width, 2.0), glitch_color)
	
	# Edge glow on panel borders
	var edge_glow := Color(0.2, 0.7, 1.0, intensity * 0.5)
	_scanline_overlay.draw_rect(Rect2(0, 0, panel_size.x, 3), edge_glow)
	_scanline_overlay.draw_rect(Rect2(0, panel_size.y - 3, panel_size.x, 3), edge_glow)
	_scanline_overlay.draw_rect(Rect2(0, 0, 3, panel_size.y), edge_glow)
	_scanline_overlay.draw_rect(Rect2(panel_size.x - 3, 0, 3, panel_size.y), edge_glow)

func _process(delta: float) -> void:
	if _anim_state == 0:
		return
	
	_anim_time += delta
	
	if _anim_state == 1: # Animating in
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_progress = 1.0
			_anim_state = 2
			if _scanline_overlay:
				_scanline_overlay.visible = false
		else:
			if _scanline_overlay:
				_scanline_overlay.queue_redraw()
		# Fade in content
		modulate.a = _anim_progress
		
	elif _anim_state == 3: # Animating out
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_progress = 1.0
			_finish_close()
		else:
			if _scanline_overlay:
				_scanline_overlay.queue_redraw()
		# Fade out content
		modulate.a = 1.0 - _anim_progress

func _finish_close() -> void:
	_anim_state = 0
	visible = false
	modulate.a = 1.0
	if _scanline_overlay:
		_scanline_overlay.visible = false
	# Always unpause on close to resume gameplay
	_pending_unpause = false
	get_tree().paused = false
	emit_signal("tree_closed")

func _build_stats_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 700)
	
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_color = UI.ACCENT_PRIMARY_DIM
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(15)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "STATS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	vbox.add_child(title)
	
	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)
	
	# Character name display (shows which character stats are for)
	var char_label := Label.new()
	char_label.name = "CharLabel"
	char_label.text = "Current"
	char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_label.add_theme_font_size_override("font_size", 16)
	char_label.add_theme_color_override("font_color", UI.TALENT_HOVER_BORDER)
	vbox.add_child(char_label)
	
	# Small spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 5)
	vbox.add_child(spacer1)
	
	# Level display
	var level_row := _create_stat_row("LVL", "1", Color(1.0, 0.85, 0.3))
	level_row.name = "LevelRow"
	vbox.add_child(level_row)
	
	# Small spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)
	
	# ATK stat (multiplier based on level)
	var atk_row := _create_stat_row("ATK", "1x", Color(1.0, 0.4, 0.4))
	atk_row.name = "AtkRow"
	vbox.add_child(atk_row)
	
	# HP stat
	var hp_row := _create_stat_row("HP", "10", Color(0.4, 1.0, 0.4))
	hp_row.name = "HpRow"
	vbox.add_child(hp_row)
	
	# Burst Gen Rate stat (% per hit)
	var burst_row := _create_stat_row("BURST GEN", "5%", Color(0.4, 0.7, 1.0))
	burst_row.name = "BurstRow"
	vbox.add_child(burst_row)
	
	# Speed stat (actual value)
	var speed_row := _create_stat_row("SPEED", "400", Color(0.9, 0.7, 1.0))
	speed_row.name = "SpeedRow"
	vbox.add_child(speed_row)
	
	# Crit Rate stat
	var crit_row := _create_stat_row("CRIT RATE", "20%", Color(1.0, 0.6, 0.2))
	crit_row.name = "CritRow"
	vbox.add_child(crit_row)
	
	# Fill remaining space
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(filler)
	
	return panel

func _create_stat_row(label_text: String, value_text: String, value_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	
	# Stat name
	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	
	# Stat value
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", 20)
	value_label.add_theme_color_override("font_color", value_color)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	
	return row

func _update_stats_panel(char_id: int = -1) -> void:
	if _stats_panel == null:
		return

	# Stats always show the run's character
	var display_char: int = char_id if char_id >= 0 else _run_character

	# Update character label
	var char_name: String = CHARACTER_NAMES[display_char] if display_char >= 0 and display_char < CHARACTER_NAMES.size() else "Current"
	_set_char_label(char_name)
	
	# Get base character stats from CharacterRegistry for the hovered character
	# This shows the character's BASE stats, not the current player's in-game stats
	var current_level: int = 1
	var display_damage: int = 1
	var display_hp: int = 10
	var display_speed: int = 400
	var display_crit: float = 0.2
	var burst_rate: float = 1.0
	
	# Get level from player if in-game
	if _player_ref and is_instance_valid(_player_ref) and "level" in _player_ref:
		current_level = _player_ref.level
	
	# Always get base stats from the hovered character's data (not the player)
	if _character_registry:
		var char_data = _character_registry.get_character_by_index(display_char)
		if char_data:
			display_damage = int(char_data.base_damage)
			display_hp = char_data.base_hp
			display_speed = int(char_data.base_speed)
			display_crit = char_data.crit_chance if "crit_chance" in char_data else 0.2
			
			# Get burst rate from BurstConfig based on weapon type
			var weapon_type := _get_weapon_type_for_index(display_char)
			burst_rate = BurstConfig.get_rate(weapon_type)
	
	# Update labels with current values
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
			var bonus_atk = int(scaled_damage * low_hp_mult)
			_set_stat_value("AtkRow", "%d (+%d%%)" % [bonus_atk, int((low_hp_mult - 1.0) * 100)])
		else:
			_set_stat_value("AtkRow", _format_stat_with_bonus(scaled_damage, atk_bonus, true))
	else:
		_set_stat_value("AtkRow", _format_stat_with_bonus(scaled_damage, atk_bonus, true))
	
	_set_stat_value("HpRow", _format_stat_with_flat_bonus(display_hp, hp_bonus))
	_set_stat_value("BurstRow", "%.1f%%" % burst_rate if burst_rate < 1.0 else "%.0f%%" % burst_rate)
	@warning_ignore("integer_division")
	_set_stat_value("SpeedRow", _format_stat_with_bonus(display_speed / 10, speed_bonus, true))
	_set_stat_value("CritRow", _format_crit_with_bonus(display_crit, crit_bonus))

## Format stat with percentage bonus (e.g., "10 +25%")
func _format_stat_with_bonus(base_value: int, bonus: float, is_percent: bool) -> String:
	if bonus > 0 and is_percent:
		return "%d +%d%%" % [base_value, int(bonus * 100)]
	return str(base_value)

## Format stat with flat bonus (e.g., "10 +5")
func _format_stat_with_flat_bonus(base_value: int, bonus: int) -> String:
	if bonus > 0:
		return "%d +%d" % [base_value, bonus]
	return str(base_value)

## Format crit with bonus (e.g., "20% +4%")
func _format_crit_with_bonus(base_crit: float, bonus: float) -> String:
	var base_pct := int(base_crit * 100.0)
	if bonus > 0:
		return "%d%% +%d%%" % [base_pct, int(bonus * 100)]
	return "%.0f%%" % (base_crit * 100.0)

func _set_char_label(char_name: String) -> void:
	if _stats_panel == null:
		return
	var vbox := _stats_panel.get_child(0)
	var char_label := vbox.get_node_or_null("CharLabel")
	if char_label != null:
		char_label.text = char_name

func _set_stat_value(row_name: String, value: String) -> void:
	if _stats_panel == null:
		return
	var vbox := _stats_panel.get_child(0)
	var row := vbox.get_node_or_null(row_name)
	if row != null:
		var value_label := row.get_node_or_null("Value")
		if value_label != null:
			value_label.text = value

func _get_weapon_type_for_index(char_index: int) -> String:
	# Map character index to weapon type for BurstConfig lookup
	# Indices: 0=snow_white, 1=scarlet, 2=rapunzel, 3=nayuta, 4=commander, 
	#          5=marian, 6=crown, 7=kilo, 8=cecil, 9=sin
	match char_index:
		0: # Snow White
			return "sniper"
		1: # Scarlet
			return "sword"
		2: # Rapunzel
			return "rocket"
		3: # Nayuta
			return "smg"
		4: # Commander
			return "assault"
		5: # Marian
			return "minigun"
		6: # Crown
			return "minigun"
		7: # Kilo
			return "shotgun"
		8: # Cecil
			return "smg"
		9: # Sin
			return "smg"
		10: # Wells
			return "sniper"
		_:
			return "smg"

func _style_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	normal.border_color = UI.ACCENT_PRIMARY_DIM
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.12, 0.12, 0.18, 1.0)
	hover.border_color = UI.TALENT_HOVER_BORDER
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

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
	title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	title_bar.add_child(title)
	
	# Skill points
	var points := Label.new()
	points.name = "TreeSkillPoints"
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_font_size_override("font_size", 22)
	points.add_theme_color_override("font_color", UI.TALENT_HOVER_BORDER)
	points.text = "Skill Points: %d" % _skill_points
	_tree_panel.add_child(points)
	
	# Tree container panel (holds lines and nodes)
	var tree_panel := PanelContainer.new()
	tree_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tree_panel.custom_minimum_size = Vector2(720, 445)
	var tree_style := StyleBoxFlat.new()
	tree_style.bg_color = Color(0.03, 0.03, 0.05, 1.0)
	tree_style.border_color = Color(0.5, 0.5, 0.55, 1.0)
	tree_style.set_border_width_all(2)
	tree_style.set_corner_radius_all(8)
	tree_style.set_content_margin_all(10)
	tree_panel.add_theme_stylebox_override("panel", tree_style)
	_tree_panel.add_child(tree_panel)
	
	var tree_holder := Control.new()
	tree_holder.custom_minimum_size = Vector2(700, 425)
	tree_panel.add_child(tree_holder)
	
	# Lines layer (behind nodes) - uses custom drawing
	_lines_control = Control.new()
	_lines_control.name = "Lines"
	_lines_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines_control.set_script(preload("res://scripts/ui/TalentTreeLines.gd"))
	# Set meta AFTER script is applied to ensure it's not cleared
	_lines_control.set_meta("tree_ref", self)
	_lines_control.set_meta("char_id", char_id)
	tree_holder.add_child(_lines_control)
	
	# Create talent nodes in a grid
	var talents: Array = TALENT_DATA[char_id]
	var node_width: float = 180.0
	var node_height: float = 90.0
	var h_spacing: float = 230.0
	var v_spacing: float = 155.0 # Increased from 105 to fill tree_holder height better
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
	
	# Close button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tree_panel.add_child(btn_row)

	var close_btn := Button.new()
	close_btn.text = "✕ CLOSE"
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.custom_minimum_size = Vector2(160, 50)
	close_btn.pressed.connect(_on_close)
	_style_button(close_btn)
	btn_row.add_child(close_btn)

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
	_tooltip.z_index = 200 # Above everything
	_tooltip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tooltip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.02, 0.02, 0.04, 0.98)
	tooltip_style.border_color = Color(1.0, 0.85, 0.2, 1.0) # Golden border
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
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0)) # Golden title
	vbox.add_child(title_label)
	
	# Short description
	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0)) # White
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
	tooltip_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1.0)) # Slightly dimmer white
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
	var bg_color := Color(0.08, 0.08, 0.1, 1.0) # Dark gray when locked
	var border_color := UI.TALENT_LOCKED
	
	# Determine talent type
	var is_special: bool = talent.get("special", false)
	var is_burst: bool = talent.get("burst", false)
	
	# Set colors based on state and type
	if is_burst:
		# Red/Crimson for burst
		if is_maxed:
			bg_color = Color(0.6, 0.15, 0.15, 1.0) # Bright red
			border_color = Color(1.0, 0.4, 0.4, 1.0)
		elif is_unlocked:
			bg_color = Color(0.45, 0.1, 0.1, 1.0) # Medium red
			border_color = Color(0.9, 0.3, 0.3, 1.0)
		else:
			bg_color = Color(0.15, 0.05, 0.05, 1.0) # Dark red
	elif is_special:
		# Yellow/Gold for special
		if is_maxed:
			bg_color = Color(0.5, 0.4, 0.1, 1.0) # Bright gold
			border_color = Color(1.0, 0.85, 0.3, 1.0)
		elif is_unlocked:
			bg_color = Color(0.4, 0.3, 0.08, 1.0) # Medium gold
			border_color = Color(0.9, 0.75, 0.25, 1.0)
		else:
			bg_color = Color(0.12, 0.1, 0.03, 1.0) # Dark gold
	else:
		# Green for regular upgrades
		if is_maxed:
			bg_color = Color(0.15, 0.4, 0.15, 1.0) # Bright green
			border_color = UI.TALENT_UNLOCKED
		elif is_unlocked:
			bg_color = Color(0.1, 0.25, 0.1, 1.0) # Medium green
			border_color = Color(0.6, 0.8, 0.3, 1.0)
		elif can_unlock:
			border_color = UI.TALENT_HOVER_BORDER if hovered else border_color
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
	var name_color := UI.TEXT_PRIMARY if (is_unlocked or can_unlock) else UI.TALENT_LOCKED
	var name_size := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var name_x := (btn.size.x - name_size.x) / 2.0
	btn.draw_string(font, Vector2(name_x, 32), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_color)
	
	# Level
	var level_text := "%d / %d" % [current_level, max_level]
	var level_color := UI.TALENT_UNLOCKED if is_maxed else (UI.TEXT_SECONDARY if is_unlocked else UI.TALENT_LOCKED)
	var level_size := font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var level_x := (btn.size.x - level_size.x) / 2.0
	btn.draw_string(font, Vector2(level_x, 56), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, level_color)
	
	# Cost
	if not is_maxed and can_unlock:
		var cost_text := "Cost: %d" % talent["cost"]
		var cost_size := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var cost_x := (btn.size.x - cost_size.x) / 2.0
		btn.draw_string(font, Vector2(cost_x, 78), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TALENT_HOVER_BORDER)

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
	self._skill_points -= talent["cost"]
	
	# Play confirm sound for successful purchase
	UISounds.play_confirm()
	
	print("[TalentTree] UNLOCKED %s! New state: %s" % [talent_id, _unlocked_talents[char_id]])
	
	# Track skill purchase for achievement
	if has_node("/root/AchievementManager"):
		get_node("/root/AchievementManager").on_skill_purchased(char_id, talent_id)
	
	emit_signal("talent_unlocked", char_id, talent_id)
	
	# Refresh the tree UI to show updated state
	_refresh_tree()
	
	# Only close if no skill points remaining - with delay for player to prepare
	if _skill_points <= 0:
		_on_close(true) # true = with delay before unpause

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
	
	# Update stats (talents may modify player stats)
	_update_stats_panel()

func _on_close(with_delay: bool = false) -> void:
	UISounds.play_back()
	# Start close animation
	_anim_state = 3
	_anim_progress = 0.0
	_anim_time = 0.0
	_pending_unpause = with_delay

	# Position scanline overlay over main panel
	if _scanline_overlay and _main_panel:
		_scanline_overlay.global_position = _main_panel.global_position
		_scanline_overlay.size = _main_panel.size
		_scanline_overlay.visible = true
		_scanline_overlay.queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event.is_action_pressed("ui_cancel"):
		_on_close()
		get_viewport().set_input_as_handled()

# Public API
func show_tree(player: Node = null) -> void:
	if player != null:
		_player_ref = player
	else:
		# Try to find player automatically
		_player_ref = get_tree().get_first_node_in_group("player")
		if _player_ref == null:
			_player_ref = get_node_or_null("/root/Level/Player")
	
	# Start open animation
	visible = true
	modulate.a = 0.0
	_anim_state = 1
	_anim_progress = 0.0
	_anim_time = 0.0
	
	# Pause the game (and timers)
	get_tree().paused = true
	_pending_unpause = true
	
	# Position scanline overlay over main panel after a frame so layout is computed
	if _scanline_overlay and _main_panel:
		await get_tree().process_frame
		_scanline_overlay.global_position = _main_panel.global_position
		_scanline_overlay.size = _main_panel.size
		_scanline_overlay.visible = true
		_scanline_overlay.queue_redraw()
	
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

	# Update UI if valid
	if _tree_panel:
		var points := _tree_panel.get_node_or_null("TreeSkillPoints")
		if points:
			points.text = "Skill Points: %d" % _skill_points
