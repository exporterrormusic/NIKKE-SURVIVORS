@tool
extends Node2D
class_name PlayerOverheadHud

## HUD displayed above the player sprite showing HP, Ammo, and Burst bars

const HEALTH_BAR_WIDTH := 112.0
const HEALTH_BAR_HEIGHT := 12.0
const SHIELD_BAR_HEIGHT := 8.0
const AMMO_BAR_HEIGHT := 8.0
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
# Supports all 10 characters: Scarlet, Commander, Rapunzel, Kilo, Marian, Crown, Snow White, Sin, Cecil, Nayuta
var _reload_progress_per_char: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# Special ability cooldown tracking
var _special_cooldown_progress: float = 0.0  # 0 = on cooldown, 1 = ready
var _special_unlocked: bool = false  # Is the special ability unlocked for current character
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
		if _current_character >= 0 and _current_character < 10:
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
		_draw_bar(shield_rect, float(_current_shield), float(_max_shield), shield_background_color, shield_fill_color, shield_border_color)
		
		# Draw shield text
		var shield_text := "%d" % _current_shield
		var shield_center := Vector2(0, current_y - SHIELD_BAR_HEIGHT - BAR_SPACING + SHIELD_BAR_HEIGHT * 0.5)
		_draw_bar_text(shield_text, shield_center, 7)
	
	# Draw health bar
	var health_rect := Rect2(Vector2(left_x, current_y), Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT))
	_draw_bar(health_rect, float(_current_health), float(_max_health), health_background_color, health_fill_color, health_border_color)
	
	# Draw health text (centered in bar)
	var health_text := "%d/%d" % [_current_health, _max_health]
	var health_center := Vector2(0, TOP_OFFSET_Y + HEALTH_BAR_HEIGHT * 0.5)
	_draw_bar_text(health_text, health_center, 10)
	
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
		_draw_bar_text("RELOAD", ammo_center, 7)
	elif _current_character == 1 and not _scarlet_special_unlocked:
		# Scarlet with locked special - show LOCKED
		draw_rect(ammo_rect, Color(0.2, 0.2, 0.25, 0.9), true)
		draw_rect(ammo_rect, Color(0.4, 0.4, 0.5, 0.8), false, BORDER_THICKNESS)
		var ammo_center := Vector2(0, ammo_top + AMMO_BAR_HEIGHT * 0.5)
		_draw_bar_text("LOCKED", ammo_center, 7)
	else:
		# Normal ammo display
		_draw_bar(ammo_rect, float(_current_ammo), float(_max_ammo), ammo_background_color, ammo_fill_color, ammo_border_color)
		var ammo_text := "%d/%d" % [_current_ammo, _max_ammo]
		var ammo_center := Vector2(0, ammo_top + AMMO_BAR_HEIGHT * 0.5)
		_draw_bar_text(ammo_text, ammo_center, 8)
	
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
	
	_draw_bar(burst_rect, burst_value, _max_burst, burst_bg, fill_color, burst_border)
	
	# Draw burst percent text (centered in bar)
	var burst_text: String
	if not _burst_unlocked:
		burst_text = "BURST"  # Show BURST even when locked
	else:
		var burst_percent := int((_current_burst / _max_burst) * 100.0) if _max_burst > 0 else 0
		burst_text = "%d%%" % burst_percent
	var burst_center := Vector2(0, burst_top + BURST_BAR_HEIGHT * 0.5)
	_draw_bar_text(burst_text, burst_center, 8)
	
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
	_draw_rounded_rect(indicator_rect.grow(5.0), LEVEL_UP_INDICATOR_CORNER_RADIUS + 2.0, glow_color)
	
	# Background with rounded corners
	var bg_color := Color(0.15, 0.12, 0.05, 0.95)  # Dark golden-brown bg
	_draw_rounded_rect(indicator_rect.grow(2.0), LEVEL_UP_INDICATOR_CORNER_RADIUS + 1.0, bg_color)
	
	# Golden fill
	var fill_color := Color(LEVEL_UP_GOLD.r * pulse, LEVEL_UP_GOLD.g * pulse, LEVEL_UP_GOLD.b, 1.0)
	_draw_rounded_rect(indicator_rect, LEVEL_UP_INDICATOR_CORNER_RADIUS, fill_color)
	
	# Bright border
	var border_color := Color(1.0, 0.95, 0.7, 0.9)
	_draw_rounded_rect_outline(indicator_rect, LEVEL_UP_INDICATOR_CORNER_RADIUS, border_color, BORDER_THICKNESS)
	
	# Draw arrow-up icon in center
	_draw_level_up_arrow_icon(center)

func _draw_level_up_arrow_icon(center: Vector2) -> void:
	## Draws an upward arrow icon (chevron with stem) in the level up indicator
	var icon_color := Color(0.15, 0.1, 0.02, 1.0)  # Dark brown for contrast
	var highlight_color := Color(1.0, 1.0, 0.9, 0.8)  # Light highlight
	
	# Arrow dimensions
	var arrow_height := 16.0
	var arrow_width := 14.0
	var stem_width := 5.0
	var chevron_thickness := 4.0
	
	# Chevron (V shape pointing up)
	var chevron_top := center + Vector2(0, -arrow_height * 0.4)
	var chevron_left := center + Vector2(-arrow_width * 0.5, -arrow_height * 0.1)
	var chevron_right := center + Vector2(arrow_width * 0.5, -arrow_height * 0.1)
	
	# Draw chevron as thick lines
	draw_line(chevron_left, chevron_top, icon_color, chevron_thickness + 1.0)
	draw_line(chevron_top, chevron_right, icon_color, chevron_thickness + 1.0)
	draw_line(chevron_left, chevron_top, highlight_color, chevron_thickness - 1.0)
	draw_line(chevron_top, chevron_right, highlight_color, chevron_thickness - 1.0)
	
	# Stem (rectangle going down from center)
	var stem_top := center.y - arrow_height * 0.05
	var stem_bottom := center.y + arrow_height * 0.4
	var stem_rect := Rect2(
		Vector2(center.x - stem_width * 0.5, stem_top),
		Vector2(stem_width, stem_bottom - stem_top)
	)
	draw_rect(stem_rect, icon_color, true)
	
	# Lighter inner stem
	var inner_rect := stem_rect.grow(-1.0)
	if inner_rect.size.x > 0 and inner_rect.size.y > 0:
		draw_rect(inner_rect, highlight_color, true)

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
	_draw_rounded_rect(indicator_rect.grow(2.0), SPECIAL_INDICATOR_CORNER_RADIUS + 1.0, bg_color)
	
	# Draw the base colored fill
	var ready_color := _get_special_ready_color()
	
	# For Snow White turrets (index 0), check if we have charges available
	var has_charges := true
	if _current_character == 0:  # Snow White
		has_charges = _turret_charges > 0
	
	if _special_cooldown_progress < 1.0 or not has_charges:
		# Draw full ready color as base
		_draw_rounded_rect(indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, ready_color)
		
		# Draw rotating dark clock overlay on top (hides the ready portion)
		# The dark overlay shrinks clockwise as cooldown progresses
		var dark_color := Color(0.12, 0.12, 0.15, 0.92)
		var remaining := 1.0 - _special_cooldown_progress  # How much is still on cooldown
		if remaining > 0.01:
			# Clockwise from top: start at top (-PI/2), sweep clockwise (negative direction)
			# remaining = 1.0 means full dark circle, remaining = 0.0 means no dark
			var start_angle := -PI / 2.0  # 12 o'clock position
			var sweep := -TAU * remaining  # Negative for clockwise
			var end_angle := start_angle + sweep
			_draw_pie_slice_smooth(center, indicator_rect, start_angle, end_angle, dark_color)
		
		# Border
		var border_color := Color(0.4, 0.4, 0.45, 1.0)
		_draw_rounded_rect_outline(indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, border_color, BORDER_THICKNESS)
	else:
		# Fully ready - draw glowing square
		var pulse := sin(_glow_time * 2.0) * 0.15 + 0.85
		var glow_color := Color(ready_color.r * 1.3, ready_color.g * 1.3, ready_color.b * 1.3, 0.4 * pulse)
		_draw_rounded_rect(indicator_rect.grow(4.0), SPECIAL_INDICATOR_CORNER_RADIUS + 2.0, glow_color)
		_draw_rounded_rect(indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, ready_color)
		
		# Bright border when ready
		var border_color := Color(1.0, 1.0, 1.0, 0.7)
		_draw_rounded_rect_outline(indicator_rect, SPECIAL_INDICATOR_CORNER_RADIUS, border_color, BORDER_THICKNESS)
	
	# Draw icon in center
	_draw_special_icon(center)
	
	# For Snow White (index 0), draw charge count below the indicator
	if _current_character == 0 and _turret_max_charges > 0:
		var charge_text := "%d/%d" % [_turret_charges, _turret_max_charges]
		var text_pos := Vector2(indicator_x + SPECIAL_INDICATOR_SIZE * 0.5, TOP_OFFSET_Y + SPECIAL_INDICATOR_SIZE + 10)
		_draw_bar_text(charge_text, text_pos, 9)

func _draw_pie_slice_smooth(center: Vector2, clip_rect: Rect2, start_angle: float, end_angle: float, color: Color) -> void:
	# Draw a smooth pie slice for clock-style cooldown, clipped to the indicator rect
	
	# Create pie slice polygon
	var pie_points := PackedVector2Array()
	pie_points.append(center)
	
	# Use enough segments for smooth animation
	var angle_range := absf(end_angle - start_angle)
	var segments := maxi(32, int(64.0 * angle_range / TAU))
	
	# Radius large enough to cover corners of the rect
	var radius := clip_rect.size.length()
	
	var angle_step := (end_angle - start_angle) / float(segments)
	for i in range(segments + 1):
		var angle := start_angle + angle_step * float(i)
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		pie_points.append(point)
	
	# Get the rounded rect polygon to use as clip mask
	var clip_polygon := _get_rounded_rect_points(clip_rect, SPECIAL_INDICATOR_CORNER_RADIUS)
	
	# Intersect the pie slice with the rounded rect
	var clipped := Geometry2D.intersect_polygons(pie_points, clip_polygon)
	
	# Draw all resulting polygons (intersection can produce multiple)
	for polygon in clipped:
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, color)

func _draw_rounded_rect(rect: Rect2, radius: float, color: Color) -> void:
	# Draw a filled rounded rectangle using polygon approximation
	var points := _get_rounded_rect_points(rect, radius)
	if points.size() >= 3:
		draw_colored_polygon(points, color)

func _draw_rounded_rect_outline(rect: Rect2, radius: float, color: Color, width: float) -> void:
	# Draw outline of rounded rectangle
	var points := _get_rounded_rect_points(rect, radius)
	if points.size() >= 3:
		points.append(points[0])  # Close the loop
		draw_polyline(points, color, width)

func _draw_rounded_rect_partial(full_rect: Rect2, fill_rect: Rect2, radius: float, color: Color) -> void:
	# Draw a partial fill of a rounded rect (for cooldown animation)
	# This clips the fill to the intersection of fill_rect and the rounded rect shape
	var segments_per_corner := 6
	
	# We need to trace the outline but only include points within fill_rect
	var left := full_rect.position.x
	var right := full_rect.position.x + full_rect.size.x
	var top := fill_rect.position.y
	var bottom := full_rect.position.y + full_rect.size.y
	
	var corner_top := bottom - radius
	
	if top >= corner_top:
		# Fill is entirely in the rounded bottom corners region
		# Draw as rectangle (corners are at bottom)
		var fill_points := PackedVector2Array()
		fill_points.append(Vector2(left, top))
		fill_points.append(Vector2(right, top))
		
		# Bottom right corner
		for i in range(segments_per_corner + 1):
			var angle := -PI / 2.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
			var cx := right - radius
			var cy := bottom - radius
			var px := cx + cos(angle) * radius
			var py := cy + sin(angle) * radius
			if py >= top:
				fill_points.append(Vector2(px, py))
		
		# Bottom left corner
		for i in range(segments_per_corner + 1):
			var angle := 0.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
			var cx := left + radius
			var cy := bottom - radius
			var px := cx + cos(angle) * radius
			var py := cy + sin(angle) * radius
			if py >= top:
				fill_points.append(Vector2(px, py))
		
		if fill_points.size() >= 3:
			draw_colored_polygon(fill_points, color)
	else:
		# Fill extends above the corner region - simple rect with bottom corners
		var fill_points := PackedVector2Array()
		fill_points.append(Vector2(left, top))
		fill_points.append(Vector2(right, top))
		fill_points.append(Vector2(right, corner_top))
		
		# Bottom right corner
		for i in range(segments_per_corner + 1):
			var angle := -PI / 2.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
			var cx := right - radius
			var cy := bottom - radius
			fill_points.append(Vector2(cx + cos(angle) * radius, cy + sin(angle) * radius))
		
		# Bottom left corner
		for i in range(segments_per_corner + 1):
			var angle := 0.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
			var cx := left + radius
			var cy := bottom - radius
			fill_points.append(Vector2(cx + cos(angle) * radius, cy + sin(angle) * radius))
		
		fill_points.append(Vector2(left, corner_top))
		
		if fill_points.size() >= 3:
			draw_colored_polygon(fill_points, color)

func _get_rounded_rect_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments_per_corner := 6
	var left := rect.position.x
	var right := rect.position.x + rect.size.x
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	
	# Top left corner
	for i in range(segments_per_corner + 1):
		var angle := PI + (PI / 2.0) * float(i) / float(segments_per_corner)
		points.append(Vector2(left + r + cos(angle) * r, top + r + sin(angle) * r))
	
	# Top right corner
	for i in range(segments_per_corner + 1):
		var angle := -PI / 2.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
		points.append(Vector2(right - r + cos(angle) * r, top + r + sin(angle) * r))
	
	# Bottom right corner
	for i in range(segments_per_corner + 1):
		var angle := 0.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
		points.append(Vector2(right - r + cos(angle) * r, bottom - r + sin(angle) * r))
	
	# Bottom left corner
	for i in range(segments_per_corner + 1):
		var angle := PI / 2.0 + (PI / 2.0) * float(i) / float(segments_per_corner)
		points.append(Vector2(left + r + cos(angle) * r, bottom - r + sin(angle) * r))
	
	return points

func _get_special_ready_color() -> Color:
	match _current_character:
		0:  # Scarlet - Red
			return Color(0.9, 0.3, 0.3, 1.0)
		1:  # Snow White - Ice Blue
			return Color(0.4, 0.7, 1.0, 1.0)
		2:  # Rapunzel - Golden
			return Color(1.0, 0.85, 0.3, 1.0)
		3:  # Kilo - Orange
			return Color(1.0, 0.5, 0.2, 1.0)
		_:
			return Color(0.7, 0.7, 0.7, 1.0)

func _draw_special_icon(center: Vector2) -> void:
	var icon_color := Color(1.0, 1.0, 1.0, 0.9)
	if _special_cooldown_progress < 1.0:
		icon_color = Color(0.6, 0.6, 0.6, 0.7)  # Dimmed when on cooldown
	
	# CharacterRegistry order: 0=SnowWhite, 1=Scarlet, 2=Rapunzel, 3=Nayuta, 4=Commander, 5=Marian, 6=Crown, 7=Kilo, 8=Cecil, 9=Sin
	match _current_character:
		0:  # Snow White - Turret icon
			_draw_turret_icon(center, icon_color)
		1:  # Scarlet - Sword icon
			_draw_sword_icon(center, icon_color)
		2:  # Rapunzel - Cross icon (healing)
			_draw_cross_icon(center, icon_color)
		3:  # Nayuta - Clone icon
			_draw_clone_icon(center, icon_color)
		4:  # Commander - Clock icon (time freeze)
			_draw_clock_icon(center, icon_color)
		5:  # Marian - Mind control/charm icon
			_draw_mind_control_icon(center, icon_color)
		6:  # Crown - Horse/cavalry icon
			_draw_horse_icon(center, icon_color)
		7:  # Kilo - Shotgun shell icon
			_draw_shotgun_icon(center, icon_color)
		8:  # Cecil - Drone icon
			_draw_drone_icon(center, icon_color)
		9:  # Sin - Mind control/charm icon
			_draw_mind_control_icon(center, icon_color)

func _draw_sword_icon(center: Vector2, color: Color) -> void:
	# Simple sword shape - scaled for 35px indicator
	var blade_length := 12.0
	var blade_width := 3.0
	var hilt_width := 9.0
	var hilt_height := 3.0
	
	# Blade (vertical line)
	draw_line(center + Vector2(0, -blade_length), center + Vector2(0, blade_length * 0.3), color, blade_width)
	# Hilt (horizontal line)
	draw_line(center + Vector2(-hilt_width * 0.5, blade_length * 0.1), center + Vector2(hilt_width * 0.5, blade_length * 0.1), color, hilt_height)
	# Handle
	draw_line(center + Vector2(0, blade_length * 0.3), center + Vector2(0, blade_length * 0.6), color, blade_width * 0.8)

func _draw_clock_icon(center: Vector2, color: Color) -> void:
	# Clock icon for Commander's time freeze ability
	var radius := 10.0
	var accent := Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, color.a)
	var gold_tint := Color(1.0, 0.85, 0.3, color.a)  # Commander's golden theme
	
	# Outer ring
	var ring_points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0 - PI / 2.0
		ring_points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polyline(ring_points, gold_tint, 2.0)
	# Close the ring
	draw_line(ring_points[ring_points.size() - 1], ring_points[0], gold_tint, 2.0)
	
	# Inner circle
	draw_circle(center, radius - 2.0, accent)
	draw_circle(center, radius - 3.0, color)
	
	# Hour markers (12, 3, 6, 9)
	for i in range(4):
		var angle := TAU * float(i) / 4.0 - PI / 2.0
		var marker_start := center + Vector2(cos(angle), sin(angle)) * (radius - 4.0)
		var marker_end := center + Vector2(cos(angle), sin(angle)) * (radius - 2.0)
		draw_line(marker_start, marker_end, gold_tint, 1.5)
	
	# Hour hand (pointing to ~10)
	var hour_angle := -PI / 3.0
	var hour_length := 5.0
	draw_line(center, center + Vector2(cos(hour_angle), sin(hour_angle)) * hour_length, color, 2.0)
	
	# Minute hand (pointing to 12)
	var minute_angle := -PI / 2.0
	var minute_length := 7.0
	draw_line(center, center + Vector2(cos(minute_angle), sin(minute_angle)) * minute_length, color, 1.5)
	
	# Center dot
	draw_circle(center, 1.5, gold_tint)

func _draw_turret_icon(center: Vector2, color: Color) -> void:
	# Turret icon matching actual in-game turret: hexagonal base with triple barrels
	var base_radius := 8.0
	var barrel_length := 10.0
	var barrel_width := 2.5
	
	# Accent color (slightly darker)
	var accent := Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, color.a)
	
	# Draw hexagonal base
	var hex_points := PackedVector2Array()
	for i in range(6):
		var angle := TAU * i / 6.0 - PI / 6.0
		hex_points.append(center + Vector2(cos(angle), sin(angle)) * base_radius)
	draw_colored_polygon(hex_points, accent)
	
	# Inner hexagon (lighter)
	var inner_hex := PackedVector2Array()
	for i in range(6):
		var angle := TAU * i / 6.0 - PI / 6.0
		inner_hex.append(center + Vector2(cos(angle), sin(angle)) * (base_radius - 2.0))
	draw_colored_polygon(inner_hex, color)
	
	# Center pivot
	draw_circle(center, 3.0, accent)
	draw_circle(center, 2.0, color)
	
	# Main barrel (pointing up-right)
	var main_dir := Vector2(0.7, -0.7).normalized()
	var main_end := center + main_dir * barrel_length
	draw_line(center + main_dir * 3.0, main_end, color, barrel_width + 1.0)
	draw_line(center + main_dir * 3.0, main_end, accent, barrel_width - 0.5)
	
	# Side barrels (left and right of main)
	var perp := Vector2(-main_dir.y, main_dir.x)
	var side_offset := 4.0
	var side_length := barrel_length * 0.7
	
	# Left side barrel
	var left_start := center + perp * side_offset
	var left_end := left_start + main_dir * side_length
	draw_line(left_start, left_end, color, barrel_width)
	
	# Right side barrel
	var right_start := center - perp * side_offset
	var right_end := right_start + main_dir * side_length
	draw_line(right_start, right_end, color, barrel_width)

func _draw_laser_icon(center: Vector2, color: Color) -> void:
	# Blue laser beam icon for Snow White's turret special
	var beam_length := 16.0
	var beam_width := 3.0
	var ice_blue := Color(0.4, 0.8, 1.0, color.a)
	var core_white := Color(0.9, 0.95, 1.0, color.a)
	
	# Main beam (pointing up-right at 45 degrees)
	var beam_dir := Vector2(0.7, -0.7).normalized()
	var beam_start := center - beam_dir * beam_length * 0.3
	var beam_end := center + beam_dir * beam_length * 0.7
	
	# Outer glow
	draw_line(beam_start, beam_end, ice_blue, beam_width + 2.0)
	# Core beam
	draw_line(beam_start, beam_end, core_white, beam_width)
	
	# Energy lines emanating from beam (like a sniper tracer)
	var perp := Vector2(-beam_dir.y, beam_dir.x)
	for i in range(3):
		var t := 0.3 + i * 0.25
		var pos := beam_start.lerp(beam_end, t)
		var line_len := 4.0 - i * 0.5
		draw_line(pos - perp * line_len, pos + perp * line_len, ice_blue, 1.5)
	
	# Bullet/projectile head at the end
	draw_circle(beam_end, 3.5, ice_blue)
	draw_circle(beam_end, 2.0, core_white)

func _draw_cross_icon(center: Vector2, color: Color) -> void:
	# Medical/healing cross - scaled for 35px indicator
	var arm_length := 10.0
	var arm_width := 5.0
	
	# Vertical arm
	draw_line(center + Vector2(0, -arm_length), center + Vector2(0, arm_length), color, arm_width)
	# Horizontal arm
	draw_line(center + Vector2(-arm_length, 0), center + Vector2(arm_length, 0), color, arm_width)

func _draw_shotgun_icon(center: Vector2, color: Color) -> void:
	# Shotgun blast icon - shell with spread lines
	var accent := Color(color.r * 0.75, color.g * 0.75, color.b * 0.75, color.a)
	
	# Shell body (rounded rectangle shape)
	var shell_width := 6.0
	var shell_height := 14.0
	var shell_top := center.y - shell_height * 0.5
	var shell_bottom := center.y + shell_height * 0.5
	
	# Shell rectangle
	var shell_points := PackedVector2Array([
		Vector2(center.x - shell_width * 0.5, shell_top + 2),
		Vector2(center.x + shell_width * 0.5, shell_top + 2),
		Vector2(center.x + shell_width * 0.5, shell_bottom),
		Vector2(center.x - shell_width * 0.5, shell_bottom)
	])
	draw_colored_polygon(shell_points, accent)
	
	# Shell brass base (bottom portion)
	var brass_points := PackedVector2Array([
		Vector2(center.x - shell_width * 0.5, shell_bottom - 4),
		Vector2(center.x + shell_width * 0.5, shell_bottom - 4),
		Vector2(center.x + shell_width * 0.5, shell_bottom),
		Vector2(center.x - shell_width * 0.5, shell_bottom)
	])
	draw_colored_polygon(brass_points, Color(0.85, 0.65, 0.3, color.a))
	
	# Spread lines (blast pattern emanating upward)
	var spread_base := center + Vector2(0, shell_top - 1)
	var spread_length := 8.0
	var angles := [-0.4, -0.15, 0.0, 0.15, 0.4]  # 5 pellets spread
	
	for angle in angles:
		var dir := Vector2(sin(angle), -cos(angle))
		draw_line(spread_base, spread_base + dir * spread_length, color, 1.5)

func _draw_mind_control_icon(center: Vector2, color: Color) -> void:
	# Mind control icon - stylized eye with swirl/hypnotic pattern
	var accent := Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, color.a)
	var purple_tint := Color(0.8, 0.5, 1.0, color.a)  # Sin's purple theme
	
	# Outer eye shape (almond)
	var eye_width := 14.0
	var eye_height := 8.0
	var eye_points := PackedVector2Array()
	var segments := 16
	
	# Top curve
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var x: float = lerpf(-eye_width * 0.5, eye_width * 0.5, t)
		var curve := 1.0 - pow(2.0 * t - 1.0, 2.0)  # Parabolic curve
		var y := -eye_height * 0.5 * curve
		eye_points.append(center + Vector2(x, y))
	
	# Bottom curve (reverse)
	for i in range(segments, -1, -1):
		var t := float(i) / float(segments)
		var x: float = lerpf(-eye_width * 0.5, eye_width * 0.5, t)
		var curve := 1.0 - pow(2.0 * t - 1.0, 2.0)
		var y := eye_height * 0.5 * curve
		eye_points.append(center + Vector2(x, y))
	
	draw_colored_polygon(eye_points, accent)
	
	# Inner iris circle
	draw_circle(center, 5.0, purple_tint if _special_cooldown_progress >= 1.0 else color)
	
	# Pupil
	draw_circle(center, 2.5, Color(0.1, 0.05, 0.15, color.a))
	
	# Hypnotic swirl in pupil (small spiral lines)
	var swirl_color := Color(0.9, 0.6, 1.0, color.a * 0.8)
	var spiral_radius := 1.8
	draw_arc(center + Vector2(0.5, -0.5), spiral_radius, 0, PI * 0.8, 8, swirl_color, 1.0)
	draw_arc(center + Vector2(-0.3, 0.3), spiral_radius * 0.6, PI, PI * 1.8, 6, swirl_color, 1.0)
	
	# Eye highlight
	draw_circle(center + Vector2(-1.5, -1.5), 1.0, Color(1.0, 1.0, 1.0, 0.6))

func _draw_horse_icon(center: Vector2, color: Color) -> void:
	# Horse head icon for Crown's cavalry charge
	var accent := Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, color.a)
	var gold_tint := Color(1.0, 0.85, 0.3, color.a)  # Crown's golden theme
	
	# Horse head silhouette (simplified)
	var head_points := PackedVector2Array()
	
	# Build horse head shape - facing right
	head_points.append(center + Vector2(8, -2))   # Nose tip
	head_points.append(center + Vector2(6, -6))   # Nose bridge
	head_points.append(center + Vector2(2, -8))   # Forehead
	head_points.append(center + Vector2(-2, -10)) # Ear tip
	head_points.append(center + Vector2(-4, -6))  # Behind ear
	head_points.append(center + Vector2(-6, -2))  # Top of neck
	head_points.append(center + Vector2(-8, 4))   # Back of neck
	head_points.append(center + Vector2(-4, 8))   # Bottom of neck
	head_points.append(center + Vector2(2, 6))    # Jaw
	head_points.append(center + Vector2(6, 2))    # Chin
	
	# Draw filled horse head
	var fill_color := gold_tint if _special_cooldown_progress >= 1.0 else color
	draw_colored_polygon(head_points, fill_color)
	
	# Eye
	draw_circle(center + Vector2(0, -4), 2.0, accent)
	draw_circle(center + Vector2(0, -4), 1.0, Color(0.1, 0.1, 0.1, color.a))
	
	# Nostril
	draw_circle(center + Vector2(6, 0), 1.0, accent)
	
	# Mane lines
	var mane_color := Color(fill_color.r * 1.2, fill_color.g * 1.1, fill_color.b, color.a)
	draw_line(center + Vector2(-2, -8), center + Vector2(-6, -4), mane_color, 1.5)
	draw_line(center + Vector2(-4, -6), center + Vector2(-7, -1), mane_color, 1.5)
	draw_line(center + Vector2(-5, -4), center + Vector2(-8, 2), mane_color, 1.5)

func _draw_drone_icon(center: Vector2, color: Color) -> void:
	# Drone/robot icon for Cecil's drone companions
	var accent := Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, color.a)
	var blue_tint := Color(0.3, 0.7, 1.0, color.a)  # Cecil's blue theme
	
	# Main drone body (circular)
	var body_color := blue_tint if _special_cooldown_progress >= 1.0 else color
	draw_circle(center, 7.0, body_color)
	draw_circle(center, 5.0, accent)
	
	# Central eye/lens
	draw_circle(center, 2.5, Color(0.2, 0.5, 0.9, color.a))
	draw_circle(center + Vector2(-0.5, -0.5), 1.0, Color(1.0, 1.0, 1.0, 0.7))
	
	# Propeller arms (4 directions)
	var arm_color := body_color
	for i in range(4):
		var angle := i * PI * 0.5 + PI * 0.25  # 45 degree offset
		var arm_start := center + Vector2(cos(angle), sin(angle)) * 6
		var arm_end := center + Vector2(cos(angle), sin(angle)) * 11
		draw_line(arm_start, arm_end, arm_color, 2.0)
		# Small propeller circle at end
		draw_circle(arm_end, 2.5, accent)
	
	# Antenna on top
	draw_line(center + Vector2(0, -7), center + Vector2(0, -11), arm_color, 1.5)
	draw_circle(center + Vector2(0, -11), 1.5, blue_tint)

func _draw_clone_icon(center: Vector2, color: Color) -> void:
	# Clone icon for Nayuta's clone ability - two overlapping figures
	var accent := Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, color.a)
	var purple_tint := Color(0.7, 0.4, 1.0, color.a)  # Nayuta's purple/ninja theme
	
	var clone_color := purple_tint if _special_cooldown_progress >= 1.0 else color
	
	# Back figure (slightly offset and dimmer)
	var offset := Vector2(4, -2)
	# Head
	draw_circle(center + offset + Vector2(0, -6), 3.0, accent)
	# Body
	draw_line(center + offset + Vector2(0, -3), center + offset + Vector2(0, 4), accent, 2.5)
	# Arms
	draw_line(center + offset + Vector2(-4, 0), center + offset + Vector2(4, 0), accent, 2.0)
	# Legs
	draw_line(center + offset + Vector2(0, 4), center + offset + Vector2(-3, 10), accent, 2.0)
	draw_line(center + offset + Vector2(0, 4), center + offset + Vector2(3, 10), accent, 2.0)
	
	# Front figure (main clone)
	var main_offset := Vector2(-2, 1)
	# Head
	draw_circle(center + main_offset + Vector2(0, -6), 3.5, clone_color)
	# Body
	draw_line(center + main_offset + Vector2(0, -3), center + main_offset + Vector2(0, 4), clone_color, 3.0)
	# Arms
	draw_line(center + main_offset + Vector2(-5, 0), center + main_offset + Vector2(5, 0), clone_color, 2.5)
	# Legs
	draw_line(center + main_offset + Vector2(0, 4), center + main_offset + Vector2(-3, 10), clone_color, 2.5)
	draw_line(center + main_offset + Vector2(0, 4), center + main_offset + Vector2(3, 10), clone_color, 2.5)

func _draw_bar_text(text: String, center_pos: Vector2, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	# Get text size for proper centering
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# Calculate position: center horizontally, and vertically account for baseline
	var draw_pos := Vector2(
		center_pos.x - text_size.x * 0.5,
		center_pos.y + text_size.y * 0.35  # Approximate vertical center (baseline adjustment)
	)
	
	# Draw shadow/outline for readability
	var shadow_color := Color(0, 0, 0, 0.8)
	var offsets := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	for offset in offsets:
		draw_string(font, draw_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow_color)
	# Draw main text
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _draw_bar(rect: Rect2, current_value: float, max_value: float, background_color: Color, fill_color: Color, border_color: Color) -> void:
	var clamped_max: float = maxf(0.0001, max_value)
	draw_rect(rect, background_color, true)
	var ratio: float = clampf(current_value / clamped_max, 0.0, 1.0)
	if ratio > 0.0:
		var fill_rect := Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y))
		draw_rect(fill_rect, fill_color, true)
	draw_rect(rect, border_color, false, BORDER_THICKNESS)

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

func update_special_ability(unlocked: bool, cooldown_progress: float) -> void:
	## Update the special ability indicator
	## cooldown_progress: 0.0 = just used (on cooldown), 1.0 = fully ready
	_special_unlocked = unlocked
	_special_cooldown_progress = clampf(cooldown_progress, 0.0, 1.0)
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
