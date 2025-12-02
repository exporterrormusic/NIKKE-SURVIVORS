extends CharacterBody2D

@onready var hp_bar = $ProgressBar
@onready var _animator = $AnimatedSprite2D

var hp = 1
var max_hp = 1
var speed = 150
var player

# HP bar overlay for drawing text
var _hp_overlay: Node2D = null

# Simple distance-based behavior - no physics collision
const STOP_DISTANCE := 45.0
const DAMAGE_DISTANCE := 50.0
const DAMAGE_COOLDOWN := 1.0
var _damage_timer := 0.0

var is_stunned = false
var stun_timer = 0.0

# Charmed state (Sin's special ability)
var _is_charmed := false
var _charm_owner: Node = null
var _charm_target: Node = null  # Current enemy target when charmed

# Laser shooting parameters
const LASER_RANGE := 500.0           # Distance at which enemy can shoot
const LASER_FIRE_INTERVAL := 3.0     # Seconds between shots
const LASER_SPEED := 500.0           # Laser projectile speed
const LASER_DAMAGE := 1              # Damage per laser hit
const LASER_CHARGE_TIME := 1.0       # Seconds to charge before firing
var _laser_cooldown := 0.0
var _can_shoot := true               # Toggle for enabling/disabling shooting
var _is_charging := false
var _charge_timer := 0.0
var _charge_direction := Vector2.ZERO
var _charge_effect: Node2D = null

# Preload laser scene
const EnemyLaserScene = preload("res://scenes/projectiles/EnemyLaser.tscn")

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
	var texture = load("res://assets/characters/rapture1-sprite.png")
	if texture and _animator:
		_animator.configure(texture, 3, 4, 6.0, 0.15)
	add_to_group("enemies")
	
	# Apply glow shader so enemy glows through night darkness
	_apply_glow_shader()
	
	# Randomize initial cooldown so enemies don't all fire at once
	_laser_cooldown = randf_range(0.0, LASER_FIRE_INTERVAL)

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
	# Position at the center of the HP bar (bar is at -69 to -59, so center is -64)
	_hp_overlay.position = Vector2(0, -64)
	add_child(_hp_overlay)
	_hp_overlay.set_script(preload("res://scripts/EnemyHPLabel.gd"))
	_hp_overlay.setup(self)

func _update_hp_label() -> void:
	if _hp_overlay and _hp_overlay.has_method("update_values"):
		_hp_overlay.update_values(hp, max_hp)

func _physics_process(delta: float) -> void:
	# Process combat juice effects
	_process_death_anticipation(delta)
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
	
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	var dir: Vector2 = to_player.normalized() if dist > 0 else Vector2.ZERO
	
	# Handle charging state
	if _is_charging:
		_charge_timer += delta
		# Update charge direction to track player
		_charge_direction = dir
		# Update charge effect position and direction
		_update_charge_effect()
		# Fire when charge is complete
		if _charge_timer >= LASER_CHARGE_TIME:
			_fire_laser(_charge_direction)
			_end_charging()
			_laser_cooldown = LASER_FIRE_INTERVAL
		# Don't move while charging
		velocity = Vector2.ZERO
	else:
		# Chase player, but stop at STOP_DISTANCE
		if dist > STOP_DISTANCE:
			global_position += dir * speed * delta
		
		# Deal damage when close
		if dist < DAMAGE_DISTANCE and _damage_timer <= 0:
			if player and player.has_method("take_damage"):
				player.take_damage(1)
			_damage_timer = DAMAGE_COOLDOWN
		
		# Attempt to start charging laser at player
		if _can_shoot:
			_attempt_laser_attack(dist, dir)
	
	# Animation
	velocity = dir * speed if dist > STOP_DISTANCE else Vector2.ZERO
	if _animator:
		_animator.update_state(velocity, dir)

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
	_charge_effect.set_script(preload("res://scripts/EnemyChargeEffect.gd"))
	add_child(_charge_effect)
	_charge_effect.position = _charge_direction * 25.0
	_charge_effect.start_charge(LASER_CHARGE_TIME)

func _update_charge_effect() -> void:
	if _charge_effect and is_instance_valid(_charge_effect):
		_charge_effect.position = _charge_direction * 25.0
		if _charge_effect.has_method("set_progress"):
			_charge_effect.set_progress(_charge_timer / LASER_CHARGE_TIME)

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
	laser.damage = LASER_DAMAGE
	laser.lifetime = maxf((LASER_RANGE * 1.5) / LASER_SPEED, 1.0)
	
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

func take_damage(dmg, is_crit: bool = false, hit_direction: Vector2 = Vector2.ZERO, from_burst: bool = false):
	# Apply vulnerability debuff if present (from Scarlet's Expose Weakness talent)
	var actual_dmg: int = dmg
	if has_meta("damage_vulnerability"):
		var vuln_mult: float = get_meta("damage_vulnerability")
		actual_dmg = int(dmg * vuln_mult)
	
	hp -= actual_dmg
	hp_bar.value = hp
	_update_hp_label()
	
	# Store hit direction for knockback visual
	_last_hit_direction = hit_direction if hit_direction != Vector2.ZERO else Vector2.RIGHT
	
	# Knockback visual (just visual offset, not actual movement) - MORE NOTICEABLE
	_knockback_offset = _last_hit_direction * 15.0
	
	# Spawn hit spark
	var HitSparkScript = preload("res://scripts/HitSpark.gd")
	if get_parent() and HitSparkScript:
		if is_crit:
			HitSparkScript.spawn_critical(get_parent(), global_position, _last_hit_direction)
		else:
			HitSparkScript.spawn_normal(get_parent(), global_position, _last_hit_direction)
	
	# Camera punch only on critical hits
	if is_crit:
		var combat_juice_script = load("res://scripts/CombatJuice.gd")
		if combat_juice_script and combat_juice_script.instance:
			combat_juice_script.camera_punch(-_last_hit_direction, 4.0)
	
	# Spawn floating damage number (higher up to avoid sprite/HP bar)
	var FloatingNumber = preload("res://scripts/FloatingDamageNumber.gd")
	if get_parent():
		if is_crit:
			FloatingNumber.spawn_critical(get_parent(), global_position + Vector2(0, -50), actual_dmg)
		else:
			FloatingNumber.spawn_damage(get_parent(), global_position + Vector2(0, -50), actual_dmg)
	
	if hp <= 0:
		# Calculate overkill (excess damage beyond what was needed)
		_overkill_damage = -hp  # hp is negative, so negate it
		
		# Only grant burst gauge if kill wasn't from a burst ability
		if not from_burst and player and player.has_method("register_burst_hit"):
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
		sparkle.set_script(preload("res://scripts/SparkleEffect.gd"))
		sparkle.duration = duration
		sparkle.z_index = 10
		add_child(sparkle)

func set_can_shoot(enabled: bool) -> void:
	"""Enable or disable shooting for this enemy."""
	_can_shoot = enabled

func die():
	# Calculate overkill multiplier (3x damage = overkill)
	var overkill_multiplier := 1.0
	var is_overkill: bool = _overkill_damage >= (max_hp * 2)  # 3x total = 2x excess
	if is_overkill:
		overkill_multiplier = 2.0
	
	# Register kill with combat juice for momentum
	var combat_juice_script = load("res://scripts/CombatJuice.gd")
	if combat_juice_script and combat_juice_script.instance:
		combat_juice_script.register_kill(overkill_multiplier)
	
	# Spawn robot death effect
	var death_effect := Node2D.new()
	death_effect.set_script(preload("res://scripts/RobotDeathEffect.gd"))
	death_effect.global_position = global_position
	# Pass overkill state for bigger explosion
	if death_effect.has_method("set_overkill"):
		death_effect.set_overkill(is_overkill)
	get_parent().add_child(death_effect)
	
	# Spawn XP orbs
	for i in 5:
		var orb_scene = preload("res://scenes/effects/XPOrb.tscn")
		var orb = orb_scene.instantiate()
		get_parent().add_child(orb)
		orb.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	call_deferred("queue_free")

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
			charm_fx.set_script(preload("res://scripts/SinCharmEffect.gd"))
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
	
	# Chase the target
	if dist > STOP_DISTANCE:
		global_position += dir * speed * delta
	
	# Deal damage when close
	if dist < DAMAGE_DISTANCE and _damage_timer <= 0:
		if _charm_target.has_method("take_damage"):
			_charm_target.take_damage(1)
		_damage_timer = DAMAGE_COOLDOWN
	
	# Animation
	velocity = dir * speed if dist > STOP_DISTANCE else Vector2.ZERO
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
		if child.get("_is_charmed") == true:
			continue
		if child.get("hp") != null and child.hp <= 0:
			continue
		
		var dist: float = global_position.distance_to(child.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = child
	
	return nearest
