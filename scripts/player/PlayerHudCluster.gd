extends Control
class_name PlayerHudCluster
## Player HUD cluster (dark field register, approved mockup
## docs/mockups/hud_v2.html): bracket-frame panel with portrait + HP and BURST
## rows. Small letter-spaced labels left, flat bars center, oblique value
## numerals OUTSIDE the bars on the right. Stamina bar removed (sprint needs no
## gauge) - update_stamina() is kept as a no-op for callers.

signal portrait_shaken
signal health_fill_finished
signal burst_fill_finished
signal stamina_fill_finished

const UI := preload("res://scripts/ui/UITheme.gd")
const BracketStyleBoxScript := preload("res://scripts/ui/components/BracketStyleBox.gd")

@export var shake_distance: float = 4.0
@export_range(0.05, 1.5, 0.01) var shake_duration: float = 0.2
@export_range(0.05, 1.0, 0.01) var fill_transition_time: float = 0.22
@export_range(0.0, 1.0, 0.01) var low_health_threshold: float = 0.25
@export var auto_apply_styles: bool = true

@export var hp_bar_color: Color = Color(0.29, 0.87, 0.5, 1.0)
@export var burst_bar_color: Color = Color(1.0, 0.824, 0.247, 1.0)
@export var bar_background: Color = Color(0.039, 0.051, 0.071, 0.75)
@export var low_health_color: Color = Color(1.0, 0.4, 0.4, 1.0)
@export var burst_locked_bar_color: Color = Color(0.35, 0.35, 0.4, 0.6)

@onready var _outer_frame: Panel = %OuterFrame
@onready var _portrait_slot: Control = %PortraitShake
@onready var _portrait_frame: Panel = %PortraitFrame
@onready var _portrait_background: ColorRect = %PortraitBackground
@onready var _portrait_texture: TextureRect = %PortraitTexture
@onready var _hp_label: Label = %HPLabel
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _hp_value: Label = %HPValue
@onready var _burst_label: Label = %BurstLabel
@onready var _burst_bar: ProgressBar = %BurstBar
@onready var _burst_value: Label = %BurstValue

var _portrait_origin: Vector2 = Vector2.ZERO
var _default_portrait_modulate: Color = Color(1, 1, 1, 1)

var _health_tween: Tween = null
var _burst_tween: Tween = null
var _shake_tween: Tween = null
var _burst_ready_tween: Tween = null

var _max_health: int = 1
var _current_health: int = 1
var _max_burst: float = 1.0
var _current_burst: float = 0.0
var _burst_ready_state: bool = false
var _burst_unlocked: bool = false

# Character portraits - dynamically loaded from GameManager/CharacterRegistry
var _character_portraits: Array[String] = []
var _portrait_indices: Array[int] = [] # Map slot index to registry index


func _ready() -> void:
	_load_character_portraits()
	_portrait_origin = _portrait_slot.position
	_default_portrait_modulate = _portrait_texture.modulate
	if auto_apply_styles:
		_apply_styles()
	_refresh_bars()
	_update_bar_value_labels()
	_apply_low_health_state()
	set_burst_ready(false, false)
	# Burst bar starts locked (greyed out) until unlocked
	set_burst_unlocked(false)
	# Default to first character
	set_character(0)


func _load_character_portraits() -> void:
	# Load the portrait of the selected character from GameManager
	_character_portraits.clear()
	_portrait_indices.clear()

	var game_manager = get_node_or_null("/root/GameManager")

	if game_manager:
		var idx: int = game_manager.player_character_index
		_portrait_indices = [idx]

		# Get CharacterRegistry to map index to portrait path
		var registry = CharacterRegistry.get_instance()
		if registry:
			var all_ids: Array[String] = registry.get_all_character_ids()
			if idx >= 0 and idx < all_ids.size():
				var char_id: String = all_ids[idx]
				var folder_name: String = char_id.replace("_", "-")
				_character_portraits.append("res://assets/characters/%s/portrait-sq.png" % folder_name)
			else:
				_character_portraits.append("")

	# Fallback if nothing loaded
	if _character_portraits.is_empty():
		_character_portraits = ["res://assets/characters/snow-white/portrait-sq.png"]
		_portrait_indices = [0]


func _update_bar_value_labels() -> void:
	if _hp_value:
		_hp_value.text = "%d/%d" % [_current_health, _max_health]
	if _burst_value and not _burst_ready_state:
		var burst_percent := int((_current_burst / _max_burst) * 100.0) if _max_burst > 0 else 0
		_burst_value.text = "%d%%" % burst_percent


func set_character(character_slot: int, burst_unlocked: bool = true) -> void:
	if not is_inside_tree():
		return

	# Guard against empty portraits array
	if _character_portraits.is_empty():
		_load_character_portraits()

	if _character_portraits.is_empty():
		return # Still empty, can't set portrait

	# Single-character runs: only slot 0 exists
	if character_slot < 0 or character_slot >= _character_portraits.size():
		character_slot = 0

	var portrait_path = _character_portraits[character_slot]
	if portrait_path.is_empty():
		return

	var texture = load(portrait_path) as Texture2D
	if texture and _portrait_texture:
		_portrait_texture.texture = texture
		_portrait_texture.visible = true

	# Update burst unlock status for this character
	set_burst_unlocked(burst_unlocked)


func set_burst_unlocked(unlocked: bool) -> void:
	_burst_unlocked = unlocked
	_apply_burst_locked_style()
	if not unlocked:
		# Reset burst to 0 when locked
		_current_burst = 0.0
		if _burst_bar:
			_burst_bar.value = 0.0
		_update_bar_value_labels()
		set_burst_ready(false, false)


func _apply_burst_locked_style() -> void:
	if not _burst_bar:
		return
	if _burst_unlocked:
		_burst_bar.add_theme_stylebox_override("fill", _create_bar_fill(burst_bar_color))
		_burst_bar.modulate = Color.WHITE
		if _burst_label:
			_burst_label.modulate = Color.WHITE
		if _burst_value:
			_burst_value.modulate = Color.WHITE
	else:
		_burst_bar.add_theme_stylebox_override("fill", _create_bar_fill(burst_locked_bar_color))
		_burst_bar.modulate = Color(0.6, 0.6, 0.65, 1.0)
		if _burst_label:
			_burst_label.modulate = Color(0.6, 0.6, 0.65, 1.0)
		if _burst_value:
			_burst_value.modulate = Color(0.6, 0.6, 0.65, 1.0)


func configure(current_health: int, max_health: int, burst_current: float = 0.0, burst_max: float = 1.0, _stamina_current: float = 100.0, _stamina_max: float = 100.0) -> void:
	_max_health = maxi(1, max_health)
	_current_health = clampi(current_health, 0, _max_health)
	_max_burst = maxf(0.001, burst_max)
	_current_burst = clampf(burst_current, 0.0, _max_burst)
	_refresh_bars()
	_update_bar_value_labels()
	_apply_low_health_state()


func update_health(current: int, max_value: int, delta: int = 0, animate: bool = true) -> void:
	var new_max: int = maxi(1, max_value)
	var clamped: int = clampi(current, 0, new_max)
	var previous: int = _current_health
	_max_health = new_max
	_current_health = clamped
	_hp_bar.max_value = _max_health
	_update_bar_value_labels()
	if _health_tween and _health_tween.is_running():
		_health_tween.kill()
		_health_tween = null
	if animate:
		_health_tween = create_tween()
		var tween_ref: Tween = _health_tween
		_health_tween.tween_property(_hp_bar, "value", float(_current_health), fill_transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_health_tween.finished.connect(func():
			if not is_instance_valid(self):
				return
			emit_signal("health_fill_finished")
			if _health_tween == tween_ref:
				_health_tween = null
		)
	else:
		_hp_bar.value = _current_health
		emit_signal("health_fill_finished")
	_apply_low_health_state()
	if delta < 0 and _current_health < previous:
		_trigger_damage_shake()


func update_burst(current: float, max_value: float, animate: bool = true) -> void:
	# Don't update burst if locked
	if not _burst_unlocked:
		return

	var new_max: float = maxf(0.001, max_value)
	var clamped: float = clampf(current, 0.0, new_max)
	_max_burst = new_max
	_current_burst = clamped
	_burst_bar.max_value = _max_burst
	_update_bar_value_labels()
	if _burst_tween and _burst_tween.is_running():
		_burst_tween.kill()
		_burst_tween = null
	if animate:
		_burst_tween = create_tween()
		var tween_ref: Tween = _burst_tween
		_burst_tween.tween_property(_burst_bar, "value", float(_current_burst), fill_transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_burst_tween.finished.connect(func():
			if not is_instance_valid(self):
				return
			emit_signal("burst_fill_finished")
			if _burst_tween == tween_ref:
				_burst_tween = null
		)
	else:
		_burst_bar.value = _current_burst
		emit_signal("burst_fill_finished")

	# Check if burst is ready
	var was_ready = _burst_ready_state
	var is_ready = _current_burst >= _max_burst
	if is_ready != was_ready:
		set_burst_ready(is_ready, animate)


## Stamina bar removed from the HUD (sprint needs no gauge). Kept as a no-op
## so PlayerCore's stamina_changed wiring stays valid.
func update_stamina(_current: float, _max_value: float, _animate: bool = true) -> void:
	emit_signal("stamina_fill_finished")


func set_burst_ready(is_ready: bool, animate: bool = true) -> void:
	if _burst_ready_state == is_ready and animate:
		return
	_burst_ready_state = is_ready
	if _burst_ready_tween and _burst_ready_tween.is_running():
		_burst_ready_tween.kill()
		_burst_ready_tween = null
	if _burst_value:
		if is_ready:
			_burst_value.text = "READY!"
			_burst_value.add_theme_color_override("font_color", UI.ACCENT_SECONDARY)
		else:
			_burst_value.add_theme_color_override("font_color", UI.ACCENT_SECONDARY.lightened(0.25))
			_update_bar_value_labels()
		_burst_value.scale = Vector2.ONE
	if animate and is_ready and _burst_value and is_inside_tree():
		_burst_value.pivot_offset = _burst_value.size * 0.5
		_burst_ready_tween = create_tween()
		var tween_ref: Tween = _burst_ready_tween
		_burst_ready_tween.tween_property(_burst_value, "scale", Vector2(1.18, 1.18), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_burst_ready_tween.tween_property(_burst_value, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_burst_ready_tween.finished.connect(func():
			if not is_instance_valid(self):
				return
			if _burst_ready_tween == tween_ref:
				_burst_ready_tween = null
		)


func _refresh_bars() -> void:
	_hp_bar.max_value = _max_health
	_hp_bar.value = _current_health
	_burst_bar.max_value = _max_burst
	_burst_bar.value = _current_burst


func _apply_low_health_state() -> void:
	if _max_health <= 0:
		_portrait_texture.modulate = _default_portrait_modulate
		return
	var ratio: float = float(_current_health) / float(_max_health)
	_portrait_texture.modulate = low_health_color if ratio <= low_health_threshold else _default_portrait_modulate
	if _hp_value:
		_hp_value.add_theme_color_override("font_color",
			low_health_color if ratio <= low_health_threshold else UI.TEXT_PRIMARY)


func _apply_styles() -> void:
	# Bracket-frame panel (NIKKE target-box vocabulary)
	if _outer_frame:
		var frame_style = BracketStyleBoxScript.new()
		_outer_frame.add_theme_stylebox_override("panel", frame_style)

	if _portrait_frame:
		var portrait_style := StyleBoxFlat.new()
		portrait_style.bg_color = Color(0.04, 0.05, 0.07, 0.92)
		portrait_style.border_color = Color(1, 1, 1, 0.35)
		portrait_style.set_border_width_all(1)
		portrait_style.set_corner_radius_all(0)
		_portrait_frame.add_theme_stylebox_override("panel", portrait_style)

	for bar_label in [_hp_label, _burst_label]:
		if bar_label:
			UI.style_subtitle_label(bar_label, 11, Color(1, 1, 1, 0.6))
			bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bar_label.size_flags_vertical = Control.SIZE_FILL

	for value_label in [_hp_value, _burst_value]:
		if value_label:
			value_label.add_theme_font_override("font", UI.FONT_TITLE_OBLIQUE)
			value_label.add_theme_font_size_override("font_size", 21)
			value_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
			value_label.add_theme_constant_override("shadow_offset_x", 1)
			value_label.add_theme_constant_override("shadow_offset_y", 2)
			value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			value_label.size_flags_vertical = Control.SIZE_FILL
	if _hp_value:
		_hp_value.add_theme_color_override("font_color", UI.TEXT_PRIMARY)
	if _burst_value:
		_burst_value.add_theme_color_override("font_color", UI.ACCENT_SECONDARY.lightened(0.25))

	if _hp_bar:
		_hp_bar.add_theme_stylebox_override("background", _create_bar_background())
		_hp_bar.add_theme_stylebox_override("fill", _create_bar_fill(hp_bar_color))
	if _burst_bar:
		_burst_bar.add_theme_stylebox_override("background", _create_bar_background())
		_burst_bar.add_theme_stylebox_override("fill", _create_bar_fill(burst_bar_color))
	set_burst_ready(_burst_ready_state, false)


func _create_bar_background() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bar_background
	box.set_corner_radius_all(0)
	return box


func _create_bar_fill(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(0)
	return box


func _trigger_damage_shake() -> void:
	if not is_inside_tree():
		return
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.kill()
		_shake_tween = null
	_portrait_slot.position = _portrait_origin
	_shake_tween = create_tween()
	var tween_ref: Tween = _shake_tween
	_shake_tween.set_trans(Tween.TRANS_SINE)
	_shake_tween.set_ease(Tween.EASE_OUT)
	var left: Vector2 = _portrait_origin + Vector2(-shake_distance, 0)
	var right: Vector2 = _portrait_origin + Vector2(shake_distance * 0.6, 0)
	_shake_tween.tween_property(_portrait_slot, "position", left, shake_duration * 0.35)
	_shake_tween.tween_property(_portrait_slot, "position", right, shake_duration * 0.3)
	_shake_tween.tween_property(_portrait_slot, "position", _portrait_origin, shake_duration * 0.35)
	_shake_tween.finished.connect(func():
		if not is_instance_valid(self):
			return
		_portrait_slot.position = _portrait_origin
		if _shake_tween == tween_ref:
			_shake_tween = null
		emit_signal("portrait_shaken")
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and auto_apply_styles:
		_apply_styles()
