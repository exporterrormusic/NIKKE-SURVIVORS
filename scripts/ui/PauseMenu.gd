extends CanvasLayer
class_name PauseMenu
## Pause / results overlay (dark field register, approved mockup
## docs/mockups/pause_results_v2.html). Pause = center terminal: live field
## telemetry left, command column center, damage log right. Defeat/victory =
## after-action report: full-height Nikke burst strip left, verdict + score +
## report cells right; reward bar on victory, damage log on defeat.
## Static chrome lives in PauseMenu.tscn; this script wires data + signals.

signal restart_requested
signal resume_requested
signal settings_requested
signal character_select_requested
signal quit_requested

enum MenuMode {PAUSE, DEFEAT, VICTORY}

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")

var _menu_mode: int = MenuMode.PAUSE
var _cheats_menu: Node = null
var _hidden_hud: Array = []  # CanvasLayers hidden while the overlay is up

@onready var _pause_layout: Control = %PauseLayout
@onready var _results_layout: Control = %ResultsLayout
@onready var _mid_column: VBoxContainer = %MidColumn
@onready var _cheats_host: CenterContainer = %CheatsHost

# Pause layout
@onready var _pause_title: Label = %PauseTitle
@onready var _pause_sub: Label = %PauseSub
@onready var _telemetry_cap: Label = %TelemetryCap
@onready var _op_portrait: TextureRect = %OpPortrait
@onready var _op_name: Label = %OpName
@onready var _op_squad: Label = %OpSquad
@onready var _pause_cells = %PauseCells  # KVCellGrid (untyped: indexing lag)
@onready var _log_cap: Label = %LogCap
@onready var _pause_log = %PauseLog     # NikkeDamageLog
@onready var _resume_btn: Button = %ResumeBtn
@onready var _restart_btn: Button = %RestartBtn
@onready var _char_select_btn: Button = %CharSelectBtn
@onready var _settings_btn: Button = %SettingsBtn
@onready var _cheats_btn: Button = %CheatsBtn
@onready var _quit_btn: Button = %QuitBtn

# Results layout
@onready var _result_art = %ResultArt   # CoverArtRect
@onready var _nikke_cap: Label = %NikkeCap
@onready var _result_nikke_name: Label = %ResultNikkeName
@onready var _verdict_label: Label = %VerdictLabel
@onready var _verdict_sub: Label = %VerdictSub
@onready var _verdict_bar: ColorRect = %VerdictBar
@onready var _score_cap: Label = %ScoreCap
@onready var _score_value: Label = %ScoreValue
@onready var _gf_chip: PanelContainer = %GfChip
@onready var _gf_label: Label = %GfLabel
@onready var _report_cells = %ReportCells  # KVCellGrid
@onready var _reward_bar: PanelContainer = %RewardBar
@onready var _reward_icon: Label = %RewardIcon
@onready var _reward_cap: Label = %RewardCap
@onready var _reward_value: Label = %RewardValue
@onready var _loss_log_panel: PanelContainer = %LossLogPanel
@onready var _loss_log_cap: Label = %LossLogCap
@onready var _loss_log = %LossLog       # NikkeDamageLog
@onready var _result_primary_btn = %ResultPrimaryBtn  # PauseCommandButton (untyped: custom props)
@onready var _result_char_select_btn: Button = %ResultCharSelectBtn
@onready var _result_menu_btn: Button = %ResultMenuBtn

const WIN_TEXT := Color(0.482, 0.878, 0.604, 1.0)
const WIN_BAR := Color(0.247, 0.682, 0.369, 1.0)
const LOSS_TEXT := Color(1.0, 0.42, 0.38, 1.0)


func _ready() -> void:
	layer = 125 # Higher than Queen Explosion (120)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	_style_chrome()

	_resume_btn.pressed.connect(_on_resume_pressed)
	_restart_btn.pressed.connect(_on_restart_pressed)
	_char_select_btn.pressed.connect(_on_character_select_pressed)
	_settings_btn.pressed.connect(_on_settings_pressed)
	_cheats_btn.pressed.connect(_on_cheats_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	_result_primary_btn.pressed.connect(_on_restart_pressed)
	_result_char_select_btn.pressed.connect(_on_character_select_pressed)
	_result_menu_btn.pressed.connect(_on_quit_pressed)


func _style_chrome() -> void:
	_pause_title.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_pause_title.add_theme_font_size_override("font_size", 69)
	_pause_title.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	UI.style_subtitle_label(_pause_sub, 18, Color(1, 1, 1, 0.6))

	for cap in [_telemetry_cap, _log_cap, _loss_log_cap]:
		UI.style_subtitle_label(cap, 16, Color(1, 1, 1, 0.55))

	_op_name.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_op_name.add_theme_font_size_override("font_size", 39)
	_op_name.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	UI.style_subtitle_label(_op_squad, 15, Color(1, 1, 1, 0.55))

	_verdict_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_verdict_label.add_theme_font_size_override("font_size", 99)
	UI.style_subtitle_label(_verdict_sub, 18, Color(1, 1, 1, 0.7))

	UI.style_subtitle_label(_nikke_cap, 16, Color(1, 1, 1, 0.65))
	_result_nikke_name.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_result_nikke_name.add_theme_font_size_override("font_size", 51)
	_result_nikke_name.add_theme_color_override("font_color", UI.TEXT_PRIMARY)

	UI.style_subtitle_label(_score_cap, 16, Color(1, 1, 1, 0.55))
	_score_value.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
	_score_value.add_theme_font_size_override("font_size", 84)
	_score_value.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)

	UI.style_subtitle_label(_gf_label, 16, Color(1.0, 0.706, 0.682, 1.0))

	_reward_icon.add_theme_font_size_override("font_size", 33)
	_reward_icon.add_theme_color_override("font_color", UI.ACCENT_CYAN)
	UI.style_subtitle_label(_reward_cap, 14, Color(1, 1, 1, 0.6))
	_reward_value.add_theme_font_override("font", UI.FONT_BOLD)
	_reward_value.add_theme_font_size_override("font_size", 24)
	_reward_value.add_theme_color_override("font_color", Color(0.749, 0.914, 0.984, 1.0))


# =============================================================================
# SHOW / HIDE (API used by Level.gd and bosses)
# =============================================================================

func show_pause() -> void:
	_menu_mode = MenuMode.PAUSE
	_pause_layout.visible = true
	_results_layout.visible = false
	_mid_column.visible = true
	_close_cheats()
	_refresh_telemetry()
	_pause_log.refresh()
	_hide_game_hud()
	visible = true
	get_tree().paused = true
	call_deferred("_grab_initial_focus")


func show_defeat() -> void:
	_show_results(MenuMode.DEFEAT)


func show_victory() -> void:
	_show_results(MenuMode.VICTORY)


func _show_results(mode: int) -> void:
	_menu_mode = mode
	_pause_layout.visible = false
	_results_layout.visible = true
	_close_cheats()
	_refresh_results()
	_hide_game_hud()
	visible = true
	get_tree().paused = true
	call_deferred("_grab_initial_focus")


func hide_menu() -> void:
	visible = false
	_restore_game_hud()
	get_tree().paused = false

	# Fix: Reset enemy time scale in case it got stuck (e.g. paused during hitstop)
	if GameManager:
		GameManager.enemy_time_scale = 1.0


## The overlay replaces the in-game HUD entirely (approved mockup shows no HUD
## chrome). HUD pieces live on many separate CanvasLayers (10-126, music player
## sits ABOVE 125), so hide every positive-layer CanvasLayer except ourselves
## and restore the exact set on close. Negative layers are world backgrounds.
func _hide_game_hud() -> void:
	if not _hidden_hud.is_empty():
		return
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == self:
			continue
		if node is CanvasLayer and not node is ParallaxBackground:
			if node.visible and node.layer >= 0:
				_hidden_hud.append(node)
				node.visible = false
			continue
		for child in node.get_children():
			stack.append(child)


func _restore_game_hud() -> void:
	for hud_layer in _hidden_hud:
		if is_instance_valid(hud_layer):
			hud_layer.visible = true
	_hidden_hud.clear()


func _grab_initial_focus() -> void:
	if _menu_mode == MenuMode.PAUSE:
		_resume_btn.grab_focus()
	else:
		_result_primary_btn.grab_focus()


# =============================================================================
# DATA
# =============================================================================

func _nikke_data():  # -> CharacterData (untyped: members accessed dynamically)
	var registry = CharacterRegistry.get_instance()
	if registry == null or GameManager == null:
		return null
	var char_id: String = registry.get_character_id(GameManager.player_character_index)
	if char_id.is_empty():
		return null
	return registry.get_character(char_id)


func _refresh_telemetry() -> void:
	var data = _nikke_data()
	if data:
		_op_name.text = str(data.display_name).to_upper()
		_op_portrait.texture = data.get_portrait()
		var squad := str(data.squad)
		_op_squad.visible = not squad.is_empty()
		_op_squad.text = "SQUAD // %s" % squad.to_upper()
	_pause_cells.set_cells(_telemetry_cells(false))


func _refresh_results() -> void:
	var is_win := _menu_mode == MenuMode.VICTORY
	var data = _nikke_data()
	if data:
		_result_nikke_name.text = str(data.display_name).to_upper()
		var registry = CharacterRegistry.get_instance()
		var char_id: String = registry.get_character_id(GameManager.player_character_index)
		var burst_path := "res://assets/characters/%s/burst.png" % char_id.replace("_", "-")
		if ResourceLoader.exists(burst_path):
			_result_art.texture = load(burst_path)
		else:
			_result_art.texture = data.get_portrait()

	if is_win:
		_verdict_label.text = "MISSION COMPLETE"
		_verdict_sub.text = "ALL HOSTILES NEUTRALIZED // AREA SECURED"
		_verdict_label.add_theme_color_override("font_color", WIN_TEXT)
		_verdict_bar.color = WIN_BAR
		_result_primary_btn.title_text = "PLAY AGAIN"
	else:
		_verdict_label.text = "NIKKE DOWN"
		_verdict_sub.text = "SIGNAL LOST // OPERATION FAILED"
		_verdict_label.add_theme_color_override("font_color", LOSS_TEXT)
		_verdict_bar.color = UI.COLOR_DANGER
		_result_primary_btn.title_text = "RETRY MISSION"

	_score_value.text = _format_score(GameManager.current_score if GameManager else 0)
	_gf_chip.visible = GameManager != null and GameManager.goddess_fall_mode
	_report_cells.set_cells(_telemetry_cells(true))

	_reward_bar.visible = is_win
	_loss_log_panel.visible = not is_win
	if not is_win:
		_loss_log.refresh()


func _telemetry_cells(for_results: bool) -> Array:
	var score := 0
	var wave := 0
	var time := 0.0
	var diff := 1.0
	var kills := 0
	var bosses := 0
	var damage := 0
	if GameManager:
		score = GameManager.current_score
		wave = GameManager.current_wave
		time = GameManager.run_time
		diff = GameManager.difficulty_multiplier
		var stats: Dictionary = GameManager.get_run_stats()
		for val in stats.get("normal_kills_by_character", {}).values():
			kills += val
		for val in stats.get("boss_kills_by_character", {}).values():
			bosses += val
		for val in stats.get("damage_by_character", {}).values():
			damage += val

	@warning_ignore("integer_division")
	var time_text := "%d:%02d" % [int(time) / 60, int(time) % 60]
	var diff_text := "×%d" % roundi(diff) if is_equal_approx(diff, roundf(diff)) else "×%.1f" % diff

	if for_results:
		return [
			{"k": "WAVE REACHED", "v": str(wave)},
			{"k": "SURVIVAL TIME", "v": time_text},
			{"k": "DIFFICULTY", "v": diff_text},
			{"k": "KILLS", "v": _format_score(kills)},
			{"k": "BOSSES", "v": str(bosses)},
			{"k": "DAMAGE DEALT", "v": _abbrev(damage)},
		]
	return [
		{"k": "SCORE", "v": _format_score(score)},
		{"k": "WAVE", "v": str(wave)},
		{"k": "TIME", "v": time_text},
		{"k": "DIFFICULTY", "v": diff_text},
		{"k": "KILLS", "v": _format_score(kills)},
		{"k": "BOSSES", "v": str(bosses)},
	]


static func _format_score(value: int) -> String:
	var str_val := str(value)
	var result := ""
	var count := 0
	for i in range(str_val.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_val[i] + result
		count += 1
	return result


static func _abbrev(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)


# =============================================================================
# INPUT / BUTTONS
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Only allow ESC to close if it's a pause menu (not defeat/victory)
	if event.is_action_pressed("ui_cancel") and _menu_mode == MenuMode.PAUSE:
		if _cheats_menu != null:
			return # CheatsMenu handles its own close
		UISounds.play_back()
		hide_menu()
		get_viewport().set_input_as_handled()


func _on_resume_pressed() -> void:
	UISounds.play_back()
	hide_menu()
	resume_requested.emit()


func _on_restart_pressed() -> void:
	UISounds.play_confirm()
	hide_menu()
	restart_requested.emit()


func _on_settings_pressed() -> void:
	# Hide pause menu so it doesn't show behind settings
	visible = false
	settings_requested.emit()


func _on_character_select_pressed() -> void:
	# No sound for pause menu options - they have their own transitions
	hide_menu()
	character_select_requested.emit()


func _on_quit_pressed() -> void:
	UISounds.play_back()
	hide_menu()
	quit_requested.emit()


func _on_cheats_pressed() -> void:
	var CheatsMenuScript = load("res://scripts/ui/CheatsMenu.gd")
	if CheatsMenuScript == null:
		return
	UISounds.play_select()
	_cheats_menu = CheatsMenuScript.new()
	_mid_column.visible = false
	_cheats_host.visible = true
	_cheats_host.add_child(_cheats_menu)
	_cheats_menu.close_requested.connect(func():
		_close_cheats()
		_mid_column.visible = true
		_refresh_telemetry() # Cheats can change run state
		_pause_log.refresh()
		call_deferred("_grab_initial_focus")
	)


func _close_cheats() -> void:
	if _cheats_menu and is_instance_valid(_cheats_menu):
		_cheats_menu.queue_free()
	_cheats_menu = null
	_cheats_host.visible = false
