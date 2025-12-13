extends "res://scripts/characters/CharacterController.gd"
class_name CrownController
## Crown - Minigun with Cavalry Charge special and Golden Nova burst
## Special: Summon ethereal horse for invincible charge with V-shaped damage
## Burst: Massive golden AoE blast, upgradeable with forward beam

# Minigun config
var bullet_speed: float = 1100.0
var bullets_per_burst: int = 1

# Special config (Cavalry Charge)
var charge_cooldown: float = 10.0  # Base 10s cooldown
var charge_duration: float = 2.5  # Lasts 2.5 seconds
var charge_speed: float = 600.0  # Fast charge speed
var charge_damage: int = 15  # Base damage per hit
var charge_length: float = 350.0  # How far ahead the V extends
var charge_width: float = 250.0  # Max width at the back of the V
var charge_knockback: float = 400.0  # Knockback force for survivors

# Burst config
const BURST_DAMAGE := 50  # Massive damage
const BURST_DURATION := 1.0  # Visual duration
const BEAM_DURATION := 3.0  # Forward beam lasts 3 seconds
const BEAM_DAMAGE := 25  # Beam damage per tick
const BEAM_TICK_RATE := 0.1  # Damage every 0.1s
const BEAM_WIDTH := 120.0

# Charge state
var _is_charging: bool = false
var _charge_timer: float = 0.0
var _charge_direction: Vector2 = Vector2.RIGHT
var _charge_visual: Node2D = null
var _hit_enemies: Array = []  # Track enemies hit during charge

# Marked enemies (for explosion upgrade)
var _marked_enemies: Array = []  # [{enemy_ref, mark_time, effect_ref}]
const MARK_EXPLOSION_DELAY := 1.5

# Burst beam state
var _beam_active: bool = false
var _beam_timer: float = 0.0
var _beam_tick_timer: float = 0.0
var _beam_direction: Vector2 = Vector2.RIGHT
var _beam_visual: Node2D = null

# Talent states
var special_cooldown_level: int = 0  # -2s per level, max 3
var special_explosion_level: int = 0  # Explosion damage/range upgrade, max 3
var burst_charge_unlocked: bool = false  # Burst generates burst gauge
var burst_beam_unlocked: bool = false  # Adds forward beam to burst

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	data.special_cooldown = charge_cooldown

func _on_process(delta: float) -> void:
	# Update charge state
	if _is_charging:
		_update_charge(delta)
	
	# Update marked enemies
	_update_marked_enemies(delta)
	
	# Update burst beam
	if _beam_active:
		_update_burst_beam(delta)

func _can_attack() -> bool:
	return not is_reloading and ammo > 0 and not _is_charging

func _perform_attack(direction: Vector2) -> void:
	# Fire golden minigun bullet with swirling effect
	const CrownBulletScript = preload("res://scripts/characters/effects/CrownBullet.gd")
	
	# Slight random spread for minigun
	var spread := 0.0
	var spread_dir := direction.rotated(spread)
	
	var bullet = CrownBulletScript.new()
	# Initialize bullet properties before parenting
	bullet.global_position = player.global_position + spread_dir * 30
	bullet.velocity = spread_dir * bullet_speed
	bullet.rotation = spread_dir.angle()
	bullet.owner_node = player
	# Use character's base damage with level scaling
	bullet.base_damage = player.calc_damage()
	
	# Add to world
	player.get_parent().add_child(bullet)
	
	_play_sound("minigun")

func _can_use_special() -> bool:
	return special_timer <= 0 and not _is_charging

func _perform_special(direction: Vector2) -> void:
	# Start cavalry charge
	_is_charging = true
	_charge_timer = charge_duration
	_charge_direction = direction.normalized()
	_hit_enemies.clear()
	
	# Create charge visual
	_spawn_charge_visual()
	
	# Calculate cooldown with upgrades
	var cooldown_reduction := special_cooldown_level * 2.0
	special_timer = max(charge_cooldown - cooldown_reduction, 4.0)
	data.special_cooldown = special_timer

func _update_charge(delta: float) -> void:
	_charge_timer -= delta
	
	if _charge_timer <= 0:
		_end_charge()
		return
	
	# Steer toward mouse position during charge
	var mouse_pos := player.get_global_mouse_position()
	var to_mouse := mouse_pos - player.global_position
	
	# Only steer if mouse is far enough away to have a meaningful direction
	if to_mouse.length() > 20.0:
		var target_dir := to_mouse.normalized()
		# Smooth turning - interpolate toward mouse direction
		_charge_direction = _charge_direction.lerp(target_dir, 6.0 * delta).normalized()
	
	# Move player in charge direction
	player.global_position += _charge_direction * charge_speed * delta
	
	# Update visual position and rotation to match current direction
	if _charge_visual and is_instance_valid(_charge_visual):
		_charge_visual.global_position = player.global_position
		_charge_visual.rotation = _charge_direction.angle()
	
	# Damage enemies in V zone
	_damage_enemies_in_charge_zone()

func _damage_enemies_in_charge_zone() -> void:
	var tree := player.get_tree()
	if not tree:
		return
	
	var enemies := TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		# Skip already hit enemies
		if enemy in _hit_enemies:
			continue
		
		var enemy_node := enemy as Node2D
		var to_enemy := enemy_node.global_position - player.global_position
		
		# Check if within V-shaped zone
		# V extends forward from player, widening toward the back
		var forward_dist := to_enemy.dot(_charge_direction)
		
		# Must be in front of player and within charge length
		if forward_dist < -50 or forward_dist > charge_length:
			continue
		
		# Width increases with distance from tip (V shape)
		# At tip (forward_dist = charge_length), width is small
		# At back (forward_dist = 0), width is charge_width
		var t := 1.0 - clampf(forward_dist / charge_length, 0.0, 1.0)  # 0 at tip, 1 at back
		var max_lateral := 30.0 + t * charge_width * 0.5  # Min 30 at tip, expands toward player
		var lateral: float = abs(to_enemy.dot(_charge_direction.orthogonal()))
		if lateral > max_lateral:
			continue
		
		# Hit this enemy
		_hit_enemies.append(enemy)
		
		# Calculate damage with level scaling
		var scaled_damage: int = player.calc_damage(float(charge_damage) / player.get_base_damage())
		
		if enemy.has_method("take_damage"):
			enemy.take_damage(scaled_damage, false, _charge_direction, true)
		
		# Check if enemy survived and should be marked
		if special_explosion_level > 0 and is_instance_valid(enemy):
			# Check if enemy is still alive (has HP > 0)
			var still_alive := true
			if enemy.has_method("get_hp"):
				still_alive = enemy.get_hp() > 0
			elif "hp" in enemy:
				still_alive = enemy.hp > 0
			
			if still_alive:
				_mark_enemy_for_explosion(enemy)
		
		# Knockback survivors away from V center
		if is_instance_valid(enemy):
			var knockback_dir := to_enemy.normalized()
			if knockback_dir.length_squared() < 0.01:
				knockback_dir = _charge_direction.orthogonal()
			
			if enemy.has_method("apply_knockback"):
				enemy.apply_knockback(knockback_dir * charge_knockback)
			elif "velocity" in enemy:
				enemy.velocity += knockback_dir * charge_knockback

func _mark_enemy_for_explosion(enemy: Node) -> void:
	# Create golden glow effect
	var effect := Node2D.new()
	effect.set_script(_get_mark_effect_script())
	enemy.add_child(effect)
	effect.position = Vector2.ZERO
	
	_marked_enemies.append({
		"enemy_ref": weakref(enemy),
		"effect_ref": weakref(effect),
		"mark_time": Time.get_ticks_msec() * 0.001
	})

func _update_marked_enemies(_delta: float) -> void:
	if _marked_enemies.is_empty():
		return
	
	var now := Time.get_ticks_msec() * 0.001
	var updated: Array = []
	
	for entry in _marked_enemies:
		var enemy_ref: WeakRef = entry.get("enemy_ref")
		var enemy: Node = enemy_ref.get_ref() if enemy_ref else null
		var mark_time: float = entry.get("mark_time", now)
		
		if enemy == null or not is_instance_valid(enemy):
			# Enemy died, clean up effect
			var effect_ref: WeakRef = entry.get("effect_ref")
			if effect_ref:
				var effect: Node = effect_ref.get_ref()
				if effect and is_instance_valid(effect):
					effect.queue_free()
			continue
		
		# Check if explosion time
		if now - mark_time >= MARK_EXPLOSION_DELAY:
			# Explode!
			var pos := (enemy as Node2D).global_position
			_trigger_mark_explosion(pos, enemy)
			
			# Clean up effect
			var effect_ref: WeakRef = entry.get("effect_ref")
			if effect_ref:
				var effect: Node = effect_ref.get_ref()
				if effect and is_instance_valid(effect):
					effect.queue_free()
			continue
		
		updated.append(entry)
	
	_marked_enemies = updated

func _trigger_mark_explosion(position: Vector2, _source_enemy: Node) -> void:
	var tree := player.get_tree()
	if not tree:
		return
	
	# Calculate damage and radius based on upgrade level
	# Base: 2x player attack, +50% per level
	var base_dmg := int(player.get_base_damage() * 2)
	var damage_mult := 1.0 + (special_explosion_level - 1) * 0.5
	var explosion_damage := int(base_dmg * damage_mult)
	
	# Base radius 80, +20% per level
	var base_radius := 80.0
	var radius_mult := 1.0 + (special_explosion_level - 1) * 0.2
	var explosion_radius := base_radius * radius_mult
	
	# Spawn visual
	_spawn_explosion_visual(position, explosion_radius)
	
	# Damage enemies
	var enemies := TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var dist := (enemy as Node2D).global_position.distance_to(position)
		if dist > explosion_radius:
			continue
		
		if enemy.has_method("take_damage"):
			var hit_dir := ((enemy as Node2D).global_position - position).normalized()
			enemy.take_damage(explosion_damage, false, hit_dir, true)

func _spawn_explosion_visual(position: Vector2, radius: float) -> void:
	var visual := Node2D.new()
	visual.set_script(_get_explosion_visual_script())
	visual.set("radius", radius)
	player.get_parent().add_child(visual)
	visual.global_position = position

func _end_charge() -> void:
	_is_charging = false
	_charge_timer = 0.0
	_hit_enemies.clear()
	
	if _charge_visual and is_instance_valid(_charge_visual):
		_charge_visual.queue_free()
		_charge_visual = null

func _spawn_charge_visual() -> void:
	if _charge_visual and is_instance_valid(_charge_visual):
		_charge_visual.queue_free()
	
	_charge_visual = Node2D.new()
	_charge_visual.set_script(_get_charge_visual_script())
	_charge_visual.set("charge_length", charge_length)
	_charge_visual.set("charge_width", charge_width)
	# Add the charge visual to the world and mark its CanvasItems to the
	# effects layer so it's not darkened by world modulate.
	player.get_parent().add_child(_charge_visual)
	_charge_visual.global_position = player.global_position
	_charge_visual.rotation = _charge_direction.angle()
	_charge_visual.z_index = 200

func is_invincible() -> bool:
	return _is_charging  # Invincible during charge

func _on_burst_start() -> void:
	# Massive golden nova
	_spawn_burst_nova()
	
	# If beam upgrade is unlocked, start the beam
	if burst_beam_unlocked:
		_start_burst_beam()
	
	# Screen flash
	if player.screen_flash and player.screen_flash.has_method("flash"):
		player.screen_flash.flash(Color(1.0, 0.9, 0.4, 0.5), 0.5)

func _spawn_burst_nova() -> void:
	var tree := player.get_tree()
	if not tree:
		return
	
	var viewport := player.get_viewport()
	if not viewport:
		return
	
	# Get visible area
	var camera := viewport.get_camera_2d()
	var view_rect: Rect2
	if camera:
		var viewport_size := viewport.get_visible_rect().size
		var cam_pos := camera.global_position
		var half_size := viewport_size / (2.0 * camera.zoom)
		view_rect = Rect2(cam_pos - half_size, half_size * 2.0)
	else:
		view_rect = Rect2(Vector2.ZERO, Vector2(1920, 1080))
	
	# Spawn visual
	var visual := Node2D.new()
	visual.set_script(_get_nova_visual_script())
	visual.set("max_radius", view_rect.size.length() * 0.6)
	# Parent to the player's parent (world) and place on effects layer
	player.get_parent().add_child(visual)
	visual.global_position = player.global_position
	visual.z_index = 200
	
	# Damage all visible enemies
	var enemies := TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_node := enemy as Node2D
		if not view_rect.has_point(enemy_node.global_position):
			continue
		
		if enemy.has_method("take_damage"):
			var hit_dir := (enemy_node.global_position - player.global_position).normalized()
			# Should this charge burst gauge?
			var from_burst := not burst_charge_unlocked
			# Scale burst damage with player level (+50% per level)
			var level_mult: float = 1.0
			if "level" in player:
				level_mult = 1.0 + (player.level - 1) * 0.5
			var scaled_damage := int(BURST_DAMAGE * level_mult)
			enemy.take_damage(scaled_damage, false, hit_dir, from_burst)
		
		# Register hit for burst gauge if upgrade unlocked
		if burst_charge_unlocked and player.has_method("register_burst_hit"):
			player.register_burst_hit(enemy, false)

func _start_burst_beam() -> void:
	_beam_active = true
	_beam_timer = BEAM_DURATION
	_beam_tick_timer = 0.0
	_beam_direction = (player.get_global_mouse_position() - player.global_position).normalized()
	
	# Create beam visual
	_beam_visual = Node2D.new()
	_beam_visual.set_script(_get_beam_visual_script())
	_beam_visual.set("beam_width", BEAM_WIDTH)
	_beam_visual.set("beam_length", 2000.0)  # Long beam
	# Add beam visual to world and mark its CanvasItems to the effects layer
	player.get_parent().add_child(_beam_visual)
	_beam_visual.global_position = player.global_position
	_beam_visual.rotation = _beam_direction.angle()
	_beam_visual.z_index = 200

func _update_burst_beam(delta: float) -> void:
	_beam_timer -= delta
	
	if _beam_timer <= 0:
		_end_burst_beam()
		return
	
	# Update beam direction to follow mouse (like Marian's beam)
	var mouse_pos := player.get_global_mouse_position()
	var to_mouse := mouse_pos - player.global_position
	if to_mouse.length() > 10.0:
		var target_direction := to_mouse.normalized()
		# Smoothly rotate beam toward mouse
		_beam_direction = _beam_direction.lerp(target_direction, 4.0 * delta).normalized()
	
	# Update visual position and rotation (follows player and mouse)
	if _beam_visual and is_instance_valid(_beam_visual):
		_beam_visual.global_position = player.global_position
		_beam_visual.rotation = _beam_direction.angle()
	
	# Damage tick
	_beam_tick_timer -= delta
	if _beam_tick_timer <= 0:
		_beam_tick_timer = BEAM_TICK_RATE
		_damage_enemies_in_beam()

func _damage_enemies_in_beam() -> void:
	var tree := player.get_tree()
	if not tree:
		return
	
	var enemies := TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		var enemy_node := enemy as Node2D
		var to_enemy := enemy_node.global_position - player.global_position
		
		# Check if in beam (rectangular area in front)
		var forward_dist := to_enemy.dot(_beam_direction)
		if forward_dist < 0 or forward_dist > 2000:
			continue
		
		var lateral: float = abs(to_enemy.dot(_beam_direction.orthogonal()))
		if lateral > BEAM_WIDTH * 0.5:
			continue
		
		# Damage enemy
		if enemy.has_method("take_damage"):
			var from_burst := not burst_charge_unlocked
			# Scale beam damage with player level (+50% per level)
			var level_mult: float = 1.0
			if "level" in player:
				level_mult = 1.0 + (player.level - 1) * 0.5
			var scaled_beam_damage := int(BEAM_DAMAGE * level_mult)
			enemy.take_damage(scaled_beam_damage, false, _beam_direction, from_burst)
		
		if burst_charge_unlocked and player.has_method("register_burst_hit"):
			player.register_burst_hit(enemy, false)

func _end_burst_beam() -> void:
	_beam_active = false
	_beam_timer = 0.0
	
	if _beam_visual and is_instance_valid(_beam_visual):
		_beam_visual.queue_free()
		_beam_visual = null

func _on_burst_end() -> void:
	if _beam_active:
		_end_burst_beam()

func _on_cleanup() -> void:
	if _is_charging:
		_end_charge()
	if _beam_active:
		_end_burst_beam()
	
	# Clean up marked enemies
	for entry in _marked_enemies:
		var effect_ref: WeakRef = entry.get("effect_ref")
		if effect_ref:
			var effect: Node = effect_ref.get_ref()
			if effect and is_instance_valid(effect):
				effect.queue_free()
	_marked_enemies.clear()

func _play_sound(weapon_type: String) -> void:
	if player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)

func get_attack_cooldown() -> float:
	return data.attack_cooldown

func _get_weapon_type_name() -> String:
	return "minigun"

## Apply talent upgrade
func apply_talent(talent_id: String) -> void:
	match talent_id:
		"special":
			special_unlocked = true
			reset_special_cooldown()
		"special_cooldown":
			special_cooldown_level = mini(special_cooldown_level + 1, 3)
			var reduction := special_cooldown_level * 2.0
			data.special_cooldown = max(charge_cooldown - reduction, 4.0)
			reset_special_cooldown()
		"special_explosion":
			special_explosion_level = mini(special_explosion_level + 1, 3)
			reset_special_cooldown()
		"burst_charge":
			burst_charge_unlocked = true
		"burst_beam":
			burst_beam_unlocked = true

# ============ VISUAL EFFECT SCRIPTS ============

func _get_charge_visual_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var charge_length: float = 350.0
var charge_width: float = 250.0
var _time: float = 0.0
var _particles: Array = []
var _wisps: Array = []

func _ready() -> void:
	z_index = 150
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 150

	# Initialize particle trails
	for i in range(25):
		_particles.append({
			\"pos\": Vector2(randf_range(-50, 0), randf_range(-30, 30)),
			\"vel\": Vector2(randf_range(-200, -100), randf_range(-50, 50)),
			\"life\": randf(),
			\"size\": randf_range(3, 8)
		})
	# Initialize flowing wisps for edges
	for i in range(12):
		_wisps.append({
			\"offset\": randf() * TAU,
			\"speed\": randf_range(3.0, 6.0),
			\"amplitude\": randf_range(15.0, 35.0),
			\"side\": 1 if i % 2 == 0 else -1
		})

func _process(delta: float) -> void:
	_time += delta
	for p in _particles:
		p.life -= delta * 2.0
		p.pos += p.vel * delta
		if p.life <= 0:
			p.pos = Vector2(randf_range(0, 50), randf_range(-20, 20))
			p.vel = Vector2(randf_range(-300, -150), randf_range(-80, 80))
			p.life = 1.0
			p.size = randf_range(4, 10)
	queue_redraw()

func _draw() -> void:
	var gold: Color = Color(1.0, 0.8, 0.0, 0.95)
	var white_gold: Color = Color(1.0, 1.0, 0.7, 1.0)
	
	# Hard tip point at the front
	var tip: Vector2 = Vector2(charge_length, 0)
	
	# Draw flowing ethereal edges - curves that get more wavy further from tip
	var num_edge_points: int = 20
	var left_edge: PackedVector2Array = PackedVector2Array()
	var right_edge: PackedVector2Array = PackedVector2Array()
	
	left_edge.append(tip)
	right_edge.append(tip)
	
	for i in range(1, num_edge_points + 1):
		var t: float = float(i) / float(num_edge_points)
		var x_pos: float = charge_length * (1.0 - t)
		# Width expands from tip toward player
		var base_y: float = (30.0 + charge_width * 0.5 * t)
		
		# Flowing wave amplitude increases with distance from tip
		var wave_strength: float = t * t * 25.0
		var wave1: float = sin(_time * 8.0 + t * 6.0) * wave_strength
		var wave2: float = sin(_time * 12.0 + t * 4.0 + 1.5) * wave_strength * 0.5
		var wave3: float = sin(_time * 5.0 + t * 8.0 + 3.0) * wave_strength * 0.3
		var total_wave: float = wave1 + wave2 + wave3
		
		left_edge.append(Vector2(x_pos, -base_y + total_wave))
		right_edge.append(Vector2(x_pos, base_y - total_wave))
	
	# Build polygon from edges
	var poly_points: PackedVector2Array = PackedVector2Array()
	for pt in left_edge:
		poly_points.append(pt)
	for i in range(right_edge.size() - 1, -1, -1):
		poly_points.append(right_edge[i])
	
	# Outer ethereal glow
	var glow_points: PackedVector2Array = PackedVector2Array()
	glow_points.append(tip * 1.1)
	for i in range(1, num_edge_points + 1):
		var t: float = float(i) / float(num_edge_points)
		var x_pos: float = charge_length * (1.0 - t) * 1.05
		var base_y: float = (40.0 + charge_width * 0.6 * t)
		var wave: float = sin(_time * 6.0 + t * 5.0) * t * t * 30.0
		glow_points.append(Vector2(x_pos, -base_y + wave))
	for i in range(num_edge_points, 0, -1):
		var t: float = float(i) / float(num_edge_points)
		var x_pos: float = charge_length * (1.0 - t) * 1.05
		var base_y: float = (40.0 + charge_width * 0.6 * t)
		var wave: float = sin(_time * 6.0 + t * 5.0) * t * t * 30.0
		glow_points.append(Vector2(x_pos, base_y - wave))
	draw_colored_polygon(glow_points, Color(1.0, 0.7, 0.0, 0.25))
	
	# Main V body
	draw_colored_polygon(poly_points, gold)
	
	# Inner bright core
	var core_points: PackedVector2Array = PackedVector2Array()
	core_points.append(tip * 0.9)
	for i in range(1, 12):
		var t: float = float(i) / 12.0
		var x_pos: float = charge_length * (1.0 - t) * 0.8
		var base_y: float = (15.0 + charge_width * 0.2 * t)
		var wave: float = sin(_time * 10.0 + t * 4.0) * t * 10.0
		core_points.append(Vector2(x_pos, -base_y + wave))
	for i in range(11, -1, -1):
		var t: float = float(i) / 12.0
		var x_pos: float = charge_length * (1.0 - t) * 0.8
		var base_y: float = (15.0 + charge_width * 0.2 * t)
		var wave: float = sin(_time * 10.0 + t * 4.0) * t * 10.0
		core_points.append(Vector2(x_pos, base_y - wave))
	var pulse: float = 0.8 + sin(_time * 15.0) * 0.2
	draw_colored_polygon(core_points, Color(1.0, 1.0, 0.8, pulse))
	
	# Glowing tip
	draw_circle(tip, 15.0, white_gold)
	draw_circle(tip, 8.0, Color(1.0, 1.0, 1.0, 1.0))
	draw_circle(tip, 6.0, Color(1.0, 1.0, 1.0, 1.0))
	
	# Flowing edge lines with wisps
	for i in range(left_edge.size() - 1):
		var t: float = float(i) / float(left_edge.size())
		var alpha: float = 1.0 - t * 0.5
		draw_line(left_edge[i], left_edge[i + 1], Color(1.0, 1.0, 0.8, alpha), 3.0 - t * 2.0)
		draw_line(right_edge[i], right_edge[i + 1], Color(1.0, 1.0, 0.8, alpha), 3.0 - t * 2.0)
	
	# Ethereal wisps flowing off edges
	for w in _wisps:
		var wisp_t: float = fmod(_time * w.speed + w.offset, 1.0)
		var edge_idx: int = int(wisp_t * (left_edge.size() - 1))
		var edge: PackedVector2Array = left_edge if w.side > 0 else right_edge
		if edge_idx < edge.size():
			var base_pos: Vector2 = edge[edge_idx]
			var wisp_offset: Vector2 = Vector2(-20, w.side * w.amplitude * sin(_time * 4.0 + w.offset))
			var wisp_alpha: float = sin(wisp_t * PI) * 0.6
			draw_circle(base_pos + wisp_offset, 8.0, Color(1.0, 0.95, 0.6, wisp_alpha))
	
	# Sparkle particles
	for p in _particles:
		var alpha: float = p.life * 0.9
		draw_circle(p.pos, p.size * p.life, Color(1.0, 0.95, 0.5, alpha))
	
	# Ethereal horse
	var horse_pulse: float = 0.5 + sin(_time * 6.0) * 0.3
	var horse_color: Color = Color(1.0, 0.85, 0.3, horse_pulse * 0.7)
	var horse_bright: Color = Color(1.0, 0.95, 0.6, horse_pulse * 0.5)
	draw_circle(Vector2(-60, -5), 30, horse_color)
	draw_circle(Vector2(-55, -25), 12, horse_bright)
	draw_line(Vector2(-60, 5), Vector2(-100, 15), horse_color, 18.0)
	draw_circle(Vector2(-130, 15), 45, horse_color)
	draw_circle(Vector2(-130, 15), 25, horse_bright)
	for i in range(6):
		var mane_y: float = -25 + i * 8
		var wave: float = sin(_time * 8.0 + float(i) * 0.8) * 15.0
		var mane_alpha: float = 0.4 + sin(_time * 12.0 + float(i)) * 0.2
		draw_line(Vector2(-65, mane_y), Vector2(-95 + wave, mane_y - 20 + wave * 0.3), 
			Color(1.0, 0.95, 0.6, mane_alpha), 5.0 - float(i) * 0.5)
"""
	script.reload()
	return script

func _get_mark_effect_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var _time: float = 0.0
const DURATION: float = 1.5

func _ready() -> void:
	z_index = 10
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 10

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var progress: float = _time / DURATION
	var pulse: float = 0.6 + sin(_time * 18.0) * 0.4
	var fast_pulse: float = 0.5 + sin(_time * 30.0) * 0.5
	
	# Brilliant saturated gold
	var deep_gold: Color = Color(1.0, 0.7, 0.0, 0.7 * pulse)
	var bright_gold: Color = Color(1.0, 0.85, 0.1, 0.9 * pulse)
	var white_hot: Color = Color(1.0, 1.0, 0.5, fast_pulse)
	
	# Growing radius as explosion approaches
	var base_radius: float = 25.0 + progress * 20.0
	
	# Outer glow ring
	draw_arc(Vector2.ZERO, base_radius * 1.3, 0, TAU, 32, 
		Color(1.0, 0.6, 0.0, 0.3 * pulse), 8.0)
	
	# Main pulsing ring
	draw_arc(Vector2.ZERO, base_radius, 0, TAU, 32, bright_gold, 4.0)
	
	# Inner bright ring
	draw_arc(Vector2.ZERO, base_radius * 0.7, 0, TAU, 24, white_hot, 2.0)
	
	# Center glow
	draw_circle(Vector2.ZERO, base_radius * 0.4, deep_gold)
	draw_circle(Vector2.ZERO, base_radius * 0.2, white_hot)
	
	# Rotating sparkles
	var num_sparkles: int = 6
	for i in range(num_sparkles):
		var angle: float = (float(i) / float(num_sparkles)) * TAU + _time * 4.0
		var sparkle_dist: float = base_radius * 0.85
		var sparkle_pos: Vector2 = Vector2(cos(angle), sin(angle)) * sparkle_dist
		var sparkle_size: float = 4.0 + sin(_time * 20.0 + float(i) * 2.0) * 2.0
		draw_circle(sparkle_pos, sparkle_size, white_hot)
"""
	script.reload()
	return script

func _get_explosion_visual_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var radius: float = 80.0
var _time: float = 0.0
const DURATION: float = 0.5

func _ready() -> void:
	z_index = 200

func _process(delta: float) -> void:
	_time += delta
	if _time >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress: float = _time / DURATION
	var expand: float = 0.3 + progress * 0.7
	var current_radius: float = radius * expand
	
	# Inverse alpha - starts bright, fades out
	var alpha: float = (1.0 - progress) * 1.0
	var flash_alpha: float = (1.0 - progress * progress) * 1.5
	
	# BRILLIANT saturated gold explosion
	var deep_gold: Color = Color(1.0, 0.7, 0.0, alpha)
	var bright_gold: Color = Color(1.0, 0.85, 0.1, alpha)
	var white_hot: Color = Color(1.0, 1.0, 0.5, flash_alpha)
	
	# Outer glow ring
	draw_arc(Vector2.ZERO, current_radius * 1.3, 0, TAU, 48, Color(1.0, 0.6, 0.0, alpha * 0.3), 20.0)
	
	# Main explosion circle - deep gold
	draw_circle(Vector2.ZERO, current_radius, deep_gold)
	
	# Middle ring - bright gold
	draw_circle(Vector2.ZERO, current_radius * 0.75, bright_gold)
	
	# Inner flash - white hot center
	var inner_radius: float = current_radius * 0.4 * (1.0 - progress * 0.5)
	draw_circle(Vector2.ZERO, inner_radius, white_hot)
	
	# Radiating lines
	var num_rays: int = 12
	for i in range(num_rays):
		var angle: float = (float(i) / float(num_rays)) * TAU + _time * 3.0
		var ray_start: Vector2 = Vector2(cos(angle), sin(angle)) * inner_radius
		var ray_end: Vector2 = Vector2(cos(angle), sin(angle)) * current_radius * 1.1
		var ray_alpha: float = alpha * (0.5 + sin(_time * 20.0 + float(i)) * 0.3)
		draw_line(ray_start, ray_end, Color(1.0, 0.9, 0.3, ray_alpha), 3.0)
	
	# Outer ring edge
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 48, white_hot, 4.0 * (1.0 - progress))
	
	# Sparkle particles
	for i in range(8):
		var angle: float = (float(i) / 8.0) * TAU + _time * 5.0
		var dist: float = current_radius * (0.6 + sin(_time * 15.0 + float(i) * 2.0) * 0.3)
		var sparkle_pos: Vector2 = Vector2(cos(angle), sin(angle)) * dist
		var sparkle_size: float = 6.0 * (1.0 - progress)
		draw_circle(sparkle_pos, sparkle_size, white_hot)
"""
	script.reload()
	return script

func _get_nova_visual_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var max_radius: float = 800.0
var _time: float = 0.0
var _angel_wings: Array = []
var _wisps: Array = []
const DURATION: float = 1.5

func _ready() -> void:
	z_index = 200
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 200

	# Create ethereal angel wing tendrils - Diablo 3 style
	for i in range(24):
		var angle: float = (float(i) / 24.0) * TAU
		_angel_wings.append({
			\"base_angle\": angle,
			\"length\": randf_range(0.7, 1.0),
			\"wave_offset\": randf() * TAU,
			\"wave_speed\": randf_range(4.0, 8.0),
			\"width\": randf_range(0.8, 1.2),
			\"segments\": randi_range(8, 12)
		})
	# Floating wisps
	for i in range(40):
		_wisps.append({
			\"angle\": randf() * TAU,
			\"dist\": randf(),
			\"speed\": randf_range(0.5, 2.0),
			\"size\": randf_range(4.0, 12.0),
			\"phase\": randf() * TAU
		})

func _process(delta: float) -> void:
	_time += delta
	if _time >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress: float = _time / DURATION
	var ease_progress: float = 1.0 - pow(1.0 - progress, 2.5)
	var current_radius: float = max_radius * ease_progress
	
	# Alpha - bright start, graceful fade
	var alpha: float = sin(progress * PI) * 1.0
	var flash_alpha: float = pow(1.0 - progress, 1.5) * 1.5
	var wing_alpha: float = (1.0 - progress * 0.6) * 0.9
	
	# Massive outer divine glow
	draw_circle(Vector2.ZERO, current_radius * 1.2, Color(1.0, 0.8, 0.3, alpha * 0.2))
	draw_circle(Vector2.ZERO, current_radius, Color(1.0, 0.85, 0.4, alpha * 0.15))
	
	# ANGEL WINGS - flowing ethereal tendrils like Tyrael
	for wing in _angel_wings:
		var base_angle: float = wing.base_angle
		var wave_offset: float = wing.wave_offset
		var wave_speed: float = wing.wave_speed
		var wing_length: float = current_radius * wing.length
		var num_segments: int = wing.segments
		var base_width: float = 25.0 * wing.width
		
		# Draw each wing tendril as a flowing curve
		var prev_pos: Vector2 = Vector2.ZERO
		var prev_width: float = base_width * 0.3
		
		for s in range(num_segments + 1):
			var t: float = float(s) / float(num_segments)
			var seg_dist: float = wing_length * t
			
			# Flowing wave motion - more pronounced further out
			var wave_amp: float = t * t * 40.0
			var wave1: float = sin(_time * wave_speed + wave_offset + t * 4.0) * wave_amp
			var wave2: float = sin(_time * wave_speed * 0.7 + wave_offset + t * 6.0 + 1.5) * wave_amp * 0.5
			var angle_offset: float = (wave1 + wave2) / seg_dist if seg_dist > 10 else 0
			
			var seg_angle: float = base_angle + angle_offset * 0.3
			var seg_pos: Vector2 = Vector2(cos(seg_angle), sin(seg_angle)) * seg_dist
			
			# Width tapers and flows
			var seg_width: float = base_width * (1.0 - t * 0.7) * (0.8 + sin(_time * 6.0 + t * 3.0) * 0.2)
			
			if s > 0:
				# Draw ethereal wing segment
				var seg_alpha: float = wing_alpha * (1.0 - t * 0.5) * (0.7 + sin(_time * 8.0 + t * 2.0) * 0.3)
				
				# Outer glow
				draw_line(prev_pos, seg_pos, Color(1.0, 0.8, 0.3, seg_alpha * 0.3), seg_width * 2.5)
				# Main tendril
				draw_line(prev_pos, seg_pos, Color(1.0, 0.9, 0.5, seg_alpha * 0.7), seg_width * 1.2)
				# Bright core
				draw_line(prev_pos, seg_pos, Color(1.0, 1.0, 0.8, seg_alpha), seg_width * 0.5)
			
			prev_pos = seg_pos
			prev_width = seg_width
		
		# Glowing tip
		var tip_size: float = 8.0 * (0.7 + sin(_time * 10.0 + wave_offset) * 0.3) * (1.0 - progress * 0.5)
		draw_circle(prev_pos, tip_size, Color(1.0, 1.0, 0.9, wing_alpha * 0.8))
	
	# Floating ethereal wisps
	for w in _wisps:
		var wisp_dist: float = current_radius * w.dist * (0.3 + ease_progress * 0.7)
		var wisp_angle: float = w.angle + _time * w.speed * 0.5
		var wisp_pos: Vector2 = Vector2(cos(wisp_angle), sin(wisp_angle)) * wisp_dist
		
		# Wisps float and pulse
		var float_offset: Vector2 = Vector2(
			sin(_time * 3.0 + w.phase) * 15.0,
			cos(_time * 2.5 + w.phase) * 15.0
		)
		wisp_pos += float_offset
		
		var wisp_alpha: float = alpha * (0.4 + sin(_time * 5.0 + w.phase) * 0.3)
		var wisp_size: float = w.size * (0.8 + sin(_time * 8.0 + w.phase) * 0.2)
		
		draw_circle(wisp_pos, wisp_size * 1.5, Color(1.0, 0.85, 0.4, wisp_alpha * 0.3))
		draw_circle(wisp_pos, wisp_size, Color(1.0, 0.95, 0.7, wisp_alpha * 0.7))
		draw_circle(wisp_pos, wisp_size * 0.4, Color(1.0, 1.0, 0.9, wisp_alpha))
	
	# Expanding holy rings
	for i in range(3):
		var ring_delay: float = float(i) * 0.12
		var ring_progress: float = clamp((progress - ring_delay) / (1.0 - ring_delay * 2), 0.0, 1.0)
		var ring_radius: float = max_radius * ring_progress * 0.9
		var ring_alpha: float = alpha * (1.0 - float(i) * 0.25) * (1.0 - ring_progress * 0.3)
		
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 64, Color(1.0, 0.9, 0.5, ring_alpha * 0.4), 12.0 - float(i) * 3.0)
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 64, Color(1.0, 1.0, 0.8, ring_alpha * 0.6), 4.0 - float(i))
	
	# Divine center - holy light core
	var core_pulse: float = 0.8 + sin(_time * 12.0) * 0.2
	var core_size: float = 100.0 * (1.0 - progress * 0.5) * core_pulse
	draw_circle(Vector2.ZERO, core_size * 2.0, Color(1.0, 0.85, 0.4, flash_alpha * 0.3))
	draw_circle(Vector2.ZERO, core_size * 1.3, Color(1.0, 0.9, 0.5, flash_alpha * 0.5))
	draw_circle(Vector2.ZERO, core_size, Color(1.0, 0.95, 0.7, flash_alpha * 0.7))
	draw_circle(Vector2.ZERO, core_size * 0.5, Color(1.0, 1.0, 0.9, flash_alpha * 0.9))
	draw_circle(Vector2.ZERO, core_size * 0.2, Color(1.0, 1.0, 1.0, flash_alpha))
"""
	script.reload()
	return script

func _get_beam_visual_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node2D

var beam_width: float = 120.0
var beam_length: float = 2000.0
var _time: float = 0.0

func _ready() -> void:
	z_index = 180
	call_deferred("_assign_to_effects_layer")

func _assign_to_effects_layer() -> void:
	var env = get_tree().get_first_node_in_group("environment_controller")
	if env:
		var effects = env.get_node_or_null("EffectsLayer")
		if effects and get_parent() != effects:
			var saved_pos = global_position
			get_parent().remove_child(self)
			effects.add_child(self)
			global_position = saved_pos
			z_as_relative = false
			z_index = 180

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var pulse: float = 0.85 + sin(_time * 15.0) * 0.15
	var fast_pulse: float = 0.7 + sin(_time * 40.0) * 0.3
	
	# Brilliant saturated gold colors
	var deep_gold: Color = Color(1.0, 0.7, 0.0, 0.6 * pulse)
	var bright_gold: Color = Color(1.0, 0.85, 0.1, 0.8 * pulse)
	var white_hot: Color = Color(1.0, 1.0, 0.6, 0.95 * fast_pulse)
	
	var half_width: float = beam_width * 0.5
	
	# Outer glow (widest, most transparent)
	var outer_rect: Rect2 = Rect2(0, -half_width * 1.5, beam_length, beam_width * 1.5)
	draw_rect(outer_rect, Color(1.0, 0.6, 0.0, 0.2 * pulse))
	
	# Main beam body - deep gold
	var main_rect: Rect2 = Rect2(0, -half_width, beam_length, beam_width)
	draw_rect(main_rect, deep_gold)
	
	# Middle layer - bright gold
	var mid_rect: Rect2 = Rect2(0, -half_width * 0.7, beam_length, beam_width * 0.7)
	draw_rect(mid_rect, bright_gold)
	
	# Core - white hot center
	var core_rect: Rect2 = Rect2(0, -half_width * 0.35, beam_length, beam_width * 0.35)
	draw_rect(core_rect, white_hot)
	
	# Pulsing energy lines along beam
	for i in range(3):
		var y_offset: float = (float(i) - 1.0) * half_width * 0.5
		var line_pulse: float = sin(_time * 25.0 + float(i) * 2.0) * 0.3 + 0.7
		draw_line(Vector2(0, y_offset), Vector2(beam_length, y_offset), 
			Color(1.0, 1.0, 0.8, line_pulse * 0.6), 2.0)
	
	# Glowing edges
	draw_line(Vector2(0, -half_width), Vector2(beam_length, -half_width), white_hot, 4.0)
	draw_line(Vector2(0, half_width), Vector2(beam_length, half_width), white_hot, 4.0)
	
	# Origin flash/flare
	draw_circle(Vector2.ZERO, beam_width * 0.8, Color(1.0, 0.9, 0.3, 0.6 * pulse))
	draw_circle(Vector2.ZERO, beam_width * 0.5, Color(1.0, 0.95, 0.5, 0.8 * pulse))
	draw_circle(Vector2.ZERO, beam_width * 0.25, white_hot)
	
	# Energy particles traveling along beam
	for i in range(10):
		var particle_x: float = fmod(_time * 800.0 + float(i) * 200.0, beam_length)
		var particle_y: float = sin(_time * 10.0 + float(i)) * half_width * 0.3
		var particle_size: float = 8.0 + sin(_time * 15.0 + float(i) * 3.0) * 3.0
		draw_circle(Vector2(particle_x, particle_y), particle_size, white_hot)
"""
	script.reload()
	return script
