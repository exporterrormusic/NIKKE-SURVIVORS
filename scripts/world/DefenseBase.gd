extends Node2D
class_name DefenseBase
## ARK defense barrier at top of map for Defense mode.
## Rectangle shape filling half the top, with collision blocking player and enemies.

signal damaged(current_health: int, max_health: int)
signal destroyed()

const MAX_HEALTH := 9999
const ARK_DEPTH := 300.0  # How tall (deep) the ARK is
const ARK_WIDTH := 2000.0  # Width of the ARK (half screen width)

# Visual colors
const METAL_COLOR := Color(0.25, 0.28, 0.32, 1.0)
const METAL_DARK := Color(0.15, 0.17, 0.2, 1.0)
const METAL_LIGHT := Color(0.35, 0.38, 0.42, 1.0)
const GLOW_COLOR := Color(0.2, 0.6, 1.0, 0.8)
const DAMAGE_GLOW := Color(1.0, 0.3, 0.2, 0.8)
const BORDER_COLOR := Color(0.4, 0.45, 0.5, 1.0)

var current_health: int = MAX_HEALTH
var _ark_size: Vector2 = Vector2(ARK_WIDTH, ARK_DEPTH)
var _time := 0.0
var _damage_flash := 0.0

# Collision for blocking
var _static_body: StaticBody2D = null
var _damage_area: Area2D = null

func _ready() -> void:
	_setup_collision()
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	if _damage_flash > 0:
		_damage_flash -= delta * 2.0
	queue_redraw()

func initialize(ark_width: float, ark_depth: float) -> void:
	_ark_size = Vector2(ark_width, ark_depth)
	_setup_collision()

func _setup_collision() -> void:
	# Remove existing collision
	if _static_body:
		_static_body.queue_free()
	if _damage_area:
		_damage_area.queue_free()
	
	# Create StaticBody2D to block player and enemies
	_static_body = StaticBody2D.new()
	_static_body.name = "ArkCollision"
	_static_body.collision_layer = 1 + 4  # Player layer + base layer
	_static_body.collision_mask = 1 + 2   # Player + enemy layers
	add_child(_static_body)
	
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _ark_size
	shape.shape = rect
	shape.position = Vector2.ZERO
	_static_body.add_child(shape)
	
	# Create Area2D for enemy damage detection (at the front of the ARK)
	_damage_area = Area2D.new()
	_damage_area.name = "DamageArea"
	_damage_area.collision_layer = 4  # Base layer
	_damage_area.collision_mask = 2   # Enemy layer
	add_child(_damage_area)
	
	var damage_shape := CollisionShape2D.new()
	var damage_rect := RectangleShape2D.new()
	damage_rect.size = Vector2(_ark_size.x, 50)  # Thin damage zone at front
	damage_shape.shape = damage_rect
	damage_shape.position = Vector2(0, _ark_size.y / 2 + 25)  # Below the ARK
	_damage_area.add_child(damage_shape)
	
	_damage_area.body_entered.connect(_on_body_entered)

func _draw() -> void:
	var half_width := _ark_size.x / 2.0
	var half_height := _ark_size.y / 2.0
	var pulse := sin(_time * 2.0) * 0.1 + 0.9
	var health_ratio := float(current_health) / float(MAX_HEALTH)
	
	# === MAIN ARK BODY ===
	var ark_rect := Rect2(-half_width, -half_height, _ark_size.x, _ark_size.y)
	
	# Main metal panel
	draw_rect(ark_rect, METAL_COLOR)
	
	# Dark edge borders
	draw_rect(Rect2(-half_width, -half_height, 6, _ark_size.y), METAL_DARK)  # Left
	draw_rect(Rect2(half_width - 6, -half_height, 6, _ark_size.y), METAL_DARK)  # Right
	draw_rect(Rect2(-half_width, -half_height, _ark_size.x, 6), METAL_DARK)  # Top
	draw_rect(Rect2(-half_width, half_height - 10, _ark_size.x, 10), METAL_DARK)  # Bottom (thicker)
	
	# Horizontal panel lines (riveted sections)
	var section_width := 200.0
	var sections := int(_ark_size.x / section_width)
	for i in range(sections + 1):
		var x := -half_width + i * section_width
		draw_line(Vector2(x, -half_height + 10), Vector2(x, half_height - 10), METAL_DARK, 2.0)
	
	# Glowing tech lines at bottom edge
	var glow := GLOW_COLOR
	glow.a = 0.5 * pulse
	draw_line(Vector2(-half_width + 20, half_height - 15), Vector2(half_width - 20, half_height - 15), glow, 3.0)
	
	# === ARK LABEL ===
	var label_color := GLOW_COLOR
	label_color.a = 0.9 * pulse
	var label_pos := Vector2(-30, 0)
	draw_string(ThemeDB.fallback_font, label_pos, "ARK", HORIZONTAL_ALIGNMENT_CENTER, -1, 48, label_color)
	
	# === HEALTH BAR (at bottom of ARK) ===
	_draw_health_bar(health_ratio, pulse)
	
	# === DAMAGE FLASH OVERLAY ===
	if _damage_flash > 0:
		var flash_color := DAMAGE_GLOW
		flash_color.a = _damage_flash * 0.4
		draw_rect(ark_rect, flash_color)
	
	# === WARNING STRIPES at edges ===
	var stripe_color := Color(0.9, 0.6, 0.1, 0.7)
	for i in range(int(_ark_size.x / 100)):
		var x := -half_width + 50 + i * 100
		draw_line(Vector2(x, half_height - 8), Vector2(x + 20, half_height - 8), stripe_color, 4.0)

func _draw_health_bar(health_ratio: float, pulse: float) -> void:
	var half_width := _ark_size.x / 2.0
	var bar_width := _ark_size.x - 40
	var bar_height := 12.0
	var bar_pos := Vector2(-bar_width / 2, _ark_size.y / 2 - 35)
	
	# Background
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), METAL_DARK)
	
	# Health fill
	var health_color := Color.GREEN.lerp(Color.RED, 1.0 - health_ratio)
	health_color.a = 0.9 * pulse
	draw_rect(Rect2(bar_pos, Vector2(bar_width * health_ratio, bar_height)), health_color)
	
	# Border
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), BORDER_COLOR, false, 2.0)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies"):
		# Enemy reached the ARK - deal damage based on enemy type
		var damage := 10
		if body.has_method("get_damage_to_base"):
			damage = body.get_damage_to_base()
		elif body.is_in_group("boss_enemies"):
			damage = 50
		elif body.is_in_group("super_boss_enemies"):
			damage = 100
		
		take_damage(damage)
		
		# Destroy the enemy that reached ARK
		if body.has_method("die"):
			body.die()
		else:
			body.queue_free()

func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)
	_damage_flash = 1.0
	emit_signal("damaged", current_health, MAX_HEALTH)
	
	if current_health <= 0:
		emit_signal("destroyed")

func heal(amount: int) -> void:
	current_health = min(MAX_HEALTH, current_health + amount)

func get_health_ratio() -> float:
	return float(current_health) / float(MAX_HEALTH)
