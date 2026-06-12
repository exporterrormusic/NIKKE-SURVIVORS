extends Control
class_name MiniMap
## Square mini-map UI displayed in top-right corner during gameplay.
## Shows player, bosses, super bosses, N01, and Pristine Rapture Cores.
## Bracket-frame panel (approved HUD mockup docs/mockups/hud_v2.html).

const BracketStyleBoxScript := preload("res://scripts/ui/components/BracketStyleBox.gd")

# Styling
const MAP_SIZE := 222.0 # Square size in pixels
const BORDER_WIDTH := 3.0
const BACKGROUND_COLOR := Color(0.039, 0.051, 0.071, 0.5)
const GRID_COLOR := Color(0.2, 0.3, 0.4, 0.3)

# Map range - large enough to show entire map
const MAP_RANGE := 5000.0 # World units visible on map (whole map)

# Icon colors - bright and visible
const PLAYER_COLOR := Color(0.3, 1.0, 0.5, 1.0) # Bright green
const PRISTINE_ORB_COLOR := Color(1.0, 0.3, 0.3, 1.0) # Bright red for orbs
const PRISTINE_GLOW_COLOR := Color(1.0, 0.2, 0.1, 0.5) # Red glow
const BOSS_COLOR := Color(0.85, 0.4, 1.0, 1.0) # Bright purple for bosses
const BOSS_GLOW_COLOR := Color(0.7, 0.2, 1.0, 0.5) # Purple glow
const N01_STROKE_COLOR := Color(0.0, 0.0, 0.0, 1.0) # Black stroke for N01

# Animation
const OBJECTIVE_PULSE_SPEED := 4.0
const ARROW_SIZE := 12.0

# State
var _player: Node2D = null
var _objective_position: Vector2 = Vector2.ZERO
var _objective_type: String = "intel"
var _show_objective := false
var _time := 0.0
var _frame_counter: int = 0 # PERFORMANCE: Frame throttling

# Panel reference
var _panel: Panel = null
var _draw_layer: Control = null # Draw layer on top of panel

func _ready() -> void:
	_build_ui()
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	_frame_counter += 1
	
	# PERFORMANCE: Only redraw every 2 frames (users won't notice at 60fps)
	if _draw_layer and _frame_counter % 2 == 0:
		_draw_layer.queue_redraw()
	
	# Try to find player if not set (throttled)
	if _frame_counter % 10 == 0 and (not _player or not is_instance_valid(_player)):
		_player = TargetCache.get_player()

func _build_ui() -> void:
	# Set size and anchor to top-right corner
	custom_minimum_size = Vector2(MAP_SIZE + BORDER_WIDTH * 2, MAP_SIZE + BORDER_WIDTH * 2)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = - MAP_SIZE - BORDER_WIDTH * 2 - 30
	offset_right = -30
	offset_top = 30
	offset_bottom = 30 + MAP_SIZE + BORDER_WIDTH * 2
	
	# Background panel (draws first)
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _create_panel_style())
	add_child(_panel)
	
	# Draw layer ON TOP of panel for icons
	_draw_layer = Control.new()
	_draw_layer.name = "DrawLayer"
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.draw.connect(_on_draw_layer_draw)
	add_child(_draw_layer)

func _create_panel_style() -> StyleBox:
	var style = BracketStyleBoxScript.new()
	style.bg_color = BACKGROUND_COLOR
	return style

func _on_draw_layer_draw() -> void:
	# This draws ON TOP of the panel - using _draw_layer.draw_* methods
	var center := Vector2(BORDER_WIDTH + MAP_SIZE / 2, BORDER_WIDTH + MAP_SIZE / 2)
	var half_size := MAP_SIZE / 2.0
	
	# Draw grid lines
	_draw_grid_layer(center, half_size)
	
	# Draw player at center (always)
	_draw_player_icon_layer(center)
	
	# Draw Pristine Rapture Cores (red circles)
	_draw_pristine_cores_layer(center, half_size)
	
	# Draw bosses only (not regular enemies)
	_draw_bosses_layer(center, half_size)
	
	# Draw objective if active
	if _show_objective and _player and is_instance_valid(_player):
		_draw_objective_layer(center, half_size)
	
	# Draw cardinal direction markers
	_draw_compass_layer(center, half_size)

func _draw_pristine_cores_layer(center: Vector2, half_size: float) -> void:
	if not _player:
		return
	
	var drops := get_tree().get_nodes_in_group("drops")
	var player_pos := _player.global_position
	
	for drop in drops:
		if not is_instance_valid(drop) or not drop is Node2D:
			continue
		
		# Only show PristineCoreOrb (check class or script)
		if not (drop is PristineCoreOrb):
			continue
			
		var d_node := drop as Node2D
		var rel_pos := d_node.global_position - player_pos
		var map_pos := rel_pos * (MAP_SIZE / MAP_RANGE)
		
		# Clamp to map bounds
		if abs(map_pos.x) > half_size or abs(map_pos.y) > half_size:
			continue
		
		var draw_pos := center + map_pos
		
		# Pulsing glow effect
		var pulse := 0.8 + 0.2 * sin(_time * 4.0)
		
		# Draw outer glow (larger, semi-transparent)
		_draw_layer.draw_circle(draw_pos, 12.0 * pulse, PRISTINE_GLOW_COLOR)
		
		# Draw bright core
		_draw_layer.draw_circle(draw_pos, 6.0, PRISTINE_ORB_COLOR)
		
		# Draw inner highlight
		_draw_layer.draw_circle(draw_pos, 3.0, Color(1.0, 0.7, 0.7, 1.0))

func _draw_bosses_layer(center: Vector2, half_size: float) -> void:
	if not _player:
		return
		
	# PERFORMANCE: Use TargetCache instead of get_nodes_in_group every frame
	var enemies := TargetCache.get_enemies()
	var player_pos := _player.global_position
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		# Only show bosses, super_bosses, and N01
		var is_boss: bool = enemy.is_in_group("boss") or enemy.is_in_group("bosses")
		var is_super: bool = enemy.is_in_group("super_boss") or enemy.is_in_group("super_bosses")
		var is_n01: bool = enemy.name == "RaptureQueenN01" or enemy.is_in_group("rapture_queen")
		
		if not (is_boss or is_super or is_n01):
			continue
			
		var e_node := enemy as Node2D
		var rel_pos := e_node.global_position - player_pos
		var map_pos := rel_pos * (MAP_SIZE / MAP_RANGE)
		
		if abs(map_pos.x) > half_size or abs(map_pos.y) > half_size:
			continue
		
		var draw_pos := center + map_pos
		
		# Pulsing glow effect
		var pulse := 0.8 + 0.2 * sin(_time * 3.5)
		
		if is_n01:
			# N01: Large glowing purple with black stroke
			# Outer glow
			_draw_layer.draw_circle(draw_pos, 18.0 * pulse, BOSS_GLOW_COLOR)
			# Black stroke
			_draw_layer.draw_circle(draw_pos, 12.0, N01_STROKE_COLOR)
			# Purple fill
			_draw_layer.draw_circle(draw_pos, 9.0, BOSS_COLOR)
			# Bright center
			_draw_layer.draw_circle(draw_pos, 4.0, Color(1.0, 0.8, 1.0, 1.0))
		else:
			# Boss/Super Boss: Glowing purple circle
			var base_radius := 10.0 if is_super else 8.0
			# Outer glow
			_draw_layer.draw_circle(draw_pos, base_radius * 1.8 * pulse, BOSS_GLOW_COLOR)
			# Main circle
			_draw_layer.draw_circle(draw_pos, base_radius, BOSS_COLOR)
			# Bright center
			_draw_layer.draw_circle(draw_pos, base_radius * 0.4, Color(1.0, 0.8, 1.0, 1.0))

func _draw_grid_layer(center: Vector2, half_size: float) -> void:
	# Draw subtle grid lines
	var grid_spacing := MAP_SIZE / 4.0
	
	for i in range(-2, 3):
		var offset := i * grid_spacing
		# Vertical lines
		_draw_layer.draw_line(
			center + Vector2(offset, -half_size + BORDER_WIDTH),
			center + Vector2(offset, half_size - BORDER_WIDTH),
			GRID_COLOR, 1.0
		)
		# Horizontal lines
		_draw_layer.draw_line(
			center + Vector2(-half_size + BORDER_WIDTH, offset),
			center + Vector2(half_size - BORDER_WIDTH, offset),
			GRID_COLOR, 1.0
		)

func _draw_player_icon_layer(center: Vector2) -> void:
	# Draw player as a triangle pointing up
	var player_size := 8.0
	var points := PackedVector2Array([
		center + Vector2(0, -player_size),
		center + Vector2(-player_size * 0.7, player_size * 0.7),
		center + Vector2(player_size * 0.7, player_size * 0.7)
	])
	_draw_layer.draw_colored_polygon(points, PLAYER_COLOR)
	
	# Draw outline
	_draw_layer.draw_polyline(points, PLAYER_COLOR.lightened(0.3), 1.5, true)

func _draw_objective_layer(center: Vector2, half_size: float) -> void:
	if not _player or not is_instance_valid(_player):
		return
	
	var player_pos := _player.global_position
	var to_objective := _objective_position - player_pos
	var distance := to_objective.length()
	
	# Convert world position to minimap position
	var map_pos := (to_objective / MAP_RANGE) * half_size
	
	# Determine if objective is within map bounds
	var is_on_map: bool = abs(map_pos.x) < half_size - 5 and abs(map_pos.y) < half_size - 5
	
	# Pulsing effect
	var pulse := 0.7 + 0.3 * sin(_time * OBJECTIVE_PULSE_SPEED)
	var color := PRISTINE_ORB_COLOR if _objective_type == "intel" else BOSS_COLOR
	color.a = pulse
	
	if is_on_map:
		# Draw objective marker on map
		var final_pos := center + map_pos
		_draw_objective_icon_layer(final_pos, color)
	else:
		# Draw arrow at edge pointing to objective
		var direction := to_objective.normalized()
		var edge_pos := center + direction * (half_size - ARROW_SIZE - 5)
		
		# Clamp to square bounds
		edge_pos.x = clampf(edge_pos.x, BORDER_WIDTH + ARROW_SIZE, BORDER_WIDTH + MAP_SIZE - ARROW_SIZE)
		edge_pos.y = clampf(edge_pos.y, BORDER_WIDTH + ARROW_SIZE, BORDER_WIDTH + MAP_SIZE - ARROW_SIZE)
		
		_draw_direction_arrow_layer(edge_pos, direction, color)
		
		# Draw distance text
		var dist_text := _format_distance(distance)
		_draw_layer.draw_string(
			ThemeDB.fallback_font,
			edge_pos + Vector2(-20, 20),
			dist_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1, 10, color
		)

func _draw_objective_icon_layer(pos: Vector2, color: Color) -> void:
	# Draw diamond shape for objective
	var size := 6.0
	var points := PackedVector2Array([
		pos + Vector2(0, -size),
		pos + Vector2(size, 0),
		pos + Vector2(0, size),
		pos + Vector2(-size, 0)
	])
	_draw_layer.draw_colored_polygon(points, color)
	
	# Draw glow ring
	var ring_size := size + 3.0 + sin(_time * 6.0) * 2.0
	_draw_layer.draw_arc(pos, ring_size, 0, TAU, 16, color.darkened(0.3), 1.5)

func _draw_direction_arrow_layer(pos: Vector2, direction: Vector2, color: Color) -> void:
	# Draw arrow pointing in direction
	var arrow_length := ARROW_SIZE
	var arrow_width := ARROW_SIZE * 0.6
	
	var tip := pos + direction * arrow_length
	var base := pos - direction * arrow_length * 0.3
	var perp := Vector2(-direction.y, direction.x)
	
	var points := PackedVector2Array([
		tip,
		base + perp * arrow_width,
		base - perp * arrow_width
	])
	_draw_layer.draw_colored_polygon(points, color)

func _draw_compass_layer(center: Vector2, half_size: float) -> void:
	# Draw N, S, E, W markers
	var label_offset := half_size - 8
	var label_color := Color(0.6, 0.7, 0.8, 0.7)
	var font_size := 9
	
	_draw_layer.draw_string(ThemeDB.fallback_font, center + Vector2(-3, -label_offset + 3), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, label_color)
	_draw_layer.draw_string(ThemeDB.fallback_font, center + Vector2(-3, label_offset + 3), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, label_color)
	_draw_layer.draw_string(ThemeDB.fallback_font, center + Vector2(label_offset - 3, 3), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, label_color)
	_draw_layer.draw_string(ThemeDB.fallback_font, center + Vector2(-label_offset - 3, 3), "W", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, label_color)

func _format_distance(dist: float) -> String:
	if dist >= 1000:
		return "%.1fk" % (dist / 1000.0)
	return "%dm" % int(dist)

# === PUBLIC API ===

## Set the objective position and type for the minimap arrow
func set_objective(world_position: Vector2, objective_type: String = "intel") -> void:
	_objective_position = world_position
	_objective_type = objective_type
	_show_objective = true

## Clear the objective marker
func clear_objective() -> void:
	_show_objective = false

## Set player reference directly
func set_player(player: Node2D) -> void:
	_player = player
