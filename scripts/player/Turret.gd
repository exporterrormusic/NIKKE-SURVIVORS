extends Node2D

var ammo = 4
var max_ammo = 4
var spawned_by_summon := false # Track if this turret was spawned by a SummonedAlly
var spawner_node: Node = null # The node that spawned this turret (for killer_source tracking)
var killer_source_override: String = "" # If set, missiles use this source
var fire_delay := 0.0 # Stagger fire times to spread CPU load
var _fire_timer: Timer = null # Timer for firing projectiles

# Snow White SKILL-tree talent payloads (set by the controller before add_child)
var defensive_line: bool = false      # Defensive Line: damaging red aura
var aura_radius: float = 80.0
var incendiary_level: int = 0         # Incendiary Ammo: missiles apply burn DoT
var armor_piercing_level: int = 0     # Armor-Piercing Ammo: missiles apply damage mark
var permanent: bool = false           # Permanent Emplacement: reload instead of despawn
var detonation: bool = false          # Detonation: explode when destroyed/retired
var reload_time: float = 6.0

# Rapunzel burst-tree payloads (set on "6,000? Really?" turrets)
var rapunzel_it_burns_level: int = 0  # "Incendiary Rockets": rockets leave an It Burns ground zone
var use_fixed_target: bool = false    # "Anti-Queen Bombardment": fire all rockets at a fixed point
var fixed_target_position: Vector2 = Vector2.ZERO

const ARMOR_PIERCE_MULTS := [2.0, 4.0, 6.0]
const INCENDIARY_MULTS := [2.0, 4.0, 6.0]
const RAPUNZEL_IT_BURNS_MULTS := [2.0, 4.0, 6.0]
const MISSILE_DMG_MULT := 0.5          # turret missile damage = player damage x this
const MISSILE_EXPLOSION_RADIUS := 60.0 # a turret missile's blast size
const DETONATION_DMG_MULT := 3.0
const DETONATION_RADIUS_MULT := 3.0
const MISSILE_CAP := 32 # perf: max concurrent turret missiles (paces the Century barrage)

# Per-missile visual scale + blast radius. Barrage turrets (A CENTURY / Rapunzel's
# "6,000") bump these to the bigger original look; the normal turret keeps the smaller
# defaults.
var missile_scale: float = 1.0
var missile_explosion_radius: float = MISSILE_EXPLOSION_RADIUS * 2.0

var _aura_timer: Timer = null
var _reloading := false

@onready var ammo_bar = get_node_or_null("AmmoBar")
@onready var ammo_label = get_node_or_null("AmmoLabel")

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
const BASE_COLOR := Color(0.85, 0.87, 0.9, 1.0) # Light gray metal
const ACCENT_COLOR := Color(0.7, 0.72, 0.75, 1.0) # Darker gray accent
const HIGHLIGHT_COLOR := Color(0.95, 0.96, 0.98, 1.0) # White highlight
const SHADOW_COLOR := Color(0.4, 0.42, 0.45, 1.0) # Dark gray shadow
const WARNING_COLOR := Color(1.0, 0.3, 0.2, 1.0) # Red warning
const MUZZLE_FLASH_COLOR := Color(1.0, 0.9, 0.7, 1.0) # Warm flash

const ROTATION_SPEED := 8.0
const DEPLOY_TIME := 0.4

var _enemy_cache: Array = []
var _target_update_timer := 0.0

func _ready() -> void:
	_rng.randomize()
	# Randomize initial update timer to desync expensive logic
	_target_update_timer = _rng.randf_range(0.0, 0.2)
	
	# max_ammo may have been set before adding to scene
	if max_ammo < ammo:
		max_ammo = ammo
	
	# Fix UI Layout - ensure bar fits the text
	# Text is height 20 (-56 to -36)
	if ammo_bar:
		ammo_bar.max_value = max_ammo
		ammo_bar.value = ammo
		ammo_bar.size.y = 20.0
		ammo_bar.position.y = -56.0
		# Ensure it's wide enough centered
		ammo_bar.position.x = -35.0
		ammo_bar.size.x = 70.0
		
	if ammo_label:
		ammo_label.position.y = -58.0 # Fine-tuned for visual center
		ammo_label.size.y = 20.0
		ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ammo_label.add_theme_font_size_override("font_size", 16) # Increased font size to be readable and less blurry
	
	_update_ammo_label()
	
	# Hide the original sprite - we'll draw our own
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
	
	_fire_timer = Timer.new()
	add_child(_fire_timer)
	_fire_timer.wait_time = 2.0 # Assuming a default fire rate of 2 seconds
	_fire_timer.timeout.connect(Callable(self, "shoot"))
	
	# Apply fire_delay to stagger initial shots across turrets
	if fire_delay > 0.0:
		get_tree().create_timer(fire_delay).timeout.connect(func(): _fire_timer.start())
	else:
		# Randomize start time slightly to prevent all turrets firing on the exact same frame
		# This spreads instancing/audio load over 0.4 seconds
		var random_delay = _rng.randf_range(0.0, 0.4)
		get_tree().create_timer(random_delay).timeout.connect(func(): _fire_timer.start())
	
	# Make turret unshaded (bright) to match other summons
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	
	# Apply to UI elements too
	if ammo_bar:
		ammo_bar.material = mat
	if ammo_label:
		ammo_label.material = mat

	# Defensive Line: damaging aura ticking once per second
	if defensive_line:
		_aura_timer = Timer.new()
		_aura_timer.wait_time = 1.0
		_aura_timer.one_shot = false
		add_child(_aura_timer)
		_aura_timer.timeout.connect(_aura_tick)
		_aura_timer.start()

	set_process(true)

func _process(delta: float) -> void:
	_age += delta
	
	# Deployment animation
	if not _is_deployed:
		_deploy_progress = minf(_deploy_progress + delta / DEPLOY_TIME, 1.0)
		if _deploy_progress >= 1.0:
			_is_deployed = true
	
	# Update targeting logic (scanning is throttled, rotation is smooth)
	_update_targeting(delta)
	
	# Muzzle flash decay
	if _muzzle_flash_timer > 0:
		_muzzle_flash_timer -= delta
	
	# Low ammo warning pulse
	if ammo <= 1:
		_low_ammo_pulse = sin(_age * 6.0) * 0.5 + 0.5
	
	# Throttle redraws to every 2nd frame for performance
	if Engine.get_process_frames() % 2 == 0:
		queue_redraw()

func _update_targeting(delta: float) -> void:
	# Anti-Queen Bombardment: always aim at the painted point, skip enemy scanning.
	if use_fixed_target:
		_target_angle = (fixed_target_position - global_position).angle()
		var ad := wrapf(_target_angle - _current_angle, -PI, PI)
		_current_angle += ad * ROTATION_SPEED * delta
		return

	# Only scan for new targets periodically (approx 4 times/sec)
	# This drastically reduces CPU load when many turrets are active (Rapunzel Ultra Burst)
	_target_update_timer -= delta
	if _target_update_timer <= 0:
		_target_update_timer = _rng.randf_range(0.2, 0.3) # Randomize to prevent frame spikes
		_scan_for_target()

	# Rotate towards current target if valid
	if is_instance_valid(_current_target):
		var to_target = _current_target.global_position - global_position
		_target_angle = to_target.angle()
	
	# Smooth rotation toward target (runs every frame for smoothness)
	var angle_diff = wrapf(_target_angle - _current_angle, -PI, PI)
	_current_angle += angle_diff * ROTATION_SPEED * delta

func _scan_for_target() -> void:
	# Get all potential targets
	var enemies = TargetCache.get_enemies()
	
	# Find closest
	var closest_enemy: Node2D = null
	var min_dist_sq := INF
	var my_pos := global_position
	
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Node2D:
			# Simple distance check - using squared distance avoids sqrt() for speed
			var dist_sq = my_pos.distance_squared_to(enemy.global_position)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				closest_enemy = enemy
	
	_current_target = closest_enemy

func _draw() -> void:
	# Defensive Line: red damaging aura (drawn behind the turret body)
	if defensive_line:
		var pulse := 0.10 + 0.04 * sin(_age * 3.0)
		draw_circle(Vector2.ZERO, aura_radius, Color(1.0, 0.13, 0.1, pulse))
		draw_arc(Vector2.ZERO, aura_radius, 0.0, TAU, 48, Color(1.0, 0.25, 0.2, 0.45), 2.0)

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
	# Perf: bound concurrent turret missiles so a 20-turret barrage can't flood the
	# screen with missiles/explosions in one frame. Ammo is NOT consumed when capped,
	# so the turret simply retries on its next fire tick (paces volume, keeps visuals).
	if ExplosiveProjectile._active_missiles.size() >= MISSILE_CAP:
		return

	# Resolve up to 2 targets. Anti-Queen Bombardment fires every rocket at the
	# painted point; otherwise pick the 2 nearest enemies (preferring ones not
	# already over-targeted) in ONE O(n) pass.
	var target_positions: Array = []
	var target_nodes: Array = []
	if use_fixed_target:
		target_positions = [fixed_target_position, fixed_target_position]
		target_nodes = [null, null]
	else:
		var my_pos := global_position
		var t1: Node2D = null
		var t1_d := INF
		var t2: Node2D = null
		var t2_d := INF
		var nearest: Node2D = null # fallback if every enemy is already over-targeted
		var nearest_d := INF
		for e in TargetCache.get_enemies():
			if not (e is Node2D) or not is_instance_valid(e) or not e.has_method("take_damage"):
				continue
			var d := my_pos.distance_squared_to((e as Node2D).global_position)
			if d < nearest_d:
				nearest_d = d
				nearest = e
			if ExplosiveProjectile.targeters_of(e) >= ExplosiveProjectile.MAX_TARGETERS:
				continue
			if d < t1_d:
				t2 = t1; t2_d = t1_d
				t1 = e; t1_d = d
			elif d < t2_d:
				t2 = e; t2_d = d

		if t1 == null:
			t1 = nearest # everything over-targeted -> just use the nearest enemy
		if t1 == null:
			return # no enemies, don't fire
		if t2 == null:
			t2 = t1
		target_nodes = [t1, t2]
		target_positions = [t1.global_position, t2.global_position]

	# Trigger muzzle flash (we have a target)
	_muzzle_flash_timer = 0.15

	var missiles_to_fire := mini(2, ammo)

	for i in missiles_to_fire:
		# Consume ammo for each missile
		ammo -= 1
		if ammo_bar:
			ammo_bar.value = ammo
		_update_ammo_label()

		var missile = ProjectileCache.create_rocket()
		get_parent().add_child(missile)

		# Fire from the barrel tips
		var dir := Vector2(cos(_current_angle), sin(_current_angle))
		var perp := Vector2(-dir.y, dir.x)
		var offset := perp * (12.0 if i == 0 else -12.0)
		missile.global_position = global_position + dir * 20.0 + offset

		# ExplosiveProjectile properties (Rocket.tscn is the shared explosive)
		var target_pos = target_positions[i]
		var fire_dir = (target_pos - missile.global_position).normalized()
		missile.direction = fire_dir
		missile.speed = 300
		missile.acceleration = 1200
		missile.max_speed = 2500
		missile.target_position = target_pos
		missile.explode_at_target = true

		# Set owner_node and killer_source based on who spawned the turret
		if spawned_by_summon:
			# Set killer_source_override directly so it persists even after summon is freed
			missile.killer_source_override = "summon"
			if is_instance_valid(spawner_node):
				missile.owner_node = spawner_node
			# Performance optimizations for summoned-turret missiles
			missile.homing_enabled = false
			missile.target_node = null # Don't track, just fly to position
			missile.exhaust_enabled = false
			missile.trail_enabled = false
			missile.smoke_enabled = false
			missile.lightweight_mode = true
		else:
			missile.owner_node = get_parent().get_node_or_null("Player")
			if use_fixed_target:
				# Anti-Queen Bombardment: fly to the painted point, don't home.
				missile.target_node = null
				missile.homing_enabled = false
			else:
				missile.target_node = target_nodes[i] # Normal turrets track targets
				missile.homing_enabled = true
				missile.homing_strength = 6.0 # gentler turns -> smoother arcs
				missile.coordinate_targeting = true # join the cross-missile target spread

		missile.scale = Vector2(missile_scale, missile_scale)

		# Turret missile damage = 50% of player's calculated damage
		var missile_dmg := _missile_damage()
		missile.damage = missile_dmg
		missile.explosion_damage = missile_dmg
		missile.explosion_radius = missile_explosion_radius

		# Incendiary Rockets (Rapunzel): leave an "It Burns" ground zone on impact.
		if rapunzel_it_burns_level > 0:
			missile.ground_fire_enabled = true
			missile.ground_fire_duration = 3.0
			missile.ground_fire_radius = 120.0
			missile.ground_fire_damage = maxi(int(missile_dmg / 3.0), 1)
			missile.ground_fire_it_burns_mult = RAPUNZEL_IT_BURNS_MULTS[mini(rapunzel_it_burns_level, 3) - 1]
			missile.ground_fire_attack_damage = missile_dmg
		else:
			missile.ground_fire_enabled = false
			missile.ground_fire_damage = 0
			missile.ground_fire_duration = 0.0

		# Snow White missile talents (carried to the missile's explosion)
		if armor_piercing_level > 0:
			missile.armor_pierce_mult = ARMOR_PIERCE_MULTS[armor_piercing_level - 1]
		if incendiary_level > 0:
			missile.incendiary_total = INCENDIARY_MULTS[incendiary_level - 1] * float(missile.explosion_damage)

	# Out of ammo: permanent turrets reload, normal turrets despawn (and Detonate).
	if ammo <= 0:
		if permanent:
			_start_reload()
		else:
			_despawn()

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


## A turret missile's base damage (player damage scaled). Read live so it tracks
## ATK growth even for permanent turrets placed earlier.
func _missile_damage() -> int:
	var p = get_parent().get_node_or_null("Player") if get_parent() else null
	if p and p.has_method("calc_damage"):
		return maxi(1, int(p.calc_damage() * MISSILE_DMG_MULT))
	return 2


## Defensive Line: damage every enemy inside the aura once per second. Routes
## through take_damage so Weak Point / Armor-Piercing marks amplify it.
func _aura_tick() -> void:
	var dmg := _missile_damage()
	var r_sq := aura_radius * aura_radius
	for e in TargetCache.get_enemies():
		if not is_instance_valid(e) or not e is Node2D:
			continue
		if e.is_in_group("charmed_allies"):
			continue
		if global_position.distance_squared_to((e as Node2D).global_position) <= r_sq:
			if e.has_method("take_damage"):
				e.take_damage(dmg, false, Vector2.ZERO, false, "snow_white_turret_aura")


## Permanent Emplacement: refill ammo after a reload delay instead of despawning.
func _start_reload() -> void:
	if _reloading:
		return
	_reloading = true
	if _fire_timer:
		_fire_timer.stop()
	var t := get_tree().create_timer(reload_time)
	t.timeout.connect(func():
		if not is_instance_valid(self):
			return
		ammo = max_ammo
		if ammo_bar:
			ammo_bar.value = ammo
		_update_ammo_label()
		_reloading = false
		if _fire_timer:
			_fire_timer.start()
	)


## Called by the controller when retiring the oldest turret at the cap.
func request_despawn() -> void:
	_despawn()


func _despawn() -> void:
	_detonate()
	_spawn_destruction_effect()
	queue_free()


## Detonation: explode for 3x missile damage in 3x a rocket's blast, carrying the
## Armor-Piercing / Incendiary missile debuffs.
func _detonate() -> void:
	if not detonation:
		return
	var parent = get_parent()
	if parent == null:
		return

	var dmg := int(_missile_damage() * DETONATION_DMG_MULT)
	var blast := MISSILE_EXPLOSION_RADIUS * DETONATION_RADIUS_MULT

	var explosion = ProjectileCache.create_explosion()
	if explosion.has_method("initialize"):
		explosion.initialize(dmg, blast)
	explosion.owner_node = parent.get_node_or_null("Player")
	explosion.killer_source_override = "snow_white_detonation"
	if armor_piercing_level > 0:
		explosion.armor_pierce_mult = ARMOR_PIERCE_MULTS[armor_piercing_level - 1]
	if incendiary_level > 0:
		explosion.incendiary_total = INCENDIARY_MULTS[incendiary_level - 1] * float(_missile_damage())
	if explosion.has_node("Sprite2D"):
		explosion.get_node("Sprite2D").visible = false
	parent.add_child(explosion)
	explosion.global_position = global_position

	var visual = ProjectileCache.create_explosion_effect()
	if visual:
		if "radius" in visual:
			visual.radius = blast
		parent.add_child(visual)
		visual.global_position = global_position
