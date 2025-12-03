extends Control
class_name AchievementsMenu
## Displays achievements, stats, and character-specific accomplishments.

signal back_requested

# Achievement categories
enum Category { ALL, COMBAT, EXPLORATION, CHARACTERS, CHALLENGES }

# Visual constants
const BG_COLOR := Color(0.08, 0.08, 0.12, 0.98)
const HEADER_COLOR := Color(0.95, 0.95, 1.0)
const UNLOCKED_COLOR := Color(0.7, 0.85, 1.0)
const LOCKED_COLOR := Color(0.4, 0.4, 0.5)
const PROGRESS_BG := Color(0.15, 0.15, 0.2)
const PROGRESS_FILL := Color(0.4, 0.7, 1.0)

# Achievement data structure
var _achievements: Array[Dictionary] = []
var _current_category: Category = Category.ALL
var _character_filter: String = ""

# Character registry
var _registry: RefCounted = null

# UI refs
@onready var _background: Panel = $Background
@onready var _title_label: Label = $UiRoot/VBoxContainer/TitlePanel/Title
@onready var _stats_label: Label = $UiRoot/VBoxContainer/TitlePanel/StatsLabel
@onready var _category_buttons: HBoxContainer = $UiRoot/VBoxContainer/CategoryBar
@onready var _achievement_list: VBoxContainer = $UiRoot/VBoxContainer/ContentPanel/ScrollContainer/AchievementList
@onready var _back_button: Button = $UiRoot/VBoxContainer/BottomBar/BackButton
@onready var _character_filter_button: Button = $UiRoot/VBoxContainer/CategoryBar/CharacterFilter


func _ready() -> void:
	_load_registry()
	_load_achievements()
	_setup_ui()
	_connect_signals()
	_populate_achievements()


func _load_registry() -> void:
	var CharacterRegistryClass = load("res://scripts/characters/CharacterRegistry.gd")
	if CharacterRegistryClass:
		_registry = CharacterRegistryClass.get_instance()


func _load_achievements() -> void:
	# Define achievements
	# In a full implementation, this would load from a save file
	_achievements = [
		# Combat achievements
		{
			"id": "first_blood",
			"title": "First Blood",
			"description": "Defeat your first enemy",
			"category": Category.COMBAT,
			"unlocked": true,
			"progress": 1,
			"target": 1,
		},
		{
			"id": "kill_100",
			"title": "Century Slayer",
			"description": "Defeat 100 enemies in a single run",
			"category": Category.COMBAT,
			"unlocked": false,
			"progress": 67,
			"target": 100,
		},
		{
			"id": "kill_1000",
			"title": "Massacre",
			"description": "Defeat 1000 enemies total",
			"category": Category.COMBAT,
			"unlocked": false,
			"progress": 423,
			"target": 1000,
		},
		{
			"id": "boss_slayer",
			"title": "Boss Slayer",
			"description": "Defeat a boss enemy",
			"category": Category.COMBAT,
			"unlocked": false,
			"progress": 0,
			"target": 1,
		},
		{
			"id": "no_damage",
			"title": "Untouchable",
			"description": "Complete a wave without taking damage",
			"category": Category.CHALLENGES,
			"unlocked": false,
			"progress": 0,
			"target": 1,
		},
		
		# Exploration achievements
		{
			"id": "all_maps",
			"title": "World Traveler",
			"description": "Play on all maps",
			"category": Category.EXPLORATION,
			"unlocked": false,
			"progress": 2,
			"target": 4,
		},
		{
			"id": "night_owl",
			"title": "Night Owl",
			"description": "Complete a run at midnight",
			"category": Category.EXPLORATION,
			"unlocked": false,
			"progress": 0,
			"target": 1,
		},
		
		# Character achievements
		{
			"id": "scarlet_mastery",
			"title": "Scarlet Mastery",
			"description": "Win 10 runs with Scarlet",
			"category": Category.CHARACTERS,
			"character": "scarlet",
			"unlocked": false,
			"progress": 3,
			"target": 10,
		},
		{
			"id": "nayuta_clones",
			"title": "Clone Army",
			"description": "Have 5 Nayuta clones active at once",
			"category": Category.CHARACTERS,
			"character": "nayuta",
			"unlocked": true,
			"progress": 5,
			"target": 5,
		},
		{
			"id": "snow_white_sniper",
			"title": "Sharpshooter",
			"description": "Hit 50 enemies in a row without missing as Snow White",
			"category": Category.CHARACTERS,
			"character": "snow_white",
			"unlocked": false,
			"progress": 23,
			"target": 50,
		},
		
		# Challenge achievements
		{
			"id": "speed_run",
			"title": "Speed Demon",
			"description": "Complete wave 10 in under 5 minutes",
			"category": Category.CHALLENGES,
			"unlocked": false,
			"progress": 0,
			"target": 1,
		},
		{
			"id": "max_level",
			"title": "Fully Powered",
			"description": "Reach max level in a single run",
			"category": Category.CHALLENGES,
			"unlocked": false,
			"progress": 0,
			"target": 1,
		},
	]


func _setup_ui() -> void:
	# Style background
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BG_COLOR
	if _background:
		_background.add_theme_stylebox_override("panel", bg_style)
	
	# Try to load fonts
	var title_font = load("res://resources/fonts/futura_condensed_extra_bold.tres") as Font
	
	if _title_label:
		_title_label.text = "ACHIEVEMENTS"
		_title_label.add_theme_color_override("font_color", HEADER_COLOR)
		if title_font:
			_title_label.add_theme_font_override("font", title_font)
		_title_label.add_theme_font_size_override("font_size", 48)
	
	_update_stats_label()
	_setup_category_buttons()


func _update_stats_label() -> void:
	if not _stats_label:
		return
	
	var unlocked := 0
	for achievement in _achievements:
		if achievement.unlocked:
			unlocked += 1
	
	_stats_label.text = "%d / %d Unlocked" % [unlocked, _achievements.size()]


func _setup_category_buttons() -> void:
	if not _category_buttons:
		return
	
	# Clear existing buttons except character filter
	for child in _category_buttons.get_children():
		if child != _character_filter_button:
			child.queue_free()
	
	# Add category buttons
	var categories := ["All", "Combat", "Exploration", "Characters", "Challenges"]
	for i in range(categories.size()):
		var btn := Button.new()
		btn.text = categories[i]
		btn.custom_minimum_size = Vector2(120, 36)
		btn.pressed.connect(_on_category_selected.bind(i))
		_category_buttons.add_child(btn)
		_category_buttons.move_child(btn, i)


func _connect_signals() -> void:
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)
	if _character_filter_button:
		_character_filter_button.pressed.connect(_on_character_filter_pressed)


func _populate_achievements() -> void:
	if not _achievement_list:
		return
	
	# Clear existing
	for child in _achievement_list.get_children():
		child.queue_free()
	
	# Filter achievements
	var filtered: Array[Dictionary] = []
	for achievement in _achievements:
		# Category filter
		if _current_category != Category.ALL and achievement.category != _current_category:
			continue
		# Character filter
		if _character_filter != "" and achievement.get("character", "") != _character_filter:
			continue
		filtered.append(achievement)
	
	# Sort: unlocked first, then by progress percentage
	filtered.sort_custom(func(a, b):
		if a.unlocked != b.unlocked:
			return a.unlocked  # unlocked first
		var progress_a: float = float(a.progress) / float(a.target)
		var progress_b: float = float(b.progress) / float(b.target)
		return progress_a > progress_b
	)
	
	# Create achievement items
	for achievement in filtered:
		var item := _create_achievement_item(achievement)
		_achievement_list.add_child(item)


func _create_achievement_item(achievement: Dictionary) -> Control:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(0, 80)
	
	# Style container
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.9) if achievement.unlocked else Color(0.08, 0.08, 0.1, 0.7)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = UNLOCKED_COLOR if achievement.unlocked else Color(0.25, 0.25, 0.3)
	container.add_theme_stylebox_override("panel", style)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	container.add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)
	
	# Icon placeholder
	var icon := Panel.new()
	icon.custom_minimum_size = Vector2(56, 56)
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = UNLOCKED_COLOR if achievement.unlocked else LOCKED_COLOR
	icon_style.set_corner_radius_all(8)
	icon.add_theme_stylebox_override("panel", icon_style)
	hbox.add_child(icon)
	
	# Text content
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(text_vbox)
	
	# Title
	var title := Label.new()
	title.text = achievement.title
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UNLOCKED_COLOR if achievement.unlocked else Color(0.7, 0.7, 0.75))
	text_vbox.add_child(title)
	
	# Description
	var desc := Label.new()
	desc.text = achievement.description
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	text_vbox.add_child(desc)
	
	# Progress bar (if not unlocked and has progress)
	if not achievement.unlocked and achievement.target > 1:
		var progress_container := HBoxContainer.new()
		progress_container.add_theme_constant_override("separation", 8)
		text_vbox.add_child(progress_container)
		
		var progress_bar := ProgressBar.new()
		progress_bar.custom_minimum_size = Vector2(200, 12)
		progress_bar.max_value = achievement.target
		progress_bar.value = achievement.progress
		progress_bar.show_percentage = false
		progress_container.add_child(progress_bar)
		
		var progress_label := Label.new()
		progress_label.text = "%d / %d" % [achievement.progress, achievement.target]
		progress_label.add_theme_font_size_override("font_size", 12)
		progress_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		progress_container.add_child(progress_label)
	
	# Checkmark for unlocked
	if achievement.unlocked:
		var check := Label.new()
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 32)
		check.add_theme_color_override("font_color", UNLOCKED_COLOR)
		hbox.add_child(check)
	
	return container


func _on_category_selected(category_index: int) -> void:
	_current_category = category_index as Category
	_populate_achievements()


func _on_character_filter_pressed() -> void:
	if not _registry:
		return
	
	# Cycle through characters
	var char_ids: Array = _registry.get_all_character_ids()
	if _character_filter == "":
		_character_filter = char_ids[0] if char_ids.size() > 0 else ""
	else:
		var idx := char_ids.find(_character_filter)
		if idx == -1 or idx >= char_ids.size() - 1:
			_character_filter = ""  # Reset to All
		else:
			_character_filter = char_ids[idx + 1]
	
	# Update button text
	if _character_filter_button:
		if _character_filter == "":
			_character_filter_button.text = "All Characters"
		else:
			var char_data = _registry.get_character(_character_filter)
			if char_data:
				_character_filter_button.text = char_data.display_name
	
	_populate_achievements()


func _on_back_pressed() -> void:
	emit_signal("back_requested")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		accept_event()
