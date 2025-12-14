extends Node2D
class_name ShielderShield

## Protective energy shield for Shielder enemy type
## Absorbs damage for all enemies within its radius
## Uses child Area2D for bullet collision detection

var owner_enemy: Node2D = null

# Shield stats
var shield_hp: int = 100
var max_shield_hp: int = 100
var shield_radius: float = 169.0

# Configuration
var color_theme: Color = Color(0.3, 0.6, 1.0)
var auto_regen: bool = true
var recharge_duration: float = 5.0
var bar_offset_y: float = -75.0
var bar_width: float = 90.0  # Configurable bar width
var bar_height: float = 16.0  # Configurable bar height
var draw_hp_bar: bool = true



# Signals
signal recharge_complete
signal shield_damaged(amount, source)

# Regeneration
var _regen_timer: float = 0.0
var _is_regenerating: bool = false
var _is_waiting_for_activation: bool = false # New state for manual activation

# Visual
var _pulse_time: float = 0.0
var _hit_flash: float = 0.0
var _shimmer_offset: float = 0.0
var _form_progress: float = 1.0

# Break effect
var _break_timer: float = 0.0
var _is_breaking: bool = false
var _crack_points: Array = []

# Active state
var _is_active: bool = true

# Collision
var _collision_area: Area2D = null


func initialize(enemy: Node2D, enemy_hp: int, hp_multiplier: float = 2.0, radius_override: float = -1.0) -> void:
	owner_enemy = enemy
	max_shield_hp = int(enemy_hp * hp_multiplier)
	shield_hp = max_shield_hp
	if radius_override > 0:
		shield_radius = radius_override
		# Update shape if already ready
		if _collision_area and _collision_area.get_child_count() > 0:
			var shape = _collision_area.get_child(0).shape as CircleShape2D
			if shape: shape.radius = shield_radius

func deactivate_initially() -> void:
	_is_active = false
	shield_hp = 0
	_form_progress = 0.0
	_is_regenerating = true # Start in recharge mode? Or just off?
	# "Don't start with shield" -> means starts effectively broken/on cooldown or just ready?
	# "deploy it randomly" -> implies it is ready to deploy.
	# So we set _is_regenerating = false, _is_active = false, _is_waiting_for_activation = true
	_is_regenerating = false
	_is_waiting_for_activation = true
	if _collision_area and _collision_area.get_child_count() > 0:
		_collision_area.get_child(0).set_deferred("disabled", true)
	emit_signal("recharge_complete") # Immediately ready

func activate() -> void:
	if _is_waiting_for_activation:
		_start_reforming()

func _ready() -> void:
	z_index = 35
	add_to_group("shielder_shields")
	add_to_group("boss_shields")  # For explosion collision detection
	
	# Fix for Night Mode: Use unshaded material to ignore CanvasModulate darkening
	var mat = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Create collision Area2D as child
	_collision_area = Area2D.new()
	_collision_area.name = "ShieldCollision"
	# Layer 1 = World/Default (Guaranteed detection)
	_collision_area.collision_layer = 1
	_collision_area.collision_mask = 4  # Projectiles
	add_child(_collision_area)
	
	# Add collision shape
	var collision_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = shield_radius
	collision_shape.shape = circle_shape
	_collision_area.add_child(collision_shape)
	
	# Connect signals
	_collision_area.area_entered.connect(_on_area_entered)
	_collision_area.body_entered.connect(_on_body_entered)


func _on_area_entered(area: Area2D) -> void:
	if not _is_active:
		return
	_handle_projectile_hit(area)


func _on_body_entered(body: Node2D) -> void:
	if not _is_active:
		return
	_handle_projectile_hit(body)


func _handle_projectile_hit(projectile: Node2D) -> void:
	# Skip enemy projectiles (boss missiles, etc) - shields shouldn't block own team
	if projectile.is_in_group("enemy_projectiles"):
		return
	
	# Check if it's a projectile
	if not projectile.is_in_group("player_projectiles") and not projectile.is_in_group("projectiles"):
		if not ("velocity" in projectile or "damage" in projectile or "base_damage" in projectile):
			return
	
	# Get damage
	var damage := 1
	if "base_damage" in projectile:
		damage = projectile.base_damage
	elif "damage" in projectile:
		damage = projectile.damage
	
	# Try to identify source from projectile/area
	var src: String = "projectile"
	
	# Check properties directly on the collider first
	if projectile.get("killer_source"):
		src = projectile.killer_source
	elif projectile.has_method("get_source"):
		src = projectile.get_source()
	elif "source" in projectile:
		src = projectile.source
	else:
		# Check parent (e.g. Area2D child of a Beam node)
		var parent = projectile.get_parent()
		if parent:
			if parent.get("killer_source"):
				src = parent.killer_source
			elif parent.has_method("get_source"):
				src = parent.get_source()
			elif "source" in parent:
				src = parent.source
	
	take_shield_damage(damage, src)
	
	# Destroy projectile
	if projectile.has_method("queue_free"):
		projectile.queue_free()


func _process(delta: float) -> void:
	if owner_enemy and is_instance_valid(owner_enemy):
		global_position = owner_enemy.global_position
	else:
		queue_free()
		return
	
	# Regeneration
	if _is_regenerating:
		_regen_timer += delta
		if _regen_timer >= recharge_duration:
			if auto_regen:
				_start_reforming()
			else:
				# Complete recharge but don't activate yet
				_is_regenerating = false
				_is_waiting_for_activation = true
				recharge_complete.emit()
				
	# Forming animation
	if _form_progress < 1.0 and _is_active:
		_form_progress += delta * 2.0
		if _form_progress >= 1.0:
			_form_progress = 1.0
			_collision_area.get_child(0).set_deferred("disabled", false)
	
	# Break effect
	if _is_breaking:
		_break_timer += delta
		if _break_timer >= 0.5:
			_is_breaking = false
			_start_regeneration()
		queue_redraw()
		return
	
	if not _is_active:
		queue_redraw()
		return
	
	_pulse_time += delta
	_shimmer_offset += delta * 1.5
	
	if _hit_flash > 0:
		_hit_flash -= delta * 3.0
	
	queue_redraw()


func _start_regeneration() -> void:
	_is_regenerating = true
	_is_waiting_for_activation = false
	_regen_timer = 0.0
	_collision_area.get_child(0).set_deferred("disabled", true)


func _start_reforming() -> void:
	_is_regenerating = false
	_is_active = true
	shield_hp = max_shield_hp
	_form_progress = 0.0
	_crack_points.clear()


func take_shield_damage(amount: int, source: String = "unknown") -> void:
	if not _is_active:
		return
		
	shield_hp -= amount
	
	# Visual feedback
	# _play_hit_effect() # This function is not defined in the provided code.
	
	# Emit signal using the source
	shield_damaged.emit(amount, source)
	_hit_flash = 1.0
	_generate_cracks()
	
	if shield_hp <= 0:
		shield_hp = 0
		_is_breaking = true
		_break_timer = 0.0
		_is_active = false
		_collision_area.get_child(0).set_deferred("disabled", true)


func is_active() -> bool:
	return _is_active and shield_hp > 0


func is_point_inside(point: Vector2) -> bool:
	if not _is_active:
		return false
	return global_position.distance_to(point) <= shield_radius


func protects_owner() -> bool:
	return _is_active and shield_hp > 0


func get_shield_hp_ratio() -> float:
	if max_shield_hp <= 0:
		return 0.0
	return float(shield_hp) / float(max_shield_hp)


func _generate_cracks() -> void:
	_crack_points.clear()
	for _i in range(randi_range(2, 4)):
		var angle := randf() * TAU
		var start_pos := Vector2(cos(angle), sin(angle)) * shield_radius
		var crack := {"start": start_pos, "segments": []}
		var current := start_pos
		var toward := -start_pos.normalized()
		for _j in range(randi_range(2, 4)):
			var jitter := Vector2(randf_range(-30, 30), randf_range(-30, 30))
			var next := current + toward * randf_range(20, 50) + jitter
			crack["segments"].append({"from": current, "to": next})
			current = next
		_crack_points.append(crack)


func _draw() -> void:
	# Break effect - use color_theme instead of hardcoded blue
	if _is_breaking:
		var alpha := 1.0 - (_break_timer / 0.5)
		var radius := shield_radius * (1.0 + _break_timer * 0.3)
		# Use theme color for shatter effect
		var c_arc = color_theme; c_arc.a = alpha * 0.8
		var c_crack = color_theme.lightened(0.4); c_crack.a = alpha * 0.9
		var c_particle = color_theme.lightened(0.2); c_particle.a = alpha * 0.7
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, c_arc, 5.0)
		for crack in _crack_points:
			for seg in crack["segments"]:
				draw_line(seg["from"], seg["to"], c_crack, 3.0)
		for i in range(12):
			var a := (TAU / 12.0) * i + _break_timer * 2.0
			var pos := Vector2(cos(a), sin(a)) * (radius + _break_timer * 150)
			draw_circle(pos, 6.0 * alpha, c_particle)
		return
	
	# Regenerating
	if _is_regenerating:
		var progress := _regen_timer / maxf(recharge_duration, 0.1)
		var pulse := sin(_regen_timer * 3.0) * 0.1 + 0.2
		draw_arc(Vector2.ZERO, shield_radius, 0, TAU, 64, Color(color_theme.r, color_theme.g, color_theme.b, pulse * progress), 2.0)
		return
	
	if not _is_active:
		return
	
	var form := _form_progress
	var pulse := sin(_pulse_time * 2.0) * 0.05 + 1.0
	var radius := shield_radius * pulse * form
	var hp := get_shield_hp_ratio()
	var alpha := (0.4 + hp * 0.3) * form
	var flash := _hit_flash * 0.3
	
	# Colors derived from theme
	var c_base = color_theme
	var c_glow1 = c_base.darkened(0.1); c_glow1.a = (0.1 + flash * 0.1) * form
	var c_glow2 = c_base; c_glow2.a = (0.15 + flash * 0.1) * form
	var c_glow3 = c_base.lightened(0.1); c_glow3.a = (0.25 + flash * 0.15) * form
	
	var c_bubble_outer = c_base.lightened(0.2); c_bubble_outer.a = alpha + flash
	var c_bubble_fill = c_base.lightened(0.05); c_bubble_fill.a = (0.15 + hp * 0.1 + flash * 0.1) * form
	var c_bubble_inner = c_base.lightened(0.4); c_bubble_inner.a = (0.4 + flash * 0.2) * form
	
	# Glow layers
	draw_arc(Vector2.ZERO, radius + 30, 0, TAU, 64, c_glow1, 25.0)
	draw_arc(Vector2.ZERO, radius + 15, 0, TAU, 64, c_glow2, 15.0)
	draw_arc(Vector2.ZERO, radius + 6, 0, TAU, 64, c_glow3, 8.0)
	
	# Main bubble
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, c_bubble_outer, 4.0)
	draw_circle(Vector2.ZERO, radius, c_bubble_fill)
	draw_arc(Vector2.ZERO, radius - 4, 0, TAU, 64, c_bubble_inner, 2.0)
	
	# Shimmer
	var shimmer_a := (0.3 + sin(_shimmer_offset * 1.5) * 0.15) * form
	var shimmer_s := fmod(_shimmer_offset, TAU)
	draw_arc(Vector2.ZERO, radius - 3, shimmer_s, shimmer_s + PI * 0.3, 24, Color(0.9, 1.0, 1.0, shimmer_a), 5.0)
	draw_arc(Vector2.ZERO, radius - 3, shimmer_s + PI, shimmer_s + PI * 1.3, 24, Color(0.9, 1.0, 1.0, shimmer_a), 5.0)
	
	# Cracks
	if _hit_flash > 0 and _crack_points.size() > 0:
		for crack in _crack_points:
			for seg in crack["segments"]:
				draw_line(seg["from"], seg["to"], Color(1.0, 1.0, 1.0, _hit_flash * 0.8), 2.0)
	
	if draw_hp_bar:
		# Shield HP bar above enemy - use configurable dimensions
		var bar_w := bar_width
		var bar_h := bar_height
		var bar_y := bar_offset_y
		var bar_pos := Vector2(-bar_w / 2, bar_y)
		
		# Theme colors for bar
		var c_bar_fill = color_theme.lightened(0.1); c_bar_fill.a = 0.9 * form
		var c_bar_border = color_theme.lightened(0.3); c_bar_border.a = 0.9 * form
		
		# Background
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.05, 0.1, 0.2, 0.9 * form))
		# Fill
		draw_rect(Rect2(bar_pos, Vector2(bar_w * hp, bar_h)), c_bar_fill)
		# Border
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), c_bar_border, false, 2.0)
		
		# Counter text (centered in bar) - use inverse scale for crisp text
		var parent_scale: float = 1.0
		if owner_enemy and is_instance_valid(owner_enemy):
			parent_scale = max(abs(owner_enemy.scale.x), 0.1)
		var font = ThemeDB.fallback_font
		var font_size := int(8 * parent_scale)  # Scale font with parent
		var text := "%d/%d" % [shield_hp, max_shield_hp]
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		# Divide by parent scale to counter-act the parent's scaling transform
		var text_pos := Vector2(-text_size.x / 2 / parent_scale, bar_y + bar_h / 2 + text_size.y / 4 / parent_scale)
		
		# Apply inverse scale transform for text drawing
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE / parent_scale)
		# Text shadow
		var scaled_text_pos = text_pos * parent_scale  # Adjust for inverse transform
		draw_string(font, scaled_text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.0, 0.0, 0.0, 0.8 * form))
		# Text
		draw_string(font, scaled_text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1.0, 1.0, 1.0, form))
		# Reset transform
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


