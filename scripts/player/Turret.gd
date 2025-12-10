extends Node2D

var ammo = 4
var max_ammo = 4
var spawned_by_summon := false  # Track if this turret was spawned by a SummonedAlly
var spawner_node: Node = null  # The node that spawned this turret (for killer_source tracking)

@onready var ammo_bar = $AmmoBar
@onready var ammo_label = $AmmoLabel

# Visual state
var _target_angle := 0.0
var _current_angle := 0.0
var _age := 0.0
var _deploy_progress := 0.0
var _is_deployed := false
var _muzzle_flash_timer := 0.0
var _low_ammo_pulse := 0.0
var _current_target: Node2D = null
var _rng := RandomNumberGenerator.new()

# Visual constants - Iron Man style white/gray metal
const BASE_COLOR := Color(0.85, 0.87, 0.9, 1.0)        # Light gray metal
const ACCENT_COLOR := Color(0.7, 0.72, 0.75, 1.0)      # Darker gray accent
const HIGHLIGHT_COLOR := Color(0.95, 0.96, 0.98, 1.0)  # White highlight
const SHADOW_COLOR := Color(0.4, 0.42, 0.45, 1.0)      # Dark gray shadow
const WARNING_COLOR := Color(1.0, 0.3, 0.2, 1.0)       # Red warning
const MUZZLE_FLASH_COLOR := Color(1.0, 0.9, 0.7, 1.0)  # Warm flash

const ROTATION_SPEED := 8.0
const DEPLOY_TIME := 0.4

func _ready():
	_rng.randomize()
	# max_ammo may have been set before adding to scene
	if max_ammo < ammo:
		max_ammo = ammo
	ammo_bar.max_value = max_ammo
	ammo_bar.value = ammo
	_update_ammo_label()
	
	# Hide the original sprite - we'll draw our own
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
	
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 2.0
	timer.connect("timeout", Callable(self, "shoot"))
	timer.start()
	
	# Make turret unshaded (bright) to match other summons
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Apply to UI elements too
	if ammo_bar:
		ammo_bar.material = mat
	if ammo_label:
		ammo_label.material = mat
	
	set_process(true)

func _process(delta: float) -> void:
	_age += delta
	
	# Deployment animation
	if not _is_deployed:
		_deploy_progress = minf(_deploy_progress + delta / DEPLOY_TIME, 1.0)
		if _deploy_progress >= 1.0:
			_is_deployed = true
	
	# Track target
	_update_targeting(delta)
	
	# Muzzle flash decay
	if _muzzle_flash_timer > 0:
		_muzzle_flash_timer -= delta
	
	# Low ammo warning pulse
	if ammo <= 1:
		_low_ammo_pulse = sin(_age * 6.0) * 0.5 + 0.5
	
	queue_redraw()

var _enemy_cache: Array = []
var _enemy_cache_timer := 0.0
const ENEMY_CACHE_INTERVAL := 0.1  # Update enemy list every 100ms instead of every frame

func _update_targeting(delta: float) -> void:
	# Update enemy cache periodically instead of every frame
	_enemy_cache_timer += delta
	if _enemy_cache_timer >= ENEMY_CACHE_INTERVAL:
		_enemy_cache_timer = 0.0
		_enemy_cache = get_tree().get_nodes_in_group("enemies")
	
	# Find closest enemy to track using cached list
	var closest_enemy: Node2D = null
	var min_dist := INF
	for enemy in _enemy_cache:
		if is_instance_valid(enemy) and enemy is Node2D and enemy.has_method("take_damage"):
			var dist = global_position.distance_to(enemy.global_position)
			if dist < min_dist:
				min_dist = dist
				closest_enemy = enemy
	
	_current_target = closest_enemy
	
	if closest_enemy:
		var to_target = closest_enemy.global_position - global_position
		_target_angle = to_target.angle()
	
	# Smooth rotation toward target
	var angle_diff = wrapf(_target_angle - _current_angle, -PI, PI)
	_current_angle += angle_diff * ROTATION_SPEED * delta

func _draw() -> void:
	var deploy := _ease_out_back(_deploy_progress)
	
	# Draw base/platform
	_draw_base(deploy)
	
	# Draw rotating barrel assembly
	_draw_barrel(deploy)
	
	# Draw muzzle flash
	if _muzzle_flash_timer > 0:
		_draw_muzzle_flash()
	
	# Draw low ammo warning
	if ammo <= 1 and _is_deployed:
		_draw_low_ammo_warning()

func _draw_base(deploy: float) -> void:
	var base_scale := deploy
	
	# Main base plate (hexagonal-ish)
	var base_radius := 22.0 * base_scale
	var base_points := PackedVector2Array()
	for i in range(6):
		var angle := TAU * i / 6.0 - PI / 6.0
		base_points.append(Vector2(cos(angle), sin(angle)) * base_radius)
	
	# Shadow
	draw_polygon(base_points, [SHADOW_COLOR])
	
	# Main base slightly smaller
	var inner_points := PackedVector2Array()
	for i in range(6):
		var angle := TAU * i / 6.0 - PI / 6.0
		inner_points.append(Vector2(cos(angle), sin(angle)) * (base_radius - 3))
	draw_polygon(inner_points, [BASE_COLOR])
	
	# Center mount ring
	draw_circle(Vector2.ZERO, 10.0 * base_scale, ACCENT_COLOR)
	draw_circle(Vector2.ZERO, 7.0 * base_scale, BASE_COLOR)
	
	# Highlight arc
	draw_arc(Vector2.ZERO, 8.0 * base_scale, -PI * 0.7, -PI * 0.3, 8, HIGHLIGHT_COLOR, 2.0)
	
	# Panel lines on base
	for i in range(3):
		var angle := TAU * i / 3.0
		var start := Vector2(cos(angle), sin(angle)) * 8.0 * base_scale
		var end := Vector2(cos(angle), sin(angle)) * (base_radius - 4) * base_scale
		draw_line(start, end, SHADOW_COLOR, 1.0)

func _draw_barrel(deploy: float) -> void:
	if deploy < 0.3:
		return
	
	var barrel_deploy := clampf((deploy - 0.3) / 0.7, 0.0, 1.0)
	var barrel_length := 28.0 * barrel_deploy
	var barrel_width := 6.0
	
	# Barrel direction
	var dir := Vector2(cos(_current_angle), sin(_current_angle))
	var perp := Vector2(-dir.y, dir.x)
	
	# Main barrel housing
	var housing_start := dir * 5.0
	var housing_end := dir * (barrel_length - 5.0)
	
	# Draw barrel shadow
	var shadow_offset := Vector2(2, 2)
	draw_line(housing_start + shadow_offset, housing_end + shadow_offset, Color(0, 0, 0, 0.3), barrel_width + 4)
	
	# Main barrel body
	draw_line(housing_start, housing_end, ACCENT_COLOR, barrel_width + 2)
	draw_line(housing_start, housing_end, BASE_COLOR, barrel_width)
	
	# Barrel tip (darker)
	var tip_start := dir * (barrel_length - 8.0)
	var tip_end := dir * barrel_length
	draw_line(tip_start, tip_end, SHADOW_COLOR, barrel_width + 2)
	draw_line(tip_start, tip_end, ACCENT_COLOR, barrel_width - 1)
	
	# Barrel highlight stripe
	var highlight_start := housing_start + perp * (barrel_width * 0.3)
	var highlight_end := housing_end + perp * (barrel_width * 0.3)
	draw_line(highlight_start, highlight_end, HIGHLIGHT_COLOR, 1.5)
	
	# Side detail vents (left barrel)
	var left_offset := perp * 12.0
	_draw_mini_barrel(housing_start + left_offset, dir, barrel_length * 0.7, 3.0, barrel_deploy)
	
	# Side detail vents (right barrel)  
	var right_offset := -perp * 12.0
	_draw_mini_barrel(housing_start + right_offset, dir, barrel_length * 0.7, 3.0, barrel_deploy)
	
	# Pivot joint
	draw_circle(Vector2.ZERO, 5.0, SHADOW_COLOR)
	draw_circle(Vector2.ZERO, 4.0, ACCENT_COLOR)
	draw_circle(Vector2.ZERO, 2.5, HIGHLIGHT_COLOR)

func _draw_mini_barrel(start: Vector2, dir: Vector2, length: float, width: float, deploy: float) -> void:
	var end := start + dir * length * deploy
	draw_line(start, end, SHADOW_COLOR, width + 1)
	draw_line(start, end, ACCENT_COLOR, width)
	# Tip
	var tip := start + dir * (length * deploy - 3.0)
	draw_line(tip, end, SHADOW_COLOR, width - 1)

func _draw_muzzle_flash() -> void:
	var flash_alpha := _muzzle_flash_timer / 0.15
	var flash_size := 15.0 + (1.0 - flash_alpha) * 10.0
	
	var dir := Vector2(cos(_current_angle), sin(_current_angle))
	var flash_pos := dir * 30.0
	
	# Main flash
	var flash_color := Color(MUZZLE_FLASH_COLOR.r, MUZZLE_FLASH_COLOR.g, MUZZLE_FLASH_COLOR.b, flash_alpha * 0.8)
	draw_circle(flash_pos, flash_size, flash_color)
	
	# Inner bright core
	var core_color := Color(1.0, 1.0, 1.0, flash_alpha)
	draw_circle(flash_pos, flash_size * 0.4, core_color)
	
	# Side flashes for the two side barrels
	var perp := Vector2(-dir.y, dir.x)
	var side_flash_size := flash_size * 0.6
	draw_circle(flash_pos + perp * 12.0 - dir * 8.0, side_flash_size, flash_color)
	draw_circle(flash_pos - perp * 12.0 - dir * 8.0, side_flash_size, flash_color)

func _draw_low_ammo_warning() -> void:
	var warning_alpha := _low_ammo_pulse * 0.5
	var warning_color := Color(WARNING_COLOR.r, WARNING_COLOR.g, WARNING_COLOR.b, warning_alpha)
	
	# Pulsing ring around turret
	draw_arc(Vector2.ZERO, 28.0, 0, TAU, 32, warning_color, 2.0)
	
	# Small warning indicators
	for i in range(4):
		var angle := TAU * i / 4.0 + _age * 2.0
		var pos := Vector2(cos(angle), sin(angle)) * 32.0
		draw_circle(pos, 3.0 * _low_ammo_pulse, warning_color)

func _ease_out_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)

func shoot():
	# Trigger muzzle flash
	_muzzle_flash_timer = 0.15
	
	# Find enemies to target
	var enemies = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node2D and enemy.has_method("take_damage"):
			enemies.append(enemy)
	enemies.sort_custom(func(a, b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	
	if enemies.size() == 0:
		return  # No enemies, don't fire
	
	# Determine how many rockets to fire (up to 2, but limited by ammo)
	var rockets_to_fire := mini(2, ammo)
	var targets = []
	if enemies.size() >= 2:
		targets = [enemies[0], enemies[1]]
	else:
		targets = [enemies[0], enemies[0]]
	
	for i in rockets_to_fire:
		# Consume ammo for each rocket
		ammo -= 1
		ammo_bar.value = ammo
		_update_ammo_label()
		
		var rocket = ProjectileCache.create_rocket()
		get_parent().add_child(rocket)
		
		# Fire from the barrel tips
		var dir := Vector2(cos(_current_angle), sin(_current_angle))
		var perp := Vector2(-dir.y, dir.x)
		var offset := perp * (12.0 if i == 0 else -12.0)
		rocket.global_position = global_position + dir * 20.0 + offset
		
		var target_pos = targets[i].global_position
		var fire_dir = (target_pos - rocket.global_position).normalized()
		rocket.direction = fire_dir
		rocket.speed = 300
		rocket.acceleration = 1200
		rocket.max_speed = 2500
		rocket.target_position = target_pos
		rocket.explode_at_target = true
		rocket.target_node = targets[i]
		# Set owner_node and killer_source based on who spawned the turret
		if spawned_by_summon:
			# Set killer_source_override directly so it persists even after summon is freed
			rocket.killer_source_override = "summon"
			if is_instance_valid(spawner_node):
				rocket.owner_node = spawner_node
		else:
			rocket.owner_node = get_parent().get_node_or_null("Player")
		rocket.scale = Vector2(0.5, 0.5)
		rocket.ground_fire_enabled = false
		rocket.homing_enabled = true  # Enable homing for turret rockets
		rocket.homing_strength = 10.0  # Strong homing
		# Turret damage = 50% of player's calculated damage
		var player_node = get_parent().get_node_or_null("Player")
		if player_node and player_node.has_method("calc_damage"):
			var turret_damage: int = maxi(1, int(player_node.calc_damage() * 0.5))
			rocket.damage = turret_damage
			rocket.explosion_damage = turret_damage
		else:
			# Fallback if player not found
			rocket.damage = 2
			rocket.explosion_damage = 2
		rocket.explosion_radius = 60.0  # Smaller explosion radius
	
	# Check if out of ammo after firing
	if ammo <= 0:
		_spawn_destruction_effect()
		queue_free()

func _spawn_destruction_effect() -> void:
	# Spawn sparks and smoke when turret is destroyed
	for i in range(12):
		var spark := _create_spark()
		get_parent().add_child(spark)
		spark.global_position = global_position

func _create_spark() -> Node2D:
	var spark := Node2D.new()
	spark.set_script(preload("res://scripts/player/TurretSpark.gd"))
	return spark

func _update_ammo_label() -> void:
	if ammo_label:
		ammo_label.text = str(ammo) + "/" + str(max_ammo)
