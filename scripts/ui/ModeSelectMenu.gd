extends Control
class_name ModeSelectMenu
## Mode selection screen: STANDARD vs SURFACE EXPLORATION.
## Shown after PLAY is pressed on main menu.
## Matches header layout and styling of Shop/Achievements menus.

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")
const VenetianBlindsScript = preload("res://scripts/ui/components/VenetianBlindsBackground.gd")

signal standard_selected
signal back_requested

var _bg: Control
var _standard_btn: Panel
var _exploration_btn: Panel
var _coming_soon_dialog: Control = null

func _ready() -> void:
	_build_ui()
	call_deferred("_grab_initial_focus")

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	
	# Handle coming soon dialog first
	if _coming_soon_dialog and _coming_soon_dialog.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			_hide_coming_soon()
			get_viewport().set_input_as_handled()
		return
	
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	# Background with venetian blinds effect
	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.set_script(VenetianBlindsScript)
	add_child(_bg)
	
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = UI.OVERLAY_LIGHT
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	
	# === TOP BAR (matches Shop/Achievements) ===
	var top_bar := Panel.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = 24
	top_bar.offset_bottom = 160
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_stylebox_override("panel", _make_letterbox_style())
	add_child(top_bar)
	
	# Title label - centered in header
	var title_label := Label.new()
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.text = "SELECT MODE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if UI.FONT_TITLE:
		title_label.add_theme_font_override("font", UI.FONT_TITLE)
	title_label.add_theme_font_size_override("font_size", 80)
	title_label.add_theme_color_override("font_color", UI.ACCENT_PRIMARY)
	title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.5))
	title_label.add_theme_constant_override("outline_size", 3)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(title_label)
	
	# BACK Button - using SciFiBackButton class
	var back_btn := SciFiBackButton.new()
	back_btn.position = Vector2(48, 30)
	back_btn.custom_minimum_size = Vector2(200, 75)
	back_btn.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_btn)
	
	# === MAIN CONTENT PANEL ===
	var content_panel := Panel.new()
	content_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_panel.offset_left = 48
	content_panel.offset_top = 176
	content_panel.offset_right = -48
	content_panel.offset_bottom = -48
	content_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(content_panel)
	
	# HBox container that fills the content panel with expanding cards
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 32
	hbox.offset_right = -32
	hbox.offset_top = 32
	hbox.offset_bottom = -32
	hbox.add_theme_constant_override("separation", 40)
	content_panel.add_child(hbox)
	
	# STANDARD Mode Button - expands to fill
	_standard_btn = _create_mode_card(
		"STANDARD",
		"Classic 12-wave survival run.\nBattle through increasingly difficult waves\nand defeat the Rapture Queen to win.",
		"⚔️",
		true # is_available
	)
	_standard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_standard_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_standard_btn)
	
	# SURFACE EXPLORATION Mode Button - expands to fill (COMING SOON)
	_exploration_btn = _create_mode_card(
		"SURFACE EXPLORATION",
		"Roguelike node map adventure.\nChoose your path through dangerous territory.\nRecruit allies and reach the Rapture Queen.",
		"🗺️",
		false # is_available - Surface Exploration COMING SOON
	)
	_exploration_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exploration_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_exploration_btn)

func _create_mode_card(title: String, description: String, icon: String, is_available: bool) -> Panel:
	var card := Panel.new()
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Store availability on the card itself
	card.set_meta("is_available", is_available)
	card.set_meta("mode_title", title)
	
	# Style based on availability
	_apply_card_style(card, is_available, false)
	
	# Hover effects
	card.mouse_entered.connect(_on_card_hover.bind(card))
	card.mouse_exited.connect(_on_card_unhover.bind(card))
	card.focus_entered.connect(_on_card_hover.bind(card))
	card.focus_exited.connect(_on_card_unhover.bind(card))
	card.gui_input.connect(_on_card_input.bind(card))
	
	# Content VBox - centered
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 32)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)
	
	# Icon - large
	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 120)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_available:
		icon_lbl.modulate = Color(0.5, 0.5, 0.5)
	vbox.add_child(icon_lbl)
	
	# Title - large
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_BOLD:
		title_lbl.add_theme_font_override("font", UI.FONT_BOLD)
	title_lbl.add_theme_font_size_override("font_size", 48)
	title_lbl.add_theme_color_override("font_color", UI.ACCENT_PRIMARY if is_available else UI.TEXT_MUTED)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)
	
	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = description
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_MEDIUM:
		desc_lbl.add_theme_font_override("font", UI.FONT_MEDIUM)
	desc_lbl.add_theme_font_size_override("font_size", 24)
	desc_lbl.add_theme_color_override("font_color", UI.TEXT_SECONDARY if is_available else UI.TEXT_MUTED)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)
	
	# Status label
	var status_lbl := Label.new()
	if is_available:
		status_lbl.text = "▶ CLICK TO PLAY"
		status_lbl.add_theme_color_override("font_color", UI.COLOR_SUCCESS)
	else:
		status_lbl.text = "🔒 COMING SOON"
		status_lbl.add_theme_color_override("font_color", UI.COLOR_DANGER)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UI.FONT_BOLD:
		status_lbl.add_theme_font_override("font", UI.FONT_BOLD)
	status_lbl.add_theme_font_size_override("font_size", 28)
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(status_lbl)
	
	return card

func _apply_card_style(card: Panel, is_available: bool, is_hovered: bool) -> void:
	var style := StyleBoxFlat.new()
	if is_available:
		style.bg_color = UI.BG_MID if is_hovered else UI.BG_DEEP
		style.border_color = UI.ACCENT_HOVER if is_hovered else UI.ACCENT_PRIMARY
	else:
		style.bg_color = Color(0.12, 0.12, 0.18, 0.95) if is_hovered else Color(0.08, 0.08, 0.12, 0.95)
		style.border_color = UI.COLOR_LOCKED
	style.set_border_width_all(5 if is_hovered else 4)
	style.set_corner_radius_all(20)
	card.add_theme_stylebox_override("panel", style)

func _on_card_hover(card: Panel) -> void:
	var is_available: bool = card.get_meta("is_available", false)
	_apply_card_style(card, is_available, true)
	
	# Scale effect
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "scale", Vector2(1.02, 1.02), 0.1)

func _on_card_unhover(card: Panel) -> void:
	var is_available: bool = card.get_meta("is_available", false)
	_apply_card_style(card, is_available, false)
	
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "scale", Vector2.ONE, 0.1)

func _on_card_input(event: InputEvent, card: Panel) -> void:
	var clicked := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked = true
	elif event.is_action_pressed("ui_accept"):
		clicked = true
	
	if clicked:
		var is_available: bool = card.get_meta("is_available", false)
		var mode_title: String = card.get_meta("mode_title", "")
		_select_mode(mode_title, is_available)

func _select_mode(mode_title: String, is_available: bool) -> void:
	print("[ModeSelectMenu] Selected: %s, available: %s" % [mode_title, is_available])
	if is_available:
		UISounds.play_confirm()
		if mode_title == "STANDARD":
			standard_selected.emit()
	else:
		UISounds.play_back()
		_show_coming_soon()

func _show_coming_soon() -> void:
	if _coming_soon_dialog and _coming_soon_dialog.visible:
		return
	
	if _coming_soon_dialog:
		_coming_soon_dialog.visible = true
		var btn = _coming_soon_dialog.get_node_or_null("Panel/VBox/BtnContainer/CloseBtn")
		if btn:
			btn.grab_focus.call_deferred()
		return
	
	# Create overlay
	_coming_soon_dialog = Control.new()
	_coming_soon_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_coming_soon_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_coming_soon_dialog)
	
	# Dark background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UI.BG_OVERLAY
	bg.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_hide_coming_soon()
	)
	_coming_soon_dialog.add_child(bg)
	
	# Panel
	var panel := Panel.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(500, 280)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = -140
	panel.offset_bottom = 140
	
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI.BG_MID
	panel_style.border_color = UI.ACCENT_PRIMARY
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	_coming_soon_dialog.add_child(panel)
	
	# Content
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 32
	vbox.offset_right = -32
	vbox.offset_top = 32
	vbox.offset_bottom = -32
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var title := Label.new()
	title.text = "🚧 COMING SOON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if UI.FONT_BOLD:
		title.add_theme_font_override("font", UI.FONT_BOLD)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)
	vbox.add_child(title)
	
	var desc := Label.new()
	desc.text = "Surface Exploration mode is still under development.\nCheck back in a future update!"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 20)
	desc.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	vbox.add_child(desc)
	
	var btn_container := HBoxContainer.new()
	btn_container.name = "BtnContainer"
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)
	
	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "OK"
	close_btn.custom_minimum_size = Vector2(140, 50)
	_apply_close_button_style(close_btn)
	close_btn.pressed.connect(_hide_coming_soon)
	btn_container.add_child(close_btn)
	
	# Grab focus for controller
	close_btn.grab_focus.call_deferred()

func _hide_coming_soon() -> void:
	UISounds.play_back()
	if _coming_soon_dialog:
		_coming_soon_dialog.visible = false

func _make_letterbox_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_color = UI.ACCENT_PRIMARY
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.set_corner_radius_all(0)
	return style

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG_DEEP
	style.border_color = UI.ACCENT_PRIMARY
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	return style

func _apply_close_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UI.BG_MID
	normal.border_color = UI.ACCENT_PRIMARY
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = UI.BG_LIGHT
	hover.border_color = UI.ACCENT_HOVER
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", UI.TEXT_PRIMARY)

func _on_back_pressed() -> void:
	UISounds.play_back()
	back_requested.emit()

func _grab_initial_focus() -> void:
	if _standard_btn:
		_standard_btn.grab_focus()
