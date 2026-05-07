@tool
extends Node2D
class_name PlayerOverheadHud

## HUD displayed above the player sprite showing HP, Ammo, and Burst bars.
## Drawing utilities delegated to OverheadHudDraw.

const Draw := preload("res://scripts/player/OverheadHudDraw.gd")

const HEALTH_BAR_WIDTH := 112.0
const HEALTH_BAR_HEIGHT := 12.0
const SHIELD_BAR_HEIGHT := 8.0
const AMMO_BAR_HEIGHT := 10.0 # Increased from 8.0 to fit text
const BURST_BAR_HEIGHT := 9.0
const BAR_SPACING := 3.0
const TOP_OFFSET_Y := -110.0  # Raised higher to avoid overlapping player sprite
const BORDER_THICKNESS := 2.0

# Shield bar colors (cyan/blue)
@export var shield_fill_color: Color = Color(0.3, 0.85, 0.95, 1.0)
@export var shield_background_color: Color = Color(0.08, 0.15, 0.2, 0.92)
@export var shield_border_color: Color = Color(0.2, 0.6, 0.8, 1.0)

@export var health_fill_color: Color = Color(0.32, 0.86, 0.48, 1.0)
@export var health_background_color: Color = Color(0.11, 0.14, 0.18, 0.92)
@export var health_border_color: Color = Color(0.26, 0.36, 0.51, 1.0)
@export var ammo_fill_color: Color = Color(0.3, 0.6, 1.0, 1.0)
@export var ammo_background_color: Color = Color(0.08, 0.12, 0.18, 0.92)
@export var ammo_border_color: Color = Color(0.2, 0.4, 0.7, 1.0)
@export var ammo_reloading_color: Color = Color(0.5, 0.7, 1.0, 0.6)
@export var burst_fill_color: Color = Color(0.95, 0.82, 0.32, 1.0)
@export var burst_background_color: Color = Color(0.18, 0.14, 0.05, 0.92)
@export var burst_border_color: Color = Color(0.62, 0.5, 0.18, 1.0)
@export var burst_ready_fill_color: Color = Color(1.0, 0.9, 0.4, 1.0)
@export var burst_ready_glow_color: Color = Color(1.0, 0.95, 0.6, 0.5)

# Use constants for locked state to avoid nil issues in @tool script
const BURST_LOCKED_FILL := Color(0.4, 0.4, 0.45, 0.7)
const BURST_LOCKED_BG := Color(0.15, 0.15, 0.18, 0.92)
const BURST_LOCKED_BORDER := Color(0.35, 0.35, 0.4, 1.0)

var _player: Node2D = null
var _current_health: int = 10
var _max_health: int = 10
var _current_ammo: int = 7
var _max_ammo: int = 7
var _is_reloading: bool = false
var _reload_progress: float = 0.0  # 0 to 1, fills up during reload
var _reload_time: float = 1.5  # Total reload time
var _current_character: int = 1  # CharacterRegistry indices: 0=SnowWhite, 1=Scarlet, 2=Rapunzel, 3=Nayuta, 4=Commander, etc.
var _current_burst: float = 50.0
var _max_burst: float = 100.0
var _burst_ready: bool = false
var _burst_unlocked: bool = false  # Whether burst ability is unlocked
var _scarlet_special_unlocked: bool = false  # Whether Scarlet's special attack is unlocked
var _glow_time: float = 0.0
var _initialized: bool = false

# Shield bar (Kilo's upgrade or Cecil's shield)
var _current_shield: int = 0
var _max_shield: int = 0
var _shield_visible: bool = false

# Per-character reload progress tracking to prevent reset on swap
# Supports all 11 characters: Scarlet, Commander, Rapunzel, Kilo, Marian, Crown, Snow White, Sin, Cecil, Nayuta, Wells
var _reload_progress_per_char: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# Special ability cooldown tracking
var _special_cooldown_progress: float = 0.0  # 0 = on cooldown, 1 = ready
var _special_unlocked: bool = false  # Is the special ability unlocked for current character
var _special_locked: bool = false  # Is the special ability locked (Wells: Future Marian active)
# Height matches all 3 bars: HP(12) + spacing(3) + Ammo(8) + spacing(3) + Burst(9) = 35
const SPECIAL_INDICATOR_SIZE := 35.0
const SPECIAL_INDICATOR_GAP := 6.0  # Gap between bars and indicator
const SPECIAL_INDICATOR_CORNER_RADIUS := 4.0

# Skill points / Level up indicator (left side, matches special ability style)
var _skill_points_available: bool = false
var _level_up_glow_time: float = 0.0
const LEVEL_UP_INDICATOR_SIZE := 35.0  # Match special indicator size
const LEVEL_UP_INDICATOR_GAP := 6.0
const LEVEL_UP_INDICATOR_CORNER_RADIUS := 4.0
# Golden colors for level up
const LEVEL_UP_GOLD := Color(1.0, 0.85, 0.3, 1.0)
const LEVEL_UP_GOLD_GLOW := Color(1.0, 0.9, 0.4, 0.5)
const LEVEL_UP_GOLD_DARK := Color(0.8, 0.65, 0.15, 1.0)

func _ready() -> void:
	top_level = true
	z_as_relative = false
	light_mask = 0
	z_index = 220
	material = _build_unshaded_material()
	if not Engine.is_editor_hint():
		_process_initial_owner()
	set_process(true)
	_initialized = true
	queue_redraw()

func _process(delta: float) -> void:
	# In editor, just redraw for preview
	if Engine.is_editor_hint():
		queue_redraw()
		return
	
	var player_node2d := _player as Node2D
	if player_node2d == null or not is_instance_valid(player_node2d):
		visible = false
		return
	global_position = player_node2d.global_position.round()
	visible = true
	
	# Counter-scale to compensate for camera zoom (keeps HUD crisp)
	var viewport := get_viewport()
	if viewport:
		var camera := viewport.get_camera_2d()
		if camera and camera.zoom.x > 0:
			# Inverse of camera zoom to maintain constant screen size
			scale = Vector2.ONE / camera.zoom
	
	# Always animate glow time for effects
	_glow_time += delta * 3.0
	
	# Animate level up indicator glow
	if _skill_points_available:
		_level_up_glow_time += delta * 3.0
	
	# Animate reload progress for current character
	if _is_reloading and _reload_time > 0:
		_reload_progress += delta / _reload_time
		_reload_progress = minf(_reload_progress, 1.0)
		# Store in per-character array
		if _current_character >= 0 and _current_character < 11:
			_reload_progress_per_char[_current_character] = _reload_progress
	
	queue_redraw()

func _build_unshaded_material() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	return mat

func _draw() -> void:
	# Guard against drawing before initialization (can happen with @tool in editor)
	if not _initialized:
		return
	
	var left_x := -HEALTH_BAR_WIDTH * 0.5
	var current_y := TOP_OFFSET_Y
	
	# Draw shield bar above HP if active
	if _shield_visible and _max_shield > 0:
		var shield_rect := Rect2(Vector2(left_x, current_y - SHIELD_BAR_HEIGHT - BAR_SPACING), Vector2(HEALTH_BAR_WIDTH, SHIELD_BAR_HEIGHT))
		Draw.draw_bar(self, shield_rect, float(_current_shield), float(_max_shield), shield_background_color, shield_fill_color, shield_border_color, BORDER_THICKNESS)
		
		# Draw shield text
		var shield_text := "%d" % _current_shield
		var shield_center := Vector2(0, current_y - SHIELD_BAR_HEIGHT - BAR_SPACING + SHIELD_BAR_HEIGHT * 0.5)
		Draw.draw_bar_text(self, shield_text, shield_center, 7)
	
	# Draw health bar
	var health_rect := Rect2(Vector2(left_x, current_y), Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT))
	Draw.draw_bar(self, health_rect, float(_current_health), float(_max_health), health_background_color, health_fill_color, health_border_color, BORDER_THICKNESS)
	
	# Draw health text (centered in bar)
	var health_text := "%d/%d" % [_current_health, _max_health]
	var health_center := Vector2(0, TOP_OFFSET_Y + HEALTH_BAR_HEIGHT * 0.5)
	Draw.draw_bar_text(self, health_text, health_center, 10)
	
	# Draw ammo bar (between HP and burst)
	var ammo_top := TOP_OFFSET_Y + HEALTH_BAR_HEIGHT + BAR_SPACING
	var ammo_rect := Rect2(Vector2(left_x, ammo_top), Vector2(HEALTH_BAR_WIDTH, AMMO_BAR_HEIGHT))
	
	# Show ammo count or reload animation for all characters
	if _is_reloading:
		# Draw reload animation - bar fills up from left to right
		draw_rect(ammo_rect, ammo_background_color, true)
		
		# Draw the filling progress bar with pulsing effect
		var pulse := sin(_glow_time * 4.0) * 0.15 + 0.85
		var reload_fill_color := Color(
			ammo_reloading_color.r * pulse + 0.2,
			ammo_reloading_color.g * pulse + 0.1,
			ammo_reloading_color.b * pulse,
			ammo_reloading_color.a
		)
		var fill_width := HEALTH_BAR_WIDTH * _reload_progress
		if fill_width > 0:
			var fill_rect := Rect2(ammo_rect.position, Vector2(fill_width, AMMO_BAR_HEIGHT))
			draw_rect(fill_rect, reload_fill_color, true)
		
		# Draw moving highlight line at the fill edge
		if _reload_progress > 0.02 and _reload_progress < 0.98:
			var line_x := left_x + fill_width
			var highlight_color := Color(1.0, 1.0, 1.0, 0.6)
			draw_line(
				Vector2(line_x, ammo_top + 1),
				Vector2(line_x, ammo_top + AMMO_BAR_HEIGHT - 1),
				highlight_color, 2.0
			)
		
		draw_rect(ammo_rect, ammo_border_color, false, BORDER_THICKNESS)
		
		# Show reload text
		var ammo_center := Vector2(0, ammo_top + AMMO_BAR_HEIGHT * 0.5)
		Draw.draw_bar_text(self, "RELOAD", ammo_center, 7)
	elif _current_character == 1 and not _scarlet_special_unlocked:
		# Scarlet with locked special - show LOCKED
		draw_rect(ammo_rect, Color(0.2, 0.2, 0.25, 0.9), true)
		draw_rect(ammo_rect, Color(0.4, 0.4, 0.5, 0.8), false, BORDER_THICKNESS)
		var ammo_center := Vector2(0, ammo_top + AMMO_BAR_HEIGHT * 0.5)
		Draw.draw_bar_text(self, "LOCKED", ammo_center, 7)
	else:
		# Normal ammo display
		Draw.draw_bar(self, ammo_rect, float(_current_ammo), float(_max_ammo), ammo_background_color, ammo_fill_color, ammo_border_color, BORDER_THICKNESS)
		var ammo_text := "%d/%d" % [_current_ammo, _max_ammo]
		var ammo_center := Vector2(0, ammo_top + AMMO_BAR_HEIGHT * 0.5)
		Draw.draw_bar_text(self, ammo_text, ammo_center, 8)
	
	# Draw burst bar
	var burst_top := ammo_top + AMMO_BAR_HEIGHT + BAR_SPACING
	var burst_rect := Rect2(Vector2(left_x, burst_top), Vector2(HEALTH_BAR_WIDTH, BURST_BAR_HEIGHT))
	
	# Determine burst bar colors based on state
	var burst_bg := burst_background_color
	var burst_border := burst_border_color
	var fill_color := burst_fill_color
	var burst_value := _current_burst
	
	if not _burst_unlocked:
		# Locked state - grey and empty
		burst_bg = BURST_LOCKED_BG
		burst_border = BURST_LOCKED_BORDER
		fill_color = BURST_LOCKED_FILL
		burst_value = 0.0  # Don't show any fill when locked
	elif _burst_ready:
		fill_color = burst_ready_fill_color
		# Draw pulsing glow effect
		var glow_alpha := (sin(_glow_time) * 0.5 + 0.5) * 0.4
		var glow_rect := Rect2(burst_rect.position - Vector2(4, 4), burst_rect.size + Vector2(8, 8))
		var glow := Color(burst_ready_glow_color.r, burst_ready_glow_color.g, burst_ready_glow_color.b, glow_alpha)
		draw_rect(glow_rect, glow, true)
	
	Draw.draw_bar(self, burst_rect, burst_value, _max_burst, burst_bg, fill_color, burst_border, BORDER_THICKNESS)
	
	# Draw burst percent text (centered in bar)
	var burst_text: String
	if not _burst_unlocked:
		burst_text = "BURST"  # Show BURST even when locked
	else:
		var burst_percent := int((_current_burst / _max_burst) * 100.0) if _max_burst > 0 else 0
		burst_text = "%d%%" % burst_percent
	var burst_center := Vector2(0, burst_top + BURST_BAR_HEIGHT * 0.5)
	Draw.draw_bar_text(self, burst_text, burst_center, 8)
	
	# Draw special ability cooldown indicator (right side of HUD)
	_draw_special_indicator()
	
	# Draw level up / skill points available indicator (left side of HUD)
	_draw_level_up_indicator()

func _draw_level_up_indicator() -> void:
	## Draws a golden level-up indicator matching the special ability indicator style
	## Shows when skill points are available
	if not _skill_points_available:
		return
	
	# Position to the left of the bars (mirror of special indicator on right)
	var indicator_x := -HEALTH_BAR_WIDTH * 0.5 - LEVEL_UP_INDICATOR_GAP - LEVEL_UP_INDICATOR_SIZE
	var indicator_rect := Rect2(
		Vector2(indicator_x, TOP_OFFSET_Y),
		Vector2(LEVEL_UP_INDICATOR_SIZE, LEVEL_UP_INDICATOR_SIZE)
	)
	var center := indicator_rect.position + indicator_rect.size * 0.5
	
	# Pulsing glow effect (always active since skill points are available)
	var pulse := sin(_level_up_glow_time * 2.0) * 0.15 + 0.85
	var glow_color := Color(LEVEL_UP_GOLD_GLOW.r * 1.2, LEVEL_UP_GOLD_GLOW.g * 1.2, LEVEL_UP_GOLD_GLOW.b, 0.5 * pulse)
	Draw.draw_rounded_rect(self, indicator_rect.grow(5.0), LEVEL_UP_INDICATOR_CORNER_RADIUS + 2.0, glow_color)
	
	# Background with rounded corners
	var bg_color := Color(0.15, 0.12, 0.05, 0.95)  # Dark golden-brown bg
	Draw.draw_rounded_rect(self, indicator_rect.grow(2.0), LEVEL_UP_INDICATOR_CORNER_RADIUS + 1.0, bg_color)
	
	# Golden fill
	var fill_color := Color(LEVEL_UP_GOLD.r * pulse, LEVEL_UP_GOLD.g * pulse, LEVEL_UP_GOLD.b, 1.0)
	Draw.draw_rounded_rect(self, indicator_rect, LEVEL_UP_INDICATOR_CORNER_RADIUS, fill_color)
	
	# Bright border
	Draw.draw_rounded_rect_outline(self, indicator_rect, LEVEL_UP_INDICATOR_CORNER_RADIUS, LEVEL_UP_GOLD, BORDER_THICKNESS)
	
	# Draw arrow-up icon in center
	Draw.draw_level_up_arrow_icon(self, center)

func _draw_special_indicator() -> void:
	# Only show if special is unlocked for this character
	if not _special_unlocked:
		return
	
	# Position to the right of the bars
	var indicator_x := HEALTH_BAR_WIDTH * 0.5 + SPECIAL_INDICATOR_GAP
	var indicator_rect := Rect2(
		Vector2(indicator_x, TOP_OFFSET_Y),
		Vector2(SPECIAL_INDICATOR_SIZE, SPECIAL_INDICATOR_SIZE)
	)
	var center := indicator_rect.position + indicator_rect.size * 0.5
	
	# Draw background with rounded corners
	var bg_color := Color(0.1, 0.1, 0.12, 0.95)
	Draw.draw_rounded_rect(self, indicator_rect.grow(2.0), SPECIAL_INDICATOR_CORNER_RADIUS + 1.0, bg_color)
	
	# Check if special is locked (Wells: Future Marian active)
	if _special_locked:
		# Draw red locked state
		var locked_color := Color(0.6, 0.15, 0.15, 1.0)
		Draw.draw_rounded_rect(self, indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, locked_color)
		
		# Border
		Draw.draw_rounded_rect_outline(self, indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, Color(0.6, 0.2, 0.2, 1.0), BORDER_THICKNESS)
		
		# Draw lock icon
		Draw.draw_lock_icon(self, center)
		return
	
	# Draw the base colored fill
	var ready_color := Draw.get_special_ready_color(_current_character, _special_cooldown_progress)
	
	# For Snow White turrets (index 0), check if we have charges available
	var has_charges := true
	if _current_character == 0:  # Snow White
		has_charges = _turret_charges > 0
	
	if _special_cooldown_progress < 1.0 or not has_charges:
		# Draw full ready color as base
		Draw.draw_rounded_rect(self, indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, ready_color)
		
		# Draw rotating dark clock overlay on top (hides the ready portion)
		var dark_color := Color(0.12, 0.12, 0.15, 0.92)
		var remaining := 1.0 - _special_cooldown_progress
		if remaining > 0.01:
			var start_angle := -PI / 2.0
			var sweep := -TAU * remaining
			var end_angle := start_angle + sweep
			Draw.draw_pie_slice_smooth(self, center, indicator_rect, start_angle, end_angle, dark_color, SPECIAL_INDICATOR_CORNER_RADIUS)
		
		# Border
		var border_color := Color(0.4, 0.4, 0.45, 1.0)
		Draw.draw_rounded_rect_outline(self, indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, border_color, BORDER_THICKNESS)
	else:
		# Fully ready - draw glowing square
		var pulse := sin(_glow_time * 2.0) * 0.15 + 0.85
		var glow_color := Color(ready_color.r * 1.3, ready_color.g * 1.3, ready_color.b * 1.3, 0.4 * pulse)
		Draw.draw_rounded_rect(self, indicator_rect.grow(4.0), SPECIAL_INDICATOR_CORNER_RADIUS + 2.0, glow_color)
		Draw.draw_rounded_rect(self, indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, ready_color)
		
		# Bright border when ready
		var border_color := Color(1.0, 1.0, 1.0, 0.7)
		Draw.draw_rounded_rect_outline(self, indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, border_color, BORDER_THICKNESS)
	
	# Draw icon in center
	_draw_special_icon(center)
	
	# For Snow White (index 0), draw charge count inside the indicator (bottom)
	if _current_character == 0 and _turret_max_charges > 0:
		var charge_text := "%d/%d" % [_turret_charges, _turret_max_charges]
		# Move inside the box, near the bottom but higher to avoid spill
		var text_pos := Vector2(indicator_x + SPECIAL_INDICATOR_SIZE * 0.5, TOP_OFFSET_Y + SPECIAL_INDICATOR_SIZE - 12)
		# Reduce font size to fit
		Draw.draw_bar_text(self, charge_text, text_pos, 8)

func _draw_special_icon(center: Vector2) -> void:
	var icon_color := Color(1.0, 1.0, 1.0, 0.9)
	if _special_cooldown_progress < 1.0:
		icon_color = Color(0.6, 0.6, 0.6, 0.7)
	match _current_character:
		0:  Draw.draw_turret_icon(self, center, icon_color)
		1:  Draw.draw_sword_icon(self, center, icon_color)
		2:  Draw.draw_cross_icon(self, center, icon_color)
		3:  Draw.draw_clone_icon(self, center, icon_color)
		4:  Draw.draw_clock_icon(self, center, icon_color)
		5:  Draw.draw_mind_control_icon(self, center, icon_color)
		6:  Draw.draw_horse_icon(self, center, icon_color)
		7:  Draw.draw_shotgun_icon(self, center, icon_color)
		8:  Draw.draw_drone_icon(self, center, icon_color)
		9:  Draw.draw_mind_control_icon(self, center, icon_color)
		10: Draw.draw_hourglass_icon(self, center, icon_color)

func _process_initial_owner() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		_player = null
		return
	if parent_node is CharacterBody2D:
		_player = parent_node
	elif parent_node.get_parent():
		_player = parent_node.get_parent()
	else:
		_player = parent_node
	if _player == null:
		return
	
	# Get initial values from player
	if "hp" in _player:
		_current_health = int(_player.hp)
	if "max_hp" in _player:
		_max_health = maxi(1, int(_player.max_hp))
	if "burst_current" in _player:
		_current_burst = float(_player.burst_current)
	if "burst_max" in _player:
		_max_burst = maxf(0.001, float(_player.burst_max))
	if "current_character" in _player:
		_current_character = int(_player.current_character)
	_update_ammo_from_player()
	
	_burst_ready = _current_burst >= _max_burst
	_connect_player_signals()
	queue_redraw()

func _update_ammo_from_player() -> void:
	# Ammo is now updated via update_ammo() calls from PlayerCore
	# This function serves as a fallback for initial setup
	if not is_instance_valid(_player):
		return
	# Default to showing "full ammo" if no controller has updated us yet
	if _max_ammo <= 0:
		_current_ammo = 1
		_max_ammo = 1
		_is_reloading = false

func _connect_player_signals() -> void:
	if not is_instance_valid(_player):
		return
	# We'll update via polling since the simple Player.gd doesn't have signals

func update_health(current: int, maximum: int) -> void:
	_current_health = current
	_max_health = maxi(1, maximum)
	queue_redraw()

func update_shield(current: int, maximum: int) -> void:
	_current_shield = current
	_max_shield = maxi(0, maximum)
	_shield_visible = maximum > 0
	queue_redraw()

func update_burst(current: float, maximum: float) -> void:
	# Don't update if locked
	if not _burst_unlocked:
		return
	_current_burst = current
	_max_burst = maxf(0.001, maximum)
	var was_ready := _burst_ready
	_burst_ready = _current_burst >= _max_burst
	if _burst_ready and not was_ready:
		_glow_time = 0.0  # Reset glow animation
	queue_redraw()

func update_burst_unlocked(unlocked: bool) -> void:
	_burst_unlocked = unlocked
	if not unlocked:
		_current_burst = 0.0
		_burst_ready = false
	queue_redraw()

func update_scarlet_special_unlocked(unlocked: bool) -> void:
	_scarlet_special_unlocked = unlocked
	queue_redraw()

func update_special_ability(unlocked: bool, cooldown_progress: float, locked: bool = false) -> void:
	## Update the special ability indicator
	## cooldown_progress: 0.0 = just used (on cooldown), 1.0 = fully ready
	## locked: true if special is blocked (Wells: Future Marian active)
	_special_unlocked = unlocked
	_special_cooldown_progress = clampf(cooldown_progress, 0.0, 1.0)
	_special_locked = locked
	queue_redraw()

func update_special_locked(locked: bool) -> void:
	## Update only the locked state (for Wells Future Marian)
	_special_locked = locked
	queue_redraw()

# Turret charge tracking
var _turret_charges: int = 3
var _turret_max_charges: int = 3

func update_special_ability_with_charges(unlocked: bool, cooldown_progress: float, charges: int, max_charges: int) -> void:
	## Update the special ability indicator with charge count (for turrets)
	_special_unlocked = unlocked
	_special_cooldown_progress = clampf(cooldown_progress, 0.0, 1.0)
	_turret_charges = charges
	_turret_max_charges = max_charges
	queue_redraw()

func update_ammo(current: int, maximum: int, is_reloading: bool, reload_time: float = 1.5) -> void:
	_current_ammo = current
	_max_ammo = maxi(1, maximum)
	_reload_time = maxf(0.1, reload_time)
	
	# Preserve reload progress when switching characters mid-reload
	if is_reloading:
		# If we weren't reloading before but now we are, check stored progress
		if not _is_reloading:
			# Starting reload - use stored progress for this character (could be mid-reload from swap)
			if _current_character >= 0 and _current_character < 10:
				_reload_progress = _reload_progress_per_char[_current_character]
			else:
				_reload_progress = 0.0
		# else: continue with current progress (already animating)
	else:
		# Not reloading - reset progress for this character
		_reload_progress = 0.0
		if _current_character >= 0 and _current_character < 10:
			_reload_progress_per_char[_current_character] = 0.0
	
	_is_reloading = is_reloading
	queue_redraw()

func update_character(character_index: int) -> void:
	# Store current character's reload progress before switching
	if _current_character >= 0 and _current_character < 10:
		_reload_progress_per_char[_current_character] = _reload_progress
	
	_current_character = character_index
	
	# Restore new character's reload progress
	if character_index >= 0 and character_index < 10:
		_reload_progress = _reload_progress_per_char[character_index]
	
	_update_ammo_from_player()
	queue_redraw()

func update_skill_points_available(available: bool) -> void:
	_skill_points_available = available
	if not available:
		_level_up_glow_time = 0.0
	queue_redraw()
