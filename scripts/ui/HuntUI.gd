extends CanvasLayer
class_name HuntUI
## HUD for HUNT mode - shows INTEL counter and direction arrow instead of wave/timer

signal intel_updated(collected: int, total: int)

# Styling
const PANEL_BG := Color(0.05, 0.08, 0.12, 0.9)
const BORDER_COLOR := Color(0.2, 0.8, 1.0, 0.8)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const INTEL_COLOR := Color(0.2, 0.9, 1.0, 1.0)
const N01_COLOR := Color(1.0, 0.3, 0.3, 1.0)

# State
var _collected: int = 0
var _total: int = 5
var _target_position: Vector2 = Vector2.ZERO
var _player: Node2D = null
var _is_n01_phase := false
var _time := 0.0

# UI References
var _main_panel: Panel = null
var _counter_label: Label = null
var _arrow_container: Control = null
var _status_label: Label = null

func _ready() -> void:
	layer = 10
	_build_ui()
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	
	# Update player reference
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	
	# Redraw arrow
	if _arrow_container:
		_arrow_container.queue_redraw()

func _build_ui() -> void:
	# Main container - top-left corner (where wave UI normally is)
	_main_panel = Panel.new()
	_main_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_main_panel.offset_left = 20
	_main_panel.offset_top = 50
	_main_panel.offset_right = 280
	_main_panel.offset_bottom = 140
	_main_panel.add_theme_stylebox_override("panel", _create_panel_style())
	add_child(_main_panel)
	
	# HBox for content
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 12
	hbox.offset_top = 8
	hbox.offset_right = -12
	hbox.offset_bottom = -8
	hbox.add_theme_constant_override("separation", 16)
	_main_panel.add_child(hbox)
	
	# Left side: Arrow in box
	_arrow_container = Control.new()
	_arrow_container.custom_minimum_size = Vector2(60, 60)
	_arrow_container.set_script(_create_arrow_script())
	_arrow_container.set("hunt_ui", self)
	hbox.add_child(_arrow_container)
	
	# Right side: text info
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)
	
	# Status label (INTEL or N01)
	_status_label = Label.new()
	_status_label.text = "INTEL TARGET"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", INTEL_COLOR)
	vbox.add_child(_status_label)
	
	# Counter label
	_counter_label = Label.new()
	_counter_label.text = "0 / 5"
	_counter_label.add_theme_font_size_override("font_size", 32)
	_counter_label.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(_counter_label)

func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style

func _create_arrow_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Control

var hunt_ui: Node = null
var _time := 0.0

func _process(delta: float) -> void:
	_time += delta

func _draw() -> void:
	if not hunt_ui:
		return
	
	var center := size / 2.0
	var box_size: float = min(size.x, size.y) - 8
	
	# Draw box background
	var box_rect := Rect2(center - Vector2(box_size/2, box_size/2), Vector2(box_size, box_size))
	var box_color := Color(0.1, 0.15, 0.2, 0.8)
	draw_rect(box_rect, box_color)
	
	# Draw box border
	var border_color: Color = Color(0.2, 0.8, 1.0, 0.8)
	if hunt_ui and hunt_ui._is_n01_phase:
		border_color = Color(1.0, 0.3, 0.3, 0.8)
	draw_rect(box_rect, border_color, false, 2.0)
	
	# Calculate direction to target
	var player = hunt_ui._player if hunt_ui else null
	var target_pos = hunt_ui._target_position if hunt_ui else Vector2.ZERO
	
	if player and is_instance_valid(player) and target_pos != Vector2.ZERO:
		var direction: Vector2 = (target_pos - player.global_position).normalized()
		var arrow_color: Color = border_color
		arrow_color.a = 0.7 + sin(_time * 4.0) * 0.3
		
		# Draw arrow pointing in direction
		var arrow_size: float = box_size * 0.35
		var tip: Vector2 = center + direction * arrow_size
		var base_pt: Vector2 = center - direction * arrow_size * 0.3
		var perp: Vector2 = Vector2(-direction.y, direction.x)
		
		var points := PackedVector2Array([
			tip,
			base_pt + perp * arrow_size * 0.5,
			base_pt - perp * arrow_size * 0.5
		])
		draw_colored_polygon(points, arrow_color)
"""
	script.reload()
	return script

# === PUBLIC API ===

func set_intel_count(collected: int, total: int) -> void:
	_collected = collected
	_total = total
	if _counter_label:
		_counter_label.text = "%d / %d" % [collected, total]
	
	emit_signal("intel_updated", collected, total)

func set_target_position(pos: Vector2) -> void:
	_target_position = pos

func set_n01_phase(is_n01: bool) -> void:
	_is_n01_phase = is_n01
	if _status_label:
		if is_n01:
			_status_label.text = "HUNT TARGET: N01"
			_status_label.add_theme_color_override("font_color", N01_COLOR)
		else:
			_status_label.text = "INTEL TARGET"
			_status_label.add_theme_color_override("font_color", INTEL_COLOR)
	if _counter_label and is_n01:
		_counter_label.text = "ELIMINATE"
