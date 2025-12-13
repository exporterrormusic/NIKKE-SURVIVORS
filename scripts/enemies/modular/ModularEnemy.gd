extends CharacterBody2D


# Replaces the monolithic logic of legacy enemy scripts

@export var stats: Resource

# Component References
@onready var health_component: Node = $HealthComponent
@onready var movement_component: Node = $MovementComponent
@onready var hitbox_component: Node = $HitboxComponent
@onready var visuals: Node2D = $AnimatedSprite2D
@onready var hp_bar: ProgressBar = $ProgressBar
@onready var hp_label: Label = $HPLabel
var shield_bar: ProgressBar = null
var shield_label: Label = null


var _generic_boss_shield: Node2D = null
var _generic_shield_ready: bool = false


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

	add_to_group("enemies")
	
	# if stats:
	# 	_apply_stats()
	
	health_component.died.connect(_on_death)
	health_component.health_changed.connect(_on_health_changed)
	# Fix: Connect for burst generation on hit
	health_component.damaged.connect(_on_damaged)
	
	# Find player to chase
	var player = get_tree().get_first_node_in_group("player")
	if player:
		movement_component.set_target(player)
		
	# RETROACTIVE DEATH CHECK: If died during spawner init (before ready), signal was missed.
	# We must manually trigger death sequence.
	# NOTE: current_hp might be reset to full by Spawner, so we MUST check is_dead() flag!
	if health_component.has_method("is_dead") and health_component.is_dead():
		_on_death()
		return # Stop further setup
		
		
	# Force initial label update
	if hp_label and health_component:
		hp_label.text = str(health_component.current_hp) + "/" + str(health_component.max_hp)
	
	# Force initial bar update (Sync with Spawner configuration)
	if hp_bar and health_component:
		hp_bar.max_value = health_component.max_hp
		hp_bar.value = health_component.current_hp

	# Configure visuals

	if visuals.has_method("configure"):
		var tex = load("res://assets/enemies/rapture-basic/sprite.png")
		visuals.configure(tex, 3, 4, 6.0, 0.15)
	
	# Create shadow
	_create_shadow()
	
	# Register sprite for night glow effect - REMOVED (Handled by EnemySpawner + Universal Shader)
	# if visuals:
	# 	NightGlowManager.register_sprite(visuals)
	
	# Setup HP bar styling (Green)
	# Hide initially - will be shown after first position sync to prevent flicker at origin
	hp_bar.visible = false
	hp_label.visible = false
	hp_bar.z_index = 50  # Below HUD layer (HUD is typically 100+)
	
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

	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0, 1, 0) # Green
	hp_bar.add_theme_stylebox_override("fill", style_box)
	
	# Background style (Grey)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2)
	hp_bar.add_theme_stylebox_override("background", bg_style)

	# DEBUG LABEL REMOVED
	
	# Update HP Bar color based on tier
	
	# Update HP Bar color based on tier
	if is_in_group("exploder"):
		var style = StyleBoxFlat.new()
		style.bg_color = Color(1.0, 0.2, 0.2) # Deep red for exploders
		hp_bar.add_theme_stylebox_override("fill", style)
	elif is_in_group("tank"):
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.95, 0.85, 0.2) # Yellow for tanks
		hp_bar.add_theme_stylebox_override("fill", style)
	elif is_in_group("boss") or is_in_group("super_boss"):
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.9, 0.0, 0.0) # Deep Red for bosses (User Requested)
		hp_bar.add_theme_stylebox_override("fill", style)
	elif is_in_group("elite"):
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.8, 0.1, 0.1) # Red for elites
		hp_bar.add_theme_stylebox_override("fill", style)
	else:
		# KEEP GREEN (Already set above)
		pass
	
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
		# Format as "Current/Max"
		hp_label.text = str(current) + "/" + str(_max)




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
const LASER_FIRE_INTERVAL := 3.0
const LASER_SPEED := 500.0
var _laser_cooldown := 0.0
const CHARGE_DURATION := 1.0
var _is_charging := false
var _charge_timer := 0.0
var _charge_effect: Node2D = null
var _glow_texture: Texture2D = null
# Default to true (Standard enemies shoot), Spawner can disable
var _can_shoot := true
const EnemyLaserScene = preload("res://scenes/projectiles/EnemyLaser.tscn")

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

func set_charmed(charm_owner: Node, charmed: bool = true, force: bool = false) -> void:
	# Validation: Don't charm Elites/Tanks/Bosses unless forced
	if not force:
		if is_in_group("elite") or is_in_group("tank") or is_in_group("boss") or is_in_group("super_boss"):
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
	# Find the closest valid target (Player, Charmed Ally, or Clone)
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
			
	_current_target = nearest
	movement_component.set_target(nearest if nearest else player)

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

func _process(delta: float) -> void:
	# If stunned, do nothing (frozen in time)
	if _is_stunned:
		return

	if _damage_timer > 0:
		_damage_timer -= delta
	if _laser_cooldown > 0:
		_laser_cooldown -= delta
		
	# Update timers
	_target_check_timer -= delta
	_shield_check_timer -= delta
	
	# Shield Check Logic (Throttled)
	if _shield_check_timer <= 0:
		_update_shield_status()
		_shield_check_timer = SHIELD_CHECK_INTERVAL
	
	# Targeting Logic (Throttled)
	if _target_check_timer <= 0:
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
			
		_target_check_timer = TARGET_CHECK_INTERVAL
	
	# Super Boss Shield Deployment (random chance to deploy when ready)
	if is_in_group("super_boss") and _generic_boss_shield:
		_process_shield_deployment()
	
	if visuals and visuals.has_method("update_state"):

		visuals.update_state(movement_component.velocity, movement_component.velocity)
		
	# Dynamic Text Scaling: Keep text physically large but rendered sharply
	if hp_label and hp_bar:
		# Optimization: Only recalculate if scale changed significantly
		var p_scale_x = abs(scale.x)
		if abs(p_scale_x - _prev_scale_x) > 0.01:
			_prev_scale_x = p_scale_x
			
			if p_scale_x > 0.001:
				# Reset pivot to default to simplified position math
				hp_label.pivot_offset = Vector2.ZERO
				
				# Ensure centered text
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
			
		# Center Alignment relative to the BAR
		# Bar is detached and scaled by 'scale'.
		var bar_global_pos = hp_bar.global_position
		var bar_visual_size = hp_bar.size * hp_bar.scale
		var bar_center_global = bar_global_pos + bar_visual_size * 0.5
		
		# Label size is now "pure" (unscaled) but reflects the larger font
		var label_size = hp_label.size
		
		# Set global position to center
		# CRITICAL FIX: Round to integer pixel coordinates to prevent jitter/blur
		var exact_pos = bar_center_global - label_size * 0.5
		hp_label.global_position = exact_pos.round()
				
	# Damage Logic (Attack Current Target)
	if is_instance_valid(_current_target):
		var dist = global_position.distance_to(_current_target.global_position)
		if dist < DAMAGE_DISTANCE and _damage_timer <= 0:
			if _current_target.has_method("take_damage"):
				# If we are charmed, we are "charmed_enemy" source
				var source = "charmed_enemy" if _is_charmed else "enemy"
				
				if _current_target.is_in_group("player"):
					# PlayerCore only accepts 1 argument
					_current_target.take_damage(base_damage)
				else:
					# Enemies/Others support extended arguments
					_current_target.take_damage(base_damage, false, Vector2.ZERO, false, source)
			_damage_timer = DAMAGE_COOLDOWN
			
	# Charging State Logic
	if _is_charging:
		_charge_timer -= delta
		
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
	if hp_bar and is_instance_valid(hp_bar):
		# Sync scale fully for the bar
		hp_bar.scale = scale
		# Calculate offset based on scale to keep it above the sprite
		# Default offset (-25, -47) for unscaled sprite
		var offset = Vector2(-25, -47) * scale
		hp_bar.global_position = (global_position + offset).round()
		
		# Sync Shield Bar (skip for bosses - they use ShielderShield's own bar)
		if shield_bar and is_instance_valid(shield_bar) and not is_in_group("boss") and not is_in_group("super_boss"):
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



	
	# Show bars after first position sync (prevents flicker at origin)
	if hp_bar and not hp_bar.visible:
		hp_bar.visible = true
	if hp_label and not hp_label.visible:
		hp_label.visible = true

func _reparent_hp_bars_to_effects_layer() -> void:
	"""DISABLED: Using top_level and unshaded material instead of reparenting."""
	pass

func _make_unshaded(node: CanvasItem) -> void:
	"""Make a node immune to lighting (stays bright at night)."""
	if not node: return
	node.top_level = true  # Position is now global, not relative to parent
	node.light_mask = 0    # Ignore all light sources
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
	var ChargeEffectScript = load("res://scripts/enemies/EnemyChargeEffect.gd")
	if ChargeEffectScript:
		_charge_effect = Node2D.new() # It's a Node2D with a script, not necessarily a Sprite
		_charge_effect.set_script(ChargeEffectScript)
		_charge_effect.z_index = 15
		add_child(_charge_effect)
		# Position slightly in front like legacy
		_charge_effect.position = dir * 25.0
		
		# Start effect
		if _charge_effect.has_method("start_charge"):
			_charge_effect.start_charge(CHARGE_DURATION)

func _update_charge_effect() -> void:
	if _charge_effect and is_instance_valid(_charge_effect):
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
	
	# Create timer to un-stun
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func(): if is_instance_valid(self): set_stunned(false))

func _fire_laser(direction: Vector2) -> void:
	var laser = EnemyLaserScene.instantiate()
	if laser == null: return
	
	# Configure laser direction
	if laser.has_method("set_direction"):
		laser.set_direction(direction)
	else:
		laser.rotation = direction.angle()
		
	laser.speed = LASER_SPEED
	laser.max_range = LASER_RANGE * 1.5
	laser.damage = base_damage
	
	# Scale laser projectile to match enemy size (Boss > Elite > Tank > Normal)
	laser.scale = scale
	laser.damage = int(base_damage * scale.x) # Optional: Scale damage slightly with size? Or is that already handled by stats?
	# User asked for visual scaling ("normal attacks are bigger"), but damage scaling often accompanies it. 
	# User said "normal attacks scale up the same amount as they scale up". Strict reading = visual scale.
	# I will stick to visual scale mostly, but damage is already set to `base_damage` which is usually 1. 
	# Elites/Bosses set `base_damage` higher via stats/spawner logic usually. 
	# Let's just scale the visual for now as requested.
	laser.scale = scale
	
	# Boss Projectile Size Enforcement
	# Ensure boss projectiles are physically large (matching 4.5x scale expectation)
	# even if the boss entity itself is scaled differently (e.g. 2.25x)
	if is_in_group("boss") or is_in_group("super_boss"):
		var min_boss_scale = Vector2(4.5, 4.5)
		if laser.scale.x < min_boss_scale.x:
			laser.scale = min_boss_scale
	
	# Configure Faction Logic (Friendly Fire)
	if _is_charmed:
		# Charmed Laser: Hits Enemies (Layer 2), Ignore Player (Layer 1)
		laser.collision_mask = 2 # Enemies
		laser.set_meta("from_charmed", true)
	else:
		# Normal Laser: Hits Player (Layer 1) AND Enemies/Charmed (Layer 2)
		# (Script logic prevents hurting allies, but we need collision)
		laser.collision_mask = 3 # Player (1) + Enemies (2)
	
	laser.global_position = global_position + direction * 20.0
	get_parent().add_child(laser)


func _on_damaged(_amount: int, source: String) -> void:
	"""Handler for when enemy takes damage. Registers burst hit if from player."""
	# Only register burst if damaged by player or their projectiles/summons
	if source in ["player", "projectile", "summon", "cecil_drone"]:
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("register_burst_hit"):
			player.register_burst_hit(self)

func _on_death(overkill: int = 0) -> void:
	# Defer ENTIRE death sequence to avoid physics locking
	call_deferred("_finalize_death", overkill)

func _finalize_death(overkill: int) -> void:
	# Check for overkill logic (2x HP damage = overkill?)
	# Legacy used: is_overkill = overkill_damage >= (max_hp * 2)
	# Here 'overkill' is just the excess.
	# So we need to check if overkill >= max_hp * 2? Or just > 0?
	# Legacy: _overkill_damage = -hp. is_overkill = _overkill_damage >= (max_hp * 2).
	# This implies doing 3x HP total damage.
	
	var is_overkill = overkill >= (stats.max_hp * 2) if stats else false
	var overkill_multiplier = 2.0 if is_overkill else 1.0
	
	# Add score to GameState
	var score_value: int = 100
	if is_in_group("elite"): score_value = 500
	elif is_in_group("boss"): score_value = 2000
	elif is_in_group("super_boss"): score_value = 5000
	elif is_in_group("tank"): score_value = 300
	
	if is_overkill:
		score_value = int(score_value * 1.5)
		
	if ClassDB.class_exists("GameState") or get_tree().root.has_node("GameState"):
		# Assuming GameState singleton exists
		var gs = get_node("/root/GameState")
		if gs and gs.has_method("add_score"):
			gs.add_score(score_value)
			
	# Emit Global Event
	# Using get_node_or_null to prevent crashes if EventBus autoload is missing/renamed in export
	var event_bus = get_node_or_null("/root/EventBus")
	if event_bus:
		event_bus.enemy_killed.emit(self, "player")
		
	# Drop Pristine Cores (Bosses)
	if has_meta("pristine_core_drop"):
		var killed_by_enrage = false
		var gs_meta = get_node_or_null("/root/GameState")
		if gs_meta and gs_meta.has_meta("killed_by_enrage"):
			killed_by_enrage = gs_meta.get_meta("killed_by_enrage")
			
		if not killed_by_enrage:
			var cores = get_meta("pristine_core_drop")
			_spawn_pristine_core_orb(cores)
			
	# Combat Juice Register
	# Combat Juice Register
	var cj = get_node_or_null("/root/CombatJuice")
	if cj: cj.register_kill(overkill_multiplier)

	# Spawn death effect
	if RobotDeathEffectScript:
		var death_effect := Node2D.new()
		death_effect.set_script(RobotDeathEffectScript)
		death_effect.global_position = global_position
		if death_effect.has_method("set_overkill"):
			death_effect.set_overkill(is_overkill)
		get_parent().add_child(death_effect)
	
	# Spawn XP orbs (Scaled by Tier)
	var xp_orb_count := 5
	if is_in_group("tank"): xp_orb_count = 8
	elif is_in_group("elite"): xp_orb_count = 15
	elif is_in_group("boss"): xp_orb_count = 25
	elif is_in_group("super_boss"): xp_orb_count = 40
	
	for i in xp_orb_count:
		var orb = ProjectileCache.create_xp_orb()
		if orb:
			get_parent().add_child(orb)
			orb.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	# POOLING: Return to spawner pool instead of freeing
	var spawner = get_tree().get_first_node_in_group("enemy_spawners")
	if spawner and spawner.has_method("return_enemy"):
		spawner.return_enemy(self)
	else:
		queue_free()

func _spawn_pristine_core_orb(value: int) -> void:
	if ResourceLoader.exists("res://scripts/world/PristineCoreOrb.gd"):
		var orb = Area2D.new()
		orb.set_script(load("res://scripts/world/PristineCoreOrb.gd"))
		orb.set("cores_value", value)
		orb.global_position = global_position
		get_parent().add_child(orb)


# Forwarding 'take_damage' for direct calls that bypass HitboxComponent
func take_damage(amount: int, is_crit: bool = false, direction: Vector2 = Vector2.ZERO, is_burst: bool = false, source: String = "unknown") -> void:
	# Check if protected by a Shielder's shield
	if _check_shielder_protection(amount):
		return  # Damage absorbed by shield
	hitbox_component.take_damage(amount, is_crit, direction, is_burst, source)

func _check_shielder_protection(damage_amount: int) -> bool:
	"""Check if this enemy is protected by a Shielder's shield. Returns true if damage was absorbed."""
	# Check protection status and get the shield instance
	var shielding_unit = _get_protecting_shield()
	if shielding_unit:
		shielding_unit.take_shield_damage(damage_amount)
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
	sb_bg.bg_color = Color(0,0,0,0.5)
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
	shield_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))  # Black outline
	shield_label.add_theme_constant_override("outline_size", 4)  # Match HPLabel
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
	
	# 1. Reset Physics/Movement
	velocity = Vector2.ZERO
	global_position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	
	# 2. Reset Health
	# 2. Reset Health
	# Note: Max HP is set by Spawner config immediately after retrieval
	if health_component:
		if health_component.has_method("reset"):
			health_component.reset()
		else:
			health_component.current_hp = health_component.max_hp
			# Fallback if reset() missing (legacy safety)
	
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
	var groups_to_remove = ["tank", "shielder", "exploder", "boss", "super_boss", "elite", "ranged"]
	for g in groups_to_remove:
		if is_in_group(g):
			remove_from_group(g)
			
	# 6. Reset Visuals
	visible = true # Ensure the entire node is valid
	modulate = Color.WHITE
	if visuals:
		visuals.visible = true
		visuals.modulate = Color.WHITE
		# Reset any other visual overrides?
	
	# 7. Reset UI
	if hp_bar:
		hp_bar.visible = false # Hide until position sync
		# Reset styleboxes to default Green/Grey? 
		# Actually Spawner re-applies styleboxes based on type, so this is fine.
		hp_bar.value = hp_bar.max_value
	if hp_label:
		hp_label.visible = false
	
	# 8. Reset internal logic
	_cached_font_size = -1
	_prev_scale_x = 0.0
	_cached_shield = null
	
	# 9. Re-enable processing
	set_process(true)
	set_physics_process(true)
	set_process_internal(true)
	set_physics_process_internal(true)
	
	# Reset stun state (Fix for stationary spawning if died while stunned)
	set_stunned(false)
	
	if collision_layer == 0:
		collision_layer = 1 # Restore default
		
	# 10. Signals
	# Signals should persist, but ensure distinct connections? 
	# They are connected in _ready once. We don't disconnect them on death.
	
	# Reparent bars for new lifecycle
	# DISABLED: No longer reparenting to avoid errors
	# call_deferred("_reparent_hp_bars_to_effects_layer")

	
	# FORCE HP BAR VISIBILITY
	if hp_bar:
		hp_bar.visible = true
		hp_bar.modulate.a = 1.0

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
	var enemy_max_hp := 1000  # Fallback
	if health_component and health_component.max_hp > 0:
		enemy_max_hp = health_component.max_hp
	_generic_boss_shield.initialize(self, enemy_max_hp, 0.1, 70.0)
	_generic_boss_shield.color_theme = Color(0.6, 0.2, 1.0) # Purple
	_generic_boss_shield.auto_regen = false
	_generic_boss_shield.recharge_duration = 15.0  # Faster respawn than N01 (30s)
	_generic_boss_shield.bar_offset_y = -54.0 # Just above HP bar
	_generic_boss_shield.bar_width = 50.0   # Match HP bar width
	_generic_boss_shield.bar_height = 6.0   # Match HP bar height


	
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
