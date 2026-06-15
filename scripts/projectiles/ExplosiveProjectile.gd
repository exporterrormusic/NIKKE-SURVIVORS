extends Area2D
class_name ExplosiveProjectile

@export var speed: float = 600.0
@export var acceleration: float = 800.0
@export var max_speed: float = 2000.0
@export var direction: Vector2 = Vector2.ZERO
@export var target_position: Vector2 = Vector2.ZERO
@export var explode_at_target: bool = false
@export var target_node: Node = null
@export var lifetime: float = 2.5
@export var max_flight_time: float = 5.0
@export var damage: int = 40
@export var explosion_damage: int = 60
@export var explosion_radius: float = 150.0
@export var explosion_color: Color = Color(1.0, 0.5, 0.2, 0.8)
var explosion_glow_boost: float = 1.0 # >1 brightens the explosion visual (Rapunzel burst turrets)
@export var owner_node: Node = null
var killer_source: String = "rocket" # For ShielderShield collision detection
var killer_source_override: String = "" # Override killer_source if set (for summon-spawned turrets)
## Snow White turret missile talents, carried through to the explosion.
var armor_pierce_mult: float = 0.0 # >0: Armor-Piercing Ammo / Rapunzel Anti-Armor damage-taken mark
var incendiary_total: float = 0.0  # >0: Incendiary Ammo flat burn DoT total
## Rapunzel "Concussive Blast": >0 = explosion stuns enemies hit for this many seconds.
var explosion_stun_duration: float = 0.0
## Rapunzel "It Burns" / "Endless Desire" payloads handed to the burning ground.
var ground_fire_it_burns_mult: float = 0.0
var ground_fire_attack_damage: int = 0
var ground_fire_endless: bool = false
@export var render_style: String = "grenade" # "grenade" | "rocket"
@export var special_attack: bool = false
@export var trail_enabled: bool = false
@export var trail_color: Color = Color(1.0, 0.8, 0.3, 0.8)
@export var trail_width: float = 18.0
@export var trail_spacing: float = 32.0
@export var trail_max_points: int = 14
@export var trail_core_color: Color = Color(1.0, 0.95, 0.8, 0.9)
@export var trail_glow_color: Color = Color(1.0, 0.6, 0.2, 0.6)
@export var exhaust_enabled: bool = false
@export var exhaust_length: float = 42.0
@export var exhaust_width: float = 22.0
@export var exhaust_flicker_speed: float = 18.0
@export var exhaust_glow_color: Color = Color(1.0, 0.55, 0.1, 0.7)
@export var smoke_enabled: bool = false
@export var smoke_color: Color = Color(0.55, 0.55, 0.55, 0.85)
@export var smoke_initial_radius: float = 10.0
@export var smoke_growth_rate: float = 28.0
@export var smoke_fade_speed: float = 0.9
@export var smoke_spawn_interval: float = 0.05
@export var ground_fire_enabled: bool = false
@export var ground_fire_duration: float = 0.0
@export var ground_fire_damage: int = 0
@export var ground_fire_radius: float = 0.0
@export var ground_fire_color: Color = Color(1.0, 0.5, 0.3, 0.85)
@export var homing_enabled: bool = false
@export var homing_strength: float = 8.0 # How fast the rocket turns toward target

# Performance flag for turret rockets
var reduced_smoke: bool = false # When true, spawn 75% fewer smoke particles
var lightweight_mode: bool = false # When true, disable exhaust/trail/smoke and throttle redraws

const PROJECTILE_BASE_Z_INDEX := 900
const GroundFireScript := preload("res://scripts/effects/GroundFire.gd")
# Cached ShopMenu reference to avoid load() in hot paths
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")

var _age := 0.0
var _flight_time := 0.0
var _collision_shape: CollisionShape2D
var _velocity: Vector2 = Vector2.ZERO
var _trail_points: Array = []
var _trail_ages: Array = []
var _trail_distance := 0.0
var _exploded := false
var _had_node_target := false # True once a homing node-target was assigned (for re-acquire on death)
## Cross-missile target coordination (turret missiles opt in). Lets turrets avoid
## piling missiles onto an enemy already doomed by missiles in flight, which is the
## main cause of mass redirect/curving when that enemy dies.
var coordinate_targeting := false
var _registered := false
static var _active_missiles: Array = []
## Cheap target-spread: each enemy carries a "missile_targeters" count (meta). New
## missiles prefer enemies under MAX_TARGETERS so they don't dogpile (which caused
## the overkill->mass-redirect curving). O(1) checks instead of summing all missiles.
const MAX_TARGETERS := 2
var _counted_target: Node = null
var _can_pierce_boulders := false # cached Wells chrono check, computed once per flight
var _pierce_checked := false
# Turret missiles render the body via a baked sprite (the procedural look rendered to
# rocket.png) instead of redrawing ~20 polygons every frame.
var _body_sprite: Sprite2D = null
const BODY_TEX_PATH := "res://assets/projectiles/rocket.png"
static var _body_tex: Texture2D = null
static var _body_tex_tried := false

static func _get_body_tex() -> Texture2D:
	if not _body_tex_tried:
		_body_tex_tried = true
		if ResourceLoader.exists(BODY_TEX_PATH):
			_body_tex = load(BODY_TEX_PATH)
	return _body_tex

func _ensure_body_sprite() -> void:
	if _body_sprite == null:
		var tex := _get_body_tex()
		if tex == null:
			return
		_body_sprite = Sprite2D.new()
		_body_sprite.texture = tex
		_body_sprite.centered = true
		_body_sprite.z_as_relative = false
		_body_sprite.z_index = PROJECTILE_BASE_Z_INDEX
		# Unshaded so the night/day light doesn't darken the missile (the procedural
		# body was unshaded via _apply_unshaded_material; child sprites need their own).
		var mat := CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_body_sprite.material = mat
		add_child(_body_sprite)
	_body_sprite.visible = true
var _smoke_puffs: Array = []
var _smoke_timer := 0.0
var _exhaust_time := 0.0
var _flicker_seed := 0.0
var _rng := RandomNumberGenerator.new()
var _glow_sprite: Sprite2D = null
var _glow_texture: Texture2D = null
var _motion_configured: bool = false
var _wobble_offset := 0.0
var _impact_anticipation := 0.0
var _thrust_pulse := 0.0

func _environment_tint(color: Color, _local_offset: Vector2 = Vector2.ZERO) -> Color:
	return color

func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = PROJECTILE_BASE_Z_INDEX
	add_to_group("projectiles")
	_connect_collision_signals()
	collision_layer = 2
	# Layer 1(1) = World, Layer 2(2) = Player, Layer 3(4) = Enemies
	# Mask: Include layers 1, 2, and 3 = 1 + 2 + 4 = 7
	collision_mask = 15 # Layers 1, 2, 3, 4 (Enemies/Hitboxes)
	monitorable = true
	monitoring = true
	_configure_collision_shape()
	_rng.randomize()
	_flicker_seed = _rng.randf_range(0.0, TAU)
	if trail_enabled:
		_trail_points.append(global_position)
		_trail_ages.append(0.0)
	set_process(true)
	_ensure_glow_sprite()
	_update_glow_visual()
	
	# Make rocket glow through night darkness (unshaded)
	_apply_unshaded_material()
	
	queue_redraw()

## Reset state for object pooling (called by ProjectileCache._get_from_pool)
func reset() -> void:
	# Re-enable collision detection (disabled by return_to_pool)
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	collision_mask = 15 # Layers 1, 2, 3, 4 (Enemies/Hitboxes)
	
	# Reset explosion state
	_exploded = false
	_age = 0.0
	_flight_time = 0.0
	_motion_configured = false
	_velocity = Vector2.ZERO
	
	# Reset visual state
	_trail_points.clear()
	_trail_ages.clear()
	_trail_distance = 0.0
	_smoke_puffs.clear()
	_smoke_timer = 0.0
	_exhaust_time = 0.0
	_wobble_offset = 0.0
	_impact_anticipation = 0.0
	_thrust_pulse = 0.0
	
	# Reset properties to defaults
	direction = Vector2.ZERO
	target_position = Vector2.ZERO
	target_node = null
	_had_node_target = false
	coordinate_targeting = false
	_counted_target = null
	_pierce_checked = false
	_can_pierce_boulders = false
	if _body_sprite:
		_body_sprite.visible = false
	owner_node = null
	killer_source_override = ""
	lightweight_mode = false
	reduced_smoke = false
	explosion_glow_boost = 1.0
	armor_pierce_mult = 0.0
	incendiary_total = 0.0
	explosion_stun_duration = 0.0
	ground_fire_it_burns_mult = 0.0
	ground_fire_attack_damage = 0
	ground_fire_endless = false
	ground_fire_enabled = false

	visible = true
	set_process(true)

func _process(delta: float) -> void:
	# Apply Global Enemy Time Scale (Bullet Time) - ONLY for non-player projectiles
	var time_scale = 1.0
	# Player-owned missiles (turrets) run at normal time; skip the GameManager lookup.
	if not (owner_node and owner_node.is_in_group("player")):
		var game_manager = get_node_or_null("/root/GameManager")
		time_scale = game_manager.enemy_time_scale if game_manager else 1.0
	
	# Scale delta
	var dt: float = delta * time_scale

	if not _motion_configured:
		_configure_motion()
		_motion_configured = true

	if coordinate_targeting and not _registered:
		_registered = true
		_active_missiles.append(self)
		_inc_targeter(target_node) # count the turret-assigned target

	if _exploded:
		return
	_age += dt
	_flight_time += dt
	
	# Wobble and thrust pulse animations
	_wobble_offset = sin(_age * 25.0) * 0.03 + sin(_age * 40.0) * 0.015
	_thrust_pulse = 0.8 + sin(_age * 35.0) * 0.2 + sin(_age * 55.0) * 0.1
	
	if lifetime > 0.0 and _age >= lifetime:
		_explode()
		return
	if max_flight_time > 0.0 and _flight_time >= max_flight_time:
		_explode()
		return
	# Update target position if following a node. If our homing target died
	# mid-flight, re-acquire the nearest enemy along our heading so the missile
	# redirects smoothly instead of curving toward an empty death spot.
	if target_node and is_instance_valid(target_node):
		target_position = target_node.global_position
		_had_node_target = true
	elif _had_node_target and homing_enabled:
		if not _reacquire_target():
			# No live enemy left: stop seeking, fly straight until timeout/impact.
			target_node = null
			target_position = Vector2.ZERO
			_had_node_target = false
	
	# Homing: steer velocity toward target
	if homing_enabled and target_position != Vector2.ZERO:
		var to_target := (target_position - global_position).normalized()
		if to_target != Vector2.ZERO and _velocity.length() > 0:
			# Smoothly rotate velocity toward target
			var current_dir := _velocity.normalized()
			var new_dir := current_dir.lerp(to_target, homing_strength * dt).normalized()
			_velocity = new_dir * _velocity.length()
	
	# Calculate impact anticipation (increases as rocket approaches target)
	if target_position != Vector2.ZERO:
		var distance_to_target := global_position.distance_to(target_position)
		_impact_anticipation = clampf(1.0 - (distance_to_target / 400.0), 0.0, 1.0)
		_impact_anticipation = _impact_anticipation * _impact_anticipation # Exponential ramp-up
	else:
		_impact_anticipation = 0.0
	# Apply acceleration - speed ramps up over time
	if acceleration > 0.0 and _velocity.length() < max_speed:
		var current_speed = _velocity.length()
		var new_speed = min(current_speed + acceleration * dt, max_speed)
		_velocity = _velocity.normalized() * new_speed
	var step := _velocity * dt
	var new_position := global_position + step
	if explode_at_target and target_position != Vector2.ZERO:
		var to_target := target_position - global_position
		var max_distance := step.length() + 6.0
		if to_target.length() <= max_distance:
			global_position = target_position
			_explode()
			return
	# Check for proximity to target (if homing toward an enemy)
	# This catches cases where collision detection doesn't trigger for large enemies
	if target_node and is_instance_valid(target_node) and target_node is Node2D:
		var enemy_scale: float = target_node.scale.x if target_node.scale.x > 1.0 else 1.0
		var scaled_hit_radius: float = 15.0 + 35.0 * (enemy_scale - 1.0) # Larger hitbox for scaled enemies
		if global_position.distance_to(target_node.global_position) < scaled_hit_radius:
			_explode()
			return
	
	# Check boulder collision - explode on impact
	if _check_boulder_collision():
		_explode()
		return
	
	global_position = new_position
	var is_rocket := render_style.to_lower() == "rocket"
	
	# Lightweight mode: skip all expensive visual updates
	if lightweight_mode:
		# Only redraw every 3rd frame in lightweight mode
		if Engine.get_process_frames() % 3 == 0:
			queue_redraw()
		return
	
	if trail_enabled:
		_update_trail(step.length())
		_advance_trail_ages(delta)
	if smoke_enabled and is_rocket:
		_update_smoke(delta)
	if exhaust_enabled and is_rocket:
		_exhaust_time += delta
	# Turret missiles: body is a baked sprite, so just orient the sprites each frame
	# (cheap transforms) - no procedural redraw at all.
	if coordinate_targeting:
		_ensure_body_sprite()
		if _body_sprite and _velocity.length() > 0.0:
			_body_sprite.rotation = _velocity.angle()
		_update_glow_visual()
		return
	_update_glow_visual()
	queue_redraw()

func _exit_tree() -> void:
	if _registered:
		_active_missiles.erase(self)
		_registered = false
	_dec_targeter()
	if _glow_sprite and is_instance_valid(_glow_sprite):
		_glow_sprite.queue_free()


## Number of coordinating missiles currently targeting an enemy (O(1) meta read).
static func targeters_of(enemy: Node) -> int:
	if enemy == null:
		return 0
	return int(enemy.get_meta("missile_targeters", 0))

func _inc_targeter(node) -> void:
	if node and is_instance_valid(node):
		node.set_meta("missile_targeters", int(node.get_meta("missile_targeters", 0)) + 1)
		_counted_target = node

func _dec_targeter() -> void:
	if _counted_target and is_instance_valid(_counted_target):
		var c := int(_counted_target.get_meta("missile_targeters", 0)) - 1
		if c <= 0:
			_counted_target.remove_meta("missile_targeters")
		else:
			_counted_target.set_meta("missile_targeters", c)
	_counted_target = null

## Re-point at a new target, keeping the per-enemy targeter counts in sync.
func _set_missile_target(new_target: Node) -> void:
	if new_target != _counted_target:
		_dec_targeter()
		_inc_targeter(new_target)
	target_node = new_target
	if new_target and is_instance_valid(new_target):
		target_position = (new_target as Node2D).global_position


## Pick the existing enemy closest to our current flight path (used when a homing
## missile's target dies). Returns true if a new target was assigned. Only enemies
## within a forward cone are considered (no hard U-turns), and enemies already
## doomed by other in-flight missiles are skipped.
func _reacquire_target() -> bool:
	var heading := _velocity.normalized()
	if heading == Vector2.ZERO:
		heading = direction.normalized()
	var best: Node2D = null
	var best_score := INF
	for e in TargetCache.get_enemies():
		if not is_instance_valid(e) or not e is Node2D:
			continue
		if e.is_in_group("charmed_allies"):
			continue
		var node2d := e as Node2D
		var to_e: Vector2 = node2d.global_position - global_position
		var dist := to_e.length()
		if dist < 1.0:
			best = node2d
			break
		var align := heading.dot(to_e / dist) # 1 = dead ahead, <=0 = behind
		if align < 0.5: # only ~60-degree forward cone -> gentle redirects, no whipping
			continue
		# Prefer enemies not already over-targeted (cheap O(1) count).
		if coordinate_targeting and targeters_of(node2d) >= MAX_TARGETERS:
			continue
		# Perpendicular deviation from the heading ray + a mild distance bias.
		var perp := dist * sqrt(maxf(0.0, 1.0 - align * align))
		var score := perp + dist * 0.25
		if score < best_score:
			best_score = score
			best = node2d
	if best:
		_set_missile_target(best)
		return true
	return false

func _apply_unshaded_material() -> void:
	# Create unshaded material so rockets/projectiles glow through night darkness
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	material = mat

func _connect_collision_signals() -> void:
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("area_entered", Callable(self, "_on_area_entered"))

func _configure_collision_shape() -> void:
	_collision_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = max(20.0, explosion_radius * 0.3)
	_collision_shape.shape = shape
	add_child(_collision_shape)

func _configure_motion() -> void:
	if direction != Vector2.ZERO:
		_velocity = direction.normalized() * speed
	elif explode_at_target and target_position != Vector2.ZERO:
		var to_target := target_position - global_position
		if to_target.length() > 0.01:
			direction = to_target.normalized()
			_velocity = direction * speed
		else:
			direction = Vector2.UP
			_velocity = direction * speed
	else:
		direction = Vector2.UP
		_velocity = direction * speed

func _update_trail(distance_step: float) -> void:
	_trail_distance += distance_step
	if _trail_distance < trail_spacing:
		return
	_trail_distance = 0.0
	_trail_points.append(global_position)
	_trail_ages.append(0.0)
	if _trail_points.size() > trail_max_points:
		_trail_points.pop_front()
		_trail_ages.pop_front()

func _advance_trail_ages(delta: float) -> void:
	for i in range(_trail_ages.size()):
		_trail_ages[i] += delta

func _spawn_smoke_puff() -> void:
	var dir := _velocity.normalized()
	if dir.length() == 0.0:
		dir = Vector2.RIGHT
	var base_offset: Vector2 = - dir * max(exhaust_length * 0.4, 24.0)
	var jitter: Vector2 = Vector2(
		_rng.randf_range(-smoke_initial_radius * 0.6, smoke_initial_radius * 0.6),
		_rng.randf_range(-smoke_initial_radius * 0.4, smoke_initial_radius * 0.4)
	)
	var puff_position: Vector2 = global_position + base_offset + jitter
	var initial_radius: float = smoke_initial_radius * _rng.randf_range(0.6, 1.4)
	var initial_alpha: float = clampf(smoke_color.a * _rng.randf_range(0.7, 1.1), 0.0, 1.0)
	
	# Add drift velocity for more dynamic smoke
	var drift := Vector2(
		_rng.randf_range(-20.0, 20.0),
		_rng.randf_range(-30.0, -10.0) # Slight upward drift
	)
	
	_smoke_puffs.append({
		"position": puff_position,
		"radius": initial_radius,
		"alpha": initial_alpha,
		"color": smoke_color,
		"age": 0.0,
		"drift": drift,
		"rotation": _rng.randf_range(0, TAU)
	})

func _update_smoke(delta: float) -> void:
	_smoke_timer += delta
	# reduced_smoke = spawn every 4th particle (75% reduction)
	var effective_interval := smoke_spawn_interval * (4.0 if reduced_smoke else 1.0)
	while _smoke_timer >= effective_interval:
		_smoke_timer -= effective_interval
		_spawn_smoke_puff()
	for i in range(_smoke_puffs.size() - 1, -1, -1):
		var puff: Dictionary = _smoke_puffs[i]
		puff["age"] = puff.get("age", 0.0) + delta
		puff["radius"] = puff.get("radius", smoke_initial_radius) + smoke_growth_rate * delta
		var new_alpha: float = float(puff.get("alpha", smoke_color.a)) - smoke_fade_speed * delta
		puff["alpha"] = new_alpha
		
		# Apply drift movement
		var drift: Vector2 = puff.get("drift", Vector2.ZERO)
		puff["position"] = puff.get("position", Vector2.ZERO) + drift * delta
		# Slow down drift over time
		puff["drift"] = drift * 0.95
		
		_smoke_puffs[i] = puff
		if new_alpha <= 0.02:
			_smoke_puffs.remove_at(i)

func _on_body_entered(body: Node) -> void:
	if _should_ignore_target(body):
		return
	_explode()

func _on_area_entered(area: Area2D) -> void:
	if _should_ignore_target(area):
		return
	_explode()

func _should_ignore_target(target: Node) -> bool:
	if not is_instance_valid(target):
		return true
	if target == owner_node:
		return true
	# Never damage player from player-owned projectiles
	if target.name == "Player" and owner_node:
		return true
	# Skip charmed enemies (they're friendly now)
	if target.is_in_group("charmed_allies"):
		return true
	# Also check if target is a child of the owner (e.g., hitbox Area2D of a clone)
	if owner_node and is_instance_valid(owner_node):
		if target.get_parent() == owner_node:
			return true
	# Ignore other rockets/projectiles - they shouldn't collide with each other
	if target is ExplosiveProjectile:
		return true
	# Also check by group or script name for other projectile types
	if target.is_in_group("projectiles"):
		return true
	# Don't detonate on enemy projectiles (lasers / enemy missiles) - they share
	# the enemy collision layer, so without this the missile blows up on them.
	if target.is_in_group("enemy_projectiles"):
		return true
	
	if target.is_in_group("shielder_shields") or target.is_in_group("boss_shields"):
		# Skip if Chrono-Intangibility upgrade is active AND playing Wells
		var player = get_tree().get_first_node_in_group("player")
		var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
		var playing_wells = false
		if player and player.has_method("is_playing_character"):
			playing_wells = player.is_playing_character("wells")
			
		if has_upgrade and playing_wells:
			return true # Ignore shield, let projectile pass through
			
	# Also check parent in case we hit a collision area child of a shield
	if target.get_parent() and (target.get_parent().is_in_group("shielder_shields") or target.get_parent().is_in_group("boss_shields")):
		# Skip if Chrono-Intangibility upgrade is active AND playing Wells
		var player = get_tree().get_first_node_in_group("player")
		var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
		var playing_wells = false
		if player and player.has_method("is_playing_character"):
			playing_wells = player.is_playing_character("wells")
			
		if has_upgrade and playing_wells:
			return true # Ignore shield, let projectile pass through
	
	if target.get_script() and target.get_script().resource_path:
		var script_path: String = target.get_script().resource_path
		if script_path.find("Rocket") != -1 or script_path.find("Missile") != -1 or script_path.find("Projectile") != -1:
			return true
			
	# Explicitly check Boulders for Intangibility
	if target.is_in_group("boulders"):
		var player = get_tree().get_first_node_in_group("player")
		var has_upgrade = ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")
		var playing_wells = false
		if player and player.has_method("is_playing_character"):
			playing_wells = player.is_playing_character("wells")
			
		if has_upgrade and playing_wells:
			# DIAGNOSTIC for Body Entered (only print occasionally if needed, but logic is shared)
			# print("[Explosive] Ignored Boulder due to Intangibility")
			return true
			
	return false

static var _shared_glow_texture: Texture2D = null

func _check_boulder_collision() -> bool:
	"""Check if projectile hit a boulder."""
	# Cheap early-out: usually there are no boulders, so skip the whole player/talent
	# lookup that used to run every frame per missile (a big missile-travel cost).
	var boulders := TargetCache.get_boulders()
	if boulders.is_empty():
		return false

	# Wells Chrono-Intangibility lets shots phase boulders. Cache it once per flight
	# instead of querying the registry + talent tree every frame.
	if not _pierce_checked:
		_pierce_checked = true
		_can_pierce_boulders = _compute_can_pierce_boulders()
	if _can_pierce_boulders:
		return false

	for boulder in boulders:
		if not is_instance_valid(boulder):
			continue
		var boulder_pos: Vector2 = boulder.global_position
		var boulder_radius: float = 150.0
		if boulder.get("boulder_size") != null:
			boulder_radius = boulder.boulder_size * 0.5
		var dist_sq = global_position.distance_squared_to(boulder_pos)
		if dist_sq < boulder_radius * boulder_radius:
			return true
	return false

func _compute_can_pierce_boulders() -> bool:
	var player = TargetCache.get_player()
	if player == null or not player.has_method("is_playing_character"):
		return false
	if not player.is_playing_character("wells"):
		return false
	return ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility")

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	_play_explosion_sound()
	
	# Create damage-dealing explosion (invisible - just does the damage)
	var explosion = ProjectileCache.create_explosion()
	if explosion.has_method("initialize"):
		# Use explosion_damage directly
		var final_damage = explosion_damage if explosion_damage > 0 else damage
		explosion.initialize(final_damage, explosion_radius)
	
	if is_instance_valid(owner_node):
		explosion.owner_node = owner_node
	explosion.killer_source_override = killer_source_override
	explosion.armor_pierce_mult = armor_pierce_mult
	explosion.incendiary_total = incendiary_total
	explosion.stun_duration = explosion_stun_duration
	
	# Hide the sprite (we'll use procedural effect instead)
	if explosion.has_node("Sprite2D"):
		explosion.get_node("Sprite2D").visible = false
	
	if get_parent():
		get_parent().add_child(explosion)
		explosion.global_position = global_position
		
		# Create visual explosion effect (procedural - no stripes)
		var visual = ProjectileCache.create_explosion_effect()
		visual.radius = explosion_radius
		# Turret/barrage missiles use the cheap cached-glow explosion (many concurrent).
		if "simple" in visual:
			visual.simple = coordinate_targeting
		# Pooled effect: always assign glow_color so a boosted value can't
		# leak into the next explosion
		if "glow_color" in visual:
			var g := Color(1.0, 0.6, 0.26, 0.6) # ExplosionEffect default
			if explosion_glow_boost > 1.0:
				g = Color(minf(g.r * explosion_glow_boost, 1.0),
					minf(g.g * explosion_glow_boost, 1.0),
					minf(g.b * explosion_glow_boost, 1.0),
					minf(g.a * explosion_glow_boost, 1.0))
			visual.glow_color = g
		get_parent().add_child(visual)
		visual.global_position = global_position
	else:
		explosion.queue_free()
	
	_spawn_ground_fire_if_needed()
	queue_free()

func _play_explosion_sound() -> void:
	# Try to find audio director in scene
	var player_node = TargetCache.get_player()
	if player_node == null:
		player_node = get_tree().root.find_child("Player", true, false)
	if player_node and player_node.has_node("AudioDirector"):
		var audio = player_node.get_node("AudioDirector")
		if audio and audio.has_method("play_rocket_explosion_sound"):
			audio.play_rocket_explosion_sound()

# Removed _apply_explosion_damage

func _spawn_explosion_effect() -> void:
	var effect_instance = ProjectileCache.create_explosion_effect()
	if effect_instance == null:
		return
	if not (effect_instance is ExplosionEffect):
		effect_instance.queue_free()
		return
	var effect: ExplosionEffect = effect_instance
	effect.radius = explosion_radius
	effect.base_color = explosion_color
	effect.duration = 0.55 if special_attack else 0.4
	effect.ring_thickness = max(6.0, explosion_radius * 0.12)
	if get_parent():
		effect.global_position = global_position
		get_parent().add_child(effect)
	else:
		effect.queue_free()


func _create_ground_fire_effect() -> GroundFire:
	var instance: Node = ProjectileCache.create_ground_fire()
	if instance is GroundFire:
		return instance as GroundFire
	instance.queue_free()
	if GroundFireScript:
		return GroundFireScript.new()
	return null

func _spawn_ground_fire_if_needed() -> void:
	if not ground_fire_enabled and ground_fire_damage <= 0:
		return
	var fire: GroundFire = _create_ground_fire_effect()
	if fire == null:
		return
	fire.radius = ground_fire_radius if ground_fire_radius > 0.0 else max(explosion_radius * 0.7, 80.0)
	fire.duration = max(ground_fire_duration, 0.1)
	fire.damage_per_tick = max(1, ground_fire_damage) if ground_fire_damage > 0 else max(1, int(damage * 0.25))
	fire.color = ground_fire_color
	# Rapunzel "It Burns" / "Endless Desire" payloads.
	fire.it_burns_mult = ground_fire_it_burns_mult
	fire.burn_attack_damage = ground_fire_attack_damage
	fire.endless = ground_fire_endless
	fire.global_position = global_position
	if get_parent():
		get_parent().add_child(fire)

func _draw() -> void:
	# Turret missiles render their body via the baked sprite (_body_sprite) - no draw.
	if coordinate_targeting:
		return
	var style := render_style.to_lower()
	if smoke_enabled and style == "rocket" and not _smoke_puffs.is_empty():
		_draw_smoke()
	if trail_enabled and (_trail_points.size() > 0):
		_draw_trail()
	match style:
		"rocket":
			_draw_rocket()
		"grenade":
			_draw_grenade_body()
		_:
			draw_circle(Vector2.ZERO, 10.0, _environment_tint(explosion_color, Vector2.ZERO))
	_draw_glow_guides_if_debug()

func _ensure_glow_sprite() -> void:
	if _glow_sprite:
		return
	
	# Use shared static texture to prevent expensive per-instance generation
	if _shared_glow_texture == null:
		_shared_glow_texture = _create_radial_glow_texture()
	
	_glow_texture = _shared_glow_texture
	
	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = _glow_texture
	_glow_sprite.centered = true
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_sprite.material = glow_material
	_glow_sprite.visible = true
	_glow_sprite.z_as_relative = false
	_glow_sprite.z_index = PROJECTILE_BASE_Z_INDEX + 1
	_glow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_glow_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	add_child(_glow_sprite)

func _update_glow_visual() -> void:
	if _glow_sprite == null:
		return
	var style := render_style.to_lower()
	var dir := _velocity
	if dir.length() == 0.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var base_color := explosion_color
	var scale_value := 0.8
	var alpha := clampf(base_color.a * 0.75, 0.0, 1.0)
	var offset := Vector2.ZERO
	var angle := dir.angle()
	if style == "rocket":
		var flame_color := exhaust_glow_color if exhaust_glow_color.a > 0.0 else trail_glow_color
		if flame_color.a <= 0.0:
			flame_color = explosion_color
		base_color = Color(
			clampf(flame_color.r * 1.05 + 0.05, 0.0, 1.0),
			clampf(flame_color.g * 0.9 + 0.02, 0.0, 1.0),
			clampf(flame_color.b * 0.6 + 0.03, 0.0, 1.0),
			clampf(flame_color.a * 0.9 + 0.1, 0.0, 1.0)
		)
		scale_value = 1.08 if special_attack else 0.96
		scale_value = clampf(scale_value, 0.7, 1.35)
		alpha = clampf(base_color.a * 1.08, 0.45, 1.0)
		offset = - dir * max(exhaust_length * 0.34, 18.0)
		angle = dir.angle()
	else:
		angle = 0.0
		alpha = clampf(base_color.a * 0.5 + 0.12, 0.0, 0.6)
		scale_value = clampf(explosion_radius * 0.0024 + 0.38, 0.32, 0.82)
	_glow_sprite.modulate = _environment_tint(Color(base_color.r, base_color.g, base_color.b, alpha), offset)
	_glow_sprite.scale = Vector2.ONE * scale_value
	_glow_sprite.position = offset
	_glow_sprite.rotation = angle

func _create_radial_glow_texture(size: int = 128) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var max_distance := center.length()
	for y in size:
		for x in size:
			var pos := Vector2(x + 0.5, y + 0.5)
			var distance := pos.distance_to(center)
			var normalized := clampf(distance / max_distance, 0.0, 1.0)
			var falloff := pow(1.0 - normalized, 2.4)
			var alpha := clampf(falloff, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

func _draw_glow_guides_if_debug() -> void:
	pass

func _draw_trail() -> void:
	if _trail_points.is_empty() and trail_width <= 0.0:
		return
	var total_points := _trail_points.size() + 1
	if total_points <= 1:
		return
	for idx in range(total_points):
		var array_index := total_points - 1 - idx
		var point: Vector2
		var age: float = 0.0
		if array_index == _trail_points.size():
			point = global_position
		else:
			point = _trail_points[array_index]
			if array_index < _trail_ages.size():
				age = _trail_ages[array_index]
		var t: float = float(idx) / max(1.0, float(total_points - 1))
		var fade: float = clampf(1.0 - t * 0.9, 0.0, 1.0) * clampf(1.0 - age * 0.7, 0.0, 1.0)
		if fade <= 0.01:
			continue
		var local := point - global_position
		var main_radius: float = lerpf(trail_width, trail_width * 0.2, t)
		if main_radius <= 0.5:
			continue
		var outer_color := trail_color
		outer_color.a = trail_color.a * fade
		var core_color := trail_core_color
		core_color.a = trail_core_color.a * fade * 0.9
		var glow_color := trail_glow_color
		glow_color.a = trail_glow_color.a * fade * 0.6
		outer_color = _environment_tint(outer_color, local)
		core_color = _environment_tint(core_color, local)
		glow_color = _environment_tint(glow_color, local)
		draw_circle(local, main_radius, outer_color)
		draw_circle(local, main_radius * 0.45, core_color)
		draw_circle(local, main_radius * 1.5, glow_color)

func _draw_smoke() -> void:
	for puff_variant in _smoke_puffs:
		if not (puff_variant is Dictionary):
			continue
		var puff := puff_variant as Dictionary
		var radius: float = float(puff.get("radius", smoke_initial_radius))
		var alpha: float = clampf(float(puff.get("alpha", smoke_color.a)), 0.0, 1.0)
		if alpha <= 0.01 or radius <= 0.5:
			continue
		var stored_color: Variant = puff.get("color", smoke_color)
		var puff_color: Color = smoke_color
		if stored_color is Color:
			puff_color = stored_color
		var outer := Color(puff_color.r, puff_color.g, puff_color.b, alpha * 0.35)
		var core := Color(puff_color.r * 0.9, puff_color.g * 0.9, puff_color.b * 0.9, alpha)
		var local := (puff.get("position", global_position) as Vector2) - global_position
		outer = _environment_tint(outer, local)
		core = _environment_tint(core, local)
		draw_circle(local, radius * 1.6, outer)
		draw_circle(local, radius, core)

func _draw_rocket() -> void:
	var dir := _velocity
	if dir.length() == 0.0:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	
	# Apply wobble to perpendicular direction
	var wobble_rotation := _wobble_offset
	dir = dir.rotated(wobble_rotation)
	var perp := Vector2(-dir.y, dir.x)
	var body_length: float = 92.0 if special_attack else 74.0
	var body_width: float = 26.0 if special_attack else 20.0
	
	# Draw impact anticipation glow (intensifies as rocket approaches target)
	if _impact_anticipation > 0.1:
		_draw_impact_anticipation(dir, body_length)
	
	if exhaust_enabled:
		_draw_rocket_exhaust(dir, perp, body_length, body_width)
	_draw_rocket_body(dir, perp, body_length, body_width)

func _draw_rocket_exhaust(dir: Vector2, perp: Vector2, body_length: float, body_width: float) -> void:
	var flicker := 1.0 + 0.3 * sin(_exhaust_time * exhaust_flicker_speed + _flicker_seed)
	paint_rocket_exhaust(self, dir, perp, body_length, body_width, special_attack, exhaust_length, flicker, _thrust_pulse)

## Pure-geometry exhaust flame painter (no instance state) so it can be drawn live OR
## baked into the rocket texture. Pass flicker=1, thrust=1 for a static bake.
static func paint_rocket_exhaust(ci: CanvasItem, dir: Vector2, perp: Vector2, body_length: float, body_width: float, special_attack: bool, exhaust_length: float, flicker: float, thrust: float) -> void:
	var tail := -dir * (body_length * 0.5 - body_width * 0.12)
	var f := flicker * thrust
	var outer_length: float = exhaust_length * 1.15 * f
	var outer_width: float = body_width * (1.7 if special_attack else 1.4) * (0.9 + thrust * 0.15)
	var outer_tip := tail - dir * outer_length
	var outer_left := tail + perp * outer_width
	var outer_right := tail - perp * outer_width
	var outer_color: Color = Color(1.0, 0.44, 0.12, 0.9) if special_attack else Color(1.0, 0.58, 0.16, 0.85)
	ci.draw_polygon(PackedVector2Array([outer_tip, outer_right, tail, outer_left]), PackedColorArray([outer_color, outer_color, outer_color, outer_color]))
	var inner_length: float = outer_length * 0.62
	var inner_width: float = outer_width * 0.55
	var inner_tip := tail - dir * inner_length
	var inner_left := tail + perp * inner_width
	var inner_right := tail - perp * inner_width
	var inner_color: Color = Color(1.0, 0.78, 0.36, 0.92) if special_attack else Color(1.0, 0.88, 0.46, 0.92)
	ci.draw_polygon(PackedVector2Array([inner_tip, inner_right, tail, inner_left]), PackedColorArray([inner_color, inner_color, inner_color, inner_color]))
	var core_length: float = inner_length * 0.55
	var core_width: float = inner_width * 0.45
	var core_tip := tail - dir * core_length
	var core_left := tail + perp * core_width
	var core_right := tail - perp * core_width
	var core_color := Color(1.0, 0.97, 0.78, 0.95)
	ci.draw_polygon(PackedVector2Array([core_tip, core_right, tail, core_left]), PackedColorArray([core_color, core_color, core_color, core_color]))
	var glow_radius: float = max(body_width * 0.85, inner_width * 0.9)
	var glow_color := Color(outer_color.r, outer_color.g, outer_color.b, outer_color.a * 0.5)
	var inner_glow_color := Color(core_color.r, core_color.g, core_color.b, 0.7)
	var inner_glow_center := tail - dir * (outer_length * 0.4)
	ci.draw_circle(tail, glow_radius, glow_color)
	ci.draw_circle(inner_glow_center, glow_radius * 0.45, inner_glow_color)

func _draw_impact_anticipation(dir: Vector2, body_length: float) -> void:
	# Pulsing glow ahead of the rocket that intensifies near impact
	var pulse := sin(_age * 20.0) * 0.3 + 0.7
	var glow_intensity := _impact_anticipation * pulse
	
	# Forward glow position
	var glow_offset := dir * (body_length * 0.6)
	
	# Outer warning glow (red/orange)
	var outer_radius := 35.0 + _impact_anticipation * 25.0
	var outer_color := Color(1.0, 0.4, 0.2, glow_intensity * 0.4)
	var tinted_outer := _environment_tint(outer_color, glow_offset)
	draw_circle(glow_offset, outer_radius, tinted_outer)
	
	# Middle glow (orange/yellow)
	var mid_radius := 20.0 + _impact_anticipation * 15.0
	var mid_color := Color(1.0, 0.7, 0.3, glow_intensity * 0.6)
	var tinted_mid := _environment_tint(mid_color, glow_offset)
	draw_circle(glow_offset, mid_radius, tinted_mid)
	
	# Inner hot core (white/yellow)
	var inner_radius := 8.0 + _impact_anticipation * 10.0
	var inner_color := Color(1.0, 0.95, 0.8, glow_intensity * 0.8)
	var tinted_inner := _environment_tint(inner_color, glow_offset)
	draw_circle(glow_offset, inner_radius, tinted_inner)
	
	# Danger ring pulsing outward
	if _impact_anticipation > 0.5:
		var ring_expand := fmod(_age * 3.0, 1.0)
		var ring_radius := outer_radius * (0.5 + ring_expand * 0.8)
		var ring_alpha := (1.0 - ring_expand) * glow_intensity * 0.5
		var ring_color := Color(1.0, 0.3, 0.1, ring_alpha)
		var tinted_ring := _environment_tint(ring_color, glow_offset)
		draw_arc(glow_offset, ring_radius, 0, TAU, 24, tinted_ring, 2.5)

func _draw_rocket_body(dir: Vector2, perp: Vector2, body_length: float, body_width: float) -> void:
	paint_rocket_body(self, dir, perp, body_length, body_width, special_attack)

## Pure-geometry rocket body painter (no per-frame/instance state) so the exact same
## look can be drawn by a live missile OR baked into a texture. Centered at the
## canvas origin, pointing along `dir`.
static func paint_rocket_body(ci: CanvasItem, dir: Vector2, perp: Vector2, body_length: float, body_width: float, special_attack: bool) -> void:
	var half_length := body_length * 0.5
	var segment_count := 5 if special_attack else 4
	var segment_span: float = body_length / float(segment_count)
	var segment_half_width: float = body_width * 0.5
	for segment_index in range(segment_count):
		var start_offset := -half_length + segment_span * float(segment_index)
		var end_offset := start_offset + segment_span * 0.9
		var start_vec := dir * start_offset
		var end_vec := dir * end_offset
		var intensity: float = float(segment_index) / max(1.0, float(segment_count - 1))
		var segment_color: Color
		if special_attack:
			segment_color = Color(0.68 + 0.18 * intensity, 0.32 + 0.14 * intensity, 0.32 + 0.12 * intensity, 1.0)
		else:
			segment_color = Color(0.58 + 0.18 * intensity, 0.58 + 0.18 * intensity, 0.68 + 0.2 * intensity, 1.0)
		var body_points := PackedVector2Array([
			end_vec + perp * segment_half_width,
			end_vec - perp * segment_half_width,
			start_vec - perp * segment_half_width,
			start_vec + perp * segment_half_width
		])
		ci.draw_polygon(body_points, PackedColorArray([segment_color, segment_color, segment_color, segment_color]))
		var highlight_width: float = segment_half_width * 0.55
		var highlight_color := segment_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.35)
		var highlight_points := PackedVector2Array([
			end_vec + perp * highlight_width,
			end_vec - perp * highlight_width * 0.2,
			start_vec - perp * highlight_width * 0.2,
			start_vec + perp * highlight_width
		])
		ci.draw_polygon(highlight_points, PackedColorArray([highlight_color, highlight_color, highlight_color, highlight_color]))
	var tip_front := dir * half_length
	var tip_back: Vector2 = dir * (half_length - max(body_width * 0.85, 14.0))
	var tip_color: Color = Color(1.0, 0.58, 0.32, 1.0) if special_attack else Color(1.0, 0.86, 0.45, 1.0)
	var tip_points := PackedVector2Array([tip_front, tip_back + perp * (body_width * 0.5), tip_back - perp * (body_width * 0.5)])
	ci.draw_polygon(tip_points, PackedColorArray([tip_color, tip_color, tip_color]))
	var tip_highlight := tip_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.4)
	var inner_tip_points := PackedVector2Array([tip_front, tip_back + perp * (body_width * 0.28), tip_back - perp * (body_width * 0.28)])
	ci.draw_polygon(inner_tip_points, PackedColorArray([tip_highlight, tip_highlight, tip_highlight]))
	var nose_center := tip_front - dir * (body_width * 0.1)
	var nose_color := Color(tip_color.r, tip_color.g, tip_color.b, 0.45)
	ci.draw_circle(nose_center, body_width * 0.45, nose_color)
	var fin_origin := dir * (-half_length * 0.82)
	var fin_length := body_width * (1.7 if special_attack else 1.35)
	var fin_root_offset := body_width * 0.28
	var fin_angles: Array = [0.75, -0.75, 2.35, -2.35]
	if special_attack:
		fin_angles = fin_angles + [0.0, PI]
	for fin_angle in fin_angles:
		var fin_dir := dir.rotated(fin_angle)
		var fin_tip := fin_origin + fin_dir * fin_length
		var fin_base_left := fin_origin + perp * fin_root_offset
		var fin_base_right := fin_origin - perp * fin_root_offset
		var fin_color: Color = Color(0.82, 0.34, 0.34, 0.85) if special_attack else Color(0.7, 0.52, 0.52, 0.85)
		ci.draw_polygon(PackedVector2Array([fin_base_left, fin_tip, fin_base_right]), PackedColorArray([fin_color, fin_color, fin_color]))
		var fin_highlight := fin_color.lerp(Color(1.0, 0.92, 0.92, 1.0), 0.4)
		var highlight_tip := fin_origin + fin_dir * (fin_length * 0.68)
		var highlight_points := PackedVector2Array([fin_origin + perp * (fin_root_offset * 0.5), highlight_tip, fin_origin - perp * (fin_root_offset * 0.5)])
		ci.draw_polygon(highlight_points, PackedColorArray([fin_highlight, fin_highlight, fin_highlight]))

func _draw_grenade_body() -> void:
	var grenade_radius := 12.0
	var base_color := Color(0.28, 0.34, 0.2, 1.0)
	var shadow_color := Color(0.16, 0.2, 0.11, 1.0)
	var highlight_color := Color(0.65, 0.72, 0.48, 0.65)
	var groove_color := Color(0.18, 0.22, 0.12, 0.95)
	var outline_color := Color(0.12, 0.14, 0.08, 1.0)
	var center := Vector2.ZERO
	var base_tinted := _environment_tint(base_color, center)
	var shadow_offset := center + Vector2(0, grenade_radius * 0.12)
	var shadow_tinted := _environment_tint(shadow_color, shadow_offset)
	var highlight_offset := center - Vector2(grenade_radius * 0.35, grenade_radius * 0.35)
	var highlight_tinted := _environment_tint(highlight_color, highlight_offset)
	var outline_tinted := _environment_tint(outline_color, center)
	draw_circle(center, grenade_radius, base_tinted)
	draw_circle(shadow_offset, grenade_radius * 0.94, shadow_tinted)
	draw_circle(highlight_offset, grenade_radius * 0.42, highlight_tinted)
	draw_arc(center, grenade_radius, 0.0, TAU, 32, outline_tinted, 2.0)
	for groove_index in range(-1, 2):
		var groove_y := float(groove_index) * grenade_radius * 0.35
		var y_start := Vector2(-grenade_radius * 0.7, groove_y)
		var y_end := Vector2(grenade_radius * 0.7, groove_y)
		var groove_tinted := _environment_tint(groove_color, (y_start + y_end) * 0.5)
		draw_line(y_start, y_end, groove_tinted, 2.0)
	for groove_index in range(-1, 2):
		var groove_x := float(groove_index) * grenade_radius * 0.35
		var x_start := Vector2(groove_x, -grenade_radius * 0.7)
		var x_end := Vector2(groove_x, grenade_radius * 0.7)
		var groove_tinted_v := _environment_tint(groove_color, (x_start + x_end) * 0.5)
		draw_line(x_start, x_end, groove_tinted_v, 2.0)
	var strap_width := grenade_radius * 1.4
	var strap_height := grenade_radius * 0.35
	var strap_center := center - Vector2(0, grenade_radius * 0.15)
	var strap_half_w := strap_width * 0.5
	var strap_half_h := strap_height * 0.5
	var strap_points := PackedVector2Array([
		Vector2(-strap_half_w, -strap_half_h) + strap_center,
		Vector2(strap_half_w, -strap_half_h) + strap_center,
		Vector2(strap_half_w, strap_half_h) + strap_center,
		Vector2(-strap_half_w, strap_half_h) + strap_center
	])
	var strap_center_local := (strap_points[0] + strap_points[1] + strap_points[2] + strap_points[3]) * 0.25
	var strap_tinted := _environment_tint(groove_color, strap_center_local)
	draw_polygon(strap_points, PackedColorArray([strap_tinted, strap_tinted, strap_tinted, strap_tinted]))
	var pin_base := Vector2(0, -grenade_radius * 0.7)
	var pin_color := Color(0.78, 0.78, 0.8, 1.0)
	var pin_tinted := _environment_tint(pin_color, pin_base)
	draw_circle(pin_base, grenade_radius * 0.3, pin_tinted)
	var ring_radius := grenade_radius * 0.55
	var ring_points := 36
	var ring_color := Color(0.9, 0.9, 0.92, 0.9)
	var previous_point := Vector2.ZERO
	for i in range(ring_points + 1):
		var angle := TAU * float(i) / float(ring_points)
		var point := pin_base + Vector2(cos(angle), sin(angle)) * ring_radius
		if i > 0:
			var ring_mid := (previous_point + point) * 0.5
			var ring_tinted := _environment_tint(ring_color, ring_mid)
			draw_line(previous_point, point, ring_tinted, 2.0)
		previous_point = point
	var pin_handle := PackedVector2Array([
		pin_base + Vector2(-grenade_radius * 0.25, 0),
		pin_base + Vector2(grenade_radius * 0.35, -grenade_radius * 0.15),
		pin_base + Vector2(grenade_radius * 0.45, grenade_radius * 0.1)
	])
	var handle_center := (pin_handle[0] + pin_handle[1] + pin_handle[2]) / 3.0
	var handle_tinted := _environment_tint(pin_color, handle_center)
	draw_polygon(pin_handle, PackedColorArray([handle_tinted, handle_tinted, handle_tinted]))
