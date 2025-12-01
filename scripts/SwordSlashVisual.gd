@tool
extends Node2D
class_name SwordSlashVisual

@export var preview_radius: float = 260.0
@export_range(10.0, 360.0, 1.0) var preview_arc_degrees: float = 110.0
@export var preview_core_color: Color = Color(0.62, 0.36, 0.95, 0.85)
@export var preview_edge_color: Color = Color(0.9, 0.82, 1.0, 0.9)
@export var preview_glow_color: Color = Color(0.3, 0.16, 0.55, 0.55)
@export_range(1, 16, 1) var preview_sparkle_count: int = 6
@export var additive_blend: bool = true
@export_range(0.0, 1.0, 0.01) var preview_inner_ratio: float = 0.25

var _radius: float = 0.0
var _arc_degrees: float = 0.0
var _core_color: Color = Color.WHITE
var _edge_color: Color = Color.WHITE
var _glow_color: Color = Color.WHITE
var _fade: float = 1.0
var _wipe: float = 0.0
var _sparkle_seed: int = 0
var _sparkle_count: int = 6
var _inner_ratio: float = 0.25

# Sweep animation - the arc sweeps from start to end
@export var wipe_progress: float = 0.0:
	set(value):
		_wipe = clampf(value, 0.0, 1.0)
		queue_redraw()

func _ready() -> void:
	if additive_blend:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
	if Engine.is_editor_hint():
		_set_preview_state()

func update_visual(params: Dictionary) -> void:
	_radius = maxf(float(params.get("radius", preview_radius)), 0.0)
	_arc_degrees = clampf(float(params.get("arc_degrees", preview_arc_degrees)), 1.0, 360.0)
	_core_color = params.get("core_color", preview_core_color)
	_edge_color = params.get("edge_color", preview_edge_color)
	_glow_color = params.get("glow_color", preview_glow_color)
	_fade = clampf(float(params.get("fade", 1.0)), 0.0, 1.0)
	_wipe = clampf(float(params.get("wipe_progress", 0.0)), 0.0, 1.0)
	_inner_ratio = clampf(float(params.get("inner_ratio", preview_inner_ratio)), 0.0, 1.0)
	_sparkle_seed = int(params.get("sparkle_seed", 0))
	_sparkle_count = clampi(int(params.get("sparkle_count", preview_sparkle_count)), 0, 24)
	queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_set_preview_state()

func _set_preview_state() -> void:
	_radius = preview_radius
	_arc_degrees = preview_arc_degrees
	_core_color = preview_core_color
	_edge_color = preview_edge_color
	_glow_color = preview_glow_color
	_fade = 1.0
	_wipe = 1.0
	_sparkle_count = preview_sparkle_count
	_inner_ratio = preview_inner_ratio
	queue_redraw()

func _draw() -> void:
	if _radius <= 0.01 or _wipe <= 0.0:
		return
	
	# The sweep draws an arc that grows from one side to the other
	# Like Link to the Past sword slash - starts thin, sweeps across
	var half_arc := deg_to_rad(_arc_degrees) * 0.5
	var sweep_end_angle := -half_arc + deg_to_rad(_arc_degrees) * _wipe
	
	# Draw the filled arc from start to current sweep position
	_draw_filled_arc(-half_arc, sweep_end_angle)
	
	# Blade edge removed — was drawing white lines at the arc ends
	
	# Draw sparkles along the swept area
	if _wipe > 0.2:
		_draw_sweep_sparkles(sweep_end_angle)

func _draw_filled_arc(start_angle: float, end_angle: float) -> void:
	if end_angle <= start_angle:
		return
	
	var outer := _radius
	var inner := _radius * _inner_ratio
	var segments := 20
	
	# Glow layer (largest, most transparent)
	var glow_outer := outer * 1.2
	var glow_inner := inner * 0.5
	_draw_arc_band(start_angle, end_angle, glow_outer, glow_inner, 
		Color(_glow_color.r, _glow_color.g, _glow_color.b, _glow_color.a * _fade * 0.5), segments)
	
	# Core layer (main visible slash)
	_draw_arc_band(start_angle, end_angle, outer * 1.05, inner * 0.8,
		Color(_core_color.r, _core_color.g, _core_color.b, _core_color.a * _fade * 0.9), segments)
	
	# Bright edge layer (innermost, brightest)
	_draw_arc_band(start_angle, end_angle, outer * 0.9, inner,
		Color(_edge_color.r, _edge_color.g, _edge_color.b, _edge_color.a * _fade), segments)

func _draw_arc_band(start_angle: float, end_angle: float, outer_r: float, inner_r: float, color: Color, segments: int) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	
	# Outer edge
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var angle := lerpf(start_angle, end_angle, t)
		points.append(Vector2(cos(angle), sin(angle)) * outer_r)
	
	# Inner edge (reversed)
	for i in range(segments, -1, -1):
		var t := float(i) / float(segments)
		var angle := lerpf(start_angle, end_angle, t)
		points.append(Vector2(cos(angle), sin(angle)) * inner_r)
	
	for _p in points:
		colors.append(color)
	
	if points.size() >= 3:
		draw_polygon(points, colors)

func _draw_blade_edge(angle: float) -> void:
	# Draw a bright line at the leading edge of the sweep
	var inner_pt := Vector2(cos(angle), sin(angle)) * (_radius * 0.2)
	var outer_pt := Vector2(cos(angle), sin(angle)) * (_radius * 1.15)
	
	# Bright core line
	var bright := Color(_edge_color.r, _edge_color.g, _edge_color.b, _fade)
	draw_line(inner_pt, outer_pt, bright, 6.0, true)
	
	# White hot center
	var white := Color(1.0, 1.0, 1.0, _fade * 0.9)
	draw_line(inner_pt * 1.1, outer_pt * 0.95, white, 3.0, true)

func _draw_sweep_sparkles(lead_angle: float) -> void:
	var half_arc := deg_to_rad(_arc_degrees) * 0.5
	var start_angle := -half_arc
	var rng := RandomNumberGenerator.new()
	rng.seed = _sparkle_seed
	
	var sparkle_color := Color(_edge_color.r, _edge_color.g, _edge_color.b, _edge_color.a * _fade * 0.8)
	
	for i in range(_sparkle_count):
		# Place sparkles along the swept area
		var t := rng.randf()
		if t > _wipe:
			continue  # Only show sparkles in the swept area
		var angle := lerpf(start_angle, lead_angle, t)
		var radius := lerpf(_radius * 0.35, _radius * 1.0, rng.randf())
		var pos := Vector2(cos(angle), sin(angle)) * radius
		var size := rng.randf_range(4.0, 10.0)
		
		# Small cross sparkle
		draw_line(pos - Vector2(size, 0), pos + Vector2(size, 0), sparkle_color, 2.0, true)
		draw_line(pos - Vector2(0, size * 0.6), pos + Vector2(0, size * 0.6), sparkle_color, 2.0, true)
