extends Control
class_name CharacterSelectMenu
## Character and Stage Selection Menu - NIKKE squad-file style (light admin
## register, approved mockup docs/mockups/character_select_v7.html).
## Phase 1: card grid + diagonal art strip + detail panel; click selects,
## DEPLOY advances. Phase 2: stage selector (unchanged, redesign pending).
## Static chrome lives in CharacterSelectMenu.tscn; the roster grid is
## data-driven from CharacterRegistry.

const UI := preload("res://scripts/ui/UITheme.gd")
const UISounds := preload("res://scripts/ui/UISoundManager.gd")
# MissionSelect.tscn is loaded lazily: preloading it here is circular (the
# scene's script chain references back through this menu), which breaks
# resource loading under some load orders (exports, -s harnesses).
const ShopMenuScript := preload("res://scripts/ui/ShopMenu.gd")
const CharacterSelectCardScript := preload("res://scripts/ui/components/CharacterSelectCard.gd")
const NikkePopupScript := preload("res://scripts/ui/components/NikkePopup.gd")

signal play_requested(character_index: int, stage_id: String)
signal back_requested

const CARD_SIZE := Vector2(165, 258)

# Mild page wash per character (user-specified theme colors)
const CHARACTER_TINTS := {
	"snow_white": Color("cfd6dd"), "scarlet": Color("7d5bd6"),
	"kilo": Color("4caf6d"), "rapunzel": Color("e8c84a"),
	"commander": Color("a8854a"), "nayuta": Color("6b6bd6"),
	"marian": Color("9b59d0"), "crown": Color("d4a730"),
	"cecil": Color("3aa8a0"), "sin": Color("8348c9"),
	"wells": Color("3a7bd5"),
}
const TINT_ALPHA := 0.12

enum Phase {CHARACTER, STAGE}
var _phase: Phase = Phase.CHARACTER
var _selected_char_id: String = ""
var _pending_unlock_id: String = ""

var _registry: RefCounted
var _cards: Dictionary = {}        # char_id -> CharacterSelectCard
var _card_order: Array[String] = []
var _burst_audio: AudioStreamPlayer
var _stage_selector: MissionSelect = null
var _transition_tween: Tween = null
var _active_popup: Control = null

@onready var _tint: ColorRect = %TintOverlay
@onready var _char_container: Control = %CharContainer
@onready var _art_strip: DiagonalArtStrip = %ArtStrip
@onready var _header_title: Label = %HeaderTitle
@onready var _header_sub: Label = %HeaderSub
@onready var _grid: GridContainer = %CardGrid
@onready var _detail: CharacterDetailPanel = %DetailPanel
@onready var _back_button: Button = %BackButton
@onready var _operator_chip: OperatorChip = %OperatorChip
@onready var _stage_container: Control = %StageContainer


func _ready() -> void:
	_registry = CharacterRegistry.get_instance()
	_style_header()
	_populate_grid()
	_build_stage_phase()
	_setup_burst_audio()

	_detail.deploy_pressed.connect(_on_deploy_pressed)
	_back_button.pressed.connect(_go_back)
	visibility_changed.connect(_on_visibility_changed)

	_ensure_menu_music()
	_select_initial_character()
	call_deferred("_grab_initial_focus")


func _style_header() -> void:
	UI.style_header_label(_header_title, 56, UI.ADMIN_TEXT)
	UI.style_subtitle_label(_header_sub, 17, UI.ADMIN_TEXT_DIM)
	# BackButton (NikkeCardButton) keeps its own styling from the scene


func _setup_burst_audio() -> void:
	_burst_audio = AudioStreamPlayer.new()
	_burst_audio.bus = "SFX"
	add_child(_burst_audio)


func _ensure_menu_music() -> void:
	if MenuManager:
		MenuManager.start_menu_music()


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and _phase == Phase.CHARACTER and _art_strip.has_method("play_entrance"):
		_art_strip.play_entrance()
		call_deferred("_grab_initial_focus")


# =============================================================================
# GRID
# =============================================================================

func _populate_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cards.clear()
	_card_order.clear()

	for char_id in _registry.get_all_character_ids():
		var data = _registry.get_character(char_id)
		var card: CharacterSelectCard = CharacterSelectCardScript.new()
		card.char_id = char_id
		card.display_name = data.display_name if data else char_id
		card.weapon_tag = CharacterRegistry.get_weapon_tag(str(data.weapon_kind)) if data else ""
		card.portrait_texture = data.get_portrait() if data else null
		card.is_unlocked = ShopMenuScript.is_character_unlocked(char_id)
		card.unlock_cost = CharacterRegistry.get_unlock_cost(char_id)
		card.custom_minimum_size = CARD_SIZE
		card.card_selected.connect(_on_card_selected)
		_grid.add_child(card)
		_cards[char_id] = card
		_card_order.append(char_id)

	var random_card: CharacterSelectCard = CharacterSelectCardScript.new()
	random_card.is_random = true
	random_card.custom_minimum_size = CARD_SIZE
	random_card.card_selected.connect(_on_card_selected)
	_grid.add_child(random_card)

	call_deferred("_setup_focus_neighbors")


func _on_card_selected(char_id: String) -> void:
	if char_id == "":  # RANDOM slot
		var unlocked: Array[String] = []
		for id in _card_order:
			if _cards[id].is_unlocked:
				unlocked.append(id)
		if unlocked.is_empty():
			return
		UISounds.play_select()
		_apply_selection(unlocked.pick_random(), true)
		return

	if not _cards[char_id].is_unlocked:
		_try_unlock(char_id)
		return

	if char_id == _selected_char_id:
		return
	UISounds.play_select()
	_apply_selection(char_id, true)


func _apply_selection(char_id: String, animate: bool) -> void:
	_selected_char_id = char_id
	var data = _registry.get_character(char_id)

	for id in _cards:
		_cards[id].set_selected(id == char_id)

	var art := _load_burst_art(char_id)
	if animate:
		_detail.swap_to_character(data)
		_art_strip.swap_art(art)
	else:
		_detail.show_character(data)
		_art_strip.set_art(art)
		_art_strip.play_entrance()

	var tint_color: Color = CHARACTER_TINTS.get(char_id, Color.TRANSPARENT)
	tint_color.a = TINT_ALPHA
	var tween := create_tween()
	tween.tween_property(_tint, "color", tint_color, 0.6).set_trans(Tween.TRANS_SINE)

	if data:
		_operator_chip.set_operator(data.display_name, data.get_portrait())

	_play_burst_sfx(char_id)


func _load_burst_art(char_id: String) -> Texture2D:
	var path := "res://assets/characters/%s/burst.png" % char_id.replace("_", "-")
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _select_initial_character() -> void:
	for char_id in _card_order:
		if _cards[char_id].is_unlocked:
			_apply_selection(char_id, false)
			return
	if not _card_order.is_empty():
		_apply_selection(_card_order[0], false)


# =============================================================================
# UNLOCK FLOW
# =============================================================================

func _try_unlock(char_id: String) -> void:
	var cost := CharacterRegistry.get_unlock_cost(char_id)

	if GameManager.get_pristine_cores() < cost:
		UISounds.play_back()
		var card: Control = _cards.get(char_id)
		if card:
			var orig_x := card.position.x
			var tween := create_tween()
			for offset in [5.0, -5.0, 3.0, 0.0]:
				tween.tween_property(card, "position:x", orig_x + offset, 0.05)
		return

	if _active_popup:
		return
	_pending_unlock_id = char_id
	var data = _registry.get_character(char_id)
	var char_name: String = data.display_name if data else char_id

	var popup := NikkePopupScript.create("Unlock %s?" % char_name, "Pristine core exchange")
	popup.add_text("Unlock %s for ◆ %d Pristine Cores?\nYou have ◆ %d." % [
		char_name, cost, GameManager.get_pristine_cores()])
	popup.add_button("CANCEL", "secondary").pressed.connect(popup.close)
	popup.add_button("UNLOCK", "primary").pressed.connect(func():
		popup.close()
		_on_unlock_confirmed()
	)
	_open_popup(popup)


func _open_popup(popup: Control) -> void:
	_active_popup = popup
	popup.closed.connect(func():
		_active_popup = null
		call_deferred("_grab_initial_focus")
	)
	popup.open(self)


func _on_unlock_confirmed() -> void:
	if _pending_unlock_id.is_empty():
		return
	var char_id := _pending_unlock_id
	_pending_unlock_id = ""

	var cost := CharacterRegistry.get_unlock_cost(char_id)
	if not GameManager.spend_pristine_cores(cost):
		return

	ShopMenuScript.unlock_character(char_id)
	if has_node("/root/AchievementManager"):
		get_node("/root/AchievementManager").on_character_unlocked_in_shop(char_id)

	UISounds.play_confirm()
	_populate_grid()
	call_deferred("_apply_selection", char_id, true)
	print("[CharacterSelectMenu] Unlocked character: %s (%d cores)" % [char_id, cost])


# =============================================================================
# STAGE PHASE (MissionSelect - NIKKE field briefing)
# =============================================================================

func _build_stage_phase() -> void:
	_stage_container.position.y = get_viewport_rect().size.y
	_stage_container.modulate.a = 0.0

	_stage_selector = load("res://scenes/ui/MissionSelect.tscn").instantiate()
	_stage_selector.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_selector.stage_confirmed.connect(_on_stage_confirmed)
	_stage_selector.back_requested.connect(_on_stage_back)
	_stage_container.add_child(_stage_selector)


func _on_deploy_pressed() -> void:
	if _selected_char_id.is_empty():
		return
	UISounds.play_confirm()
	_transition_to_stage()


func _transition_to_stage() -> void:
	if _phase == Phase.STAGE:
		return
	_phase = Phase.STAGE
	_stage_container.visible = true

	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()

	if _transition_tween:
		_transition_tween.kill()
	var vh := get_viewport_rect().size.y
	_transition_tween = create_tween().set_parallel(true)
	_transition_tween.tween_property(_char_container, "position:y", -vh, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_char_container, "modulate:a", 0.0, 0.4)
	_transition_tween.tween_property(_stage_container, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_stage_container, "modulate:a", 1.0, 0.4).set_delay(0.1)

	if _stage_selector:
		var data = _registry.get_character(_selected_char_id)
		_stage_selector.prepare_open(
			data.display_name if data else _selected_char_id,
			data.get_portrait() if data else null)


func _transition_to_character() -> void:
	if _phase == Phase.CHARACTER:
		return
	_phase = Phase.CHARACTER

	if _transition_tween:
		_transition_tween.kill()
	var vh := get_viewport_rect().size.y
	_transition_tween = create_tween().set_parallel(true)
	_transition_tween.tween_property(_stage_container, "position:y", vh, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_stage_container, "modulate:a", 0.0, 0.4)
	_transition_tween.tween_property(_char_container, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(_char_container, "modulate:a", 1.0, 0.4).set_delay(0.1)
	_transition_tween.set_parallel(false)
	_transition_tween.tween_callback(func(): _stage_container.visible = false)

	call_deferred("_grab_initial_focus")


func _on_stage_back() -> void:
	UISounds.play_back()
	_transition_to_character()


func _on_stage_confirmed(stage_id: String) -> void:
	var all_ids = _registry.get_all_character_ids()
	var char_index: int = all_ids.find(_selected_char_id)
	if char_index < 0:
		push_warning("[CharacterSelectMenu] No character selected, defaulting to 0")
		char_index = 0

	play_requested.emit(char_index, stage_id)
	if play_requested.get_connections().is_empty():
		_start_game(char_index, stage_id)


func _start_game(char_index: int, stage_id: String) -> void:
	if GameManager:
		GameManager.set_player_character(char_index)
		GameManager.current_stage_id = stage_id
	if MenuManager:
		MenuManager.stop_menu_music()
	get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")


# =============================================================================
# INPUT / NAVIGATION
# =============================================================================

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		if _active_popup:
			return  # NikkePopup closes itself
		if _phase == Phase.STAGE:
			UISounds.play_back()
			if _stage_selector:
				_stage_selector.reset_on_leave()
			_transition_to_character()
		else:
			_go_back()
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()


func _go_back() -> void:
	UISounds.play_back()
	if back_requested.get_connections().size() > 0:
		back_requested.emit()
	elif MenuManager:
		MenuManager.return_to_main_menu()
	else:
		back_requested.emit()


func _grab_initial_focus() -> void:
	if _phase != Phase.CHARACTER or not is_visible_in_tree():
		return
	var card: Control = _cards.get(_selected_char_id)
	if card:
		card.grab_focus()
	elif not _cards.is_empty():
		_cards.values()[0].grab_focus()


func _setup_focus_neighbors() -> void:
	var cards: Array[Control] = []
	for child in _grid.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			cards.append(child)
	var cols := _grid.columns
	var deploy: Button = _detail.get_deploy_button()

	for i in cards.size():
		var card := cards[i]
		var row := floori(float(i) / cols)
		var col := i % cols
		var row_start := row * cols
		var row_end := mini(row_start + cols - 1, cards.size() - 1)

		card.focus_neighbor_left = card.get_path_to(cards[row_end] if col == 0 else cards[i - 1])
		if col == cols - 1 or i == cards.size() - 1:
			# Right edge of the grid jumps to the DEPLOY slab
			if deploy:
				card.focus_neighbor_right = card.get_path_to(deploy)
		else:
			card.focus_neighbor_right = card.get_path_to(cards[i + 1])
		if i - cols >= 0:
			card.focus_neighbor_top = card.get_path_to(cards[i - cols])
		if i + cols < cards.size():
			card.focus_neighbor_bottom = card.get_path_to(cards[i + cols])

	if deploy and not cards.is_empty():
		deploy.focus_neighbor_left = deploy.get_path_to(cards[mini(cols - 1, cards.size() - 1)])


func _play_burst_sfx(char_id: String) -> void:
	if _burst_audio.playing:
		_burst_audio.stop()
	var stream: AudioStream = _registry.get_burst_sound(char_id)
	if stream:
		_burst_audio.stream = stream
		_burst_audio.play()
