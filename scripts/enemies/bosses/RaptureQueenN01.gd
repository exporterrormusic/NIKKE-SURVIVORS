extends "res://scripts/enemies/modular/ModularEnemy.gd"
class_name RaptureQueenN01

## RAPTURE QUEEN - N01
## Unique boss with animated hair, glowing eyes/mouth, teleport, and regen abilities

# Visual overlay references
var _visuals: Node2D = null

# Ability timers
var _teleport_cooldown: float = 0.0
var _regen_cooldown: float = 0.0
var _dodge_timer: float = 0.0

# Ability config
const TELEPORT_COOLDOWN := 8.0
const REGEN_COOLDOWN := 15.0
const REGEN_AMOUNT := 0.05  # 5% of max HP per tick
const REGEN_DURATION := 3.0
const DODGE_CHANCE := 0.35  # 35% chance to dodge attacks (INCREASED from 15%)

# State
var _regen_accumulator: float = 0.0
var _is_self_destructing := false
var _self_destruct_timer: float = 0.0
var _is_teleporting := false

func _ready() -> void:
	# Mark as boss BEFORE super._ready() so ModularEnemy can see the group
	add_to_group("boss")
	set_meta("enemy_tier", "boss")
	
	super._ready()
	
	# FORCE BOSS BAR (User Request)
	
	# Notify HUD
	if EventBus:
		EventBus.boss_spawned.emit(self)
	
	# 1.5 is already big, but boss requested 4.5x equivalent?
	# 4.5x is for Sprite2D scaling.
	# We use Node2D scaling.
	# User requested 1.5 -> 2.25 (50% increase)
	scale = Vector2(2.25, 2.25)
	
	# Get Visuals reference
	if has_node("Visuals"):
		_visuals = $Visuals
	
	# Setup health and movement override
	if health_component:
		health_component.max_hp = 5000
		health_component.current_hp = 5000
	
	if movement_component:
		movement_component.max_speed = 120.0 # Increased from 40.0
		movement_component.acceleration = 300.0
		movement_component.friction = 200.0

# ...

	# Add BossAI for missiles and beam (if not present)
	if not has_node("BossAI"):
		var boss_ai = Node.new()
		boss_ai.name = "BossAI"
		boss_ai.set_script(load("res://scripts/enemies/BossAI.gd"))
		add_child(boss_ai)
	
	# Add Slime Trail Manager to world (parent) not to boss
	if get_parent():
		var existing_trail = get_parent().get_node_or_null("RaptureQueenSlimeTrail")
		if not existing_trail:
			var slime_trail = Node2D.new()
			slime_trail.name = "RaptureQueenSlimeTrail"
			slime_trail.set_script(load("res://scripts/enemies/bosses/effects/RaptureQueenSlimeTrail.gd"))
			get_parent().add_child(slime_trail)
			slime_trail.setup(self)  # Pass boss reference

# Removed _setup_visual_overlays as logic is now in Visuals node

func _process(delta: float) -> void:
	super._process(delta)
	
	# Update ability cooldowns
	if _teleport_cooldown > 0:
		_teleport_cooldown -= delta
	if _regen_cooldown > 0:
		_regen_cooldown -= delta
	
	# Force HP bar position and visibility (Handle reparenting to global layer)
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.visible = true
		hp_bar.scale = Vector2.ONE
		hp_bar.size = Vector2(250, 40) # Even wider/taller
		
		# Manual Centering Calculation
		# Boss Global Center = global_position
		# Bar Global Center = global_position + Vector2(0, -220)
		# Bar TopLeft = Global Center - Size/2
		hp_bar.global_position = global_position + Vector2(-125, -220)
		
	if hp_label and is_instance_valid(hp_label):
		hp_label.visible = true
		# Full size of bar
		hp_label.scale = Vector2.ONE
		hp_label.global_position = hp_bar.global_position
		hp_label.size = hp_bar.size
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hp_label.add_theme_font_size_override("font_size", 28) # Perfectly legible size
	
	# Process regeneration (Passive)
	_process_passive_regeneration(delta)

	# Process Self Destruct
	if _is_self_destructing:
		_process_self_destruct(delta)
	# Check trigger
	elif health_component.current_hp <= health_component.max_hp * 0.10: # 10% Threshold
		_trigger_self_destruct()
		
func _process_passive_regeneration(delta: float) -> void:
	# Don't regen if dead
	if health_component.is_dead():
		return
		
	var hp_percent = float(health_component.current_hp) / float(health_component.max_hp)
	var regen_rate_percent = 0.0
	
	if hp_percent >= 0.50:
		regen_rate_percent = 0.01 # 1%
	elif hp_percent >= 0.25:
		regen_rate_percent = 0.025 # 2.5%
	else:
		regen_rate_percent = 0.05 # 5%
		
	# Apply Heal
	var heal_amount = health_component.max_hp * regen_rate_percent * delta
	
	# Accumulate fractionals if needed, but simple integer addition every frame works fine at high framerates
	# Using max() to ensure at least 1 HP if rate is very low, but floating point drift handling:
	# Better to store accumulation if precise, but for boss HP (5000+), 1% is 50/sec. 
	# Even at 60fps that's ~0.8 hp/frame. Integer truncation might lose it.
	
	_regen_accumulator += heal_amount
	if _regen_accumulator >= 1.0:
		var int_heal = int(_regen_accumulator)
		_regen_accumulator -= int_heal
		health_component.current_hp = mini(health_component.current_hp + int_heal, health_component.max_hp)
	
	# Update HP bar
	if hp_bar: hp_bar.value = health_component.current_hp
	if hp_label: hp_label.text = str(health_component.current_hp) + "/" + str(health_component.max_hp)

func _trigger_self_destruct() -> void:
	_is_self_destructing = true
	_self_destruct_timer = 10.0 # 10 seconds
	
	# Visual Warning
	if hp_label:
		hp_label.modulate = Color(1, 0, 0) # Red Text
		
	# Could play alarm sound or flash effect here
	print("WARNING: RAPTURE QUEEN SELF DESTRUCT SEQUENCE INITIATED")

func _process_self_destruct(delta: float) -> void:
	_self_destruct_timer -= delta
	
	# Visual Countdown on HP Label?
	if hp_label:
		hp_label.text = "SELF DESTRUCT: %.1f" % _self_destruct_timer
		
	# Flash red faster as time runs out
	modulate.g = abs(sin(_self_destruct_timer * 5.0))
	modulate.b = abs(sin(_self_destruct_timer * 5.0))
	
	if _self_destruct_timer <= 0:
		_execute_instant_kill()

func _execute_instant_kill() -> void:
	print("RAPTURE QUEEN EXPLOSION!")
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player) and player.has_method("take_damage"):
		# Deal 100% Max HP
		# We need to hack access to max_hp or just deal 999999
		var dmg = 999999
		if "max_hp" in player:
			dmg = player.max_hp
		elif player.has_node("HealthComponent"):
			dmg = player.get_node("HealthComponent").max_hp
			
		# Bypass iframe/armor if possible (True Damage)
		player.take_damage(dmg, false, Vector2.ZERO, true) # True Damage flag
		
	# Boss dies too (implied explosion)
	health_component.die()

func take_damage(amount: int, is_crit: bool = false, knockback_dir: Vector2 = Vector2.ZERO, is_true_damage: bool = false, source: String = "") -> void:
	# Dodge chance
	if randf() < DODGE_CHANCE and not is_true_damage:
		_perform_teleport_dodge()
		return
	
	super.take_damage(amount, is_crit, knockback_dir, is_true_damage, source)

func _perform_teleport_dodge() -> void:
	if _is_teleporting or _teleport_cooldown > 0:
		return
	
	_is_teleporting = true
	_teleport_cooldown = TELEPORT_COOLDOWN
	
	# Store start position
	var start_pos = global_position
	
	# Calculate destination - TACTICAL: teleport toward player
	var player = get_tree().get_first_node_in_group("player")
	var new_pos: Vector2
	
	if player and is_instance_valid(player):
		var to_player = player.global_position - global_position
		var distance_to_player = to_player.length()
		
		# If player is far away, teleport closer (but maintain safe distance)
		if distance_to_player > 300.0:
			# Move toward player, but stop at safe distance (200-300px)
			var target_distance = randf_range(200.0, 300.0)
			var direction = to_player.normalized()
			new_pos = player.global_position - direction * target_distance
		else:
			# Player is close, teleport to flanking position
			var angle = randf() * TAU
			var teleport_dist = randf_range(250.0, 350.0)
			var teleport_offset = Vector2(cos(angle), sin(angle)) * teleport_dist
			new_pos = global_position + teleport_offset
			
			# Ensure we don't get TOO close to player
			var new_to_player = player.global_position - new_pos
			if new_to_player.length() < 150.0:
				# Too close, push away
				new_pos = player.global_position - new_to_player.normalized() * 200.0
	else:
		# No player found, random teleport
		var teleport_angle = randf() * TAU
		var teleport_dist = randf_range(400.0, 600.0)
		var teleport_offset = Vector2(cos(teleport_angle), sin(teleport_angle)) * teleport_dist
		new_pos = global_position + teleport_offset
	
	# Visual effect: Apply dissolve to ENTIRE boss
	if _visuals and _visuals.has_method("set_teleporting"):
		_visuals.set_teleporting(true, 1.0)
	
	# Create DRAMATIC dissolve particle effect at start position
	var dissolve_effect = Node2D.new()
	dissolve_effect.set_script(load("res://scripts/enemies/bosses/effects/RaptureQueenTeleportEffect.gd"))
	get_parent().add_child(dissolve_effect)
	dissolve_effect.setup_dissolve(start_pos, scale.x)  # Pass scale for proper sizing
	
	# Multi-stage teleport animation
	var tween = create_tween()
	
	# Stage 1: Dissolve (0.4s) - Boss dissolves completely
	tween.tween_method(func(amount: float):
		if _visuals and _visuals.has_method("set_dissolve_amount"):
			_visuals.set_dissolve_amount(amount)
		# Fade out completely
		modulate.a = 1.0 - amount
	, 0.0, 1.0, 0.4)
	
	# Stage 2: Teleport happens (instant, while invisible)
	tween.tween_callback(func():
		global_position = new_pos
		# Create reform particle effect at new position
		var reform_effect = Node2D.new()
		reform_effect.set_script(load("res://scripts/enemies/bosses/effects/RaptureQueenTeleportEffect.gd"))
		get_parent().add_child(reform_effect)
		reform_effect.setup_reform(new_pos, scale.x)  # Pass scale for proper sizing
	)
	
	# Brief pause while fully dissolved
	tween.tween_interval(0.15)
	
	# Stage 3: Reform (0.4s) - Boss reappears with reverse dissolve
	tween.tween_method(func(amount: float):
		if _visuals and _visuals.has_method("set_dissolve_amount"):
			_visuals.set_dissolve_amount(1.0 - amount)
		# Fade back in completely
		modulate.a = amount
	, 0.0, 1.0, 0.4)
	
	# Stage 4: Cleanup
	tween.tween_callback(func():
		_is_teleporting = false
		modulate.a = 1.0
		if _visuals and _visuals.has_method("set_teleporting"):
			_visuals.set_teleporting(false)
		if _visuals and _visuals.has_method("set_dissolve_amount"):
			_visuals.set_dissolve_amount(0.0)
	)

func get_velocity_for_hair() -> Vector2:
	if movement_component:
		return movement_component.velocity
	return Vector2.ZERO
