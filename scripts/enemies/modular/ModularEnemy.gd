extends CharacterBody2D


# Replaces the monolithic logic of legacy enemy scripts

@export var stats: Resource

# Component references
# Component references
# Component references
var health_component: Node
var hitbox_component: Node
var movement_component: Node
var visual_component: Node
var attack_component: Node
var drop_component: Node

# Cached ShopMenu reference to avoid load() in hot paths
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")
const RaptureBasicSprite = preload("res://assets/enemies/rapture-basic/sprite.png")
@onready var visuals: Node2D = $AnimatedSprite2D
@onready var hp_bar: ProgressBar = $ProgressBar
@onready var hp_label: Label = $HPLabel
var shield_bar: ProgressBar = null
var shield_label: Label = null


var _generic_boss_shield: Node2D = null
var _generic_shield_ready: bool = false
var _generation_id: int = 0 # pooling safety
var _flash_intensity: float = 0.0

# PERFORMANCE: Static cached reference to GameManager (avoids per-frame node lookup)
static var _cached_game_manager: Node = null
static var _gm_cache_checked: bool = false

# PERFORMANCE: Static StyleBox pool (shared across all enemies to avoid per-enemy allocation)
static var _style_green: StyleBoxFlat = null
static var _style_red: StyleBoxFlat = null
static var _style_yellow: StyleBoxFlat = null
static var _style_boss_red: StyleBoxFlat = null
static var _style_elite_red: StyleBoxFlat = null
static var _style_bg: StyleBoxFlat = null

static func _ensure_styles_initialized() -> void:
	if _style_green == null:
		_style_green = StyleBoxFlat.new()
		_style_green.bg_color = Color(0, 1, 0)
	if _style_red == null:
		_style_red = StyleBoxFlat.new()
		_style_red.bg_color = Color(1.0, 0.2, 0.2)
	if _style_yellow == null:
		_style_yellow = StyleBoxFlat.new()
		_style_yellow.bg_color = Color(0.95, 0.85, 0.2)
	if _style_boss_red == null:
		_style_boss_red = StyleBoxFlat.new()
		_style_boss_red.bg_color = Color(0.9, 0.0, 0.0)
	if _style_elite_red == null:
		_style_elite_red = StyleBoxFlat.new()
		_style_elite_red.bg_color = Color(0.8, 0.1, 0.1)
	if _style_bg == null:
		_style_bg = StyleBoxFlat.new()
		_style_bg.bg_color = Color(0.2, 0.2, 0.2)

static func _get_game_manager() -> Node:
	if not _gm_cache_checked:
		_cached_game_manager = Engine.get_main_loop().root.get_node_or_null("/root/GameManager")
		_gm_cache_checked = true
	return _cached_game_manager

# PERFORMANCE: Cached group membership (checked once in _ready, not per-frame)
var _is_boss: bool = false
var _is_super_boss: bool = false
var _is_tank: bool = false
var _is_elite: bool = false
var _is_exploder: bool = false


# Compatibility variables (so existing systems can read them)
var hp: int:
	get:
		var hc = health_component if health_component else $HealthComponent
		return hc.current_hp
	set(value):
		var hc = health_component if health_component else $HealthComponent
		hc.current_hp = value
		if hp_bar: hp_bar.value = value
		if hp_label: hp_label.text = str(value) + "/" + str(hc.max_hp)
var max_hp: int:
	get:
		var hc = health_component if health_component else $HealthComponent
		return hc.max_hp
	set(value):
		var hc = health_component if health_component else $HealthComponent
		hc.set_max_hp(value)
		if hp_bar: hp_bar.max_value = value
		if hp_bar: hp_bar.value = hc.current_hp
		if hp_label: hp_label.text = str(hc.current_hp) + "/" + str(value)

var speed: float:
	get:
		var mc = movement_component if movement_component else $MovementComponent
		return mc.max_speed
	set(value):
		var mc = movement_component if movement_component else $MovementComponent
		mc.max_speed = value

func _ready() -> void:
	# Randomize timers to spread load across frames (prevent spikes)
	_target_check_timer = randf() * TARGET_CHECK_INTERVAL
	_shield_check_timer = randf() * SHIELD_CHECK_INTERVAL

	# Initialize components safely
	health_component = get_node_or_null("HealthComponent")
	hitbox_component = get_node_or_null("HitboxComponent")
	movement_component = get_node_or_null("MovementComponent")
	visual_component = get_node_or_null("VisualComponent")
	attack_component = get_node_or_null("AttackComponent")
	drop_component = get_node_or_null("DropComponent")

	add_to_group("enemies")
	
	# if stats:
	# 	_apply_stats()
	
	if health_component:
		health_component.died.connect(_on_death)
		health_component.health_changed.connect(_on_health_changed)
		# Fix: Connect for burst generation on hit
		health_component.damaged.connect(_on_damaged)
	
	# Find player to chase
	var player = get_tree().get_first_node_in_group("player")
	if player and movement_component:
		movement_component.set_target(player)
		
	# RETROACTIVE DEATH CHECK REMOVED
	# Was causing issues where fresh spawns thought they were dead.
	# EnemySpawner logic should ensure we handle "dying during spawn" cases explicitly if they occur.
	# if health_component and health_component.has_method("is_dead") and health_component.is_dead():
	# 	_on_death()
	# 	return # Stop further setup
		
		
	# Force initial label update
	if hp_label and health_component:
		hp_label.text = str(health_component.current_hp) + "/" + str(health_component.max_hp)
	
	# Force initial bar update (Sync with Spawner configuration)
	if hp_bar and health_component:
		hp_bar.max_value = health_component.max_hp
		hp_bar.value = health_component.current_hp
		# Hide initially - will be shown on first position sync in _process
		# This prevents a 1-frame flash at wrong position
		hp_bar.visible = false
	
	# Configure visuals
	if visuals.has_method("configure"):
		var tex = RaptureBasicSprite
		
		# Fallback verify texture load (Export fix)
		if tex == null:
			print("WARNING: RaptureBasicSprite preload failed. Attempting dynamic load.")
			if ResourceLoader.exists("res://assets/enemies/rapture-basic/sprite.png"):
				tex = load("res://assets/enemies/rapture-basic/sprite.png")
			else:
				print("ERROR: Sprite texture missing at res://assets/enemies/rapture-basic/sprite.png")
				
		if tex:
			visuals.configure(tex, 3, 4, 6.0, 0.15)
		else:
			# Even if texture fails, FORCE VISIBLE so we can see the debug placeholder (or at least know it exists)
			print("ERROR: Visuals configuration failed - No Texture. Forcing visible anyway.")
			visuals.visible = true
			if visuals.has_method("play"): visuals.play("down")

	
	# Create shadow
	_create_shadow()
	
	# Register sprite for night glow effect - REMOVED (Handled by EnemySpawner + Universal Shader)
	# if visuals:
	# 	NightGlowManager.register_sprite(visuals)
	
	# Apply universal shader for night visibility - DISABLED (causes visual issues during day)
	# _ensure_universal_shader()
	
	# Setup HP bar styling using shared static StyleBox pool
	# Hide initially - will be shown after first position sync to prevent flicker at origin
	hp_bar.visible = false
	hp_label.visible = false
	hp_bar.z_index = 50 # Below HUD layer (HUD is typically 100+)
	
	# Make HP bar and label immune to lighting (no reparenting needed)
	_make_unshaded(hp_bar)
	_make_unshaded(hp_label)
	
	# Setup Shield Bar
	_ensure_shield_bar_exists()


	# Super Boss Shield System
	# NOTE: Moved to setup_super_boss_shield() - called by EnemySpawner after groups are assigned
	# if is_in_group("super_boss") and not is_in_group("ignore_generic_shield"):
	# 	_setup_generic_boss_shield()


	# Reparent to EffectsLayer (deferred to ensure proper positioning)
	# DISABLED: Reparenting causes is_greater_than errors and is not necessary
	# HP bars stay as children and use z_index for layering
	# call_deferred("_reparent_hp_bars_to_effects_layer")

	# PERFORMANCE: Use shared static StyleBox pool instead of per-enemy allocation
	_ensure_styles_initialized()
	hp_bar.add_theme_stylebox_override("background", _style_bg)
	
	# Cache group membership for faster per-frame checks
	_is_exploder = is_in_group("exploder")
	_is_tank = is_in_group("tank")
	_is_boss = is_in_group("boss")
	_is_super_boss = is_in_group("super_boss")
	_is_elite = is_in_group("elite")

	# Set HP bar fill style based on cached group membership
	if _is_exploder:
		hp_bar.add_theme_stylebox_override("fill", _style_red)
	elif _is_tank:
		hp_bar.add_theme_stylebox_override("fill", _style_yellow)
	elif _is_boss or _is_super_boss:
		hp_bar.add_theme_stylebox_override("fill", _style_boss_red)
	elif _is_elite:
		hp_bar.add_theme_stylebox_override("fill", _style_elite_red)
	else:
		hp_bar.add_theme_stylebox_override("fill", _style_green)
	
	if hp_label:
		hp_label.z_index = 101 # Above bar
		hp_label.text = str(health_component.current_hp) + "/" + str(health_component.max_hp)


func _create_shadow() -> void:
	# Uses the centralized ShadowHelper utility
	if ClassDB.class_exists("ShadowHelper") or get_tree().root.has_node("ShadowHelper"):
		var shadow = ShadowHelper.create_enemy_shadow(self)
		shadow.modulate = Color(0.3, 0.1, 0.1, 0.35)
		shadow.position = Vector2(0, 18)

func _on_health_changed(current: int, _max: int) -> void:
	if hp_bar:
		hp_bar.value = current
	if hp_label:
		# Format: "100/100" (Clean)
		hp_label.text = str(current) + "/" + str(_max)
		
		# Ensure centering is enforced on text change
		if hp_label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# VISUAL FEEDBACK: Flash Red - OPTIMIZED
		_flash_intensity = 1.0


var base_damage: int = 1

# Methods expected by Spawner
# Methods expected by Spawner
func set_can_shoot(val: bool) -> void:
	_can_shoot = val

func _apply_stats() -> void:
	health_component.set_max_hp(stats.max_hp)
	movement_component.max_speed = stats.move_speed
	# TODO: Set hitbox size from stats?

# Preload death effect script
const RobotDeathEffectScript = preload("res://scripts/effects/RobotDeathEffect.gd")

# Shooting Logic
const LASER_RANGE := 500.0
const LASER_FIRE_INTERVAL := 5.0
const LASER_SPEED := 500.0
var _laser_cooldown := 0.0
const CHARGE_DURATION := 1.4
var _is_charging := false
var _charge_timer := 0.0
var _charge_effect: Node2D = null
var _glow_texture: Texture2D = null
# Default to true (Standard enemies shoot), Spawner can disable
var _can_shoot := true
const EnemyLaserScene = preload("res://scenes/projectiles/EnemyLaser.tscn")
const ChargeEffectScript = preload("res://scripts/enemies/EnemyChargeEffect.gd")

const DAMAGE_DISTANCE := 50.0
const DAMAGE_COOLDOWN := 1.0
var _damage_timer := 0.0

# Charmed State
var _is_charmed := false
var _charm_owner: Node = null
var _current_target: Node2D = null

# Optimization state
var _cached_font_size: int = -1
var _prev_scale_x: float = 0.0

# Throttling Timers
var _target_check_timer: float = 0.0
const TARGET_CHECK_INTERVAL: float = 0.25 # 4 times per second
var _shield_check_timer: float = 0.0
const SHIELD_CHECK_INTERVAL: float = 0.2 # 5 times per second
var _cached_shield: Node = null

# Wells Bullet Time Visual Effects
var _time_freeze_material: ShaderMaterial = null
var _dot_ripple_material: ShaderMaterial = null
var _dot_pulse_timer: float = 0.0
var _dot_pulse_intensity: float = 0.0
var _original_material: Material = null
var _wells_effect_age: float = 0.0
static var _time_freeze_shader: Shader = null
static var _dot_ripple_shader: Shader = null
static var _universal_shader: Shader = null
var _universal_material: ShaderMaterial = null

func set_charmed(charm_owner: Node, charmed: bool = true, force: bool = false) -> void:
	# Validation: Don't charm Elites/Tanks/Bosses unless forced
	if not force:
		# PERFORMANCE: Use cached group flags instead of is_in_group()
		if _is_elite or _is_tank or _is_boss or _is_super_boss:
			return
	
	_is_charmed = charmed
	_charm_owner = charm_owner
	
	if charmed:
		# Add charm visual effect if missing
		if not has_node("CharmEffect"):
			var charm_fx := Node2D.new()
			charm_fx.name = "CharmEffect"
			# Use generic path or assume script exists
			if ResourceLoader.exists("res://scripts/characters/effects/SinCharmEffect.gd"):
				charm_fx.set_script(load("res://scripts/characters/effects/SinCharmEffect.gd"))
			charm_fx.z_index = 10
			add_child(charm_fx)
		
		# Apply purple tint
		if visuals:
			visuals.modulate = Color(0.8, 0.5, 1.0, 1.0)
			
		# Switch to finding enemies
		_find_new_target()
	else:
		# Remove visuals
		if has_node("CharmEffect"):
			get_node("CharmEffect").queue_free()
		# Restore modulation (white)
		if visuals:
			visuals.modulate = Color.WHITE
		
		# Revert to player target
		if is_inside_tree():
			_current_target = TargetCache.get_player()
		else:
			_current_target = null
		
		movement_component.set_target(_current_target)

func _find_new_target() -> void:
	var nearest: Node2D = null
	var min_dist := INF
	
	# Simple search for nearest enemy in "enemies" group
	var potential_targets = TargetCache.get_enemies()
	for target in potential_targets:
		if target == self: continue
		if target.is_in_group("charmed_allies"): continue # Don't attack friends
		
		# Validate target
		if not is_instance_valid(target): continue
		if target.has_method("is_dead") and target.is_dead(): continue
		if target.get("hp") != null and target.hp <= 0: continue
		
		var dist = global_position.distance_to(target.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = target
			
	_current_target = nearest
	if nearest:
		movement_component.set_target(nearest)

func _find_best_target() -> void:
	# Find the closest valid target (Player, Charmed Ally, Clone, or Base in Defense mode)
	var nearest: Node2D = null
	var min_dist := INF
	
	# 1. Check Player
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		var dist = global_position.distance_to(player.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = player
			
	# 2. Check Charmed Allies
	var charmed = TargetCache.get_charmed_allies()
	for ally in charmed:
		if ally == self: continue
		if not is_instance_valid(ally): continue
		var dist = global_position.distance_to(ally.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = ally
			
	# 3. Check Clones
	var clones = TargetCache.get_nayuta_clones()
	for clone in clones:
		if not is_instance_valid(clone): continue
		if clone.get("current_hp") != null and clone.get("current_hp") <= 0: continue
		var dist = global_position.distance_to(clone.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = clone
	
	# 4. DEFENSE MODE: If player is too far (outside camera view ~600 units), target base instead
	if has_meta("defense_mode") and get_meta("defense_mode"):
		var player_in_sight := false
		if player and is_instance_valid(player):
			var player_dist := global_position.distance_to(player.global_position)
			player_in_sight = player_dist < 600.0 # Roughly camera view range
		
		if not player_in_sight:
			# Target the base instead
			var base_pos: Vector2 = get_meta("defense_base_position") if has_meta("defense_base_position") else Vector2(-3200, 0)
			var dummy_target := _get_or_create_defense_target(base_pos)
			if dummy_target:
				_current_target = dummy_target
				movement_component.set_target(dummy_target)
				return
			
	_current_target = nearest
	movement_component.set_target(nearest if nearest else player)

var _defense_target_marker: Node2D = null

func _get_or_create_defense_target(base_pos: Vector2) -> Node2D:
	# Create a simple marker node for enemies to target (the base position)
	if _defense_target_marker and is_instance_valid(_defense_target_marker):
		_defense_target_marker.global_position = base_pos
		return _defense_target_marker
	
	# Try to find the actual base entity first
	var base = get_tree().get_first_node_in_group("defense_base")
	if base and is_instance_valid(base):
		return base
	
	# Fallback: create marker at base position
	_defense_target_marker = Node2D.new()
	_defense_target_marker.global_position = base_pos
	_defense_target_marker.name = "DefenseTargetMarker"
	get_tree().current_scene.add_child(_defense_target_marker)
	return _defense_target_marker

var _is_stunned: bool = false

func set_stunned(stunned: bool) -> void:
	# print("[ModularEnemy] set_stunned: ", stunned, " on ", name)
	_is_stunned = stunned
	
	# Pause movement
	if movement_component:
		movement_component.set_paused(stunned)
	
	# Pause attacks/charging if stunned
	if stunned:
		_end_charging() # Cancel charge if active
		if visuals and visuals.has_method("set_paused"):
			visuals.set_paused(stunned)
	else:
		if visuals and visuals.has_method("set_paused"):
			visuals.set_paused(false)

func is_stunned() -> bool:
	return _is_stunned

# Screen bounds cache for off-screen culling
var _screen_bounds: Rect2 = Rect2()
var _last_bounds_frame: int = -1
const BOUNDS_UPDATE_INTERVAL := 30 # Update bounds every 30 frames

func _is_on_screen() -> bool:
	# Update cached screen bounds periodically
	var frame := Engine.get_process_frames()
	if frame - _last_bounds_frame > BOUNDS_UPDATE_INTERVAL:
		_last_bounds_frame = frame
		var viewport := get_viewport()
		if viewport:
			var camera := viewport.get_camera_2d()
			if camera and camera.zoom.length_squared() > 0.001:
				var vp_size := viewport.get_visible_rect().size
				var half_size := vp_size / (2.0 * camera.zoom)
				# Add 200px margin so enemies just off-screen still process
				_screen_bounds = Rect2(camera.global_position - half_size - Vector2(200, 200), half_size * 2 + Vector2(400, 400))
			else:
				_screen_bounds = Rect2(-3000, -3000, 6000, 6000) # Large fallback (Was -1000/3920 - Increased for safety)
	
	return _screen_bounds.has_point(global_position)

func _process(delta: float) -> void:
	# If stunned, do nothing (frozen in time)
	if _is_stunned:
		return
	
	# PERFORMANCE: Skip expensive processing for off-screen enemies
	# Still update timers and movement, but skip HP bar/visual sync
	var on_screen := _is_on_screen()
	
	# Apply Bullet Time scaling to enemy-related timers
	# PERFORMANCE: Use cached GameManager instead of per-frame lookup
	var gm = _get_game_manager()
	var time_scale = gm.enemy_time_scale if gm else 1.0

	if _damage_timer > 0:
		_damage_timer -= delta * time_scale
	if _laser_cooldown > 0:
		_laser_cooldown -= delta * time_scale
		
	# Update timers (throttling timers don't need scaling - they're for optimization)
	_target_check_timer -= delta
	_shield_check_timer -= delta
	
	# OFF-SCREEN OPTIMIZATION: Throttle expensive checks heavily if off-screen
	var effective_shield_interval = SHIELD_CHECK_INTERVAL if on_screen else SHIELD_CHECK_INTERVAL * 4.0
	
	# Shield Check Logic (Throttled)
	if _shield_check_timer <= 0:
		_update_shield_status()
		_shield_check_timer = effective_shield_interval
	
	# Wells Bullet Time Visual Effect - Time Freeze Shader
	_wells_effect_age += delta
	if time_scale < 1.0 and visuals:
		_ensure_time_freeze_shader()
		if _time_freeze_material and visuals.material == _time_freeze_material:
			_time_freeze_material.set_shader_parameter("intensity", 1.0 - time_scale)
			_time_freeze_material.set_shader_parameter("time_offset", _wells_effect_age)
	elif visuals and visuals.material == _time_freeze_material:
		# Restore original material when Bullet Time ends
		visuals.material = _original_material
	
	# DoT Pulse Effect Decay
	if _dot_pulse_intensity > 0.0:
		_dot_pulse_timer += delta
		_dot_pulse_intensity = maxf(0.0, _dot_pulse_intensity - delta * 2.0) # Fade over 0.5s
		if _dot_ripple_material and visuals and visuals.material == _dot_ripple_material:
			_dot_ripple_material.set_shader_parameter("pulse_intensity", _dot_pulse_intensity)
			_dot_ripple_material.set_shader_parameter("pulse_time", _dot_pulse_timer)
		if _dot_pulse_intensity <= 0.01 and visuals and visuals.material == _dot_ripple_material:
			# Restore time freeze or original material
			if time_scale < 1.0 and _time_freeze_material:
				visuals.material = _time_freeze_material
			else:
				visuals.material = _original_material
	
	# Targeting Logic (Throttled)
	if _target_check_timer <= 0:
		# OFF-SCREEN OPTIMIZATION: Run targeting less frequently if off-screen
		var effective_target_interval = TARGET_CHECK_INTERVAL if on_screen else TARGET_CHECK_INTERVAL * 2.0
		
		# Update logic for Charmed enemies (find new target if current dies OR becomes friend)
		if _is_charmed:
			var need_new_target := false
			if not is_instance_valid(_current_target):
				need_new_target = true
			elif _current_target.has_method("is_dead") and _current_target.is_dead():
				need_new_target = true
			elif _current_target.get("hp") != null and _current_target.hp <= 0:
				need_new_target = true
			elif _current_target.is_in_group("charmed_allies"):
				# Target was charmed by someone else (or us), stop attacking friend
				need_new_target = true
				
			if need_new_target:
				_find_new_target()
		else:
			# Normal behavior: Find best target (Player OR Charmed Enemy)
			_find_best_target()
			
		_target_check_timer = effective_target_interval
	
	# Hit Flash Decay - OPTIMIZED
	if _flash_intensity > 0.0:
		_flash_intensity = maxf(0.0, _flash_intensity - delta * 5.0) # Fade over 0.2s
		if visuals:
			visuals.modulate = Color.WHITE.lerp(Color(3.0, 0.5, 0.5), _flash_intensity)
	
	# Super Boss Shield Deployment (random chance to deploy when ready)
	# PERFORMANCE: Use cached group flag instead of is_in_group()
	if _is_super_boss and _generic_boss_shield:
		_process_shield_deployment()
	
	# PERFORMANCE: update_state() call moved below after charging state check (was duplicate)
		
	# Dynamic Text Scaling: Keep text physically large but rendered sharply
	# PERFORMANCE: Skip HP label updates for off-screen enemies
	# FIX 2: Removed position sync - now handled in _physics_process with HP bar
	if hp_label and hp_bar and on_screen:
		# Auto-show HP bar if hidden (e.g. from spawn/reset)
		if not hp_bar.visible:
			hp_bar.visible = true
			if hp_label: hp_label.visible = true
			
		# Optimization: Only recalculate if scale changed significantly
		var p_scale_x = abs(scale.x)
		if abs(p_scale_x - _prev_scale_x) > 0.01:
			_prev_scale_x = p_scale_x
			
			if p_scale_x > 0.001:
				# Reset pivot to default to simplified position math
				hp_label.pivot_offset = Vector2.ZERO
				
				# Ensure centered text (only check once per scale change)
				if hp_label.vertical_alignment != VERTICAL_ALIGNMENT_CENTER:
					hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				
				# Math: Previous visual scale was pow(scale, 0.7).
				# Base Font = 10.
				var visual_factor = pow(p_scale_x, 0.7)
				var target_font_size = int(10 * visual_factor)
				var target_outline = int(4 * visual_factor) # Scale outline so it doesn't look thin
				
				# Apply only if changed (Optimized using local cache variable)
				if _cached_font_size != target_font_size:
					hp_label.add_theme_font_size_override("font_size", target_font_size)
					hp_label.add_theme_constant_override("outline_size", target_outline)
					_cached_font_size = target_font_size
		
		# Reset scale to 1.0 for sharp rendering (Cheap operation, keep per-frame)
		hp_label.scale = Vector2.ONE
		
		# PERFORMANCE: HP value/text updates are now FULLY EVENT-DRIVEN via _on_health_changed signal
		# No per-frame polling needed - the signal fires only when HP actually changes
		
		# NOTE: HP label position sync moved to _physics_process for consolidation
			
	# Damage Logic (Attack Current Target)
	if is_instance_valid(_current_target):
		var dist = global_position.distance_to(_current_target.global_position)
		if dist < DAMAGE_DISTANCE and _damage_timer <= 0:
			if _current_target.has_method("take_damage"):
				# If we are charmed, we are "charmed_enemy" source
				var source = "charmed_enemy" if _is_charmed else "enemy"
				
				if _current_target.is_in_group("player"):
					# Get descriptive enemy name for damage log
					var enemy_tier = get_meta("enemy_tier", "Normal") if has_meta("enemy_tier") else "Normal"
					var enemy_name = enemy_tier.capitalize()
					if _is_boss or is_in_group("boss"):
						enemy_name = "Boss"
					elif _is_super_boss or is_in_group("super_boss"):
						enemy_name = "Super Boss"
					elif _is_tank or is_in_group("tank"):
						enemy_name = "Tank"
					elif _is_elite or is_in_group("elite"):
						enemy_name = "Elite"
					elif _is_exploder or is_in_group("exploder"):
						enemy_name = "Exploder"
					elif is_in_group("shielder"):
						enemy_name = "Shielder"
					# Pass source as "EnemyName:collision"
					_current_target.take_damage(base_damage, false, Vector2.ZERO, false, enemy_name + ":Collision")
				else:
					# Enemies/Others support extended arguments
					_current_target.take_damage(base_damage, false, Vector2.ZERO, false, source)
			_damage_timer = DAMAGE_COOLDOWN
			
	# Charging State Logic
	if _is_charging:
		_charge_timer -= delta * time_scale
		
		# Movement paused handled by set_paused() called in _start_charging()
		
		# Update visual effect
		_update_charge_effect()
		
		if _charge_timer <= 0:
			# Fire!
			var target_pos = global_position # Default to self if invalid? No.
			
			# Re-validate target before firing
			var has_valid_target = is_instance_valid(_current_target)
			if has_valid_target and _current_target.has_method("is_dead") and _current_target.is_dead():
				has_valid_target = false
				
			if has_valid_target:
				_fire_laser(global_position.direction_to(_current_target.global_position))
			else:
				# Fire in last known or forward direction
				_fire_laser(Vector2.RIGHT) # Fallback
			
			_end_charging()
			_laser_cooldown = LASER_FIRE_INTERVAL
			
	# Shooting Logic (If enabled and not charging)
	elif _can_shoot and _laser_cooldown <= 0:
		if is_instance_valid(_current_target):
			var dist = global_position.distance_to(_current_target.global_position)
			if dist < LASER_RANGE:
				# Start charging instead of firing immediately
				_start_charging()
				
	# Only update movement visuals if not charging (velocity is zeroed above if charging)
	if visuals and visuals.has_method("update_state") and not _is_charging:
		visuals.update_state(movement_component.velocity, movement_component.velocity)

	# Sync HP Bar position and scale (since it's now on EffectsLayer and detached)
	# Sync HP Bar position and scale (since it's now on EffectsLayer and detached)
	# PERFORMANCE: Skip position sync for off-screen enemies
	# EXPORT FIX: STRICT checking for self.visible. unique pooling bug causes ghost bars.
	if hp_bar and is_instance_valid(hp_bar):
		if on_screen and visible:
			# Sync scale fully for the bar
			hp_bar.scale = scale
			# Calculate offset based on scale to keep it above the sprite
			# Default offset (-25, -47) for unscaled sprite
			var offset = Vector2(-25, -47) * scale
			hp_bar.global_position = (global_position + offset).round()
			
			# FIX 2: Sync HP Label position here (consolidated from _process)
			if hp_label and is_instance_valid(hp_label):
				var bar_visual_size = hp_bar.size * hp_bar.scale
				var bar_center_global = hp_bar.global_position + bar_visual_size * 0.5
				var label_size = hp_label.size
				hp_label.global_position = (bar_center_global - label_size * 0.5).round()
			
			# Ensure visible (only if parent is visible!)
			if not hp_bar.visible:
				hp_bar.visible = true
			
			# Sync Shield Bar (skip for bosses - they use ShielderShield's own bar)
			# PERFORMANCE: Use cached group flags instead of is_in_group()
			if shield_bar and is_instance_valid(shield_bar) and not _is_boss and not _is_super_boss:
				shield_bar.scale = scale
				shield_bar.size.x = hp_bar.size.x
				var sb_offset = offset + Vector2(0, -9.0 * scale.y)
				shield_bar.global_position = (global_position + sb_offset).round()
				
				var s_stats = get_active_shield_stats()
				if s_stats.y > 0 and s_stats.x > 0:
					shield_bar.max_value = s_stats.y
					shield_bar.value = s_stats.x
					shield_bar.visible = true

					# Sync Shield Label (using global_position since top_level=true)
					if shield_label and is_instance_valid(shield_label):
						shield_label.text = str(int(s_stats.x)) + "/" + str(int(s_stats.y))
						# Use same position as shield bar for proper centering
						shield_label.size = Vector2(hp_bar.size.x * scale.x, 12)
						shield_label.global_position = shield_bar.global_position
						shield_label.visible = true
				else:
					shield_bar.visible = false
					if shield_label:
						shield_label.visible = false
						
			# Sync HP Label visibility (it might have been hidden by caching logic above)
			if hp_label and not hp_label.visible:
				hp_label.visible = true
				
		else:
			# OFF-SCREEN or HIDDEN: Hide detached UI elements so they don't float at last known pos
			if hp_bar.visible:
				hp_bar.visible = false
			if hp_label and hp_label.visible:
				hp_label.visible = false
			if shield_bar and is_instance_valid(shield_bar) and shield_bar.visible:
				shield_bar.visible = false
			if shield_label and is_instance_valid(shield_label) and shield_label.visible:
				shield_label.visible = false

func _reparent_hp_bars_to_effects_layer() -> void:
	"""DISABLED: Using top_level and unshaded material instead of reparenting."""
	pass

func _make_unshaded(node: CanvasItem) -> void:
	"""Make a node immune to lighting (stays bright at night)."""
	if not node: return
	node.top_level = true # Position is now global, not relative to parent
	node.light_mask = 0 # Ignore all light sources
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	node.material = mat


func _exit_tree() -> void:
	# DISABLED: No longer reparenting, so nothing to recover
	pass


func _start_charging() -> void:
	_is_charging = true
	_charge_timer = CHARGE_DURATION
	
	# Pause movement via component
	if movement_component:
		movement_component.set_paused(true)
	
	# Determine charge direction (towards target)
	var dir = Vector2.RIGHT
	if is_instance_valid(_current_target):
		dir = global_position.direction_to(_current_target.global_position)
	
	# Create visual effect (Legacy Style)
	# Use preloaded script
	if ChargeEffectScript:
		_charge_effect = Node2D.new() # It's a Node2D with a script, not necessarily a Sprite
		_charge_effect.set_script(ChargeEffectScript)
		_charge_effect.z_index = 15
		add_child(_charge_effect)
		
		# Make unshaded (Bright at night) - NOTE: This makes it top_level = true
		_make_unshaded(_charge_effect)
		
		# Position slightly in front like legacy (Sync initial pos)
		# Update: specific offest now scales with enemy size
		_charge_effect.scale = global_scale
		_charge_effect.global_position = global_position + dir * 25.0 * global_scale.x
		
		# Start effect
		if _charge_effect.has_method("start_charge"):
			_charge_effect.start_charge(CHARGE_DURATION)

func _update_charge_effect() -> void:
	if _charge_effect and is_instance_valid(_charge_effect):
		# Sync position (since unshaded makes it top_level)
		var dir = Vector2.RIGHT
		if is_instance_valid(_current_target):
			dir = global_position.direction_to(_current_target.global_position)
		_charge_effect.scale = global_scale
		_charge_effect.global_position = global_position + dir * 25.0 * global_scale.x
		
		# Legacy Enemy.gd used set_progress
		if _charge_effect.has_method("set_progress"):
			var progress = 1.0 - (_charge_timer / CHARGE_DURATION)
			_charge_effect.set_progress(progress)
			
		# Keep updating position to face target if we want dynamic tracking?
		# Legacy didn't update direction once started.
		
func _end_charging() -> void:
	_is_charging = false
	
	# Resume movement via component ONLY if not stunned
	if movement_component and not _is_stunned:
		movement_component.set_paused(false)
		
	if _charge_effect and is_instance_valid(_charge_effect):
		_charge_effect.queue_free()
		_charge_effect = null

func apply_stun(duration: float) -> void:
	if _is_stunned:
		return # Already stunned, ignore or refresh? For now ignore or maybe just extend?
		# Simple refresh:
		# set_stunned(true) # ensure on
	
	set_stunned(true)
	
	if not is_inside_tree():
		return
		
	# Create timer to un-stun
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func(): if is_instance_valid(self): set_stunned(false))

func _fire_laser(direction: Vector2) -> void:
	var laser = ProjectileCache.create_enemy_laser()
	if laser == null: return
	
	# Configure laser direction
	if laser.has_method("set_direction"):
		laser.set_direction(direction)
	else:
		laser.rotation = direction.angle()
		
	laser.speed = LASER_SPEED
	# Bosses and super bosses get unlimited range (until map border)
	if is_in_group("boss") or is_in_group("super_boss"):
		laser.max_range = 9999.0
		laser.lifetime = 30.0 # Long lifetime for traversing entire map
	else:
		laser.max_range = LASER_RANGE * 1.5
	laser.damage = base_damage
	
	# Scale laser projectile to match enemy size (Boss > Elite > Tank > Normal)
	# Scale laser projectile to match enemy size (Boss > Elite > Tank > Normal)
	var final_scale := scale
	# N01 Specific: 1.5x larger laser (Visual override per user request)
	if has_meta("display_name") and get_meta("display_name") == "RAPTURE QUEEN - N01":
		final_scale *= 1.5
		
	laser.scale = final_scale
	laser.damage = int(base_damage * scale.x) # Use base scale for damage logic
	
	# Set owner name for damage log (shows Tank, Elite, Boss, etc. instead of generic "Enemy")
	if has_meta("display_name"):
		laser.owner_name = get_meta("display_name")
	elif has_meta("enemy_tier"):
		laser.owner_name = get_meta("enemy_tier").capitalize() # "tank" -> "Tank"
	elif is_in_group("super_boss"):
		laser.owner_name = "Super Boss"
	elif is_in_group("boss"):
		laser.owner_name = "Boss"
	elif is_in_group("elite"):
		laser.owner_name = "Elite"
	elif is_in_group("tank"):
		laser.owner_name = "Tank"
	else:
		laser.owner_name = "Enemy"
	
	# NOTE: Boss projectile size enforcement REMOVED
	# Previously forced 4.5x scale for bosses which made hitboxes invisible/too large
	# Now visual scale matches entity scale, and collision is capped in EnemyLaser at 1.2x max
	
	# Configure Faction Logic (Friendly Fire)
	if _is_charmed:
		# Charmed Laser: Hits Enemies (Layer 2), Ignore Player (Layer 1)
		laser.collision_mask = 2 # Enemies
		laser.set_meta("from_charmed", true)
	else:
		# Normal Laser: Hits Player (Layer 1) AND Enemies/Charmed (Layer 2)
		# (Script logic prevents hurting allies, but we need collision)
		laser.collision_mask = 3 # Player (1) + Enemies (2)
	
	# Spawn laser OUTSIDE the enemy - scale offset by laser size to prevent instant hits
	# Update: Offset adjusted so only the TIP emerges from the charge spot
	# Calculation: ChargeSpot(25*Scale) - HalfLength(55*LaserScale)
	# This generic formula handles N01's extra laser scaling correctly (spawning deeper)
	var charge_dist: float = 25.0 * global_scale.x
	var laser_half_len: float = 55.0 * laser.scale.x
	var spawn_offset: float = charge_dist - laser_half_len
	laser.global_position = global_position + direction * spawn_offset
	get_parent().add_child(laser)


func _on_damaged(_amount: int, source: String) -> void:
	"""Handler for when enemy takes damage. Registers burst hit if from player."""
	# Only register burst if damaged by player or their projectiles/summons
	if source in ["player", "projectile", "summon", "cecil_drone"]:
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("register_burst_hit"):
			# Summons should not generate burst (is_summon = true sets rate to 0)
			var is_summon := source == "summon"
			player.register_burst_hit(self, false, "", is_summon)
	# Charmed enemies generate burst at reduced rate (0.5% per hit)
	elif source == "charmed_enemy":
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("register_burst_hit"):
			player.register_burst_hit(self, false, "charmed", false)
	# Wells DoT damage - trigger red pulse effect
	elif source == "wells_dust":
		_trigger_dot_pulse()

func _on_death(overkill: int = 0) -> void:
	# EXPORT FIX: Capture generation ID to prevent race conditions if pooled quickly
	call_deferred("_finalize_death", overkill, _generation_id)

func _finalize_death(overkill: int, death_gen_id: int = -1) -> void:
	# POOLING SAFETY CHECK
	# If generation has changed since death was signaled, we have already been reset!
	# Abort this death sequence immediately.
	if death_gen_id != -1 and death_gen_id != _generation_id:
		# print("Pooling Race Condition Avoided: Aborting death for gen ", death_gen_id, " (Current: ", _generation_id, ")")
		return

	# Add score
	# Add score
	# PERFORMANCE: Use cached GameManager
	var gm = _get_game_manager()
	if gm:
		# Fallback if Tier not set or property missing
		var tier_scale = 1.0
		if stats and "tier_scale" in stats:
			tier_scale = stats.tier_scale
			
		gm.add_score(10 * tier_scale)
		
	# Drop XP orbs
	_spawn_xp_orbs()
		
	# Special meta-drop for Pristine Core
	if has_meta("pristine_core_drop"):
		var chance = get_meta("pristine_core_drop")
		if randf() < chance:
			# Drop the core! 
			# Using _spawn_pristine_core_orb helper if available or standard drops
			pass

	# Spawn visual effect
	var death_effect = ProjectileCache.create_robot_death_effect()
	if death_effect:
		death_effect.global_position = global_position
		if death_effect.has_method("set_overkill"):
			death_effect.set_overkill(overkill)
		get_parent().add_child(death_effect)
	
	# POOLING: Return to spawner pool instead of freeing
	var spawner = _get_cached_spawner()
	if spawner and spawner.has_method("return_enemy"):
		spawner.return_enemy(self)
	else:
		queue_free()


static var _cached_spawner_ref: Node = null
static func _get_cached_spawner() -> Node:
	if not is_instance_valid(_cached_spawner_ref):
		_cached_spawner_ref = Engine.get_main_loop().root.get_tree().get_first_node_in_group("enemy_spawners")
	return _cached_spawner_ref


# XP value for this enemy (scales with tier)
var xp_value: int = 5

func _spawn_xp_orbs() -> void:
	"""Directly grant XP to the player system (XP orbs removed for performance)."""
	# Get XP value from stats resource if available
	var drop_xp := xp_value
	if stats and "xp_value" in stats:
		drop_xp = stats.xp_value
	
	# Scale XP based on tier (basic=1x, tank=2x, elite=5x, boss=10x)
	var tier_name := ""
	if has_meta("tier"):
		tier_name = get_meta("tier")
	elif is_in_group("boss") or is_in_group("super_boss"):
		tier_name = "boss"
	elif is_in_group("elite"):
		tier_name = "elite"
	elif is_in_group("tank") or is_in_group("shielder") or is_in_group("exploder"):
		tier_name = "tank"
	
	# Apply tier XP multipliers
	match tier_name:
		"tank", "shielder", "exploder":
			drop_xp = int(drop_xp * 2)
		"elite":
			drop_xp = int(drop_xp * 5)
		"boss":
			drop_xp = int(drop_xp * 10)
		"super_boss":
			drop_xp = int(drop_xp * 20)
	
	# Ensure minimum XP
	drop_xp = maxi(1, drop_xp)
	
	# DIRECT GRANT: No nodes spawned, call player directly for performance
	var player = TargetCache.get_player()
	if player and player.has_method("add_xp"):
		player.add_xp(drop_xp)
	elif EventBus.has_signal("xp_orb_collected"):
		# Fallback if player not cached yet
		EventBus.xp_orb_collected.emit(drop_xp)


func _spawn_pristine_core_orb(value: int) -> void:
	if ResourceLoader.exists("res://scripts/world/PristineCoreOrb.gd"):
		var orb = Area2D.new()
		orb.set_script(load("res://scripts/world/PristineCoreOrb.gd"))
		orb.set("cores_value", value)
		
		var player = get_tree().get_first_node_in_group("player")
		var camera := get_viewport().get_camera_2d() if get_viewport() else null
		
		# Map bounds (Safe Zone: 1700x1700 to ensure reachable)
		# Reduced from 2000 to 1800 and increased margin to ensure strict in-bounds
		var map_half_size := 1800.0
		var map_margin := 400.0 # Result: [-1400, 1400] range
		var map_min := Vector2(-map_half_size + map_margin, -map_half_size + map_margin)
		var map_max := Vector2(map_half_size - map_margin, map_half_size - map_margin)
		
		# Calculate spawn position
		var spawn_pos := global_position # Default: enemy death position
		
		if player and camera:
			# Get camera viewport bounds
			var viewport_size := get_viewport().get_visible_rect().size
			var cam_pos := camera.global_position
			var cam_zoom := camera.zoom
			var half_view := viewport_size / (2.0 * cam_zoom)
			
			# Visible screen bounds
			var view_min := cam_pos - half_view
			var view_max := cam_pos + half_view
			
			# Clamp view bounds to map bounds
			view_min.x = maxf(view_min.x, map_min.x)
			view_min.y = maxf(view_min.y, map_min.y)
			view_max.x = minf(view_max.x, map_max.x)
			view_max.y = minf(view_max.y, map_max.y)
			
			# Minimum distance from player (they need to walk to it)
			var min_dist_from_player := 150.0
			var max_dist_from_player := 400.0
			
			# If enemy death pos is on screen and far enough from player, use it
			var death_in_view := spawn_pos.x >= view_min.x and spawn_pos.x <= view_max.x and spawn_pos.y >= view_min.y and spawn_pos.y <= view_max.y
			var death_dist := spawn_pos.distance_to(player.global_position)
			
			if death_in_view and death_dist >= min_dist_from_player:
				# Use enemy death position - already good
				pass
			else:
				# Pick a random position within view, at good distance from player
				var best_pos := spawn_pos
				for _attempt in range(10):
					var test_pos := Vector2(
						randf_range(view_min.x, view_max.x),
						randf_range(view_min.y, view_max.y)
					)
					var test_dist := test_pos.distance_to(player.global_position)
					if test_dist >= min_dist_from_player and test_dist <= max_dist_from_player:
						best_pos = test_pos
						break
					elif test_dist >= min_dist_from_player:
						best_pos = test_pos # Accept but keep trying for better
				spawn_pos = best_pos
		
		# Final clamp to map bounds
		spawn_pos.x = clampf(spawn_pos.x, map_min.x, map_max.x)
		spawn_pos.y = clampf(spawn_pos.y, map_min.y, map_max.y)
		
		orb.global_position = spawn_pos
		get_parent().add_child(orb)


# Forwarding 'take_damage' for direct calls that bypass HitboxComponent
func take_damage(amount: int, is_crit: bool = false, direction: Vector2 = Vector2.ZERO, is_burst: bool = false, source: String = "unknown") -> void:
	# UNIVERSAL FRIENDLY FIRE PROTECTION
	# If this unit is mind-controlled (charmed), it should NEVER take damage from the player or their allies.
	if is_in_group("charmed_allies") and source in ["player", "projectile", "cecil_drone", "summon", "ally"]:
		return

	# Check if protected by a Shielder's shield
	if _check_shielder_protection(amount, source):
		return # Damage absorbed by shield
		
	# LOD OPTIMIZATION: Check if we should skip floating text
	# Skip if off-screen OR if zoomed out significantly (e.g. Rapunzel burst)
	# This prevents spawning 500+ labels in one frame
	var skip_floating_text := not _is_on_screen()
	if not skip_floating_text:
		var vp = get_viewport()
		if vp:
			var camera = vp.get_camera_2d()
			if camera and camera.zoom.length_squared() < 0.4: # Approx < 0.63 zoom
				skip_floating_text = true

	hitbox_component.take_damage(amount, is_crit, direction, is_burst, source, skip_floating_text)

func _check_shielder_protection(damage_amount: int, source: String = "unknown") -> bool:
	# Check protection status and get the shield instance
	var shielding_unit = _get_protecting_shield()
	# 2. Check for Chrono-Intangibility upgrade (Wells)
	if not is_inside_tree(): return false
	var player = get_tree().get_first_node_in_group("player")
	var wells_in_squad = player and player.has_method("is_character_in_squad") and player.is_character_in_squad("wells")
	if ShopMenuScript.has_character_upgrade("wells", "chrono_intangibility") and wells_in_squad:
		return false # Bypass protection
		
	if shielding_unit:
		if shielding_unit.has_method("take_shield_damage"):
			shielding_unit.take_shield_damage(damage_amount, source)
		return true
	return false

func is_protected_by_shield() -> bool:
	"""Public helper to check if enemy is currently protected."""
	return _get_protecting_shield() != null

func _update_shield_status() -> void:
	"""Update the cached shield reference. Runs periodically."""
	# Check if current shield is still valid
	if is_instance_valid(_cached_shield) and _cached_shield.is_active():
		if _cached_shield.is_point_inside(global_position):
			return # Still protected, no need to search
			
	# Search for new shield
	_cached_shield = _find_active_shield()

func _find_active_shield() -> Node:
	"""Expensive scan for nearby shields."""
	# Check if this IS a shielder - check our own shield first
	if is_in_group("shielder"):
		var my_shield = get_node_or_null("ShielderShield")
		if my_shield and my_shield.protects_owner():
			return my_shield
	
	# Find all active shielder shields
	var shields = TargetCache.get_shielder_shields()
	for shield in shields:
		if not is_instance_valid(shield):
			continue
		if not shield.is_active():
			continue
		# Check if we're inside this shield's radius
		if shield.is_point_inside(global_position):
			return shield
			
	return null

func _get_protecting_shield() -> Node:
	"""Finds an active shield protecting this unit. Uses Optimized Cache."""
	# Fast route: Check cache first
	if is_instance_valid(_cached_shield) and _cached_shield.is_active():
		if _cached_shield.is_point_inside(global_position):
			return _cached_shield
	
	# If cache failed, we usually wait for next tick.
	# BUT if we are taking damage right now, we might want to force a check?
	# For strict performance, we accept the ' vulnerability window' of 0.2s.
	# So we return null if cache is invalid.
	return null

func _ensure_shield_bar_exists() -> void:
	if shield_bar: return
	
	shield_bar = ProgressBar.new()
	shield_bar.name = "ShieldBar"
	shield_bar.show_percentage = false
	shield_bar.size = Vector2(50, 6)
	shield_bar.z_index = 51
	
	var sb_style = StyleBoxFlat.new()
	sb_style.bg_color = Color(0.2, 0.8, 1.0) # Cyan
	shield_bar.add_theme_stylebox_override("fill", sb_style)
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0, 0, 0, 0.5)
	shield_bar.add_theme_stylebox_override("background", sb_bg)
	add_child(shield_bar)
	shield_bar.visible = false
	_make_unshaded(shield_bar)
	
	# Shield Label
	shield_label = Label.new()
	shield_label.name = "ShieldLabel"
	shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shield_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shield_label.add_theme_font_size_override("font_size", 10)
	shield_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	shield_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1)) # Black outline
	shield_label.add_theme_constant_override("outline_size", 4) # Match HPLabel
	shield_label.z_index = 52
	add_child(shield_label)
	shield_label.visible = false
	_make_unshaded(shield_label)


# ==============================================================================
# POOLING RESET LOGIC
# ==============================================================================
func reset() -> void:
	"""Resets the enemy state for reuse from the pool."""
	
	# Ensure UI is ready (for pooled entities that pre-dated UI update)
	_ensure_shield_bar_exists()
	
	# 0. Visibility & Visuals Reset
	_generation_id += 1 # New life, invalidate old deferred calls
	
	# FIX: Do NOT set visible=true here! Keep hidden until spawner sets position.
	# This prevents the 1-frame HP bar flash at map center (0,0).
	# Spawner sets visible=true AFTER setting global_position.
	visible = false
	
	# Hide HP bars immediately to prevent flash at (0,0)
	if hp_bar:
		hp_bar.visible = false
	if hp_label:
		hp_label.visible = false
	if shield_bar:
		shield_bar.visible = false
	if shield_label:
		shield_label.visible = false

	if visuals:
		visuals.visible = true # Sprite itself can be visible, enemy node controls overall
		visuals.modulate = Color.WHITE
		# visuals.scale MUST be kept as configured by CharacterSpriteAnimator!
		
		_is_stunned = false
		if visuals.has_method("set_paused"):
			visuals.set_paused(false)
			
		# Reset Material (Clear shader effects only if active)
		if _time_freeze_material and visuals.material == _time_freeze_material:
			visuals.material = _original_material
		elif _dot_ripple_material and visuals.material == _dot_ripple_material:
			visuals.material = _original_material
			
		_time_freeze_material = null # Deref temp material instance
		_dot_ripple_material = null
			
	# Reset Stun
	_is_stunned = false
	
	# Reset HP Bar visual state (already hidden above)
	if hp_bar:
		hp_bar.modulate = Color.WHITE

	
	# 1. Reset Physics/Movement
	velocity = Vector2.ZERO
	global_position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	
	# 2. Reset Health
	# CRITICAL: Reset Max HP to base value (from stats or default). 
	# If we don't do this, EnemySpawner will multiply the ALREADY MULTIPLIED max_hp 
	# from the previous life, causing exponential stats growth.
	var base_hp = 100
	if stats and "max_hp" in stats:
		base_hp = stats.max_hp
	
	# Apply base HP to component
	if health_component:
		health_component.max_hp = base_hp # Directly set base
		health_component.current_hp = base_hp # Full heal
		
		if hp_label:
			hp_label.text = str(base_hp) + "/" + str(base_hp)
	
	# Reset Hitbox (Fix for invincibility bugs)
	if hitbox_component and hitbox_component.has_method("reset"):
		hitbox_component.reset()
		# EXPORT FIX: Force-link HealthComponent to ensure it's not null
		if "health_component" in hitbox_component:
			hitbox_component.health_component = health_component


	# 3. Reset State Flags
	_can_shoot = true
	_is_charging = false
	_charge_timer = 0.0
	if _charge_effect:
		_charge_effect.visible = false
	_damage_timer = 0.0
	_laser_cooldown = 0.0
	
	# 4. Reset Charm State
	if _is_charmed:
		set_charmed(null, false, true) # Force uncharm
	_is_charmed = false
	_charm_owner = null
	_current_target = null
	
	# 5. Reset Groups
	# We must remove any "special" groups assigned during lifetime/spawn
	var groups_to_remove = ["tank", "shielder", "exploder", "boss", "super_boss", "elite", "ranged", "charmed_allies"]
	for g in groups_to_remove:
		if is_in_group(g):
			remove_from_group(g)
			
	# Remove old meta flags (Critical for loot table reset and damage logic)
	if has_meta("pristine_core_drop"):
		remove_meta("pristine_core_drop")
	if has_meta("enemy_tier"):
		remove_meta("enemy_tier")
	# EXPORT FIX: Clear damage modifiers that might persist in pool
	if has_meta("super_boss_damage_reduction"):
		remove_meta("super_boss_damage_reduction")
	if has_meta("damage_vulnerability"):
		remove_meta("damage_vulnerability")
			
	# 6. CLEANUP POOLED CHILDREN
	# Remove attached AI and Effects from previous life
	# 6. CLEANUP POOLED CHILDREN
	# Remove attached AI and Effects from previous life
	var nodes_to_clean = ["BossAI", "BossEffects", "EliteEffects", "TankEffects", "SuperBossEffects", "CharmEffect", "ExploderBehavior", "ShielderShield"]
	for node_name in nodes_to_clean:
		var node = get_node_or_null(node_name)
		if node:
			# CRITICAL: Remove from tree immediately so name is free for next spawn
			remove_child(node)
			node.queue_free()
			
	# Remove Shields
	if _generic_boss_shield:
		if _generic_boss_shield.get_parent() == self:
			remove_child(_generic_boss_shield)
		_generic_boss_shield.queue_free()
		_generic_boss_shield = null
	
	# Remove BurnDOTs (scan children by script path to be safe)
	# Iterate backwards to safely remove
	for i in range(get_child_count() - 1, -1, -1):
		var child = get_child(i)
		if child.get_script() and child.get_script().resource_path.contains("BurnDOT.gd"):
			remove_child(child)
			child.queue_free()
			
	# 7. Reset Visuals
	# EXPORT FIX: Do NOT force visible=true here. Let Spawner handle it after positioning.
	# visible = true 
	modulate = Color.WHITE
	if visuals:
		# Use the NEW dedicated reset method (Fixes sprite disappearance on reuse)
		if visuals.has_method("reset"):
			visuals.reset()
		else:
			# Fallback for old animator script
			visuals.visible = true
			visuals.modulate = Color.WHITE
			if visuals.has_method("play") and visuals.sprite_frames and visuals.sprite_frames.has_animation("down"):
				visuals.play("down")
		
		# Reset any other visual overrides?
		if visuals.has_method("set_paused"):
			visuals.set_paused(false)
			
	# Reset Health Component SAFELY
	if health_component:
		# FIRST: Reset death state flags
		if health_component.has_method("reset"):
			health_component.reset()
		
		# THEN: Restore HP
		health_component.max_hp = base_hp
		health_component.current_hp = base_hp

	if hp_bar:
		hp_bar.visible = false # Hide until position sync
		
		# RESTORE DEFAULT GREEN STYLEBOX
		# Previous overrides (Red/Purple) persist if not cleared.
		# Basic enemies rely on the default Green set in _ready().
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = Color(0, 1, 0) # Default Green
		hp_bar.add_theme_stylebox_override("fill", style_box)
		
		hp_bar.value = hp_bar.max_value
	if hp_label:
		hp_label.visible = false
	
	# 9. Reset internal logic
	_cached_font_size = -1
	_prev_scale_x = 0.0
	_cached_shield = null
	
	# 10. Re-enable processing
	set_process(true)
	set_physics_process(true)
	set_process_internal(true)
	set_physics_process_internal(true)
	
	# Reset stun state (Fix for stationary spawning if died while stunned)
	set_stunned(false)
	
	if collision_layer == 0:
		collision_layer = 4 # Restore to Enemy Layer (4)
		set_collision_mask_value(1, true)
		set_collision_mask_value(2, true) # Scan player layer
		set_collision_mask_value(3, true) # Scan other enemies?
		
	# 11. Signals
	# Signals should persist, but ensure distinct connections? 
	# They are connected in _ready once. We don't disconnect them on death.
	
	# Reparent bars for new lifecycle
	# DISABLED: No longer reparenting to avoid errors
	# call_deferred("_reparent_hp_bars_to_effects_layer")

# Called by EnemySpawner after groups are assigned (can't use _ready as groups aren't set yet)
func setup_super_boss_shield() -> void:
	if is_in_group("ignore_generic_shield"): return
	_setup_generic_boss_shield()


func _setup_generic_boss_shield() -> void:
	var shield_script = load("res://scripts/enemies/effects/ShielderShield.gd")
	if not shield_script: return
	
	_generic_boss_shield = shield_script.new()
	add_child(_generic_boss_shield)
	
	# Configure Super Boss Shield (Purple, 10% HP, 30s CD)
	# Radius should be smaller - roughly matching the enemy sprite size
	var enemy_max_hp := 1000 # Fallback
	if health_component and health_component.max_hp > 0:
		enemy_max_hp = health_component.max_hp
	_generic_boss_shield.initialize(self, enemy_max_hp, 0.1, 70.0)
	_generic_boss_shield.color_theme = Color(0.6, 0.2, 1.0) # Purple
	_generic_boss_shield.auto_regen = false
	_generic_boss_shield.recharge_duration = 15.0 # Faster respawn than N01 (30s)
	_generic_boss_shield.bar_offset_y = -54.0 # Just above HP bar
	_generic_boss_shield.bar_width = 50.0 # Match HP bar width
	_generic_boss_shield.bar_height = 6.0 # Match HP bar height


	# Only hide local bar for regular bosses (they have HUD bar)
	# Super bosses don't have a HUD bar, so they need the local one
	# Note: super_boss is in BOTH "boss" and "super_boss" groups, so check both
	if is_in_group("boss") and not is_in_group("super_boss"):
		_generic_boss_shield.draw_hp_bar = false
	
	_generic_boss_shield.recharge_complete.connect(func(): _generic_shield_ready = true)
	
	# Spawn with shield ACTIVE
	_generic_boss_shield.activate()
	_generic_shield_ready = false

	
func get_active_shield_stats() -> Vector2:
	"""Returns (current_hp, max_hp) of active shield, or Vector2.ZERO"""
	var shield = _get_protecting_shield()
	if shield and "shield_hp" in shield and "max_shield_hp" in shield:
		return Vector2(shield.shield_hp, shield.max_shield_hp)
	return Vector2.ZERO

func _process_shield_deployment() -> void:
	if _generic_shield_ready and randf() < 0.005:
		if _generic_boss_shield and _generic_boss_shield.has_method("activate"):
			_generic_boss_shield.activate()
			_generic_shield_ready = false

# ============= Wells Visual Effects =============

func _ensure_universal_shader() -> void:
	"""Apply universal sprite shader for night glow."""
	if not visuals: return
	
	if not _universal_shader:
		_universal_shader = load("res://resources/shaders/universal_sprite_shader.gdshader")
	if not _universal_shader: return
		
	if not _universal_material:
		_universal_material = ShaderMaterial.new()
		_universal_material.shader = _universal_shader
		_universal_material.set_shader_parameter("enable_outline", false)
		_universal_material.set_shader_parameter("night_glow_color", Color(0.6, 0.6, 1.0, 1.0))
		_universal_material.set_shader_parameter("night_glow_intensity", 1.2)
		_universal_material.set_shader_parameter("day_brightness", 1.25)
	
	if visuals.material != _universal_material:
		visuals.material = _universal_material

func _ensure_time_freeze_shader() -> void:
	"""Lazy-load and apply time freeze shader to visuals."""
	if not visuals:
		return
	
	# Cache shader at class level (load once)
	if not _time_freeze_shader:
		_time_freeze_shader = load("res://resources/shaders/time_freeze_effect.gdshader")
	
	if not _time_freeze_shader:
		return
	
	# Create material if needed
	if not _time_freeze_material:
		_original_material = visuals.material
		_time_freeze_material = ShaderMaterial.new()
		_time_freeze_material.shader = _time_freeze_shader
	
	# Apply if not already applied
	if visuals.material != _time_freeze_material and visuals.material != _dot_ripple_material:
		_original_material = visuals.material
		visuals.material = _time_freeze_material

func _trigger_dot_pulse() -> void:
	"""Trigger red pulse effect for DoT damage."""
	if not visuals:
		return
	
	# Cache shader at class level
	if not _dot_ripple_shader:
		_dot_ripple_shader = load("res://resources/shaders/dot_ripple_effect.gdshader")
	
	if not _dot_ripple_shader:
		return
	
	# Create material if needed
	if not _dot_ripple_material:
		_dot_ripple_material = ShaderMaterial.new()
		_dot_ripple_material.shader = _dot_ripple_shader
	
	# Apply DoT shader and set intensity
	_dot_pulse_intensity = 1.0
	_dot_pulse_timer += 0.0 # Don't reset timer - keep smooth animation
	
	# Store current material if switching from time freeze
	if visuals.material == _time_freeze_material:
		pass # Will restore to time_freeze after pulse ends
	elif visuals.material != _dot_ripple_material:
		_original_material = visuals.material
	
	visuals.material = _dot_ripple_material
	_dot_ripple_material.set_shader_parameter("pulse_intensity", _dot_pulse_intensity)
	_dot_ripple_material.set_shader_parameter("pulse_time", _dot_pulse_timer)
