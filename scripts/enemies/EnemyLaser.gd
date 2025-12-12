extends Area2D

# Enemy laser beam projectile with glowing red visual
# Pulsing Energy Beam style with flickering core, trail particles, and charging effect

# Configuration
@export var speed := 500.0
@export var damage := 1
@export var max_range := 600.0
@export var lifetime := 1.5

# Visual parameters - DARK RED (compensates for daylight brightness)
const LASER_COLOR := Color(0.85, 0.0, 0.05, 1.0)  # Dark blood red
const LASER_COLOR_HOT := Color(0.9, 0.0, 0.0, 1.0)  # Dark crimson
const GLOW_COLOR := Color(0.8, 0.0, 0.0, 0.85)   # Dark red glow
const CORE_COLOR := Color(0.9, 0.15, 0.15, 1.0)   # Darker pinkish core
const CORE_COLOR_PULSE := Color(0.85, 0.1, 0.1, 1.0)  # Dark pulsing core
const TRAIL_COLOR := Color(0.8, 0.0, 0.0, 0.8)   # Dark red trail
const BEAM_LENGTH := 50.0
const BEAM_WIDTH := 8.0
const GLOW_RADIUS := 32.0

# Animation parameters
const PULSE_SPEED := 18.0           # Core flicker speed
const PULSE_INTENSITY := 0.35       # How much the core brightness varies
const TRAIL_SPAWN_INTERVAL := 0.02  # Seconds between trail particles
const TRAIL_PARTICLE_COUNT := 8     # Max trail particles
const CHARGE_DURATION := 0.08       # Brief charging flash at spawn
const SHIMMER_SPEED := 25.0         # Heat shimmer oscillation speed
const SHIMMER_AMOUNT := 1.5         # Pixels of shimmer offset

var _direction: Vector2 = Vector2.RIGHT
var _age := 0.0
var _distance_travelled := 0.0
var _is_retired := false
var _hit_targets: Dictionary = {}
var _rng := RandomNumberGenerator.new()

# Visual components
var _beam_polygon: Polygon2D = null
var _beam_outer_glow: Polygon2D = null
var _glow_sprite: Sprite2D = null
var _tip_glow: Sprite2D = null
var _core_line: Line2D = null
var _charge_flash: Sprite2D = null

# Trail system
var _trail_particles: Array = []
var _trail_timer := 0.0
var _last_position: Vector2 = Vector2.ZERO

# Cached textures
var _glow_texture: Texture2D = null

# Environment compensation
var _environment_controller: Node = null

func _ready() -> void:
	z_as_relative = false
	z_index = 900
	_rng.randomize()
	
	# Setup collision
	collision_layer = 8   # Enemy projectile layer
	collision_mask = 1 | 2 | 8   # Hit player (1), enemies for charmed (2), ally layer (8)
	monitoring = true
	monitorable = false
	
	# Create collision shape
	var collision_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(BEAM_LENGTH, BEAM_WIDTH)
	collision_shape.shape = shape
	collision_shape.position = _direction * (BEAM_LENGTH * 0.5)
	collision_shape.rotation = _direction.angle()
	add_child(collision_shape)
	
	# Cache glow texture
	_glow_texture = _create_radial_glow_texture(64)
	
	# Create visuals
	_create_visuals()
	
	# Store initial position for trail
	_last_position = global_position
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Spawn charging flash effect
	_spawn_charge_effect()
	
	# Assign to effects layer so laser glows at night
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			# Save position before reparenting
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 900

func set_direction(dir: Vector2) -> void:
	if dir.length() == 0.0:
		_direction = Vector2.RIGHT
	else:
		_direction = dir.normalized()
	rotation = _direction.angle()

func _create_visuals() -> void:
	# Extra outer glow (very large, soft ambient)
	var ambient_glow := Sprite2D.new()
	ambient_glow.texture = _glow_texture
	ambient_glow.centered = true
	ambient_glow.modulate = Color(0.8, 0.0, 0.0, 0.4)  # Dark red ambient
	ambient_glow.scale = Vector2(2.0, 1.2)
	ambient_glow.position = Vector2(BEAM_LENGTH * 0.5, 0)
	var ambient_mat := CanvasItemMaterial.new()
	ambient_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ambient_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	ambient_glow.material = ambient_mat
	ambient_glow.z_index = 896
	add_child(ambient_glow)
	
	# Second ambient layer
	var ambient_glow2 := Sprite2D.new()
	ambient_glow2.texture = _glow_texture
	ambient_glow2.centered = true
	ambient_glow2.modulate = Color(0.75, 0.0, 0.0, 0.3)  # Darker red
	ambient_glow2.scale = Vector2(2.5, 1.5)
	ambient_glow2.position = Vector2(BEAM_LENGTH * 0.5, 0)
	var ambient_mat2 := CanvasItemMaterial.new()
	ambient_mat2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ambient_mat2.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	ambient_glow2.material = ambient_mat2
	ambient_glow2.z_index = 895
	add_child(ambient_glow2)
	
	# Outer glow polygon (larger, softer)
	_beam_outer_glow = Polygon2D.new()
	_beam_outer_glow.color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.5)
	_beam_outer_glow.antialiased = true
	_beam_outer_glow.z_index = 898
	var outer_mat := CanvasItemMaterial.new()
	outer_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	outer_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_beam_outer_glow.material = outer_mat
	add_child(_beam_outer_glow)
	_update_outer_glow_polygon()
	
	# Main glow sprite (ambient light)
	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = _glow_texture
	_glow_sprite.centered = true
	_glow_sprite.modulate = Color(0.85, 0.0, 0.0, 0.9)  # Dark red glow
	_glow_sprite.scale = Vector2(1.4, 0.8)
	_glow_sprite.position = Vector2(BEAM_LENGTH * 0.5, 0)
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow_sprite.material = glow_material
	_glow_sprite.z_index = 899
	add_child(_glow_sprite)
	
	# Main beam polygon (diamond shape)
	_beam_polygon = Polygon2D.new()
	_beam_polygon.color = LASER_COLOR
	_beam_polygon.antialiased = true
	_beam_polygon.z_index = 900
	var core_mat := CanvasItemMaterial.new()
	core_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	core_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_beam_polygon.material = core_mat
	add_child(_beam_polygon)
	_update_beam_polygon()
	
	# Core line (bright flickering center)
	_core_line = Line2D.new()
	_core_line.width = BEAM_WIDTH * 0.5
	_core_line.default_color = CORE_COLOR
	_core_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_core_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_core_line.z_index = 901
	_core_line.material = core_mat # Reuse unshaded material
	add_child(_core_line)
	_update_core_line()
	
	# Tip glow (bright front) - intense red
	_tip_glow = Sprite2D.new()
	_tip_glow.texture = _glow_texture
	_tip_glow.centered = true
	_tip_glow.modulate = Color(0.9, 0.05, 0.05, 1.0)  # Dark red tip
	_tip_glow.scale = Vector2(0.6, 0.6)
	var tip_material := CanvasItemMaterial.new()
	tip_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tip_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_tip_glow.material = tip_material
	_tip_glow.position = Vector2(BEAM_LENGTH, 0)
	_tip_glow.z_index = 902
	add_child(_tip_glow)
	
	# Extra tip glow layer for more intensity
	var tip_glow2 := Sprite2D.new()
	tip_glow2.texture = _glow_texture
	tip_glow2.centered = true
	tip_glow2.modulate = Color(0.8, 0.0, 0.0, 0.7)  # Dark red tip
	tip_glow2.scale = Vector2(0.9, 0.9)
	var tip_mat2 := CanvasItemMaterial.new()
	tip_mat2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tip_mat2.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	tip_glow2.material = tip_mat2
	tip_glow2.position = Vector2(BEAM_LENGTH, 0)
	tip_glow2.z_index = 901
	add_child(tip_glow2)

func _update_beam_polygon() -> void:
	if not _beam_polygon:
		return
	
	# Diamond shape for laser beam
	var half_width := BEAM_WIDTH * 0.5
	var neck := BEAM_LENGTH * 0.15
	var mid := BEAM_LENGTH * 0.5
	var tip := BEAM_LENGTH * 0.85
	
	_beam_polygon.polygon = PackedVector2Array([
		Vector2(-2, 0),                         # Slight back extension
		Vector2(neck, half_width),              # Upper neck
		Vector2(mid, half_width * 0.9),         # Upper mid (slight bulge)
		Vector2(tip, half_width * 0.5),         # Upper tip approach
		Vector2(BEAM_LENGTH + 2, 0),            # Tip (front point, extended)
		Vector2(tip, -half_width * 0.5),        # Lower tip approach
		Vector2(mid, -half_width * 0.9),        # Lower mid
		Vector2(neck, -half_width)              # Lower neck
	])

func _update_outer_glow_polygon() -> void:
	if not _beam_outer_glow:
		return
	
	# Larger, softer outer glow
	var half_width := BEAM_WIDTH * 1.2
	var neck := BEAM_LENGTH * 0.1
	var tip := BEAM_LENGTH * 0.9
	
	_beam_outer_glow.polygon = PackedVector2Array([
		Vector2(-8, 0),
		Vector2(neck, half_width),
		Vector2(tip, half_width * 0.6),
		Vector2(BEAM_LENGTH + 8, 0),
		Vector2(tip, -half_width * 0.6),
		Vector2(neck, -half_width)
	])

func _update_core_line() -> void:
	if not _core_line:
		return
	_core_line.points = PackedVector2Array([
		Vector2(2, 0),
		Vector2(BEAM_LENGTH - 2, 0)
	])

func _spawn_charge_effect() -> void:
	# Brief expanding flash when laser spawns
	_charge_flash = Sprite2D.new()
	_charge_flash.texture = _glow_texture
	_charge_flash.centered = true
	_charge_flash.modulate = Color(0.9, 0.3, 0.25, 1.0)  # Dark reddish charge
	_charge_flash.scale = Vector2(0.3, 0.3)
	var flash_mat := CanvasItemMaterial.new()
	flash_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_charge_flash.material = flash_mat
	_charge_flash.z_index = 903
	add_child(_charge_flash)
	
	# Animate the charge flash
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_charge_flash, "scale", Vector2(0.8, 0.8), CHARGE_DURATION)
	tween.tween_property(_charge_flash, "modulate:a", 0.0, CHARGE_DURATION)
	tween.set_parallel(false)
	tween.tween_callback(_charge_flash.queue_free)

func _physics_process(delta: float) -> void:
	if _is_retired:
		return
	
	# Move laser
	var displacement := _direction * speed * delta
	global_position += displacement
	_distance_travelled += displacement.length()
	_age += delta
	
	# Check boulder collision (reparenting to EffectsLayer breaks Area2D overlap)
	if _check_boulder_collision():
		_retire()
		return
	
	# Update trail particles
	_update_trail(delta)
	
	# Pulsing/flickering effects
	_update_pulse_effects()
	
	# Heat shimmer effect on beam
	_update_shimmer()
	
	# Check lifetime and range
	if _age >= lifetime or _distance_travelled >= max_range:
		_retire()
	
	_last_position = global_position

func _check_boulder_collision() -> bool:
	"""Manual boulder collision check since lasers are in EffectsLayer (different scene tree branch)."""
	var boulders := get_tree().get_nodes_in_group("boulders")
	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = boulder.boulder_size * 0.5 if "boulder_size" in boulder else 150.0
		if global_position.distance_to(boulder_pos) < boulder_radius:
			return true
	return false


func _update_pulse_effects() -> void:
	# Multi-frequency pulse for organic flickering
	var pulse1 := sin(_age * PULSE_SPEED) * 0.5 + 0.5
	var pulse2 := sin(_age * PULSE_SPEED * 1.7 + 1.3) * 0.5 + 0.5
	var pulse3 := sin(_age * PULSE_SPEED * 0.6 + 2.7) * 0.5 + 0.5
	var combined_pulse := (pulse1 * 0.5 + pulse2 * 0.3 + pulse3 * 0.2)
	
	# Random flicker spikes
	var flicker := 1.0
	if _rng.randf() < 0.08:
		flicker = _rng.randf_range(0.7, 1.3)
	
	var intensity := (1.0 - PULSE_INTENSITY) + combined_pulse * PULSE_INTENSITY * flicker
	
	# Core line pulses in brightness and width
	if _core_line:
		var core_brightness := clampf(intensity * 1.2, 0.6, 1.0)
		_core_line.default_color = CORE_COLOR.lerp(CORE_COLOR_PULSE, 1.0 - combined_pulse)
		_core_line.default_color.a = core_brightness
		_core_line.width = BEAM_WIDTH * (0.4 + combined_pulse * 0.15)
	
	# Beam polygon color shifts between red and orange-red
	if _beam_polygon:
		_beam_polygon.color = LASER_COLOR.lerp(LASER_COLOR_HOT, combined_pulse * 0.4)
	
	# Outer glow pulses
	if _beam_outer_glow:
		_beam_outer_glow.color.a = 0.2 + combined_pulse * 0.15
	
	# Main glow sprite pulses
	if _glow_sprite:
		_glow_sprite.modulate.a = GLOW_COLOR.a * (0.7 + combined_pulse * 0.4)
		_glow_sprite.scale = Vector2(0.9 + combined_pulse * 0.2, 0.5 + combined_pulse * 0.15)
	
	# Tip glow pulses more intensely
	if _tip_glow:
		_tip_glow.modulate.a = 0.7 + combined_pulse * 0.3
		_tip_glow.scale = Vector2.ONE * (0.35 + combined_pulse * 0.1)

func _update_shimmer() -> void:
	# Subtle heat shimmer - offset the core line slightly
	if _core_line:
		var shimmer_offset := sin(_age * SHIMMER_SPEED) * SHIMMER_AMOUNT
		var shimmer_offset2 := cos(_age * SHIMMER_SPEED * 1.3) * SHIMMER_AMOUNT * 0.5
		_core_line.points = PackedVector2Array([
			Vector2(2, shimmer_offset2),
			Vector2(BEAM_LENGTH * 0.5, shimmer_offset),
			Vector2(BEAM_LENGTH - 2, -shimmer_offset2)
		])

func _update_trail(delta: float) -> void:
	_trail_timer += delta
	
	# Spawn new trail particles
	if _trail_timer >= TRAIL_SPAWN_INTERVAL:
		_trail_timer = 0.0
		_spawn_trail_particle()
	
	# Update existing trail particles
	for i in range(_trail_particles.size() - 1, -1, -1):
		var particle: Dictionary = _trail_particles[i]
		particle["age"] += delta
		particle["alpha"] = clampf(1.0 - (particle["age"] / particle["lifetime"]), 0.0, 1.0)
		particle["scale"] *= 0.96  # Shrink over time
		
		if particle["age"] >= particle["lifetime"]:
			if particle["node"] and is_instance_valid(particle["node"]):
				particle["node"].queue_free()
			_trail_particles.remove_at(i)
		else:
			# Update visual
			if particle["node"] and is_instance_valid(particle["node"]):
				particle["node"].modulate.a = particle["alpha"] * 0.6
				particle["node"].scale = Vector2.ONE * particle["scale"]
			_trail_particles[i] = particle

func _spawn_trail_particle() -> void:
	if _trail_particles.size() >= TRAIL_PARTICLE_COUNT:
		return
	
	var particle_sprite := Sprite2D.new()
	particle_sprite.texture = _glow_texture
	particle_sprite.centered = true
	
	# Randomize particle appearance
	var base_scale := _rng.randf_range(0.15, 0.25)
	particle_sprite.scale = Vector2.ONE * base_scale
	
	# Color varies slightly
	var color_shift := _rng.randf_range(-0.1, 0.1)
	particle_sprite.modulate = Color(
		TRAIL_COLOR.r + color_shift,
		TRAIL_COLOR.g + color_shift * 0.5,
		TRAIL_COLOR.b,
		TRAIL_COLOR.a
	)
	
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	particle_sprite.material = mat
	particle_sprite.z_index = 897
	
	# Position at back of beam with slight random offset
	var offset := Vector2(
		_rng.randf_range(-5, 0),
		_rng.randf_range(-BEAM_WIDTH * 0.4, BEAM_WIDTH * 0.4)
	).rotated(rotation)
	particle_sprite.global_position = global_position + offset
	
	if get_parent():
		get_parent().add_child(particle_sprite)
		
		_trail_particles.append({
			"node": particle_sprite,
			"age": 0.0,
			"lifetime": _rng.randf_range(0.15, 0.3),
			"alpha": 1.0,
			"scale": base_scale
		})

func _on_body_entered(body: Node) -> void:
	_apply_damage_to(body)

func _on_area_entered(area: Area2D) -> void:
	_apply_damage_to(area)

func _apply_damage_to(target: Node) -> void:
	if _is_retired:
		return
	if not is_instance_valid(target):
		return
	
	var instance_id := target.get_instance_id()
	if _hit_targets.has(instance_id):
		return
	_hit_targets[instance_id] = true
	
	# Check if this laser was fired by a charmed enemy
	var from_charmed: bool = has_meta("from_charmed") and get_meta("from_charmed")
	
	if from_charmed:
		# Charmed enemy laser: hit non-charmed enemies, skip player and charmed allies
		if target.is_in_group("charmed_allies"):
			return  # Don't hit other charmed allies
		if target.is_in_group("player") or target.name == "Player":
			return  # Don't hit the player
		# Hit regular enemies - pass "charmed_enemy" as killer source (no burst/shield charge)
		if target.is_in_group("enemies") and target.has_method("take_damage"):
			target.take_damage(damage, false, Vector2.ZERO, false, "charmed_enemy")
			_retire()
			return
	else:
		# Normal enemy laser: skip non-charmed enemies (enemy lasers shouldn't hurt regular enemies)
		if target.is_in_group("enemies") and not target.is_in_group("charmed_allies"):
			return
	
	# Apply damage to valid targets
	if target.has_method("take_damage"):
		target.take_damage(damage)
		_retire()
	elif target.has_method("apply_damage"):
		target.apply_damage(damage)
		_retire()

func _retire() -> void:
	if _is_retired:
		return
	_is_retired = true
	
	# Clean up trail particles
	for particle in _trail_particles:
		if particle["node"] and is_instance_valid(particle["node"]):
			particle["node"].queue_free()
	_trail_particles.clear()
	
	# Spawn impact effect
	_spawn_impact_effect()
	
	queue_free()

func _spawn_impact_effect() -> void:
	if not get_parent():
		return
	
	# Main impact flash
	var flash := Sprite2D.new()
	flash.texture = _glow_texture
	flash.modulate = Color(0.9, 0.15, 0.1, 1.0)  # Dark red impact
	flash.scale = Vector2(0.4, 0.4)
	var flash_material := CanvasItemMaterial.new()
	flash_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	flash.material = flash_material
	flash.global_position = global_position
	flash.z_index = 950
	get_parent().add_child(flash)
	
	# Animate flash
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	tween.tween_property(flash, "scale", Vector2(1.5, 1.5), 0.25).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(flash.queue_free)
	
	# Spawn impact sparks
	for i in range(4):
		var spark := Sprite2D.new()
		spark.texture = _glow_texture
		spark.modulate = Color(0.85, 0.2, 0.1, 0.9)  # Dark red sparks
		spark.scale = Vector2(0.12, 0.12)
		var spark_mat := CanvasItemMaterial.new()
		spark_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		spark_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		spark.material = spark_mat
		spark.global_position = global_position
		spark.z_index = 949
		get_parent().add_child(spark)
		
		# Random direction for spark
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(20, 45)
		var target_pos := global_position + Vector2(cos(angle), sin(angle)) * dist
		
		var spark_tween := spark.create_tween()
		spark_tween.set_parallel(true)
		spark_tween.tween_property(spark, "global_position", target_pos, 0.2).set_ease(Tween.EASE_OUT)
		spark_tween.tween_property(spark, "modulate:a", 0.0, 0.2)
		spark_tween.tween_property(spark, "scale", Vector2(0.05, 0.05), 0.2)
		spark_tween.set_parallel(false)
		spark_tween.tween_callback(spark.queue_free)

func _create_radial_glow_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var max_radius: float = minf(center.x, center.y)
	
	for y in size:
		for x in size:
			var pos := Vector2(x + 0.5, y + 0.5)
			var distance: float = pos.distance_to(center)
			var normalized: float = distance / max_radius
			var alpha := 0.0
			if normalized < 1.0:
				var falloff := pow(1.0 - normalized, 2.4)
				alpha = clampf(falloff, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	
	return ImageTexture.create_from_image(img)
