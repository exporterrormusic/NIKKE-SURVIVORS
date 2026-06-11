extends "res://scripts/characters/CharacterController.gd"
class_name CrownController
## Crown - Minigun
# Special: Royal Guard (Shield wall)
# Burst: Naked King (Huge buff)

func get_is_automatic() -> bool:
	return true
## Special: Summon ethereal horse for invincible charge with V-shaped damage
## Burst: Massive golden AoE blast, upgradeable with forward beam

# Minigun config
var bullet_speed: float = 1100.0
var bullets_per_burst: int = 1

# Special config (Cavalry Charge)
var charge_cooldown: float = 10.0 # Base 10s cooldown
var charge_duration: float = 2.5 # Lasts 2.5 seconds
var charge_speed: float = 600.0 # Fast charge speed
var charge_damage: int = 15 # Base damage per hit
var charge_length: float = 175.0 # How far ahead the V extends (reduced 50%)
var charge_width: float = 125.0 # Max width at the back of the V (reduced 50%)
var charge_knockback: float = 400.0 # Knockback force for survivors

# Burst config
const BURST_DAMAGE := 50 # Massive damage
const BURST_DURATION := 1.0 # Visual duration
const BEAM_DURATION := 3.0 # Forward beam lasts 3 seconds
const BEAM_DAMAGE := 25 # Beam damage per tick
const BEAM_TICK_RATE := 0.1 # Damage every 0.1s
const BEAM_WIDTH := 120.0

# Charge state
var _is_charging: bool = false
var _charge_timer: float = 0.0
var _charge_direction: Vector2 = Vector2.RIGHT
var _charge_visual: Node2D = null
var _hit_enemies: Array = [] # Track enemies hit during charge
var _post_charge_invincibility_timer: float = 0.0 # Safety buffer after charge ends

# Marked enemies (for explosion upgrade)
var _marked_enemies: Array = [] # [{enemy_ref, mark_time, effect_ref}]
const MARK_EXPLOSION_DELAY := 1.5

# Burst beam state
var _beam_active: bool = false
var _beam_timer: float = 0.0
var _beam_tick_timer: float = 0.0
var _beam_direction: Vector2 = Vector2.RIGHT
var _beam_visual: Node2D = null

# Talent states
var special_cooldown_level: int = 0 # -2s per level, max 3
var special_explosion_level: int = 0 # Explosion damage/range upgrade, max 3
var burst_charge_unlocked: bool = false # Burst generates burst gauge
var burst_beam_unlocked: bool = false # Adds forward beam to burst

# Trombe stacking upgrade state
var _has_trombe_stacking_upgrade: bool = false
var _trombe_stack_timers: Array = [] # Each entry is remaining time for that stack
const TROMBE_STACK_DURATION := 12.0
const TROMBE_STACK_MULTIPLIER := 1.35
const TROMBE_MAX_STACKS := 3

func _on_initialize() -> void:
	# Ammo already set from CharacterRegistry by base class
	data.special_cooldown = charge_cooldown
	
	# Check for Trombe stacking upgrade
	var ShopMenuScript = load("res://scripts/ui/ShopMenu.gd")
	if ShopMenuScript and ShopMenuScript.has_character_upgrade("crown", "trombe_stacking"):
		_has_trombe_stacking_upgrade = true
		print("[Crown] 'How Does This Keep Working?' upgrade active - Trombe stacks!")

func _on_process(delta: float) -> void:
	# Update charge state
	if _is_charging:
		_update_charge(delta)
	
	if _post_charge_invincibility_timer > 0:
		_post_charge_invincibility_timer -= delta
	
	# Update marked enemies
	_update_marked_enemies(delta)
	
	# Update burst beam
	if _beam_active:
		_update_burst_beam(delta)
	
	# Update Trombe stacking timers (each stack decays independently)
	if _has_trombe_stacking_upgrade and not _trombe_stack_timers.is_empty():
		var updated_timers: Array = []
		for timer in _trombe_stack_timers:
			var remaining = timer - delta
			if remaining > 0:
				updated_timers.append(remaining)
		_trombe_stack_timers = updated_timers

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
	
	# Add Trombe stack if upgrade owned (each use adds a stack, not refresh)
	if _has_trombe_stacking_upgrade:
		if _trombe_stack_timers.size() < TROMBE_MAX_STACKS:
			_trombe_stack_timers.append(TROMBE_STACK_DURATION)
			print("[Crown] Trombe stack added. Current stacks: %d" % _trombe_stack_timers.size())
	
	# Create charge visual
	_spawn_charge_visual()
	
	# Scale visual to match hitbox size with stacks
	if _has_trombe_stacking_upgrade and not _trombe_stack_timers.is_empty() and _charge_visual:
		var visual_scale: float = pow(TROMBE_STACK_MULTIPLIER, _trombe_stack_timers.size())
		_charge_visual.scale = Vector2(visual_scale, visual_scale)
		print("[Crown] Trombe visual scaled to %.2fx" % visual_scale)
	
	# Calculate cooldown with upgrades (1.5s per level)
	var cooldown_reduction := special_cooldown_level * 1.5
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
	
	# Calculate size multiplier from Trombe stacks (1.5x per stack)
	var size_mult := 1.0
	if _has_trombe_stacking_upgrade and not _trombe_stack_timers.is_empty():
		size_mult = pow(TROMBE_STACK_MULTIPLIER, _trombe_stack_timers.size())
	var effective_length := charge_length * size_mult
	var effective_width := charge_width * size_mult
	
	var enemies := TargetCache.get_enemies()
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		
		# Skip already hit enemies
		if enemy in _hit_enemies:
			continue
			
		# Skip charmed allies (Sin's mind control)
		if enemy.is_in_group("charmed_allies"):
			continue
		
		var enemy_node := enemy as Node2D
		var to_enemy := enemy_node.global_position - player.global_position
		
		# Check if within V-shaped zone
		# V extends forward from player, widening toward the back
		var forward_dist := to_enemy.dot(_charge_direction)
		
		# Must be in front of player and within charge length
		if forward_dist < -50 or forward_dist > effective_length:
			continue
		
		# Width increases with distance from tip (V shape)
		# At tip (forward_dist = charge_length), width is small
		# At back (forward_dist = 0), width is charge_width
		var t := 1.0 - clampf(forward_dist / effective_length, 0.0, 1.0) # 0 at tip, 1 at back
		var max_lateral := 30.0 * size_mult + t * effective_width * 0.5 # Scale tip width too
		var lateral: float = abs(to_enemy.dot(_charge_direction.orthogonal()))
		if lateral > max_lateral:
			continue
		
		# Hit this enemy
		_hit_enemies.append(enemy)
		
		# Trombe damage = 2x Crown's current attack
		var trombe_damage: int = player.calc_damage() * 2
		
		if enemy.has_method("take_damage"):
			enemy.take_damage(trombe_damage, false, _charge_direction, true)
		
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
	
	# Calculate damage based on upgrade level: 1x/2x/3x player attack
	var damage_multiplier: int = special_explosion_level # Level 1=1x, Level 2=2x, Level 3=3x
	var explosion_damage: int = player.calc_damage() * damage_multiplier
	
	# Fixed explosion radius
	var explosion_radius := 100.0
	
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
	_post_charge_invincibility_timer = 1.0 # 1 second of i-frames to dismount safely
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
	return _is_charging or _post_charge_invincibility_timer > 0 # Invincible during charge + buffer

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
			
		# Skip charmed allies (Sin's mind control)
		if enemy.is_in_group("charmed_allies"):
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
			# Tag as CrownBurst so it doesn't recharge burst in Goddess Fall mode
			enemy.take_damage(scaled_damage, false, hit_dir, from_burst, "CrownBurst")
		
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
	_beam_visual.set("beam_length", 2000.0) # Long beam
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
		# Smoothly rotate beam toward mouse (Increased speed for responsiveness)
		_beam_direction = _beam_direction.lerp(target_direction, 25.0 * delta).normalized()
	
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
			
		# Skip charmed allies (Sin's mind control)
		if enemy.is_in_group("charmed_allies"):
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
			# Tag as CrownBurst so it doesn't recharge burst in Goddess Fall mode
			enemy.take_damage(scaled_beam_damage, false, _beam_direction, from_burst, "CrownBurst")
		
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
	var script := preload("res://scripts/characters/effects/visuals/CrownChargeVisual.gd")
	return script

func _get_mark_effect_script() -> GDScript:
	var script := preload("res://scripts/characters/effects/visuals/CrownMarkEffect.gd")
	return script

func _get_explosion_visual_script() -> GDScript:
	var script := preload("res://scripts/characters/effects/visuals/CrownExplosionVisual.gd")
	return script

func _get_nova_visual_script() -> GDScript:
	var script := preload("res://scripts/characters/effects/visuals/CrownNovaVisual.gd")
	return script

func _get_beam_visual_script() -> GDScript:
	var script := preload("res://scripts/characters/effects/visuals/CrownBeamVisual.gd")
	return script
