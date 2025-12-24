extends Panel
class_name CharacterInfoPanel
## Shows character stats, special attack, and burst info when hovering.

const UI := preload("res://scripts/ui/UITheme.gd")
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

# PERFORMANCE: Cache SpriteFrames per character to avoid recreation on each hover
static var _sprite_frames_cache: Dictionary = {}

## Clean up cached sprite frames to prevent RID leaks on exit
static func cleanup() -> void:
	_sprite_frames_cache.clear()
	print("[CharacterInfoPanel] Cleanup complete")

var _char_data: Resource = null

var _sprite_viewport: SubViewport
var _animated_sprite: AnimatedSprite2D
var _portrait_container: Control
var _name_lbl: Label
var _desc_lbl: Label
var _stats_box: VBoxContainer
var _special_title: Label
var _special_desc: Label
var _special_upgrades_title: Label
var _special_upgrades_label: Label
var _burst_title: Label
var _burst_desc: Label
var _burst_upgrades_title: Label
var _burst_upgrades_label: Label

func _ready() -> void:
	_build_ui()
	_apply_style()

func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_color = UI.ACCENT_PRIMARY
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.shadow_color = UI.SHADOW_COLOR
	style.shadow_size = 4
	add_theme_stylebox_override("panel", style)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 28)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(hbox)
	
	# Left: Portrait + name + description
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 260
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)
	
	# Portrait container with clipping and border
	_portrait_container = Control.new()
	_portrait_container.custom_minimum_size = Vector2(180, 180)
	_portrait_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_portrait_container.visible = false # Hidden until character is hovered
	left.add_child(_portrait_container)
	
	# Clip panel for rounded corners
	var clip_panel := Panel.new()
	clip_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_panel.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	var clip_style := StyleBoxFlat.new()
	clip_style.bg_color = UI.CHAR_NORMAL
	clip_style.set_corner_radius_all(12)
	clip_panel.add_theme_stylebox_override("panel", clip_style)
	_portrait_container.add_child(clip_panel)
	
	# SubViewportContainer for animated sprite
	var viewport_container := SubViewportContainer.new()
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	clip_panel.add_child(viewport_container)
	
	_sprite_viewport = SubViewport.new()
	_sprite_viewport.size = Vector2i(180, 180)
	_sprite_viewport.transparent_bg = true
	_sprite_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(_sprite_viewport)
	
	_animated_sprite = AnimatedSprite2D.new()
	_animated_sprite.position = Vector2(90, 105) # Center in viewport, lowered
	_animated_sprite.centered = true
	_animated_sprite.z_index = 10
	_sprite_viewport.add_child(_animated_sprite)
	
	# White border overlay on top
	var portrait_border := Panel.new()
	portrait_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = UI.TRANSPARENT
	border_style.border_color = UI.ACCENT_PRIMARY
	border_style.set_border_width_all(3)
	border_style.set_corner_radius_all(12)
	portrait_border.add_theme_stylebox_override("panel", border_style)
	_portrait_container.add_child(portrait_border)
	
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 20)
	_name_lbl.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.clip_text = true
	_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(_name_lbl)
	
	_desc_lbl = Label.new()
	_desc_lbl.add_theme_font_size_override("font_size", 12)
	_desc_lbl.add_theme_color_override("font_color", UI.TEXT_MUTED)
	_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(_desc_lbl)
	
	# Divider
	var div1 := VSeparator.new()
	div1.custom_minimum_size.x = 3
	hbox.add_child(div1)
	
	# Middle: Stats
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 8)
	_stats_box.custom_minimum_size.x = 200
	_stats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_stats_box)
	
	var stats_title := Label.new()
	stats_title.text = "STATS"
	stats_title.add_theme_font_size_override("font_size", 20)
	stats_title.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_box.add_child(stats_title)
	
	# Divider
	var div2 := VSeparator.new()
	div2.custom_minimum_size.x = 3
	hbox.add_child(div2)
	
	# Right: Special + Burst (two columns)
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 24)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	
	# Special column
	var special_col := VBoxContainer.new()
	special_col.add_theme_constant_override("separation", 4)
	special_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(special_col)
	
	_special_title = Label.new()
	_special_title.add_theme_font_size_override("font_size", 24)
	_special_title.add_theme_color_override("font_color", UI.COLOR_SPECIAL)
	special_col.add_child(_special_title)
	
	var special_sep := HSeparator.new()
	special_col.add_child(special_sep)
	
	_special_desc = Label.new()
	_special_desc.add_theme_font_size_override("font_size", 16)
	_special_desc.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	_special_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_special_desc.custom_minimum_size.y = 50 # Fixed height for alignment
	special_col.add_child(_special_desc)
	
	# Spacer before upgrades
	var special_spacer := Control.new()
	special_spacer.custom_minimum_size.y = 8
	special_col.add_child(special_spacer)
	
	# Special upgrades section
	_special_upgrades_title = Label.new()
	_special_upgrades_title.text = "Upgrades:"
	_special_upgrades_title.add_theme_font_size_override("font_size", 14)
	_special_upgrades_title.add_theme_color_override("font_color", UI.ACCENT_SECONDARY_DIM)
	_special_upgrades_title.visible = false # Hidden until character selected
	special_col.add_child(_special_upgrades_title)
	
	_special_upgrades_label = Label.new()
	_special_upgrades_label.add_theme_font_size_override("font_size", 13)
	_special_upgrades_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
	_special_upgrades_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	special_col.add_child(_special_upgrades_label)
	
	# Burst column
	var burst_col := VBoxContainer.new()
	burst_col.add_theme_constant_override("separation", 4)
	burst_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(burst_col)
	
	_burst_title = Label.new()
	_burst_title.add_theme_font_size_override("font_size", 24)
	_burst_title.add_theme_color_override("font_color", UI.COLOR_BURST)
	burst_col.add_child(_burst_title)
	
	var burst_sep := HSeparator.new()
	burst_col.add_child(burst_sep)
	
	_burst_desc = Label.new()
	_burst_desc.add_theme_font_size_override("font_size", 16)
	_burst_desc.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	_burst_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_burst_desc.custom_minimum_size.y = 50 # Fixed height for alignment
	burst_col.add_child(_burst_desc)
	
	# Spacer before upgrades
	var burst_spacer := Control.new()
	burst_spacer.custom_minimum_size.y = 8
	burst_col.add_child(burst_spacer)
	
	# Burst upgrades section
	_burst_upgrades_title = Label.new()
	_burst_upgrades_title.text = "Upgrades:"
	_burst_upgrades_title.add_theme_font_size_override("font_size", 14)
	_burst_upgrades_title.add_theme_color_override("font_color", UI.COLOR_BURST)
	_burst_upgrades_title.visible = false # Hidden until character selected
	burst_col.add_child(_burst_upgrades_title)
	
	_burst_upgrades_label = Label.new()
	_burst_upgrades_label.add_theme_font_size_override("font_size", 13)
	_burst_upgrades_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
	_burst_upgrades_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_burst_upgrades_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	burst_col.add_child(_burst_upgrades_label)

func set_character(data: Resource) -> void:
	_char_data = data
	if not data:
		_clear()
		return
	
	_portrait_container.visible = true
	_configure_animated_sprite(data)
	_name_lbl.text = data.display_name
	_desc_lbl.text = data.description if data.description else ""
	
	# Stats
	for child in _stats_box.get_children():
		if child is HBoxContainer:
			child.queue_free()
	
	_add_stat("HP", data.base_hp, 20, UI.STAT_HP, "hp")
	_add_stat("ATK", int(data.base_damage), 20, UI.STAT_ATK, "atk")
	_add_stat("SPD", int(data.base_speed / 10), 50, UI.STAT_SPD, "speed") # Divide by 10 for cleaner display
	var crit_val: int = int(data.crit_chance * 100) if data.get("crit_chance") else 5
	_add_stat("CRIT", crit_val, 100, UI.STAT_CRIT, "crit")
	
	# Special
	_special_title.text = "SPECIAL: " + (data.special_name if data.special_name else "None")
	_special_desc.text = data.special_description if data.special_description else ""
	
	# Burst
	_burst_title.text = "BURST: " + (data.burst_name if data.burst_name else "Unknown")
	_burst_desc.text = data.burst_description if data.burst_description else ""
	
	# Get upgrade descriptions from TalentTree
	_populate_upgrades(data)

func _add_stat(stat_name: String, value: int, max_val: int, color: Color, upgrade_type: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var lbl := Label.new()
	lbl.text = stat_name
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", UI.TEXT_MUTED)
	lbl.custom_minimum_size.x = 50
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	
	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(100, 0)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UI.PROGRESS_BG
	bg_style.set_corner_radius_all(6)
	bg_style.border_color = UI.BORDER_DEFAULT
	bg_style.set_border_width_all(1)
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	row.add_child(bar_bg)
	
	var fill := ColorRect.new()
	fill.color = color
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(float(value) / float(max_val), 0.08, 1.0)
	fill.offset_left = 3
	fill.offset_right = -3
	fill.offset_top = 3
	fill.offset_bottom = -3
	bar_bg.add_child(fill)
	
	# Build value text with bonus from shop upgrades
	var bonus_text := ""
	
	if upgrade_type != "":
		var bonus: float = ShopMenuScript.get_upgrade_bonus(upgrade_type)
		if bonus > 0:
			match upgrade_type:
				"hp":
					# HP is a flat bonus (+1 per level)
					bonus_text = "+%d" % int(bonus)
				"atk":
					# ATK is a percentage bonus (+5% per level)
					bonus_text = "+%d%%" % int(bonus * 100)
				"speed":
					# Speed is a percentage bonus (+5% per level)
					bonus_text = "+%d%%" % int(bonus * 100)
				"crit":
					# Crit is a flat percentage point bonus (+2% per level)
					bonus_text = "+%d%%" % int(bonus * 100)
	
	# Create HBoxContainer for the value label content (base + bonus)
	var val_container := HBoxContainer.new()
	val_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	val_container.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_bg.add_child(val_container)
	
	# Base value label
	var val_lbl := Label.new()
	val_lbl.text = str(value)
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_container.add_child(val_lbl)
	
	# Bonus label (if any)
	if bonus_text != "":
		var bonus_lbl := Label.new()
		bonus_lbl.text = bonus_text
		bonus_lbl.add_theme_font_size_override("font_size", 14)
		bonus_lbl.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)
		bonus_lbl.add_theme_color_override("font_outline_color", UI.ACCENT_SECONDARY_DIM)
		bonus_lbl.add_theme_constant_override("outline_size", 2)
		bonus_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val_container.add_child(bonus_lbl)
	
	_stats_box.add_child(row)

func _clear() -> void:
	_portrait_container.visible = false
	if _animated_sprite:
		_animated_sprite.stop()
		_animated_sprite.sprite_frames = null
	_name_lbl.text = "Hover a Character"
	_desc_lbl.text = ""
	_special_title.text = "SPECIAL:"
	_special_desc.text = ""
	_special_upgrades_title.visible = false
	_special_upgrades_label.text = ""
	_burst_title.text = "BURST:"
	_burst_desc.text = ""
	_burst_upgrades_title.visible = false
	_burst_upgrades_label.text = ""

func _populate_upgrades(data: Resource) -> void:
	"""Get upgrade descriptions from TalentTree based on character index."""
	var char_index := _get_character_index(data.id)
	if char_index < 0:
		_special_upgrades_label.text = ""
		_burst_upgrades_label.text = ""
		return
	
	# Access TalentTree's TALENT_DATA
	var talent_tree_script = load("res://scripts/ui/TalentTree.gd")
	if not talent_tree_script:
		return
	
	# Create temporary instance to access TALENT_DATA
	var temp_tree = talent_tree_script.new()
	if not temp_tree.TALENT_DATA.has(char_index):
		_special_upgrades_label.text = ""
		_burst_upgrades_label.text = ""
		return
	
	var talents: Array = temp_tree.TALENT_DATA[char_index]
	
	# Find special upgrades (row 1, cols 0 and 2)
	var special_upgrades: Array[String] = []
	for talent in talents:
		if talent.get("row") == 1 and talent.get("col") in [0, 2]:
			var name_str: String = talent.get("name", "")
			var desc_str: String = talent.get("desc", "")
			if name_str and desc_str:
				special_upgrades.append("• %s: %s" % [name_str, desc_str])
	
	# Find burst upgrades (row 2, cols 0 and 2)
	var burst_upgrades: Array[String] = []
	for talent in talents:
		if talent.get("row") == 2 and talent.get("col") in [0, 2]:
			var name_str: String = talent.get("name", "")
			var desc_str: String = talent.get("desc", "")
			if name_str and desc_str:
				burst_upgrades.append("• %s: %s" % [name_str, desc_str])
	
	_special_upgrades_label.text = "\n".join(special_upgrades)
	_burst_upgrades_label.text = "\n".join(burst_upgrades)
	
	# Show upgrade titles now that we have content
	_special_upgrades_title.visible = true
	_burst_upgrades_title.visible = true

func _get_character_index(char_id: String) -> int:
	"""Map character ID to TalentTree index using CharacterRegistry."""
	var registry := CharacterRegistry.get_instance()
	return registry.get_character_index(char_id)

func _configure_animated_sprite(char_data: Resource) -> void:
	"""Configure the AnimatedSprite2D to play the walking right animation."""
	if not _animated_sprite or not char_data:
		return
	
	var char_id: String = char_data.id if char_data.id else ""
	
	# PERFORMANCE: Check cache first
	if _sprite_frames_cache.has(char_id):
		var cached: Dictionary = _sprite_frames_cache[char_id]
		_animated_sprite.sprite_frames = cached["frames"]
		_animated_sprite.scale = cached["scale"]
		_animated_sprite.visible = true
		_animated_sprite.animation = "right"
		if not _animated_sprite.is_playing():
			_animated_sprite.play("right")
		return
	
	var sprite_sheet: Texture2D = char_data.get_sprite()
	if not sprite_sheet:
		_animated_sprite.visible = false
		return
	
	# Use game defaults: 3 columns, 4 rows (down/left/right/up), 6 fps
	var columns: int = 3
	var rows: int = 4
	var fps: float = 6.0
	var scale_factor: float = 0.2
	
	# Override with CharacterData values if they're set properly
	if char_data.sprite_sheet_columns > 1:
		columns = char_data.sprite_sheet_columns
	if char_data.sprite_sheet_rows > 1:
		rows = char_data.sprite_sheet_rows
	if char_data.sprite_animation_fps > 0:
		fps = char_data.sprite_animation_fps
	if char_data.sprite_scale > 0:
		scale_factor = char_data.sprite_scale
	
	# Make sprite bigger for the preview (1.6x the normal scale)
	scale_factor *= 1.6
	
	var texture_size: Vector2 = sprite_sheet.get_size()
	var frame_width := int(texture_size.x / columns)
	var frame_height := int(texture_size.y / rows)
	
	var frames := SpriteFrames.new()
	
	# Create the "right" animation (row 2)
	frames.add_animation("right")
	frames.set_animation_speed("right", fps)
	frames.set_animation_loop("right", true)
	
	# Add frames for the right direction (row 2, each column is a frame)
	for col in range(columns):
		var atlas := AtlasTexture.new()
		atlas.atlas = sprite_sheet
		atlas.region = Rect2(col * frame_width, 2 * frame_height, frame_width, frame_height)
		frames.add_frame("right", atlas)
	
	# Cache for reuse
	_sprite_frames_cache[char_id] = {"frames": frames, "scale": Vector2(scale_factor, scale_factor)}
	
	_animated_sprite.sprite_frames = frames
	_animated_sprite.scale = Vector2(scale_factor, scale_factor)
	_animated_sprite.visible = true
	_animated_sprite.animation = "right"
	_animated_sprite.play("right")
