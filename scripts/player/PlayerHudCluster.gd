extends Control
class_name PlayerHudCluster

signal portrait_shaken
signal health_fill_finished
signal burst_fill_finished
signal stamina_fill_finished

@export var shake_distance: float = 4.0
@export_range(0.05, 1.5, 0.01) var shake_duration: float = 0.2
@export_range(0.05, 1.0, 0.01) var fill_transition_time: float = 0.22
@export_range(0.0, 1.0, 0.01) var low_health_threshold: float = 0.25
@export var auto_apply_styles: bool = true

# Outer container styling (HoloCure-style)
@export var outer_frame_background: Color = Color(0.08, 0.08, 0.12, 0.95)
@export var outer_frame_border_color: Color = Color(0.95, 0.95, 1.0, 1.0)
@export var outer_frame_border_width: int = 4
@export var outer_frame_corner_radius: int = 12

@export var portrait_border_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var portrait_background_color: Color = Color(0.12, 0.12, 0.15, 0.95)
@export var hp_bar_color: Color = Color(0.35, 0.85, 0.45, 1.0)
@export var hp_bar_background: Color = Color(0.12, 0.12, 0.15, 0.95)
@export var hp_bar_frame_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var burst_bar_color: Color = Color(1.0, 0.85, 0.25, 1.0)
@export var burst_bar_background: Color = Color(0.12, 0.12, 0.15, 0.95)
@export var burst_bar_frame_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var stamina_bar_color: Color = Color(0.35, 0.75, 1.0, 1.0)
@export var stamina_bar_background: Color = Color(0.12, 0.12, 0.15, 0.95)
@export var stamina_bar_frame_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var burst_badge_background: Color = Color(1.0, 0.85, 0.25, 1.0)
@export var burst_badge_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var hp_badge_background: Color = Color(0.35, 0.85, 0.45, 1.0)
@export var hp_badge_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var stamina_badge_background: Color = Color(0.35, 0.75, 1.0, 1.0)
@export var stamina_badge_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var low_health_color: Color = Color(1.0, 0.4, 0.4, 1.0)
@export var burst_ready_badge_color: Color = Color(1.0, 0.85, 0.25, 1.0)
@export var burst_ready_text_color: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var burst_locked_bar_color: Color = Color(0.35, 0.35, 0.4, 0.6)  # Greyed out fill
@export var burst_locked_badge_color: Color = Color(0.4, 0.4, 0.45, 0.8)  # Greyed out badge

@onready var _outer_frame: Panel = %OuterFrame
@onready var _portrait_slot: Control = %PortraitShake
@onready var _portrait_frame: Panel = %PortraitFrame
@onready var _portrait_background: ColorRect = %PortraitBackground
@onready var _portrait_texture: TextureRect = %PortraitTexture
@onready var _hp_badge: ColorRect = %HPBadge
@onready var _hp_badge_label: Label = %HPBadgeLabel
@onready var _burst_badge: ColorRect = %BurstBadge
@onready var _burst_badge_label: Label = %BurstBadgeLabel
@onready var _stamina_badge: ColorRect = %StaminaBadge
@onready var _stamina_badge_label: Label = %StaminaBadgeLabel
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _burst_bar: ProgressBar = %BurstBar
@onready var _stamina_bar: ProgressBar = %StaminaBar

# Labels for showing values inside bars
var _hp_value_label: Label = null
var _burst_value_label: Label = null

var _portrait_origin: Vector2 = Vector2.ZERO
var _default_portrait_modulate: Color = Color(1, 1, 1, 1)

var _health_tween: Tween = null
var _burst_tween: Tween = null
var _stamina_tween: Tween = null
var _shake_tween: Tween = null
var _burst_ready_tween: Tween = null

var _max_health: int = 1
var _current_health: int = 1
var _max_burst: float = 1.0
var _current_burst: float = 0.0
var _max_stamina: float = 100.0
var _current_stamina: float = 100.0
var _burst_ready_state: bool = false
var _burst_unlocked: bool = false  # Whether burst ability is unlocked

# Character portraits - dynamically loaded from GameState/CharacterRegistry
var _character_portraits: Array[String] = []
var _portrait_indices: Array[int] = []  # Map slot index to registry index

func _ready() -> void:
	_load_character_portraits()
	_portrait_origin = _portrait_slot.position
	_default_portrait_modulate = _portrait_texture.modulate
	if auto_apply_styles:
		_apply_styles()
	_setup_bar_value_labels()
	_refresh_bars()
	_apply_low_health_state()
	set_burst_ready(false, false)
	# Burst bar starts locked (greyed out) until unlocked
	set_burst_unlocked(false)
	# Default to first character
	set_character(0)

func _load_character_portraits() -> void:
	# Load portraits from GameState's selected characters
	# Order: [Main, Support1, Support2] - same as selected_character_indices
	_character_portraits.clear()
	_portrait_indices.clear()
	
	# Try to get from GameState autoload
	var game_state = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else null
	if not game_state:
		# Try loading via get_node
		game_state = get_node_or_null("/root/GameState")
	
	if game_state:
		# Use selected_character_indices directly (Main, Support1, Support2 order)
		var selected: Array[int] = game_state.selected_character_indices.duplicate()
		_portrait_indices = selected.duplicate()
		
		# Get CharacterRegistry to map indices to portrait paths
		var registry = CharacterRegistry.get_instance()
		if registry:
			var all_ids: Array[String] = registry.get_all_character_ids()
			for idx in selected:
				if idx >= 0 and idx < all_ids.size():
					var char_id: String = all_ids[idx]
					var folder_name: String = char_id.replace("_", "-")
					_character_portraits.append("res://assets/characters/%s/portrait-sq.png" % folder_name)
				else:
					_character_portraits.append("")
	
	# Fallback if nothing loaded
	if _character_portraits.is_empty():
		_character_portraits = [
			"res://assets/characters/scarlet/portrait-sq.png",
			"res://assets/characters/commander/portrait-sq.png",
			"res://assets/characters/marian/portrait-sq.png"
		]
		_portrait_indices = [0, 1, 4]

func _setup_bar_value_labels() -> void:
	# Create HP value label inside HP bar
	_hp_value_label = Label.new()
	_hp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_value_label.add_theme_font_size_override("font_size", 14)
	_hp_value_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_value_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hp_value_label.add_theme_constant_override("shadow_offset_x", 1)
	_hp_value_label.add_theme_constant_override("shadow_offset_y", 1)
	_hp_value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar.add_child(_hp_value_label)
	
	# Create Burst value label inside Burst bar
	_burst_value_label = Label.new()
	_burst_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_burst_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_burst_value_label.add_theme_font_size_override("font_size", 12)
	_burst_value_label.add_theme_color_override("font_color", Color.WHITE)
	_burst_value_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_burst_value_label.add_theme_constant_override("shadow_offset_x", 1)
	_burst_value_label.add_theme_constant_override("shadow_offset_y", 1)
	_burst_value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_burst_bar.add_child(_burst_value_label)
	
	_update_bar_value_labels()

func _update_bar_value_labels() -> void:
	if _hp_value_label:
		_hp_value_label.text = "%d / %d" % [_current_health, _max_health]
	if _burst_value_label:
		var burst_percent := int((_current_burst / _max_burst) * 100.0) if _max_burst > 0 else 0
		_burst_value_label.text = "%d%%" % burst_percent

func set_character(character_slot: int, burst_unlocked: bool = true) -> void:
	if not is_inside_tree():
		return
	
	# Guard against empty portraits array
	if _character_portraits.is_empty():
		_load_character_portraits()
	
	if _character_portraits.is_empty():
		return  # Still empty, can't set portrait
	
	# character_slot is the slot in the squad (0=Main, 1=Support1, 2=Support2)
	# _character_portraits is in the same order, so use directly
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
	if not _burst_bar or not _burst_badge:
		return
	
	if _burst_unlocked:
		# Normal active style - restore yellow badge and bar
		_burst_bar.add_theme_stylebox_override("fill", _create_bar_fill(burst_bar_color))
		_burst_bar.modulate = Color.WHITE
		_style_badge(_burst_badge, burst_badge_background)  # Yellow badge
		_burst_badge.modulate = Color.WHITE  # Reset modulate
		if _burst_badge_label:
			_burst_badge_label.text = "BURST"
			_burst_badge_label.modulate = burst_badge_text_color  # White text
	else:
		# Greyed out locked style - grey badge and bar
		_burst_bar.add_theme_stylebox_override("fill", _create_bar_fill(burst_locked_bar_color))
		_burst_bar.modulate = Color(0.6, 0.6, 0.65, 1.0)
		_style_badge(_burst_badge, burst_locked_badge_color)  # Grey badge
		_burst_badge.modulate = Color(0.7, 0.7, 0.75, 1.0)  # Grey modulate on badge
		if _burst_badge_label:
			_burst_badge_label.text = "BURST"  # Show BURST even when locked
			_burst_badge_label.modulate = Color(0.85, 0.85, 0.9, 1.0)  # Lighter grey text

func configure(current_health: int, max_health: int, burst_current: float = 0.0, burst_max: float = 1.0, stamina_current: float = 100.0, stamina_max: float = 100.0) -> void:
	_max_health = maxi(1, max_health)
	_current_health = clampi(current_health, 0, _max_health)
	_max_burst = maxf(0.001, burst_max)
	_current_burst = clampf(burst_current, 0.0, _max_burst)
	_max_stamina = maxf(0.001, stamina_max)
	_current_stamina = clampf(stamina_current, 0.0, _max_stamina)
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

func update_stamina(current: float, max_value: float, animate: bool = true) -> void:
	var new_max: float = maxf(0.001, max_value)
	var clamped: float = clampf(current, 0.0, new_max)
	_max_stamina = new_max
	_current_stamina = clamped
	_stamina_bar.max_value = _max_stamina
	if _stamina_tween and _stamina_tween.is_running():
		_stamina_tween.kill()
		_stamina_tween = null
	if animate:
		_stamina_tween = create_tween()
		var tween_ref: Tween = _stamina_tween
		_stamina_tween.tween_property(_stamina_bar, "value", float(_current_stamina), fill_transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_stamina_tween.finished.connect(func():
			if not is_instance_valid(self):
				return
			emit_signal("stamina_fill_finished")
			if _stamina_tween == tween_ref:
				_stamina_tween = null
		)
	else:
		_stamina_bar.value = _current_stamina
		emit_signal("stamina_fill_finished")

func set_burst_ready(is_ready: bool, animate: bool = true) -> void:
	if _burst_ready_state == is_ready and animate:
		return
	_burst_ready_state = is_ready
	if _burst_ready_tween and _burst_ready_tween.is_running():
		_burst_ready_tween.kill()
		_burst_ready_tween = null
	if _burst_badge:
		var badge_color = burst_ready_badge_color if is_ready else burst_badge_background
		_style_badge(_burst_badge, badge_color)
		if not animate or not is_ready:
			_burst_badge.scale = Vector2.ONE
	if _burst_badge_label:
		_burst_badge_label.text = "READY!" if is_ready else "BURST"
		_burst_badge_label.modulate = burst_ready_text_color if is_ready else burst_badge_text_color
	if animate and is_ready and _burst_badge and is_inside_tree():
		_burst_ready_tween = create_tween()
		var tween_ref: Tween = _burst_ready_tween
		_burst_ready_tween.tween_property(_burst_badge, "scale", Vector2(1.08, 1.08), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_burst_ready_tween.tween_property(_burst_badge, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
	_stamina_bar.max_value = _max_stamina
	_stamina_bar.value = _current_stamina

func _apply_low_health_state() -> void:
	if _max_health <= 0:
		_portrait_texture.modulate = _default_portrait_modulate
		return
	var ratio: float = float(_current_health) / float(_max_health)
	_portrait_texture.modulate = low_health_color if ratio <= low_health_threshold else _default_portrait_modulate

func _apply_styles() -> void:
	# Style the outer frame container (HoloCure-style box)
	if _outer_frame:
		var outer_style: StyleBoxFlat = StyleBoxFlat.new()
		outer_style.bg_color = outer_frame_background
		outer_style.border_color = outer_frame_border_color
		outer_style.border_width_top = outer_frame_border_width
		outer_style.border_width_bottom = outer_frame_border_width
		outer_style.border_width_left = outer_frame_border_width
		outer_style.border_width_right = outer_frame_border_width
		outer_style.corner_radius_top_left = outer_frame_corner_radius
		outer_style.corner_radius_top_right = outer_frame_corner_radius
		outer_style.corner_radius_bottom_left = outer_frame_corner_radius
		outer_style.corner_radius_bottom_right = outer_frame_corner_radius
		# Add a subtle shadow/glow effect
		outer_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
		outer_style.shadow_size = 6
		outer_style.shadow_offset = Vector2(2, 2)
		_outer_frame.add_theme_stylebox_override("panel", outer_style)
	
	if _portrait_background:
		_portrait_background.color = portrait_background_color
	if _portrait_frame:
		var frame_style: StyleBoxFlat = StyleBoxFlat.new()
		frame_style.bg_color = portrait_background_color
		frame_style.border_color = portrait_border_color
		frame_style.border_width_top = 5
		frame_style.border_width_bottom = 5
		frame_style.border_width_left = 5
		frame_style.border_width_right = 5
		frame_style.corner_radius_top_left = 8
		frame_style.corner_radius_top_right = 8
		frame_style.corner_radius_bottom_left = 8
		frame_style.corner_radius_bottom_right = 8
		# Inner shadow for depth
		frame_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
		frame_style.shadow_size = 4
		_portrait_frame.add_theme_stylebox_override("panel", frame_style)
	if _hp_badge:
		_style_badge(_hp_badge, hp_badge_background)
	if _hp_badge_label:
		_hp_badge_label.modulate = hp_badge_text_color
	if _burst_badge:
		_style_badge(_burst_badge, burst_badge_background)
	if _burst_badge_label:
		_burst_badge_label.modulate = burst_badge_text_color
	if _stamina_badge:
		_style_badge(_stamina_badge, stamina_badge_background)
	if _stamina_badge_label:
		_stamina_badge_label.modulate = stamina_badge_text_color
	if _hp_bar:
		_hp_bar.add_theme_stylebox_override("background", _create_bar_background(hp_bar_background, hp_bar_frame_color))
		_hp_bar.add_theme_stylebox_override("fill", _create_bar_fill(hp_bar_color))
	if _burst_bar:
		_burst_bar.add_theme_stylebox_override("background", _create_bar_background(burst_bar_background, burst_bar_frame_color))
		_burst_bar.add_theme_stylebox_override("fill", _create_bar_fill(burst_bar_color))
	if _stamina_bar:
		_stamina_bar.add_theme_stylebox_override("background", _create_bar_background(stamina_bar_background, stamina_bar_frame_color))
		_stamina_bar.add_theme_stylebox_override("fill", _create_bar_fill(stamina_bar_color))
	set_burst_ready(_burst_ready_state, false)

func _style_badge(badge: ColorRect, bg_color: Color) -> void:
	# ColorRect can't have rounded corners directly, so we draw on top
	# For now, just set the color - the rounded effect comes from the container
	badge.color = bg_color
	
	# Create a Panel overlay for rounded corners if not already done
	var overlay_name = "BadgeOverlay"
	var existing_overlay = badge.get_node_or_null(overlay_name)
	if existing_overlay:
		existing_overlay.queue_free()
	
	# Create styled Panel that sits on top
	var panel = Panel.new()
	panel.name = overlay_name
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = Color(1.0, 1.0, 1.0, 0.3)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	
	# Hide the original ColorRect background
	badge.color = Color(0, 0, 0, 0)
	
	# Insert panel behind the label
	badge.add_child(panel)
	badge.move_child(panel, 0)

func _create_bar_background(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.border_width_left = 4
	box.border_width_right = 4
	box.border_width_top = 4
	box.border_width_bottom = 4
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	return box

func _create_bar_fill(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	box.expand_margin_left = -2.0
	box.expand_margin_top = -2.0
	box.expand_margin_right = -2.0
	box.expand_margin_bottom = -2.0
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

