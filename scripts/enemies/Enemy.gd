extends CharacterBody2D

@onready var hp_bar = $ProgressBar
@onready var _animator = $AnimatedSprite2D

var hp = 1
var max_hp = 1
var speed = 150
var base_damage: int = 1  # Base contact damage (scaled by Goddess Fall ATK multiplier)
var player

# HP bar overlay for drawing text
var _hp_overlay: Node2D = null

# Simple distance-based behavior - no physics collision
const STOP_DISTANCE := 45.0
const DAMAGE_DISTANCE := 50.0
const DAMAGE_COOLDOWN := 1.0
const CLONE_AGGRO_RANGE := 300.0  # Range at which enemies will target clones instead of player
var _damage_timer := 0.0
var _current_target: Node2D = null  # Current attack target (player or clone)

var is_stunned = false
var stun_timer = 0.0

# Charmed state (Sin's special ability)
var _is_charmed := false
var _charm_owner: Node = null
var _charm_target: Node = null  # Current enemy target when charmed

# Track who killed this enemy for burst/shield charging
# Valid sources that charge burst: "player", "projectile", "cecil_drone"
# Invalid sources: "charmed_enemy", "summon", "unknown"
var _killer_source: String = "player"

# Laser shooting parameters
const LASER_RANGE := 500.0           # Distance at which enemy can shoot
const LASER_FIRE_INTERVAL := 3.0     # Seconds between shots (base)
const LASER_SPEED := 500.0           # Laser projectile speed
const LASER_DAMAGE := 1              # Damage per laser hit
const LASER_CHARGE_TIME := 1.0       # Seconds to charge before firing
var _laser_cooldown := 0.0
var _can_shoot := true               # Toggle for enabling/disabling shooting
var _is_charging := false
var _charge_timer := 0.0

# Get laser fire interval (30% faster in Goddess Fall mode)
func _get_laser_fire_interval() -> float:
	if GameState and GameState.goddess_fall_mode:
		return LASER_FIRE_INTERVAL * 0.7  # 30% faster
	return LASER_FIRE_INTERVAL

# Get laser charge time (30% faster in Goddess Fall mode)
func _get_laser_charge_time() -> float:
	if GameState and GameState.goddess_fall_mode:
		return LASER_CHARGE_TIME * 0.7  # 30% faster
	return LASER_CHARGE_TIME
var _charge_direction := Vector2.ZERO
var _charge_effect: Node2D = null

# Preload laser scene
const EnemyLaserScene = preload("res://scenes/projectiles/EnemyLaser.tscn")

# Preload effect scripts (cached at class level for performance)
const HitSparkScript = preload("res://scripts/effects/HitSpark.gd")
const FloatingNumberScript = preload("res://scripts/effects/FloatingDamageNumber.gd")

func _ready():
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	_setup_hp_label()
	
	# Create shadow under enemy
	_create_shadow()
	
	# Find player in the scene tree (may be sibling or under Level node)
	player = get_tree().get_first_node_in_group("player")
	if not player:
		# Fallback: search up the tree for Level node
		var level = get_tree().current_scene
		if level and level.has_node("Player"):
			player = level.get_node("Player")
	# Load rapture enemy sprite with animator
	var texture = load("res://assets/enemies/rapture-basic/sprite.png")
	if texture and _animator:
		_animator.configure(texture, 3, 4, 6.0, 0.15)
	add_to_group("enemies")
	
	# Apply glow shader so enemy glows through night darkness
	_apply_glow_shader()
	
	# Randomize initial cooldown so enemies don't all fire at once
	_laser_cooldown = randf_range(0.0, _get_laser_fire_interval())

func _create_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	# Use cached texture for performance (40x16 is close enough to 48x24)
	shadow.texture = TextureCache.get_shadow_ellipse(48, 24)
	shadow.scale = Vector2(40.0 / 48.0, 16.0 / 24.0)  # Scale to exact size
	shadow.modulate = Color(0.3, 0.1, 0.1, 0.35)  # Dark red-grey tint
	shadow.position = Vector2(0, 18)  # Below feet
	shadow.z_index = -1  # Behind enemy
	add_child(shadow)

func _create_ellipse_texture(_width: int, _height: int) -> Texture2D:
	# Deprecated - use TextureCache.get_shadow_ellipse() instead
	return TextureCache.get_shadow_ellipse(48, 24)

func _apply_glow_shader() -> void:
	# Load the unshaded shader so enemy shows at full brightness at night
	var shader = load("res://resources/shaders/enemy_red_glow.gdshader")
	if shader and _animator:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		_animator.material = mat

func _setup_hp_label() -> void:
	# Create a Node2D overlay that draws text on top of the HP bar
	_hp_overlay = Node2D.new()
	_hp_overlay.z_index = 10
	# Position at the center of the HP bar (bar is at -47 to -37, so center is -42)
	_hp_overlay.position = Vector2(0, -42)
	# Set script BEFORE adding to tree so _ready() is called properly
	_hp_overlay.set_script(preload("res://scripts/enemies/EnemyHPLabel.gd"))
	add_child(_hp_overlay)
	_hp_overlay.setup(self)

func _update_hp_label() -> void:
	if _hp_overlay and _hp_overlay.has_method("update_values"):
		_hp_overlay.update_values(hp, max_hp)

func _process(delta: float) -> void:
	# Death anticipation MUST run in _process, not _physics_process
	# because physics process gets disabled when enemies are frozen (Commander's freeze)
	# but they still need to die when HP reaches 0
	_process_death_anticipation(delta)

func _physics_process(delta: float) -> void:
	# Process knockback visual
	_process_knockback_visual(delta)
	
	# Don't process anything else during death anticipation
	if _death_anticipation:
		velocity = Vector2.ZERO
		return
	
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
			if has_node("SparkleEffect"):
				get_node("SparkleEffect").queue_free()
		else:
			# Stunned: don't move
			velocity = Vector2.ZERO
			return
	
	# Charmed enemies attack other enemies
	if _is_charmed:
		_process_charmed_behavior(delta)
		return
	
	if not player or not is_instance_valid(player):
		return
	
	_damage_timer -= delta
	_laser_cooldown -= delta
	
	# Find best target (clone if nearby, otherwise player)
	_current_target = _find_best_target()
	
	if not _current_target or not is_instance_valid(_current_target):
		_current_target = player
	
	var to_target: Vector2 = _current_target.global_position - global_position
	var dist: float = to_target.length()
	var dir: Vector2 = to_target.normalized() if dist > 0 else Vector2.ZERO
	
	# Handle charging state
	if _is_charging:
		_charge_timer += delta
		# Update charge direction to track target
		_charge_direction = dir
		# Update charge effect position and direction
		_update_charge_effect()
		# Fire when charge is complete
		if _charge_timer >= _get_laser_charge_time():
			_fire_laser(_charge_direction)
			_end_charging()
			_laser_cooldown = _get_laser_fire_interval()
		# Don't move while charging
		velocity = Vector2.ZERO
	else:
		# Chase target, but stop at STOP_DISTANCE
		if dist > STOP_DISTANCE:
			global_position += dir * speed * delta
		
		# Deal damage when close
		if dist < DAMAGE_DISTANCE and _damage_timer <= 0:
			if _current_target and _current_target.has_method("take_damage"):
				_current_target.take_damage(base_damage)
			_damage_timer = DAMAGE_COOLDOWN
		
		# Attempt to start charging laser at target
		if _can_shoot:
			_attempt_laser_attack(dist, dir)
	
	# Animation
	velocity = dir * speed if dist > STOP_DISTANCE else Vector2.ZERO
	if _animator:
		_animator.update_state(velocity, dir)

func _find_best_target() -> Node2D:
	"""Find the closest valid target. Prioritizes proximity - charmed enemies, clones, or player."""
	var tree := get_tree()
	if not tree:
		return player
	
	var nearest_target: Node2D = null
	var nearest_dist: float = INF
	
	# Check for nearby charmed allies (enemies that switched to player's side)
	var charmed_allies := tree.get_nodes_in_group("charmed_allies")
	for ally in charmed_allies:
		if ally == self:  # Don't target ourselves
			continue
		if not is_instance_valid(ally) or not ally is Node2D:
			continue
		# Skip dead enemies
		if ally.get("hp") != null and ally.get("hp") <= 0:
			continue
		
		var dist := global_position.distance_to((ally as Node2D).global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_target = ally as Node2D
	
	# Check for nearby clones
	var clones := tree.get_nodes_in_group("nayuta_clones")
	for clone in clones:
		if not is_instance_valid(clone) or not clone is Node2D:
			continue
		# Skip dying clones
		if clone.get("_is_dying") == true:
			continue
		if clone.get("current_hp") != null and clone.get("current_hp") <= 0:
			continue
		
		var dist := global_position.distance_to((clone as Node2D).global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_target = clone as Node2D
	
	# Check player distance
	if player and is_instance_valid(player):
		var player_dist := global_position.distance_to(player.global_position)
		if player_dist < nearest_dist:
			nearest_dist = player_dist
			nearest_target = player
	
	# Return the closest target, or player as fallback
	return nearest_target if nearest_target else player

func _attempt_laser_attack(distance: float, direction: Vector2) -> void:
	# Check if we can start charging
	if _laser_cooldown > 0.0:
		return
	if distance > LASER_RANGE:
		return
	if is_stunned:
		return
	if _is_charging:
		return
	
	# Start charging
	_start_charging(direction)

func _start_charging(direction: Vector2) -> void:
	_is_charging = true
	_charge_timer = 0.0
	_charge_direction = direction.normalized()
	if _charge_direction == Vector2.ZERO:
		_charge_direction = Vector2.RIGHT
	
	# Create charging visual effect
	_charge_effect = Node2D.new()
	_charge_effect.z_index = 15
	_charge_effect.set_script(preload("res://scripts/enemies/EnemyChargeEffect.gd"))
	add_child(_charge_effect)
	_charge_effect.position = _charge_direction * 25.0
	_charge_effect.start_charge(_get_laser_charge_time())

func _update_charge_effect() -> void:
	if _charge_effect and is_instance_valid(_charge_effect):
		_charge_effect.position = _charge_direction * 25.0
		if _charge_effect.has_method("set_progress"):
			_charge_effect.set_progress(_charge_timer / _get_laser_charge_time())

func _end_charging() -> void:
	_is_charging = false
	_charge_timer = 0.0
	if _charge_effect and is_instance_valid(_charge_effect):
		_charge_effect.queue_free()
		_charge_effect = null

func _fire_laser(direction: Vector2) -> void:
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	
	var laser = EnemyLaserScene.instantiate()
	if laser == null:
		return
	
	# Configure laser with longer range
	laser.set_direction(dir)
	laser.speed = LASER_SPEED
	laser.max_range = LASER_RANGE * 1.5  # Extended range
	laser.damage = base_damage  # Use scaled base_damage instead of constant
	laser.lifetime = maxf((LASER_RANGE * 1.5) / LASER_SPEED, 1.0)
	
	# Spawn slightly in front of enemy
	laser.global_position = global_position + dir * 20.0
	
	# Add to scene
	if get_parent():
		get_parent().add_child(laser)

func _fire_laser_at_enemy(direction: Vector2) -> void:
	"""Fire a laser at another enemy (used by charmed enemies)."""
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	
	var laser = EnemyLaserScene.instantiate()
	if laser == null:
		return
	
	# Configure laser - friendly fire version (hits enemies, not player)
	laser.set_direction(dir)
	laser.speed = LASER_SPEED
	laser.max_range = LASER_RANGE * 1.5
	laser.damage = base_damage
	laser.lifetime = maxf((LASER_RANGE * 1.5) / LASER_SPEED, 1.0)
	
	# Mark this laser as friendly (from charmed enemy)
	laser.set_meta("from_charmed", true)
	
	# Spawn slightly in front of enemy
	laser.global_position = global_position + dir * 20.0
	
	# Add to scene
	if get_parent():
		get_parent().add_child(laser)

# Combat juice
var _knockback_offset: Vector2 = Vector2.ZERO
var _last_hit_direction: Vector2 = Vector2.ZERO
var _death_anticipation: bool = false
var _death_anticipation_timer: float = 0.0
var _overkill_damage: int = 0  # Track excess damage for overkill effect
const DEATH_ANTICIPATION_TIME := 0.12  # Longer freeze before death (MORE NOTICEABLE)

func take_damage(dmg, is_crit: bool = false, hit_direction: Vector2 = Vector2.ZERO, from_burst: bool = false, killer_source: String = "player"):
	# Don't take damage if already dying
	if _death_anticipation:
		return
	
	# Track killer source for burst/shield charging
	_killer_source = killer_source
	
	# Debug: One-hit kill check
	var debug_player = get_tree().get_first_node_in_group("player")
	if debug_player and debug_player.has_meta("debug_one_hit_kill") and debug_player.get_meta("debug_one_hit_kill"):
		dmg = 999999
	
	# Apply vulnerability debuff if present (from Scarlet's Expose Weakness talent)
	var actual_dmg: int = dmg
	if has_meta("damage_vulnerability"):
		var vuln_mult: float = get_meta("damage_vulnerability")
		actual_dmg = int(dmg * vuln_mult)
	
	# Apply super boss aura damage reduction (Goddess Fall mode)
	if has_meta("super_boss_damage_reduction"):
		var reduction: float = get_meta("super_boss_damage_reduction")
		actual_dmg = int(actual_dmg * (1.0 - reduction))
	
	hp -= actual_dmg
	hp_bar.value = hp
	_update_hp_label()
	
	# Store hit direction for knockback visual
	_last_hit_direction = hit_direction if hit_direction != Vector2.ZERO else Vector2.RIGHT
	
	# Knockback visual (just visual offset, not actual movement) - MORE NOTICEABLE
	_knockback_offset = _last_hit_direction * 15.0
	
	# Spawn hit spark (uses cached preload)
	if get_parent():
		if is_crit:
			HitSparkScript.spawn_critical(get_parent(), global_position, _last_hit_direction)
		else:
			HitSparkScript.spawn_normal(get_parent(), global_position, _last_hit_direction)
	
	# Camera punch only on critical hits
	if is_crit:
		CombatJuice.camera_punch(-_last_hit_direction, 4.0)
	
	# Spawn floating damage number (uses cached preload)
	if get_parent():
		if is_crit:
			FloatingNumberScript.spawn_critical(get_parent(), global_position + Vector2(0, -50), actual_dmg)
		else:
			FloatingNumberScript.spawn_damage(get_parent(), global_position + Vector2(0, -50), actual_dmg)
	
	if hp <= 0:
		# Calculate overkill (excess damage beyond what was needed)
		_overkill_damage = -hp  # hp is negative, so negate it
		
		# Only grant burst gauge if kill was from valid source (not charmed enemies or generic summons)
		# Also skip if this enemy was charmed (mind controlled) - they're on our side
		# Valid sources: player, projectile, cecil_drone
		var valid_burst_source: bool = _killer_source in ["player", "projectile", "cecil_drone"]
		var is_charmed_enemy: bool = is_in_group("charmed_allies")
		if not from_burst and valid_burst_source and not is_charmed_enemy and player and player.has_method("register_burst_hit"):
			player.register_burst_hit()
		
		# Death anticipation - brief freeze before exploding
		_death_anticipation = true
		_death_anticipation_timer = DEATH_ANTICIPATION_TIME

func _process_death_anticipation(delta: float) -> void:
	if not _death_anticipation:
		return
	
	_death_anticipation_timer -= delta
	if _death_anticipation_timer <= 0:
		_death_anticipation = false
		call_deferred("die")

var _is_dead: bool = false  # Prevent multiple die() calls

func _process_knockback_visual(_delta: float) -> void:
	# Decay knockback offset with spring physics
	_knockback_offset *= 0.8
	if _animator:
		_animator.position = _knockback_offset

func apply_stun(duration: float):
	is_stunned = true
	stun_timer = duration
	# Cancel charging if stunned
	if _is_charging:
		_end_charging()
	if has_node("SparkleEffect"):
		get_node("SparkleEffect").duration = duration
	else:
		var sparkle = Node2D.new()
		sparkle.name = "SparkleEffect"
		sparkle.set_script(preload("res://scripts/effects/SparkleEffect.gd"))
		sparkle.duration = duration
		sparkle.z_index = 10
		add_child(sparkle)

func set_can_shoot(enabled: bool) -> void:
	"""Enable or disable shooting for this enemy."""
	_can_shoot = enabled

func die():
	# Prevent multiple die() calls
	if _is_dead:
		return
	_is_dead = true
	
	# Calculate overkill multiplier (3x damage = overkill)
	var overkill_multiplier := 1.0
	var is_overkill: bool = _overkill_damage >= (max_hp * 2)  # 3x total = 2x excess
	if is_overkill:
		overkill_multiplier = 2.0
	
	# Add score to GameState
	var score_value: int = 100  # Base score
	if has_meta("enemy_tier"):
		var tier: String = get_meta("enemy_tier")
		match tier:
			"elite": score_value = 500
			"boss": score_value = 2000
			"super_boss": score_value = 5000
			"tank": score_value = 300
	if is_overkill:
		score_value = int(score_value * 1.5)  # Bonus for overkill
	if GameState:
		GameState.add_score(score_value)
	
	# Drop pristine cores if boss/super_boss - spawn visual orb
	# Don't drop if dying from enrage timer (player loses)
	if has_meta("pristine_core_drop"):
		var killed_by_enrage: bool = GameState != null and GameState.has_meta("killed_by_enrage") and GameState.get_meta("killed_by_enrage") == true
		if not killed_by_enrage:
			var cores_to_drop: int = get_meta("pristine_core_drop")
			_spawn_pristine_core_orb(cores_to_drop)
			print("[Enemy] Spawned Pristine Core orb worth ", cores_to_drop, " core(s)!")
	
	# Register kill with combat juice for momentum
	CombatJuice.register_kill(overkill_multiplier)
	
	# Spawn robot death effect
	var death_effect := Node2D.new()
	death_effect.set_script(preload("res://scripts/effects/RobotDeathEffect.gd"))
	death_effect.global_position = global_position
	# Pass overkill state for bigger explosion
	if death_effect.has_method("set_overkill"):
		death_effect.set_overkill(is_overkill)
	get_parent().add_child(death_effect)
	
	# Spawn XP orbs - more for special enemies
	var xp_orb_count := 5  # Base amount
	if has_meta("enemy_tier"):
		var tier: String = get_meta("enemy_tier")
		match tier:
			"tank": xp_orb_count = 8
			"elite": xp_orb_count = 15
			"boss": xp_orb_count = 25
			"super_boss": xp_orb_count = 40
	
	for i in xp_orb_count:
		var orb = ProjectileCache.create_xp_orb()
		get_parent().add_child(orb)
		orb.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	call_deferred("queue_free")

func _spawn_pristine_core_orb(cores_value: int) -> void:
	# Spawn a visual orb that flies to the core counter
	var orb_script := preload("res://scripts/world/PristineCoreOrb.gd")
	var orb := Area2D.new()
	orb.set_script(orb_script)
	orb.cores_value = cores_value
	orb.global_position = global_position
	get_parent().add_child(orb)

# --- Charm system ---
func set_charmed(charm_owner: Node, charmed: bool = true) -> void:
	"""Set this enemy as charmed (fighting for player) or uncharm."""
	# Only normal enemies can be charmed (not elite, boss, tank)
	if has_meta("enemy_tier"):
		var tier: String = get_meta("enemy_tier")
		if tier in ["elite", "boss", "tank"]:
			return
	
	_is_charmed = charmed
	_charm_owner = charm_owner if charmed else null
	_charm_target = null
	
	if charmed:
		# Add charm visual effect
		if not has_node("CharmEffect"):
			var charm_fx := Node2D.new()
			charm_fx.name = "CharmEffect"
			charm_fx.set_script(preload("res://scripts/characters/effects/SinCharmEffect.gd"))
			charm_fx.z_index = 10
			add_child(charm_fx)
		# Apply purple tint to sprite
		if _animator:
			_animator.modulate = Color(0.8, 0.5, 1.0, 1.0)
	else:
		# Remove charm visual
		if has_node("CharmEffect"):
			get_node("CharmEffect").queue_free()
		# Restore normal tint
		if _animator:
			_animator.modulate = Color.WHITE

func is_charmed() -> bool:
	return _is_charmed

func _process_charmed_behavior(delta: float) -> void:
	"""Charmed enemies seek and attack other non-charmed enemies."""
	_damage_timer -= delta
	_laser_cooldown -= delta  # Also update laser cooldown for ranged attacks
	
	# Find a target enemy if we don't have one or it's invalid
	if _charm_target == null or not is_instance_valid(_charm_target) or _charm_target._is_charmed:
		_charm_target = _find_nearest_enemy()
	
	if _charm_target == null:
		# No valid targets, just idle
		velocity = Vector2.ZERO
		if _animator:
			_animator.update_state(Vector2.ZERO, Vector2.RIGHT)
		return
	
	var to_target: Vector2 = _charm_target.global_position - global_position
	var dist: float = to_target.length()
	var dir: Vector2 = to_target.normalized() if dist > 0 else Vector2.ZERO
	
	# Ranged attack: shoot at target if in laser range
	if dist <= LASER_RANGE and _laser_cooldown <= 0 and _can_shoot:
		_fire_laser_at_enemy(dir)
		_laser_cooldown = LASER_FIRE_INTERVAL
	
	# Chase the target if out of laser range or can't shoot
	if dist > LASER_RANGE * 0.8:  # Stay at comfortable shooting distance
		global_position += dir * speed * delta
	elif dist < STOP_DISTANCE * 2:  # Too close, back up a bit
		global_position -= dir * speed * 0.5 * delta
	
	# Melee damage when very close (fallback)
	if dist < DAMAGE_DISTANCE and _damage_timer <= 0:
		if _charm_target.has_method("take_damage"):
			# Pass "charmed_enemy" as killer source - doesn't charge burst/shield
			_charm_target.take_damage(base_damage, false, Vector2.ZERO, false, "charmed_enemy")
		_damage_timer = DAMAGE_COOLDOWN
	
	# Animation
	velocity = dir * speed if dist > LASER_RANGE * 0.8 else Vector2.ZERO
	if _animator:
		_animator.update_state(velocity, dir)

func _find_nearest_enemy() -> Node:
	"""Find the nearest non-charmed enemy."""
	var nearest: Node = null
	var nearest_dist: float = INF
	
	var parent := get_parent()
	if parent == null:
		return null
	
	for child in parent.get_children():
		if child == self:
			continue
		if not child.is_in_group("enemies"):
			continue
		# Skip other charmed enemies (they're on our side now)
		if child.is_in_group("charmed_allies"):
			continue
		if child.get("hp") != null and child.hp <= 0:
			continue
		
		var dist: float = global_position.distance_to(child.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = child
	
	return nearest
