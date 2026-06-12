class_name MissionSelect
extends Control
## Mission select - NIKKE "field briefing" register (approved mockup
## docs/mockups/stage_select_vA_v4.html). The selected zone's art fills the
## screen behind floating dark widgets: mode stack + GODDESS FALL hazard
## toggle (left), looping zone carousel (bottom), threat-level ops panel
## (right). Static chrome lives in MissionSelect.tscn; modes come from
## StageRegistry, zones from MapRegistry.

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")
const MissionModeButtonScript := preload("res://scripts/ui/components/MissionModeButton.gd")

signal stage_confirmed(stage_id: String)
signal back_requested

const MODE_TITLES := {"stage_1": "STANDARD", "stage_3": "ENDLESS"}
const TIMER_MUSIC := "res://assets/sounds/music/bgm/timer.mp3"

var _selected_stage_id := "stage_1"
var _mode_buttons: Dictionary = {}  # stage_id -> MissionModeButton
var _mode_group := ButtonGroup.new()
var _armed := false
var _map_fade_tween: Tween = null
var _arm_tween: Tween = null
var _pulse_tween: Tween = null
var _glitch_tween: Tween = null
var _cta_pulse_tween: Tween = null

@onready var _big_map: TextureRect = %BigMap
@onready var _arm_fx: Control = %ArmFX
@onready var _pulse: ColorRect = %Pulse
@onready var _glitch_line: ColorRect = %GlitchLine
@onready var _arm_banner: PanelContainer = %ArmBanner
@onready var _header_title: Label = %HeaderTitle
@onready var _header_sub: Label = %HeaderSub
@onready var _header_bar: ColorRect = %HeaderBar
@onready var _operator_chip: OperatorChip = %OperatorChip
@onready var _back_button: Button = %BackButton
@onready var _mode_list: VBoxContainer = %ModeList
@onready var _goddess_toggle: HazardToggle = %GoddessToggle
@onready var _map_name_label: Label = %MapNameLabel
@onready var _map_sub_label: Label = %MapSubLabel
@onready var _zone_counter: Label = %ZoneCounter
@onready var _carousel: ZoneCarousel = %Carousel
@onready var _prev_arrow: Button = %PrevArrow
@onready var _next_arrow: Button = %NextArrow
@onready var _ops_panel: PanelContainer = %OpsPanel
@onready var _arm_banner_label: Label = %ArmBannerLabel
@onready var _scale_row: HBoxContainer = %ScaleRow
@onready var _ops_cap: Label = %OpsCap
@onready var _diff_label: Label = %DiffLabel
@onready var _diff_slider: HSlider = %DiffSlider
@onready var _diff_value: Label = %DiffValue
@onready var _hp_scale: Label = %HpScale
@onready var _atk_scale: Label = %AtkScale
@onready var _core_scale: Label = %CoreScale
@onready var _start_button: Button = %StartButton

const NORMAL_MAP_MODULATE := Color(0.8, 0.8, 0.84, 1.0)
const ARMED_MAP_MODULATE := Color(0.62, 0.38, 0.36, 1.0)


func _ready() -> void:
	# Clean slate: goddess/she_descends must never leak in from a previous run
	GameManager.goddess_fall_mode = false
	GameManager.she_descends_mode = false

	_style_chrome()
	_build_modes()
	_setup_carousel()
	_setup_ops()

	_back_button.pressed.connect(_on_back_pressed)
	_goddess_toggle.toggled.connect(_on_goddess_toggled)
	_setup_focus_neighbors()


func _style_chrome() -> void:
	UI.style_header_label(_header_title, 56, UI.TEXT_PRIMARY)
	UI.style_subtitle_label(_header_sub, 17, Color(1, 1, 1, 0.65))

	_map_name_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_map_name_label.add_theme_font_size_override("font_size", 76)
	_map_name_label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	_map_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_map_name_label.add_theme_constant_override("shadow_offset_x", 0)
	_map_name_label.add_theme_constant_override("shadow_offset_y", 3)
	UI.style_subtitle_label(_map_sub_label, 20, UI.ACCENT_CYAN)
	UI.style_subtitle_label(_zone_counter, 15, Color(1, 1, 1, 0.45))

	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0.47, 0.03, 0.015, 0.85)
	banner_style.border_color = UI.COLOR_DANGER
	banner_style.set_border_width_all(1)
	banner_style.set_corner_radius_all(0)
	banner_style.skew = Vector2(-0.105, 0.0)
	banner_style.content_margin_left = 39
	banner_style.content_margin_right = 39
	banner_style.content_margin_top = 10
	banner_style.content_margin_bottom = 10
	_arm_banner.add_theme_stylebox_override("panel", banner_style)
	UI.style_subtitle_label(_arm_banner_label, 19, Color(1.0, 0.71, 0.68, 1.0))


func _build_modes() -> void:
	for stage in StageRegistry.STAGES:
		var is_unlocked: bool = GameManager.is_stage_unlocked(stage.id)
		var btn: MissionModeButton = MissionModeButtonScript.new()
		btn.title_text = MODE_TITLES.get(stage.id, str(stage.get("name", "???")).to_upper()) \
			if is_unlocked else "???"
		btn.desc_text = str(stage.get("description", "")) \
			if is_unlocked else "Clear previous stage to unlock"
		btn.custom_minimum_size = Vector2(0, 118)
		btn.button_group = _mode_group
		btn.disabled = not is_unlocked
		btn.toggled.connect(_on_mode_toggled.bind(stage.id))
		_mode_list.add_child(btn)
		_mode_buttons[stage.id] = btn

	for stage in StageRegistry.STAGES:
		if GameManager.is_stage_unlocked(stage.id):
			_selected_stage_id = stage.id
			_mode_buttons[stage.id].set_pressed_no_signal(true)
			break


func _on_mode_toggled(pressed_state: bool, stage_id: String) -> void:
	if pressed_state:
		UISounds.play_select()
		_selected_stage_id = stage_id


func _setup_carousel() -> void:
	_carousel.set_maps(MapRegistry.get_all_maps())
	_carousel.zone_changed.connect(_on_zone_changed)
	_prev_arrow.pressed.connect(func(): _carousel.step(-1))
	_next_arrow.pressed.connect(func(): _carousel.step(1))
	for arrow in [_prev_arrow, _next_arrow]:
		var normal := UI.create_glass_style(0.8)
		normal.border_color = Color(1, 1, 1, 0.3)
		normal.set_border_width_all(1)
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.122, 0.561, 0.878, 0.5)
		hover.set_corner_radius_all(0)
		arrow.add_theme_stylebox_override("normal", normal)
		arrow.add_theme_stylebox_override("hover", hover)
		arrow.add_theme_stylebox_override("pressed", hover)
		arrow.add_theme_stylebox_override("focus", UI.create_button_style_focus())
	_carousel.select_random(false)


func _on_zone_changed(index: int) -> void:
	var map: Dictionary = MapRegistry.MAPS[index]
	_map_name_label.text = str(map.name).to_upper()
	_map_sub_label.text = str(map.subtitle).to_upper()
	_zone_counter.text = "ZONE %02d // %02d" % [index + 1, MapRegistry.get_map_count()]

	GameManager.selected_biome = map.biome
	GameManager.selected_time = map.time

	var preview_path: String = map.preview
	var tex: Texture2D = load(preview_path) if ResourceLoader.exists(preview_path) else null
	if _map_fade_tween and _map_fade_tween.is_valid():
		_map_fade_tween.kill()
	_map_fade_tween = create_tween()
	_map_fade_tween.tween_property(_big_map, "self_modulate:a", 0.55, 0.12)
	_map_fade_tween.tween_callback(func(): _big_map.texture = tex)
	_map_fade_tween.tween_property(_big_map, "self_modulate:a", 1.0, 0.25)


func _setup_ops() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.063, 0.078, 0.102, 0.84)
	panel_style.border_color = Color(1, 1, 1, 0.16)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(0)
	_ops_panel.add_theme_stylebox_override("panel", panel_style)

	UI.style_subtitle_label(_ops_cap, 15, Color(1, 1, 1, 0.55))
	UI.style_subtitle_label(_diff_label, 16, UI.TEXT_PRIMARY)
	_diff_value.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_diff_value.add_theme_font_size_override("font_size", 45)
	_diff_value.add_theme_color_override("font_color", UI.ACCENT_CYAN)
	for label in [_hp_scale, _atk_scale, _core_scale]:
		label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
		label.add_theme_font_size_override("font_size", 33)
		label.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	for cell in _scale_row.get_children():
		if cell is VBoxContainer and cell.get_child_count() > 0:
			var caption: Label = cell.get_child(0)
			UI.style_subtitle_label(caption, 13, Color(1, 1, 1, 0.55))

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = UI.ACCENT_CYAN
	grabber.set_corner_radius_all(0)
	grabber.content_margin_left = 10
	grabber.content_margin_right = 10
	grabber.content_margin_top = 14
	grabber.content_margin_bottom = 14
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.5, 0.55, 0.61, 0.35)
	track.set_corner_radius_all(0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	_diff_slider.add_theme_stylebox_override("slider", track)
	_diff_slider.add_theme_stylebox_override("grabber_area", grabber)
	_diff_slider.add_theme_stylebox_override("grabber_area_highlight", grabber)

	_diff_slider.value = GameManager.difficulty_multiplier
	_diff_slider.value_changed.connect(_on_difficulty_changed)
	_on_difficulty_changed(_diff_slider.value)

	_start_button.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_start_button.add_theme_font_size_override("font_size", 31)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_start_button.add_theme_color_override(state, Color.WHITE)
	_apply_start_style(false)
	_start_button.pressed.connect(_on_start_pressed)


func _apply_start_style(danger: bool) -> void:
	var base_color := UI.COLOR_DANGER if danger else UI.ACCENT_CYAN
	var hover_color := base_color.lightened(0.12)
	var pressed_color := base_color.darkened(0.18)
	var corner := ChamferStyleBox.ChamferCorner.BOTTOM_RIGHT
	_start_button.add_theme_stylebox_override("normal", UI.create_chamfer_card(base_color, Color(0, 0, 0, 0), 0, corner, 21.0))
	_start_button.add_theme_stylebox_override("hover", UI.create_chamfer_card(hover_color, Color(0, 0, 0, 0), 0, corner, 21.0))
	_start_button.add_theme_stylebox_override("pressed", UI.create_chamfer_card(pressed_color, Color(0, 0, 0, 0), 0, corner, 21.0))
	_start_button.add_theme_stylebox_override("focus", UI.create_button_style_focus())


func _on_difficulty_changed(value: float) -> void:
	var difficulty := int(value)
	GameManager.difficulty_multiplier = difficulty
	_diff_value.text = "×%d" % difficulty

	var atk_mult := 1.0 + 0.25 * (difficulty - 1)
	_hp_scale.text = "×%d" % difficulty
	_atk_scale.text = ("×%d" % int(atk_mult)) if atk_mult == floorf(atk_mult) else ("×%.2f" % atk_mult)
	_core_scale.text = "×%d" % difficulty


# =============================================================================
# GODDESS FALL / SHE DESCENDS
# =============================================================================

func _on_goddess_toggled(pressed_state: bool) -> void:
	if not is_inside_tree():
		return
	_armed = pressed_state
	GameManager.goddess_fall_mode = pressed_state
	GameManager.she_descends_mode = pressed_state

	if pressed_state:
		UISounds.play_select()
		if MenuManager:
			MenuManager.stop_menu_music()
		if AudioDirector:
			AudioDirector.stop_music(0.1)
			AudioDirector.play_music_by_path(TIMER_MUSIC, true, 0.5)
	else:
		UISounds.play_back()
		if AudioDirector:
			AudioDirector.stop_music(0.1)
		if MenuManager:
			MenuManager.start_menu_music()

	_apply_arm_visuals(pressed_state)


func _apply_arm_visuals(armed: bool) -> void:
	_start_button.text = "SHE DESCENDS" if armed else "MISSION START"
	_apply_start_style(armed)
	_header_bar.color = UI.COLOR_DANGER if armed else UI.ACCENT_CYAN
	_map_sub_label.add_theme_color_override("font_color",
		Color(1.0, 0.42, 0.38, 1.0) if armed else UI.ACCENT_CYAN)
	_arm_banner.visible = armed

	if _arm_tween and _arm_tween.is_valid():
		_arm_tween.kill()
	_arm_tween = create_tween().set_parallel(true)
	_arm_tween.tween_property(_arm_fx, "modulate:a", 1.0 if armed else 0.0, 0.6)
	_arm_tween.tween_property(_big_map, "modulate",
		ARMED_MAP_MODULATE if armed else NORMAL_MAP_MODULATE, 0.6)

	_kill_fx_tweens()
	if armed:
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(_pulse, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(_pulse, "modulate:a", 0.4, 1.1).set_trans(Tween.TRANS_SINE)

		_glitch_line.visible = true
		_glitch_tween = create_tween().set_loops()
		_glitch_tween.tween_callback(func(): _glitch_line.position.y = -10.0)
		_glitch_tween.tween_property(_glitch_line, "position:y", size.y + 10.0, 2.6)
		_glitch_tween.tween_interval(0.5)

		_cta_pulse_tween = create_tween().set_loops()
		_cta_pulse_tween.tween_property(_start_button, "modulate", Color(1.25, 1.25, 1.25, 1.0), 0.8).set_trans(Tween.TRANS_SINE)
		_cta_pulse_tween.tween_property(_start_button, "modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
	else:
		_glitch_line.visible = false
		_start_button.modulate = Color.WHITE
		_pulse.modulate.a = 0.4


func _kill_fx_tweens() -> void:
	for tween in [_pulse_tween, _glitch_tween, _cta_pulse_tween]:
		if tween and tween.is_valid():
			tween.kill()


## Disarm everything when leaving the screen (back / ESC). Flags are cleared
## so a goddess run never leaks into a normal one.
func reset_on_leave() -> void:
	if _armed:
		_goddess_toggle.set_pressed_no_signal(false)
		_armed = false
		GameManager.goddess_fall_mode = false
		GameManager.she_descends_mode = false
		if AudioDirector:
			AudioDirector.stop_music(0.1)
		if MenuManager:
			MenuManager.start_menu_music()
		_apply_arm_visuals(false)
		_goddess_toggle.queue_redraw()


# =============================================================================
# OPEN / CONFIRM / BACK
# =============================================================================

## Called by the parent each time the stage phase slides in.
func prepare_open(operator_name: String, operator_portrait: Texture2D) -> void:
	_operator_chip.set_operator(operator_name, operator_portrait)
	_carousel.select_random(false)
	call_deferred("_grab_initial_focus")


func _on_start_pressed() -> void:
	UISounds.play_confirm()
	# selected_biome / selected_time already set by _on_zone_changed
	stage_confirmed.emit(_selected_stage_id)


func _on_back_pressed() -> void:
	reset_on_leave()
	back_requested.emit()


func _grab_initial_focus() -> void:
	if is_visible_in_tree() and _start_button:
		_start_button.grab_focus()


func _setup_focus_neighbors() -> void:
	var modes: Array = _mode_buttons.values()
	for i in modes.size():
		if i > 0:
			modes[i].focus_neighbor_top = modes[i].get_path_to(modes[i - 1])
			modes[i - 1].focus_neighbor_bottom = modes[i - 1].get_path_to(modes[i])
	if not modes.is_empty():
		var last: Control = modes[modes.size() - 1]
		last.focus_neighbor_bottom = last.get_path_to(_goddess_toggle)
		_goddess_toggle.focus_neighbor_top = _goddess_toggle.get_path_to(last)
		for mode in modes:
			mode.focus_neighbor_right = mode.get_path_to(_start_button)

	_goddess_toggle.focus_neighbor_bottom = _goddess_toggle.get_path_to(_prev_arrow)
	_prev_arrow.focus_neighbor_top = _prev_arrow.get_path_to(_goddess_toggle)
	_prev_arrow.focus_neighbor_right = _prev_arrow.get_path_to(_next_arrow)
	_next_arrow.focus_neighbor_left = _next_arrow.get_path_to(_prev_arrow)
	_next_arrow.focus_neighbor_right = _next_arrow.get_path_to(_start_button)
	_start_button.focus_neighbor_left = _start_button.get_path_to(_next_arrow)
	_start_button.focus_neighbor_top = _start_button.get_path_to(_diff_slider)
	_diff_slider.focus_neighbor_bottom = _diff_slider.get_path_to(_start_button)
