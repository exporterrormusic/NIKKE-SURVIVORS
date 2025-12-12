extends Panel
class_name StatsPanel
## Displays per-character damage and kill statistics for a run.
##
## Used in both the PauseMenu (live stats) and LeaderboardMenu (historical).
## Shows character portraits with damage bars and kill counts.

const UI := preload("res://scripts/ui/UITheme.gd")

# Data source
var _stats_data: Dictionary = {}  # From RunStatsTracker or leaderboard entry
var _squad_indices: Array = []     # Character indices in the squad

# UI elements
var _title_label: Label = null
var _content: VBoxContainer = null
var _character_registry = null

func _ready() -> void:
	_build_ui()
	_load_registry()

func _load_registry() -> void:
	# Use the CharacterRegistry singleton
	var registry_script = load("res://scripts/characters/CharacterRegistry.gd")
	if registry_script and registry_script.has_method("get_instance"):
		_character_registry = registry_script.get_instance()

func _build_ui() -> void:
	# Apply panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.98)
	style.border_color = Color(0.5, 0.5, 0.6, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", style)
	
	custom_minimum_size = Vector2(400, 520)
	
	# Main container
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# Title
	_title_label = Label.new()
	_title_label.text = "SQUAD STATS"
	_title_label.add_theme_font_override("font", UI.FONT_TITLE)
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)
	
	# Divider
	var divider := ColorRect.new()
	divider.color = UI.DIVIDER_SUBTLE
	divider.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(divider)
	
	# Content container for character entries
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	vbox.add_child(_content)

## Set stats from RunStatsTracker (live mode)
func set_live_stats() -> void:
	var run_stats_tracker = get_node_or_null("/root/RunStatsTracker")
	var game_state = get_node_or_null("/root/GameState")
	if run_stats_tracker and game_state:
		_stats_data = run_stats_tracker.get_run_stats()
		_squad_indices = game_state.selected_character_indices.duplicate()
		_refresh_display()

## Set stats from a leaderboard entry (historical mode)
func set_entry_stats(entry: Dictionary) -> void:
	_stats_data = entry.get("run_stats", {})
	_squad_indices = entry.get("squad_indices", [])
	
	# Fallback for old saves: try to derive squad from damage stats
	if _squad_indices.is_empty() and not _stats_data.is_empty():
		var damage_data = _stats_data.get("damage_by_character", {})
		if not damage_data.is_empty():
			_squad_indices = damage_data.keys()
			_squad_indices.sort() # Sort by index since we lost original slot order
	
	_refresh_display()

func _refresh_display() -> void:
	# Clear existing content
	for child in _content.get_children():
		child.queue_free()
	
	if _squad_indices.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No squad data"
		empty_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(empty_label)
		return
	
	# Get damage data for max calculation
	var damage_data: Dictionary = _stats_data.get("damage_by_character", {})
	var max_damage := 1  # Avoid div by zero
	for char_idx in _squad_indices:
		var dmg: int = damage_data.get(char_idx, 0)
		max_damage = max(max_damage, dmg)
	
	# Create entry for each squad member
	for char_idx in _squad_indices:
		var entry := _create_character_entry(char_idx, max_damage)
		_content.add_child(entry)
	
	# Add totals section
	var totals := _create_totals_section()
	_content.add_child(totals)

func _create_character_entry(char_idx: int, max_damage: int) -> Control:
	var container := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.1, 0.14, 0.9)
	panel_style.border_color = Color(0.4, 0.4, 0.5, 0.6)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(12)
	container.add_theme_stylebox_override("panel", panel_style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	container.add_child(hbox)
	
	# Character portrait
	var portrait_panel := Panel.new()
	portrait_panel.custom_minimum_size = Vector2(80, 80)
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.12, 0.12, 0.16)
	portrait_style.set_corner_radius_all(4)
	portrait_panel.add_theme_stylebox_override("panel", portrait_style)
	hbox.add_child(portrait_panel)
	
	var portrait := TextureRect.new()
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = _get_character_portrait(char_idx)
	portrait_panel.add_child(portrait)
	
	# Name and stats
	var stats_vbox := VBoxContainer.new()
	stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(stats_vbox)
	
	# Character name
	var name_label := Label.new()
	name_label.text = _get_character_name(char_idx)
	name_label.add_theme_font_override("font", UI.FONT_BOLD)
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	stats_vbox.add_child(name_label)
	
	# Get this character's stats
	var damage_data: Dictionary = _stats_data.get("damage_by_character", {})
	var normal_kills_data: Dictionary = _stats_data.get("normal_kills_by_character", {})
	var boss_kills_data: Dictionary = _stats_data.get("boss_kills_by_character", {})
	
	var damage: int = damage_data.get(char_idx, 0)
	var normal_kills: int = normal_kills_data.get(char_idx, 0)
	var boss_kills: int = boss_kills_data.get(char_idx, 0)
	
	# Damage bar (restored)
	var damage_bar := ProgressBar.new()
	damage_bar.custom_minimum_size = Vector2(100, 18)
	damage_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	damage_bar.max_value = max_damage
	damage_bar.value = damage
	damage_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.2)
	bar_bg.set_corner_radius_all(4)
	damage_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = UI.STAT_ATK
	bar_fill.set_corner_radius_all(4)
	damage_bar.add_theme_stylebox_override("fill", bar_fill)
	stats_vbox.add_child(damage_bar)
	
	# Kills row
	var kills_hbox := HBoxContainer.new()
	kills_hbox.add_theme_constant_override("separation", 24)
	kills_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_vbox.add_child(kills_hbox)
	
	# Normal kills
	var normal_label := Label.new()
	normal_label.text = "Kills: %d" % normal_kills
	normal_label.add_theme_font_size_override("font_size", 18)
	normal_label.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	kills_hbox.add_child(normal_label)
	
	# Boss kills
	var boss_label := Label.new()
	boss_label.text = "Bosses: %d" % boss_kills
	boss_label.add_theme_font_size_override("font_size", 18)
	boss_label.add_theme_color_override("font_color", UI.COLOR_DANGER)
	kills_hbox.add_child(boss_label)
	
	return container

func _create_totals_section() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	
	# Divider
	var divider := ColorRect.new()
	divider.color = UI.DIVIDER_SUBTLE
	divider.custom_minimum_size = Vector2(0, 1)
	container.add_child(divider)
	
	# Calculate totals
	var damage_data: Dictionary = _stats_data.get("damage_by_character", {})
	var normal_kills_data: Dictionary = _stats_data.get("normal_kills_by_character", {})
	var boss_kills_data: Dictionary = _stats_data.get("boss_kills_by_character", {})
	
	var total_damage := 0
	var total_normal := 0
	var total_boss := 0
	
	for val in damage_data.values():
		total_damage += val
	for val in normal_kills_data.values():
		total_normal += val
	for val in boss_kills_data.values():
		total_boss += val
	
	# Totals row
	var title_lbl := Label.new()
	title_lbl.text = "SQUAD TOTAL"
	title_lbl.add_theme_font_override("font", UI.FONT_BOLD)
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title_lbl)
	
	# Stats row
	var totals_hbox := HBoxContainer.new()
	totals_hbox.add_theme_constant_override("separation", 32)
	totals_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(totals_hbox)
	
	# Kills total
	var kills_total := Label.new()
	kills_total.text = "Kills: %d" % total_normal
	kills_total.add_theme_font_size_override("font_size", 20)
	kills_total.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	totals_hbox.add_child(kills_total)
	
	# Boss total
	var boss_total := Label.new()
	boss_total.text = "Bosses: %d" % total_boss
	boss_total.add_theme_font_size_override("font_size", 20)
	boss_total.add_theme_color_override("font_color", UI.COLOR_DANGER)
	totals_hbox.add_child(boss_total)
	
	return container

func _format_score(value: int) -> String:
	# Format with comma separators
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return result

func _get_character_name(char_idx: int) -> String:
	if _character_registry and _character_registry.has_method("get_character_name_by_index"):
		var name = _character_registry.get_character_name_by_index(char_idx)
		if name and name != "":
			return name
	return "Character %d" % (char_idx + 1)

func _get_character_portrait(char_idx: int) -> Texture2D:
	if _character_registry:
		# Get the character ID from index
		if _character_registry.has_method("get_character_id"):
			var char_id: String = _character_registry.get_character_id(char_idx)
			if char_id and char_id != "":
				# Use the registry's get_portrait method
				if _character_registry.has_method("get_portrait"):
					var portrait = _character_registry.get_portrait(char_id)
					if portrait:
						return portrait
				# Fallback: build path manually
				var folder = char_id.replace("_", "-")
				var path = "res://assets/characters/%s/portrait-sq.png" % folder
				if ResourceLoader.exists(path):
					return load(path)
	return null

func _format_number(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)
