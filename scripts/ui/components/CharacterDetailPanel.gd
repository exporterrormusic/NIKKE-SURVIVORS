class_name CharacterDetailPanel
extends Panel
## White admin-register character detail card (NIKKE squad-file style):
## oblique name, "SQUAD // WEAPON" role line, stat bars, Special/Burst text,
## and the cyan DEPLOY slab. swap_to_character() plays the quick out/in
## animation used when the player clicks a different character.

const UI := preload("res://scripts/ui/UITheme.gd")

signal deploy_pressed
signal skill_tree_pressed

const STAT_DEFS := [
	# key, label, max, color
	["hp", "HP", 20.0, Color(0.212, 0.702, 0.373)],
	["atk", "ATK", 20.0, Color(0.91, 0.224, 0.18)],
	["spd", "SPD", 50.0, Color(0.122, 0.561, 0.878)],
	["crit", "CRIT", 100.0, Color(0.851, 0.647, 0.078)],
]

var _content: MarginContainer
var _name_lbl: Label
var _role_lbl: Label
var _stat_bars: Dictionary = {}   # key -> {bar: ProgressBar, value: Label}
var _special_title: Label
var _special_desc: Label
var _burst_title: Label
var _burst_desc: Label
var _deploy_button: Button = null
var _skill_tree_button: Button = null
var _swap_tween: Tween = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.create_admin_card_style())
	_build_content()


func show_character(data) -> void:
	_apply_data(data)


func swap_to_character(data) -> void:
	if _swap_tween and _swap_tween.is_valid():
		_swap_tween.kill()
	_swap_tween = create_tween()
	_swap_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_swap_tween.set_parallel(true)
	_swap_tween.tween_property(_content, "position:x", 72.0, 0.16)
	_swap_tween.tween_property(self, "modulate:a", 0.0, 0.16)
	_swap_tween.set_parallel(false)
	_swap_tween.tween_callback(_apply_data.bind(data))
	_swap_tween.set_ease(Tween.EASE_OUT)
	_swap_tween.set_parallel(true)
	_swap_tween.tween_property(_content, "position:x", 0.0, 0.22)
	_swap_tween.tween_property(self, "modulate:a", 1.0, 0.22)


func _apply_data(data) -> void:
	if data == null:
		return
	_name_lbl.text = str(data.display_name).to_upper()
	var squad: String = data.squad if data.squad != "" else "ARK"
	var weapon: String = CharacterRegistry.get_weapon_display_name(str(data.weapon_kind))
	_role_lbl.text = ("%s // %s" % [squad, weapon]).to_upper()

	var values := {
		"hp": float(data.base_hp),
		"atk": float(data.base_damage),
		"spd": float(data.base_speed) / 10.0,
		"crit": float(data.crit_chance) * 100.0,
	}
	for def in STAT_DEFS:
		var key: String = def[0]
		var entry: Dictionary = _stat_bars[key]
		entry["bar"].max_value = def[2]
		entry["bar"].value = values[key]
		entry["value"].text = str(roundi(values[key]))

	_special_title.text = "⚡ SPECIAL — %s" % str(data.special_name).to_upper()
	_special_desc.text = str(data.special_description)
	_burst_title.text = "✦ BURST — %s" % str(data.burst_name).to_upper()
	_burst_desc.text = str(data.burst_description)


func _build_content() -> void:
	_content = MarginContainer.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_theme_constant_override("margin_left", 36)
	_content.add_theme_constant_override("margin_right", 36)
	_content.add_theme_constant_override("margin_top", 30)
	_content.add_theme_constant_override("margin_bottom", 30)
	add_child(_content)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_content.add_child(vbox)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_name_lbl.add_theme_font_size_override("font_size", 58)
	_name_lbl.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	_name_lbl.clip_text = true
	_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(_name_lbl)

	_role_lbl = Label.new()
	UI.style_subtitle_label(_role_lbl, 19, UI.ACCENT_CYAN_DEEP)
	vbox.add_child(_role_lbl)

	vbox.add_child(_make_spacer(10))

	for def in STAT_DEFS:
		vbox.add_child(_make_stat_row(def))

	vbox.add_child(_make_spacer(8))
	var hairline := ColorRect.new()
	hairline.color = UI.ADMIN_HAIRLINE
	hairline.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(hairline)
	vbox.add_child(_make_spacer(8))

	_special_title = _make_skill_title(Color(0.78, 0.467, 0.0))
	vbox.add_child(_special_title)
	_special_desc = _make_skill_desc()
	vbox.add_child(_special_desc)

	vbox.add_child(_make_spacer(8))
	_burst_title = _make_skill_title(Color(0.478, 0.247, 0.839))
	vbox.add_child(_burst_title)
	_burst_desc = _make_skill_desc()
	vbox.add_child(_burst_desc)

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(stretch)

	# SKILL TREE — same chamfered slab as DEPLOY, but a light grey "secondary"
	# fill with charcoal text. Opens the unit's tree as a read-only preview.
	var skill_tree := Button.new()
	skill_tree.text = "◈ TALENT TREE"
	skill_tree.custom_minimum_size = Vector2(0, 58)
	skill_tree.focus_mode = Control.FOCUS_ALL
	skill_tree.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	skill_tree.add_theme_font_size_override("font_size", 24)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		skill_tree.add_theme_color_override(state, UI.ADMIN_TEXT)
	var st_normal := UI.create_chamfer_card(Color(0.80, 0.82, 0.85), Color(0, 0, 0, 0), 0, 2, 20.0)
	var st_hover := UI.create_chamfer_card(Color(0.90, 0.92, 0.94), Color(0, 0, 0, 0), 0, 2, 20.0)
	skill_tree.add_theme_stylebox_override("normal", st_normal)
	skill_tree.add_theme_stylebox_override("hover", st_hover)
	skill_tree.add_theme_stylebox_override("pressed", st_normal)
	skill_tree.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	skill_tree.pressed.connect(func(): skill_tree_pressed.emit())
	skill_tree.name = "SkillTreeButton"
	vbox.add_child(skill_tree)
	_skill_tree_button = skill_tree

	var deploy := Button.new()
	deploy.text = "▶ DEPLOY — SELECT STAGE"
	deploy.custom_minimum_size = Vector2(0, 80)
	deploy.focus_mode = Control.FOCUS_ALL
	deploy.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	deploy.add_theme_font_size_override("font_size", 29)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		deploy.add_theme_color_override(state, Color.WHITE)
	var cta := UI.create_chamfer_card(UI.ACCENT_CYAN_DEEP.lerp(UI.ACCENT_CYAN, 0.5), Color(0, 0, 0, 0), 0, 2, 20.0)
	var cta_hover := UI.create_chamfer_card(UI.ACCENT_CYAN_BRIGHT, Color(0, 0, 0, 0), 0, 2, 20.0)
	deploy.add_theme_stylebox_override("normal", cta)
	deploy.add_theme_stylebox_override("hover", cta_hover)
	deploy.add_theme_stylebox_override("pressed", cta)
	deploy.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	deploy.pressed.connect(func(): deploy_pressed.emit())
	deploy.name = "DeployButton"
	vbox.add_child(deploy)
	_deploy_button = deploy

	# Vertical focus chain between the two stacked CTAs (gamepad/keyboard nav).
	skill_tree.focus_neighbor_bottom = skill_tree.get_path_to(deploy)
	deploy.focus_neighbor_top = deploy.get_path_to(skill_tree)


func get_deploy_button() -> Button:
	return _deploy_button


func get_skill_tree_button() -> Button:
	return _skill_tree_button


func _make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _make_stat_row(def: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var key_lbl := Label.new()
	key_lbl.text = def[1]
	key_lbl.custom_minimum_size = Vector2(68, 0)
	key_lbl.add_theme_font_override("font", UI.FONT_BOLD)
	key_lbl.add_theme_font_size_override("font_size", 20)
	key_lbl.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	row.add_child(key_lbl)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 13)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.235, 0.275, 0.32, 0.18)
	bg.set_corner_radius_all(0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = def[3]
	fill.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(50, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.add_theme_font_override("font", UI.FONT_BOLD)
	value_lbl.add_theme_font_size_override("font_size", 20)
	value_lbl.add_theme_color_override("font_color", UI.ADMIN_TEXT)
	row.add_child(value_lbl)

	_stat_bars[def[0]] = {"bar": bar, "value": value_lbl}
	return row


func _make_skill_title(color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_override("font", UI.FONT_BOLD)
	lbl.add_theme_font_size_override("font_size", 21)
	lbl.add_theme_color_override("font_color", color)
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return lbl


func _make_skill_desc() -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_override("font", UI.FONT_MEDIUM)
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", Color(0.29, 0.31, 0.34, 1.0))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl
