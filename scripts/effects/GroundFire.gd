extends Area2D
class_name GroundFire

# AOE damaging fire zone left on ground by explosions
# Visible, circular fire effect with good contrast

var radius: float = 100.0
var duration: float = 3.0
var damage_per_tick: int = 5
var color: Color = Color(1.0, 0.4, 0.2, 0.6)
var tick_interval: float = 0.5

var _age: float = 0.0
var _tick_timer: float = 0.0
var _collision_shape: CollisionShape2D

func _ready() -> void:
	# Setup collision shape
	_collision_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	_collision_shape.shape = shape
	add_child(_collision_shape)
	
	# Layer 0 (none), Mask 4 (Enemies/Hitboxes)
	collision_layer = 0
	collision_mask = 4
	# Use deferred to avoid "Function blocked during in/out signal" error
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)
	
	# Visuals - above grass (z~0) but below sprites (z~10+)
	z_as_relative = false
	z_index = 5
	
	# Use UNSHADED so it stays visible at night, but NORMAL blend (not additive)
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	modulate.a = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		_apply_damage()
	
	# Fade out near end of life
	if _age > duration * 0.7:
		modulate.a = lerpf(1.0, 0.0, (_age - duration * 0.7) / (duration * 0.3))
	
	# Throttle redraws for performance
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()

func _apply_damage() -> void:
	var overlap_bodies = get_overlapping_bodies()
	for body in overlap_bodies:
		if body.has_method("take_damage"):
			var dir = (body.global_position - global_position).normalized()
			body.take_damage(damage_per_tick, false, dir, false, "fire")
	
	var overlap_areas = get_overlapping_areas()
	for area in overlap_areas:
		var parent = area.get_parent()
		if parent and parent.has_method("take_damage") and not overlap_bodies.has(parent):
			var dir = (parent.global_position - global_position).normalized()
			parent.take_damage(damage_per_tick, false, dir, false, "fire")

func _draw() -> void:
	# Gentle pulse
	var pulse: float = 0.95 + 0.05 * sin(_age * 4.0)
	var current_radius: float = radius * pulse
	
	# Layer 1: Outer glow (semi-transparent orange)
	var outer_glow := Color(1.0, 0.4, 0.1, 0.35)
	draw_circle(Vector2.ZERO, current_radius * 1.15, outer_glow)
	
	# Layer 2: Main fire ring (solid orange-red)
	var main_color := Color(0.95, 0.35, 0.1, 0.9)
	draw_circle(Vector2.ZERO, current_radius, main_color)
	
	# Layer 3: Inner bright zone (orange-yellow)
	var inner_color := Color(1.0, 0.6, 0.2, 0.85)
	draw_circle(Vector2.ZERO, current_radius * 0.7, inner_color)
	
	# Layer 4: Hot center (bright orange-yellow)
	var core_pulse: float = 0.9 + 0.1 * sin(_age * 6.0)
	var core_color := Color(1.0, 0.75, 0.3, 0.8 * core_pulse)
	draw_circle(Vector2.ZERO, current_radius * 0.4, core_color)
	
	# Layer 5: Crisp border ring (dark red-orange for contrast)
	var border_color := Color(0.8, 0.2, 0.05, 1.0)
	_draw_ring(current_radius, border_color, 4.0)
	
	# Layer 6: Inner highlight ring
	var highlight_color := Color(1.0, 0.8, 0.4, 0.7)
	_draw_ring(current_radius * 0.7, highlight_color, 2.0)

func _draw_ring(ring_radius: float, ring_color: Color, width: float) -> void:
	var segments := 32
	var prev_pt := Vector2(ring_radius, 0)
	for i in range(1, segments + 1):
		var angle: float = (float(i) / segments) * TAU
		var pt := Vector2(cos(angle), sin(angle)) * ring_radius
		draw_line(prev_pt, pt, ring_color, width, true)
		prev_pt = pt
