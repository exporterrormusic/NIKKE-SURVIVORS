@tool
extends Node2D
class_name PlayerOverheadHud

## HUD displayed above the player sprite showing HP, Ammo, and Burst bars

const HEALTH_BAR_WIDTH := 112.0
const HEALTH_BAR_HEIGHT := 12.0
const AMMO_BAR_HEIGHT := 8.0
const BURST_BAR_HEIGHT := 9.0
const BAR_SPACING := 3.0
const TOP_OFFSET_Y := -110.0  # Raised higher to avoid overlapping player sprite
const BORDER_THICKNESS := 2.0

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
var _current_character: int = 1  # 0=Scarlet, 1=Snow White, 2=Rapunzel
var _current_burst: float = 50.0
var _max_burst: float = 100.0
var _burst_ready: bool = false
var _burst_unlocked: bool = false  # Whether burst ability is unlocked
var _scarlet_special_unlocked: bool = false  # Whether Scarlet's special attack is unlocked
var _glow_time: float = 0.0
var _initialized: bool = false

# Per-character reload progress tracking to prevent reset on swap
var _reload_progress_per_char: Array = [0.0, 0.0, 0.0]  # Scarlet, Snow White, Rapunzel

# Special ability cooldown tracking
var _special_cooldown_progress: float = 0.0  # 0 = on cooldown, 1 = ready
var _special_unlocked: bool = false  # Is the special ability unlocked for current character
# Height matches all 3 bars: HP(12) + spacing(3) + Ammo(8) + spacing(3) + Burst(9) = 35
const SPECIAL_INDICATOR_SIZE := 35.0
const SPECIAL_INDICATOR_GAP := 6.0  # Gap between bars and indicator
const SPECIAL_INDICATOR_CORNER_RADIUS := 4.0

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
	
	# Always animate glow time for effects
	_glow_time += delta * 3.0
	
	# Animate reload progress for current character
	if _is_reloading and _reload_time > 0:
		_reload_progress += delta / _reload_time
		_reload_progress = minf(_reload_progress, 1.0)
		# Store in per-character array
		if _current_character >= 0 and _current_character < 3:
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
	
	# Draw health bar
	var health_rect := Rect2(Vector2(left_x, TOP_OFFSET_Y), Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT))
	_draw_bar(health_rect, float(_current_health), float(_max_health), health_background_color, health_fill_color, health_border_color)
	
	# Draw health text (centered in bar)
	var health_text := "%d/%d" % [_current_health, _max_health]
	var health_center := Vector2(0, TOP_OFFSET_Y + HEALTH_BAR_HEIGHT * 0.5)
	_draw_bar_text(health_text, health_center, 10)
	
	# Draw ammo bar (between HP and burst)
	var ammo_top := TOP_OFFSET_Y + HEALTH_BAR_HEIGHT + BAR_SPACING
	var ammo_rect := Rect2(Vector2(left_x, ammo_top), Vector2(HEALTH_BAR_WIDTH, AMMO_BAR_HEIGHT))
	
	if _current_character == 0:
		# Scarlet - special attack has 1 ammo with cooldown when unlocked
		if _is_reloading:
			# Draw reload animation - bar fills up from left to right (same as other characters)
			draw_rect(ammo_rect, ammo_background_color, true)
			
			# Draw the filling progress bar with pulsing effect (red-tinted for Scarlet)
			var pulse := sin(_glow_time * 4.0) * 0.15 + 0.85
			var reload_fill_color := Color(
				1.0 * pulse,  # Red-tinted for Scarlet
				0.4 * pulse,
				0.4 * pulse,
				0.8
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
		elif _scarlet_special_unlocked and _current_ammo > 0:
			# Has ammo - show full bar with "READY"
			draw_rect(ammo_rect, ammo_background_color, true)
			var scarlet_fill := Color(1.0, 0.4, 0.4, 1.0)  # Red for Scarlet
			draw_rect(ammo_rect, scarlet_fill, true)
			draw_rect(ammo_rect, ammo_border_color, false, BORDER_THICKNESS)
			var ammo_center := Vector2(0, ammo_top + AMMO_BAR_HEIGHT * 0.5)
			_draw_bar_text("READY", ammo_center, 8)
		elif not _scarlet_special_unlocked:
			# Special not unlocked - show locked state (grey)
			var locked_bg := Color(0.15, 0.15, 0.18, 0.92)
			var locked_border := Color(0.35, 0.35, 0.4, 1.0)
			draw_rect(ammo_rect, locked_bg, true)
			draw_rect(ammo_rect, locked_border, false, BORDER_THICKNESS)
			var ammo_center := Vector2(0, ammo_top + AMMO_BAR_HEIGHT * 0.5)
			_draw_bar_text("LOCKED", ammo_center, 7)
		else:
			# No ammo, not reloading (shouldn't happen normally)
			draw_rect(ammo_rect, ammo_background_color, true)
			draw_rect(ammo_rect, ammo_border_color, false, BORDER_THICKNESS)
			var ammo_center := Vector2(0, ammo_top + AMMO_BAR_HEIGHT * 0.5)
			_draw_bar_text("0/1", ammo_center, 8)
	else:
		# Snow White or Rapunzel - show ammo count or reload animation
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
	
	# For Snow White turrets, check if we have charges available
	var has_charges := true
	if _current_character == 1:  # Snow White
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
	
	# For Snow White, draw charge count below the indicator
	if _current_character == 1 and _turret_max_charges > 0:
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
		_:
			return Color(0.7, 0.7, 0.7, 1.0)

func _draw_special_icon(center: Vector2) -> void:
	var icon_color := Color(1.0, 1.0, 1.0, 0.9)
	if _special_cooldown_progress < 1.0:
		icon_color = Color(0.6, 0.6, 0.6, 0.7)  # Dimmed when on cooldown
	
	match _current_character:
		0:  # Scarlet - Sword icon
			_draw_sword_icon(center, icon_color)
		1:  # Snow White - Turret icon
			_draw_turret_icon(center, icon_color)
		2:  # Rapunzel - Cross icon
			_draw_cross_icon(center, icon_color)

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

func _draw_cross_icon(center: Vector2, color: Color) -> void:
	# Medical/healing cross - scaled for 35px indicator
	var arm_length := 10.0
	var arm_width := 5.0
	
	# Vertical arm
	draw_line(center + Vector2(0, -arm_length), center + Vector2(0, arm_length), color, arm_width)
	# Horizontal arm
	draw_line(center + Vector2(-arm_length, 0), center + Vector2(arm_length, 0), color, arm_width)

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
	if not is_instance_valid(_player):
		return
	match _current_character:
		0:  # Scarlet - unlimited
			_current_ammo = 1
			_max_ammo = 1
			_is_reloading = false
		1:  # Snow White
			if "snow_white_ammo" in _player:
				_current_ammo = int(_player.snow_white_ammo)
			if "snow_white_max_ammo" in _player:
				_max_ammo = int(_player.snow_white_max_ammo)
			if "snow_white_reloading" in _player:
				_is_reloading = bool(_player.snow_white_reloading)
		2:  # Rapunzel
			if "rapunzel_ammo" in _player:
				_current_ammo = int(_player.rapunzel_ammo)
			if "rapunzel_max_ammo" in _player:
				_max_ammo = int(_player.rapunzel_max_ammo)
			if "rapunzel_reloading" in _player:
				_is_reloading = bool(_player.rapunzel_reloading)

func _connect_player_signals() -> void:
	if not is_instance_valid(_player):
		return
	# We'll update via polling since the simple Player.gd doesn't have signals

func update_health(current: int, maximum: int) -> void:
	_current_health = current
	_max_health = maxi(1, maximum)
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
			if _current_character >= 0 and _current_character < 3:
				_reload_progress = _reload_progress_per_char[_current_character]
			else:
				_reload_progress = 0.0
		# else: continue with current progress (already animating)
	else:
		# Not reloading - reset progress for this character
		_reload_progress = 0.0
		if _current_character >= 0 and _current_character < 3:
			_reload_progress_per_char[_current_character] = 0.0
	
	_is_reloading = is_reloading
	queue_redraw()

func update_character(character_index: int) -> void:
	# Store current character's reload progress before switching
	if _current_character >= 0 and _current_character < 3:
		_reload_progress_per_char[_current_character] = _reload_progress
	
	_current_character = character_index
	
	# Restore new character's reload progress
	if character_index >= 0 and character_index < 3:
		_reload_progress = _reload_progress_per_char[character_index]
	
	_update_ammo_from_player()
	queue_redraw()
