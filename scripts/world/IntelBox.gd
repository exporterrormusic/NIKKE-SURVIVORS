extends Area2D
class_name IntelBox
## Collectable INTEL box with impressive holographic visuals.
## Glowing sci-fi data terminal that guides player through HUNT mode.

signal collected(intel_index: int)

@export var intel_index: int = 0

# Visual styling
const PRIMARY_COLOR := Color(0.1, 0.9, 1.0, 1.0)    # Bright cyan
const SECONDARY_COLOR := Color(0.0, 0.6, 0.8, 1.0)   # Darker cyan
const GLOW_COLOR := Color(0.0, 0.8, 1.0, 0.5)        # Cyan glow
const CORE_COLOR := Color(1.0, 1.0, 1.0, 0.9)        # White hot center
const DATA_COLOR := Color(0.0, 1.0, 0.8, 0.8)        # Data stream color

const BOX_SIZE := 48.0
const PULSE_SPEED := 3.0
const ROTATION_SPEED := 1.5
const DATA_STREAM_COUNT := 8
const BEACON_HEIGHT := 200.0

# State
var _collected := false
var _time := 0.0
var _data_streams: Array[Dictionary] = []
var _hologram_sprite: Node2D = null
var _beacon_sprite: Node2D = null

func _ready() -> void:
	add_to_group("intel_boxes")
	_setup_collision()
	_setup_visuals()
	_init_data_streams()
	set_process(true)

func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	queue_redraw()
	
	# Update hologram rotation
	if _hologram_sprite:
		_hologram_sprite.rotation = sin(_time * ROTATION_SPEED) * 0.2

func _setup_collision() -> void:
	collision_layer = 0
	collision_mask = 1  # Player layer
	
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BOX_SIZE * 1.5  # Generous pickup radius
	shape.shape = circle
	add_child(shape)
	
	# Connect collision
	body_entered.connect(_on_body_entered)

func _setup_visuals() -> void:
	# Main hologram container
	_hologram_sprite = Node2D.new()
	_hologram_sprite.name = "Hologram"
	add_child(_hologram_sprite)
	
	# Beacon light extending upward
	_beacon_sprite = Node2D.new()
	_beacon_sprite.name = "Beacon"
	add_child(_beacon_sprite)

func _init_data_streams() -> void:
	_data_streams.clear()
	for i in range(DATA_STREAM_COUNT):
		var stream := {
			"angle": (float(i) / DATA_STREAM_COUNT) * TAU,
			"speed": randf_range(30.0, 60.0),
			"offset": randf() * 50.0,
			"height": randf_range(60.0, 100.0)
		}
		_data_streams.append(stream)

func _draw() -> void:
	if _collected:
		return
	
	var pulse := sin(_time * PULSE_SPEED) * 0.5 + 0.5
	var fast_pulse := sin(_time * PULSE_SPEED * 2.0) * 0.3 + 0.7
	
	# Draw beacon light (vertical beam)
	_draw_beacon(pulse)
	
	# Draw outer glow rings
	_draw_glow_rings(pulse)
	
	# Draw holographic box frame
	_draw_hologram_box(fast_pulse)
	
	# Draw data streams
	_draw_data_streams()
	
	# Draw floating data symbols
	_draw_data_symbols()
	
	# Draw core
	_draw_core(fast_pulse)
	
	# Draw "INTEL" text label
	_draw_label()

func _draw_beacon(pulse: float) -> void:
	# Draw vertical light beam
	var beam_width := 20.0 + pulse * 15.0
	var beam_alpha := 0.15 + pulse * 0.1
	
	# Gradient beam (wider at top)
	for i in range(10):
		var t := float(i) / 10.0
		var y := -t * BEACON_HEIGHT
		var width := beam_width * (1.0 + t * 0.5)
		var alpha := beam_alpha * (1.0 - t * 0.7)
		var color := GLOW_COLOR
		color.a = alpha
		draw_line(Vector2(-width/2, y), Vector2(width/2, y), color, 4.0)
	
	# Central bright core of beam
	var core_color := PRIMARY_COLOR
	core_color.a = 0.4 + pulse * 0.2
	draw_line(Vector2.ZERO, Vector2(0, -BEACON_HEIGHT), core_color, 3.0)

func _draw_glow_rings(pulse: float) -> void:
	# Multiple expanding rings
	for i in range(4):
		var ring_pulse := fmod(_time * 0.5 + i * 0.25, 1.0)
		var radius := BOX_SIZE * (1.5 + ring_pulse * 2.0)
		var alpha := (1.0 - ring_pulse) * 0.4
		var color := GLOW_COLOR
		color.a = alpha
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 2.0)
	
	# Static glow around box
	var glow_size := BOX_SIZE * 1.8 + pulse * 10.0
	for i in range(5):
		var glow_alpha := 0.1 * (1.0 - float(i) / 5.0)
		var glow_radius := glow_size + i * 8.0
		var color := GLOW_COLOR
		color.a = glow_alpha
		draw_circle(Vector2.ZERO, glow_radius, color)

func _draw_hologram_box(pulse: float) -> void:
	# Draw 3D-ish holographic box frame
	var size := BOX_SIZE * pulse
	var depth := size * 0.4
	
	# Front face
	var front_color := PRIMARY_COLOR
	front_color.a = 0.8
	var front_rect := Rect2(-size/2, -size/2, size, size)
	draw_rect(front_rect, front_color, false, 2.0)
	
	# Diagonal lines to back face (3D effect)
	var back_offset := Vector2(depth * 0.5, -depth * 0.5)
	var corners := [
		Vector2(-size/2, -size/2),
		Vector2(size/2, -size/2),
		Vector2(size/2, size/2),
		Vector2(-size/2, size/2)
	]
	
	var line_color := SECONDARY_COLOR
	line_color.a = 0.5
	for corner in corners:
		draw_line(corner, corner + back_offset, line_color, 1.5)
	
	# Back face
	var back_color := SECONDARY_COLOR
	back_color.a = 0.4
	var back_rect := Rect2(-size/2 + back_offset.x, -size/2 + back_offset.y, size, size)
	draw_rect(back_rect, back_color, false, 1.5)
	
	# Cross pattern on front
	var cross_color := CORE_COLOR
	cross_color.a = 0.6
	draw_line(Vector2(-size/3, 0), Vector2(size/3, 0), cross_color, 1.5)
	draw_line(Vector2(0, -size/3), Vector2(0, size/3), cross_color, 1.5)

func _draw_data_streams() -> void:
	# Vertical data streams around the box
	for stream in _data_streams:
		var angle: float = stream.angle + _time * 0.3
		var radius := BOX_SIZE * 1.2
		var base_pos := Vector2.from_angle(angle) * radius
		
		# Draw multiple particles in the stream
		var particle_count := 5
		for i in range(particle_count):
			var t := fmod((_time * stream.speed + stream.offset + i * 15.0) / stream.height, 1.0)
			var y: float = -t * stream.height
			var alpha := sin(t * PI) * 0.7
			var color := DATA_COLOR
			color.a = alpha
			
			draw_circle(base_pos + Vector2(0, y), 2.0, color)

func _draw_data_symbols() -> void:
	# Floating binary/hex symbols
	var symbol_radius := BOX_SIZE * 2.0
	var symbols := ["0", "1", "//", "[]", "{}"]
	
	for i in range(6):
		var angle := (float(i) / 6.0) * TAU + _time * 0.2
		var bob := sin(_time * 2.0 + i) * 10.0
		var pos := Vector2.from_angle(angle) * symbol_radius + Vector2(0, bob - 20)
		var alpha := 0.4 + sin(_time * 3.0 + i * 0.5) * 0.2
		var color := DATA_COLOR
		color.a = alpha
		
		var symbol_idx := i % symbols.size()
		draw_string(ThemeDB.fallback_font, pos - Vector2(5, 0), symbols[symbol_idx], HORIZONTAL_ALIGNMENT_CENTER, -1, 10, color)

func _draw_core(pulse: float) -> void:
	# Bright center core
	var core_size := BOX_SIZE * 0.25 * pulse
	
	for i in range(8):
		var t := float(i) / 8.0
		var radius := core_size * (1.0 - t)
		var alpha := 0.8 - t * 0.5
		var color := CORE_COLOR.lerp(PRIMARY_COLOR, t)
		color.a = alpha
		draw_circle(Vector2.ZERO, radius, color)

func _draw_label() -> void:
	# Draw "INTEL" text above the box
	var label_pos := Vector2(-20, -BOX_SIZE - 20)
	var label_color := PRIMARY_COLOR
	label_color.a = 0.9
	draw_string(ThemeDB.fallback_font, label_pos, "INTEL", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, label_color)
	
	# Index number
	var index_pos := Vector2(-5, -BOX_SIZE - 5)
	var index_color := CORE_COLOR
	draw_string(ThemeDB.fallback_font, index_pos, str(intel_index + 1), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, index_color)

func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	
	if body.is_in_group("player"):
		_collect()

func _collect() -> void:
	_collected = true
	
	# Play collection effect
	_spawn_collection_effect()
	
	# Emit signal
	emit_signal("collected", intel_index)
	
	# Remove after effect
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(queue_free)

func _spawn_collection_effect() -> void:
	# Create expanding ring burst
	for i in range(12):
		var angle := (float(i) / 12.0) * TAU
		var particle := _create_particle(angle)
		get_parent().add_child(particle)

func _create_particle(angle: float) -> Node2D:
	var particle := Node2D.new()
	particle.global_position = global_position
	
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var velocity: Vector2
var lifetime: float = 0.5
var _time: float = 0.0
var color: Color

func _ready() -> void:
	z_index = 100

func _process(delta: float) -> void:
	_time += delta
	global_position += velocity * delta
	velocity *= 0.95
	if _time >= lifetime:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var alpha := 1.0 - (_time / lifetime)
	var draw_color := color
	draw_color.a = alpha
	draw_circle(Vector2.ZERO, 4.0, draw_color)
"""
	script.reload()
	particle.set_script(script)
	particle.set("velocity", Vector2.from_angle(angle) * 400.0)
	particle.set("color", PRIMARY_COLOR)
	return particle
