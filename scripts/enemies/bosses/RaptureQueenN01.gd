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
const REGEN_AMOUNT := 0.05 # 5% of max HP per tick
const REGEN_DURATION := 3.0
const DODGE_CHANCE := 0.35 # 35% chance to dodge attacks (INCREASED from 15%)

# Aggression system - scales with HP loss
var _base_movement_speed: float = 120.0
var _aggression_multiplier: float = 1.0 # 1.0 at full HP, up to 1.5 at low HP
const AGGRESSION_COOLDOWN_REDUCTION := 0.5 # Up to 50% cooldown reduction at low HP
const AGGRESSION_SPEED_BOOST := 0.25 # Up to 25% speed boost at low HP

# State
var _regen_accumulator: float = 0.0
var _is_self_destructing := false
var _self_destruct_timer: float = 0.0
var _is_teleporting := false
var _event_timer: float = 0.0
var _warning_triggered: bool = false
var _explosion_triggered: bool = false
var _horde_summoned: bool = false # Track if 30% HP horde has been triggered
const EVENT_WARNING_TIME := 168.0 # 2:48
const EVENT_EXPLOSION_TIME := 174.0 # 2:54
const HORDE_COUNT := 70 # Number of enemies to spawn
const HORDE_SPAWN_DURATION := 2.0 # Stagger spawns over 2 seconds

# XP Deduplication - prevent double XP from duplicate damage signals
var _last_xp_frame: int = -1
var _last_xp_amount: int = 0
var _xp_accumulator: float = 0.0 # Accumulates partial XP for fast weapons (e.g. Minigun 0.5%)

func _ready() -> void:
	# Mark as boss BEFORE super._ready() so ModularEnemy can see the group
	add_to_group("boss")
	set_meta("enemy_tier", "boss")
	
	super._ready()
	
	# Set display name for boss bar
	set_meta("display_name", "RAPTURE QUEEN - N01")
	
	# Setup health and movement override (MOVED BEFORE HUD NOTIFICATION)
	if health_component:
		var game_manager = get_node_or_null("/root/GameManager")
		var base_hp := 6666
		
		# Apply difficulty scaling to HP (same as other enemies)
		var difficulty_mult: float = 1.0
		if game_manager:
			difficulty_mult = game_manager.difficulty_multiplier
			# Scale HP: 6666 base, +25% per difficulty level above 1
			base_hp = int(6666 * (1.0 + (difficulty_mult - 1.0) * 0.25))
		
		# Goddess Fall / She Descends override
		if game_manager and (game_manager.she_descends_mode or game_manager.goddess_fall_mode):
			health_component.max_hp = base_hp
			health_component.current_hp = base_hp
			# Connect damaged signal for XP-from-damage
			if not health_component.damaged.is_connected(_on_she_descends_damaged):
				health_component.damaged.connect(_on_she_descends_damaged)
		else:
			# Normal Boss Mode
			health_component.max_hp = base_hp
			health_component.current_hp = base_hp

	# Update local HP bar specifically because ModularEnemy initialized it with old values
	if hp_bar:
		hp_bar.max_value = health_component.max_hp
		hp_bar.value = health_component.current_hp
	
	# FORCE BOSS BAR (User Request)
	
	# Notify HUD
	if EventBus:
		EventBus.boss_spawned.emit(self)
		
	# Play Timer Music (Correct place for all spawn methods)
	if AudioDirector:
		AudioDirector.play_queen_timer_music()
	
	# N01 scale - laser hitbox is now 75% of visual (generous to player)
	scale = Vector2(2.25, 2.25)
	
	# Get Visuals reference
	if has_node("Visuals"):
		_visuals = $Visuals
	
	# Health setup moved to start of _ready
	
	if movement_component:
		_base_movement_speed = 120.0 # Store base speed for aggression scaling
		movement_component.max_speed = _base_movement_speed
		movement_component.acceleration = 300.0
		movement_component.friction = 200.0

# ...

	# Add BossAI for missiles and beam (if not present)
	if not has_node("BossAI"):
		var boss_ai = Node.new()
		boss_ai.name = "BossAI"
		boss_ai.set_script(load("res://scripts/enemies/BossAI.gd"))
		add_child(boss_ai)
	
	# Add Slime Trail Manager - DISABLED per user request
	# if get_parent():
	# 	var existing_trail = get_parent().get_node_or_null("RaptureQueenSlimeTrail")
	# 	if not existing_trail:
	# 		var slime_trail = Node2D.new()
	# 		slime_trail.name = "RaptureQueenSlimeTrail"
	# 		slime_trail.set_script(load("res://scripts/enemies/bosses/effects/RaptureQueenSlimeTrail.gd"))
	# 		get_parent().add_child(slime_trail)
	# 		slime_trail.setup(self)  # Pass boss reference

	# Setup Boss Shield (Purple, 10% HP, 30s CD)
	_setup_boss_shield()

# Removed _setup_visual_overlays as logic is now in Visuals node

func _exit_tree() -> void:
	# CLEANUP: Remove global overlays on scene switch/restart
	var overlay = get_tree().root.get_node_or_null("QueenEventOverlay")
	if overlay:
		overlay.queue_free()
	
	var explosion = get_tree().root.get_node_or_null("QueenEventExplosion")
	if explosion:
		explosion.queue_free()
		
	var explosion_end = get_tree().root.get_node_or_null("QueenExplosionEnd")
	if explosion_end:
		explosion_end.queue_free()

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
	
	# Update aggression based on HP
	_update_aggression()
	
	# Process Event Timer (Song synchronization)
	_process_event_timer(delta)

	# Process Self Destruct
	if _is_self_destructing:
		_process_self_destruct(delta)
	# Check trigger for self destruct
	elif health_component.current_hp <= health_component.max_hp * 0.10: # 10% Threshold
		_trigger_self_destruct()
	
	# Check trigger for horde summon at 30% HP
	if not _horde_summoned and health_component.current_hp <= health_component.max_hp * 0.30:
		_trigger_horde_summon()
		
	# Boss Shield Logic
	if _shield_ready_to_deploy and not _is_teleporting and not _is_self_destructing:
		# ~0.5% chance per frame to deploy shield if ready
		if randf() < 0.005:
			_deploy_shield()

var _boss_shield: Node2D = null
var _shield_ready_to_deploy: bool = false

func _setup_boss_shield() -> void:
	var shield_script = load("res://scripts/enemies/effects/ShielderShield.gd")
	if not shield_script: return
	
	_boss_shield = shield_script.new()
	# Add as child so it inherits scale (2.25x)
	add_child(_boss_shield)
	
	# Configure: Purple, 10% Max HP, Manual Regen, 30s Cooldown
	# Shield HP = 10% of boss max HP (666 at base 6666 HP)
	# Base radius reduced because 2.25x scale makes it huge
	var shield_hp := int(health_component.max_hp * 0.1)
	_boss_shield.initialize(self, shield_hp, 0.5, 120.0)
	_boss_shield.color_theme = Color(0.7, 0.3, 1.0) # Purple
	_boss_shield.auto_regen = false
	_boss_shield.recharge_duration = 30.0
	_boss_shield.bar_offset_y = -120.0 # High above HP bar
	# Note: draw_hp_bar is now enabled so boss has both HUD and world-space bars
	
	_boss_shield.recharge_complete.connect(func():
		_shield_ready_to_deploy = true
	)
	
	# 3. Boss Shield XP
	# Connect to the shield's damage signal to award XP when hitting shield
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and (game_manager.she_descends_mode or game_manager.goddess_fall_mode):
		if _boss_shield and _boss_shield.has_signal("shield_damaged"):
			if not _boss_shield.shield_damaged.is_connected(Callable(self, "_on_she_descends_damaged")):
				# Pass the actual source from the shield instead of hardcoding "boss_shield"
				_boss_shield.shield_damaged.connect(func(amount, source): _on_she_descends_damaged(amount, source))
	
	# Start inactive but ready
	_boss_shield.deactivate_initially()
	_shield_ready_to_deploy = true

func _deploy_shield() -> void:
	if _boss_shield and _boss_shield.has_method("activate"):
		_boss_shield.activate()
		_shield_ready_to_deploy = false

func get_active_shield_stats() -> Vector2:
	# Override: Return our boss shield stats for BossHealthBar
	if _boss_shield and _boss_shield.is_active():
		return Vector2(_boss_shield.shield_hp, _boss_shield.max_shield_hp)
	return Vector2.ZERO

func _process_event_timer(delta: float) -> void:
	_event_timer += delta
	
	# Debug print every 10 seconds
	if int(_event_timer) % 10 == 0 and int(_event_timer) != int(_event_timer - delta):
		print("[Queen] Event Timer: %.1f" % _event_timer)
	
	# 2:48 - Warning Phase (Red Tint + Charging)
	if _event_timer >= EVENT_WARNING_TIME and not _warning_triggered:
		print("[Queen] Triggering Event Warning at %.1f" % _event_timer)
		_trigger_event_warning()
	
	# 2:54 - Explosion Phase (Game Over)
	if _event_timer >= EVENT_EXPLOSION_TIME and not _explosion_triggered:
		print("[Queen] Triggering Event Explosion at %.1f" % _event_timer)
		_trigger_event_explosion()

func _trigger_event_warning() -> void:
	_warning_triggered = true
	print("[Queen] Creating Warning Overlay")
	
	# Create Red Overlay
	var canvas = CanvasLayer.new()
	canvas.layer = 110 # High layer
	canvas.name = "QueenEventOverlay"
	get_tree().root.add_child(canvas)
	
	var color_rect = ColorRect.new()
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.color = Color(1.0, 0.0, 0.0, 0.0)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(color_rect)
	
	# Animate Red Tint (Fade in over 6 seconds)
	var tween = create_tween()
	tween.tween_property(color_rect, "color:a", 0.4, 6.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	
	# Visual Charging Effect on Boss
	if _visuals:
		var charge_tween = create_tween()
		charge_tween.tween_property(_visuals, "modulate", Color(10.0, 0.5, 0.5, 1.0), 6.0) # Glow intense red

func _on_death(amount: int = 1) -> void:
	# Notify Director of Victory!
	var directors = get_tree().get_nodes_in_group("wave_director")
	if directors.size() > 0:
		if directors[0].has_method("notify_rapture_queen_defeated"):
			directors[0].notify_rapture_queen_defeated()
		else:
			# Fallback if specific method missing
			directors[0].notify_boss_defeated()
			
	super._on_death(amount)

func _trigger_event_explosion() -> void:
	_explosion_triggered = true
	
	# Clean up overlay
	var overlay = get_tree().root.get_node_or_null("QueenEventOverlay")
	if overlay:
		overlay.queue_free()
	
	# Massive Explosion Effect (White Flash -> Fade to Black)
	var canvas = CanvasLayer.new()
	canvas.layer = 120
	canvas.name = "QueenExplosionEnd"
	get_tree().root.add_child(canvas)
	
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color.WHITE
	flash.mouse_filter = Control.MOUSE_FILTER_STOP # Block inputs
	canvas.add_child(flash)
	
	# Animation Sequence - use tree tween so it survives if boss is freed
	# Also ensure it runs even when paused
	var tween = get_tree().create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # Run even when game is paused
	
	# 1. Hold White for 0.3s (Impact)
	tween.tween_interval(0.3)
	
	# 2. Fade to Black over 1.0s (reduced from 2.0s for snappier feel)
	tween.tween_property(flash, "color", Color.BLACK, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# 3. Brief hold on black
	tween.tween_interval(0.2)
	
	# 4. Trigger Defeat Menu (directly call Level's defeat method)
	tween.tween_callback(func():
		# First try to kill players for proper death handling
		var tree = Engine.get_main_loop() as SceneTree
		if tree:
			var players = tree.get_nodes_in_group("player")
			for p in players:
				if is_instance_valid(p) and p.has_method("take_damage"):
					p.take_damage(999999, false, Vector2.ZERO, true, "Rapture Queen:Self-Destruct")
			
			# Also directly trigger defeat menu as fallback
			var level = tree.get_first_node_in_group("level")
			if level and level.has_method("show_defeat_menu"):
				level.show_defeat_menu()
			else:
				# Try root level
				var root = tree.current_scene
				if root and root.has_method("show_defeat_menu"):
					root.show_defeat_menu()
	)

func _update_aggression() -> void:
	# Calculate aggression based on HP loss
	# At 100% HP: aggression = 1.0 (no bonus)
	# At 25% HP or below: aggression = 1.5 (max bonus)
	if not health_component:
		return
	
	var hp_percent = float(health_component.current_hp) / float(health_component.max_hp)
	
	# Aggression scales from 100% HP to 25% HP, then caps at max
	# At 100% HP: aggression_factor = 0
	# At 25% HP and below: aggression_factor = 1
	var aggression_factor: float
	if hp_percent <= 0.25:
		aggression_factor = 1.0 # Max aggression below 25%
	else:
		# Scale from 0 (at 100%) to 1 (at 25%)
		# Formula: (1.0 - hp_percent) / 0.75 when hp_percent is between 0.25 and 1.0
		aggression_factor = (1.0 - hp_percent) / 0.75
	
	_aggression_multiplier = 1.0 + aggression_factor * 0.5 # 1.0 to 1.5
	
	# Apply speed boost based on aggression
	if movement_component:
		var speed_boost = 1.0 + (aggression_factor * AGGRESSION_SPEED_BOOST)
		movement_component.max_speed = _base_movement_speed * speed_boost
	
	# Store cooldown multiplier for BossAI to read
	var cooldown_mult = 1.0 - (aggression_factor * AGGRESSION_COOLDOWN_REDUCTION)
	set_meta("aggression_cooldown_mult", cooldown_mult)

func get_aggression_cooldown_mult() -> float:
	# Called by BossAI to get current cooldown multiplier
	return get_meta("aggression_cooldown_mult", 1.0)

func _trigger_horde_summon() -> void:
	_horde_summoned = true
	
	# Show warning message
	var wave_ui = get_tree().get_first_node_in_group("wave_ui")
	if wave_ui and wave_ui.has_method("show_event"):
		wave_ui.show_event("boss", {"name": "RAPTURE QUEEN SUMMONS HER HORDE!"}, 30.0)
	elif EventBus and EventBus.has_signal("boss_warning"):
		EventBus.boss_warning.emit("RAPTURE QUEEN SUMMONS HER HORDE!")
	
	# Get spawner and camera for offscreen spawning
	var spawner = get_tree().get_first_node_in_group("enemy_spawners") as EnemySpawner
	if not spawner:
		push_warning("[RaptureQueen] No EnemySpawner found for horde summon (enemy_spawners group)!")
		print("[RaptureQueen] ERROR: No spawner in 'enemy_spawners' group!")
		return
	
	# Get camera and viewport for off-screen spawn logic
	var camera = get_tree().get_first_node_in_group("camera")
	var viewport_size := Vector2(1920, 1080) # Default fallback
	if camera and camera is Camera2D:
		viewport_size = camera.get_viewport_rect().size / camera.zoom
	var camera_pos: Vector2 = camera.global_position if camera else global_position
	
	# Get world bounds from environment controller
	var env_controller = get_tree().get_first_node_in_group("environment_controller")
	var world_bounds := Rect2(-2000, -2000, 4000, 4000) # Default fallback
	if env_controller and "get_world_bounds" in env_controller:
		world_bounds = env_controller.get_world_bounds()
	elif env_controller and "_world_bounds" in env_controller:
		world_bounds = env_controller._world_bounds
	
	# Calculate spawn positions around map edges
	var spawn_positions: Array[Vector2] = []
	var half_screen := viewport_size * 0.5
	
	# We want to spawn from ALL edges, not just visible ones
	# Divide the perimeter into HORDE_COUNT segments
	var perimeter := 2.0 * (world_bounds.size.x + world_bounds.size.y)
	var segment_length := perimeter / float(HORDE_COUNT)
	
	for i in HORDE_COUNT:
		var distance_along := segment_length * i
		var pos := Vector2.ZERO
		
		# Walk along the perimeter (inset 100px from actual edge)
		var inset := 100.0
		if distance_along < world_bounds.size.x:
			# Top edge
			pos = Vector2(world_bounds.position.x + distance_along, world_bounds.position.y + inset)
		elif distance_along < world_bounds.size.x + world_bounds.size.y:
			# Right edge
			var d := distance_along - world_bounds.size.x
			pos = Vector2(world_bounds.end.x - inset, world_bounds.position.y + d)
		elif distance_along < 2 * world_bounds.size.x + world_bounds.size.y:
			# Bottom edge
			var d := distance_along - world_bounds.size.x - world_bounds.size.y
			pos = Vector2(world_bounds.end.x - d, world_bounds.end.y - inset)
		else:
			# Left edge
			var d := distance_along - 2 * world_bounds.size.x - world_bounds.size.y
			pos = Vector2(world_bounds.position.x + inset, world_bounds.end.y - d)
		
		# CLAMP: Ensure position is strictly within world bounds with padding
		var padding := 150.0
		pos.x = clampf(pos.x, world_bounds.position.x + padding, world_bounds.end.x - padding)
		pos.y = clampf(pos.y, world_bounds.position.y + padding, world_bounds.end.y - padding)
		
		# Check if position is on screen - skip if so
		var screen_rect := Rect2(camera_pos - half_screen, viewport_size)
		if screen_rect.has_point(pos):
			# Move to just outside screen (but still within bounds)
			var to_center: Vector2 = (camera_pos - pos).normalized()
			pos -= to_center * 150.0 # Push 150px outside screen
			# Re-clamp after adjustment
			pos.x = clampf(pos.x, world_bounds.position.x + padding, world_bounds.end.x - padding)
			pos.y = clampf(pos.y, world_bounds.position.y + padding, world_bounds.end.y - padding)
		
		spawn_positions.append(pos)
	
	# Stagger spawns over HORDE_SPAWN_DURATION seconds
	var delay_per_spawn := HORDE_SPAWN_DURATION / float(HORDE_COUNT)
	
	for i in HORDE_COUNT:
		# Use a timer to stagger spawns - MUST bind i to capture by value
		var spawn_timer := get_tree().create_timer(delay_per_spawn * i)
		spawn_timer.timeout.connect(_spawn_horde_enemy.bind(spawner, spawn_positions[i]))
	
	print("[RaptureQueen] Summoning horde of %d enemies!" % HORDE_COUNT)

func _spawn_horde_enemy(spawner_ref: EnemySpawner, pos: Vector2) -> void:
	if not spawner_ref or not is_instance_valid(spawner_ref):
		return
	var enemy := spawner_ref.spawn_at_position("normal", pos)
	if enemy:
		# Give them a brief invincibility to prevent instant death from AOE
		enemy.set_meta("spawn_grace", 0.5)

func _process_passive_regeneration(delta: float) -> void:
	# Don't regen if dead
	if health_component.is_dead():
		return
		
	var hp_percent = float(health_component.current_hp) / float(health_component.max_hp)
	var regen_rate_percent = 0.0
	
	# Regen rates based on HP thresholds
	if hp_percent >= 0.50:
		regen_rate_percent = 0.005 # 0.5%/s
	elif hp_percent >= 0.25:
		regen_rate_percent = 0.01 # 1%/s
	else:
		regen_rate_percent = 0.02 # 2%/s
		
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
	
	# Show core overload warning
	var wave_ui = get_tree().get_first_node_in_group("wave_ui")
	if wave_ui and wave_ui.has_method("show_event"):
		wave_ui.show_event("boss", {"name": "CORE OVERLOAD DETECTED: 10 SECONDS"}, 30.0)
	elif EventBus and EventBus.has_signal("boss_warning"):
		EventBus.boss_warning.emit("CORE OVERLOAD DETECTED: 10 SECONDS")
	
	# Visual Warning (Reuse Timer Event Warning)
	if not _warning_triggered:
		_trigger_event_warning()
	
	# Visual Warning Local
	if hp_label:
		hp_label.modulate = Color(1, 0, 0) # Red Text

func _process_self_destruct(delta: float) -> void:
	_self_destruct_timer -= delta
	
	# Visual Countdown on HP Label?
	if hp_label:
		hp_label.text = "SELF DESTRUCT: %.1f" % _self_destruct_timer
		
	# Flash red faster as time runs out
	modulate.g = abs(sin(_self_destruct_timer * 5.0))
	modulate.b = abs(sin(_self_destruct_timer * 5.0))
	
	if _self_destruct_timer <= 0 and not _explosion_triggered:
		# Use cinematic explosion instead of instant kill
		_trigger_event_explosion()

func _execute_instant_kill() -> void:
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
		player.take_damage(dmg, false, Vector2.ZERO, true, "Rapture Queen:Self-Destruct") # True Damage flag
		
	# Boss dies too (implied explosion)
	health_component.die()

func take_damage(amount: int, is_crit: bool = false, knockback_dir: Vector2 = Vector2.ZERO, is_true_damage: bool = false, source: String = "") -> void:
	# 80% damage reduction during self-destruct countdown (only 20% damage)
	var final_amount := amount
	if _is_self_destructing:
		final_amount = maxi(1, amount / 5) # 80% reduction = 20% damage
		print("[RaptureQueen] Self-destruct damage reduction: %d -> %d" % [amount, final_amount])
	
	# Dodge chance
	if randf() < DODGE_CHANCE and not is_true_damage:
		_perform_teleport_dodge()
		return
	
	super.take_damage(final_amount, is_crit, knockback_dir, is_true_damage, source)

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
	dissolve_effect.setup_dissolve(start_pos, scale.x) # Pass scale for proper sizing
	
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
		reform_effect.setup_reform(new_pos, scale.x) # Pass scale for proper sizing
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


# --- SHE DESCENDS EASTER EGG ---

func _on_she_descends_damaged(amount: int, _source: String) -> void:
	## Award XP and Burst to player based on weapon type in She Descends mode
	## Uses unified BurstConfig for rates (same as normal mode burst gen)
	# Deduplication: Skip if same damage amount received in same frame
	# This handles the duplicate signal issue from body + hitbox collision
	var current_frame := Engine.get_process_frames()
	if current_frame == _last_xp_frame and amount == _last_xp_amount:
		return # Duplicate, skip
	_last_xp_frame = current_frame
	_last_xp_amount = amount
	
	var player_node = get_tree().get_first_node_in_group("player")
	if not player_node:
		return
	
	var src_lower: String = _source.to_lower()
	
	# Skip burst attacks entirely - no XP or Burst gain from burst skills
	if BurstConfig.is_burst_source(src_lower):
		# print("Skipping Burst Source: ", src_lower)
		return
	
	# If source doesn't map to a known weapon type (e.g., 'player', 'boss_shield', 'unknown'),
	# fall back to getting the weapon type from the player's current character
	var gain_percent: float = BurstConfig.get_rate(src_lower)
	
	# Debug tracing for burst refill bug
	# Log if we gain ANY burst to see values
	if gain_percent > 0.0:
		if player_node.has_method("get_burst_current"):
			var cur = player_node.get_burst_current()
			print("XP Add: ", gain_percent, " OldBurst: ", cur, " Source: ", src_lower)
		else:
			print("XP Add: ", gain_percent, " Source: ", src_lower)

	# Only fall back to player weapon for truly ambiguous sources (player, boss_shield)
	# Do NOT fall back for 'projectile' or 'unknown' - these could be beam/collision debris
	if gain_percent == 1.0 and src_lower in ["player", "boss_shield"]:
		# Source didn't map correctly - get weapon type from current character
		if player_node.has_method("_get_current_weapon_type"):
			var weapon_type: String = player_node._get_current_weapon_type()
			gain_percent = BurstConfig.get_rate(weapon_type)
			src_lower = weapon_type # For debug
	
	# Apply XP gain (% of 100 XP to next level)
	if player_node.has_method("add_xp") and gain_percent > 0:
		_xp_accumulator += gain_percent
		var xp_gain := int(_xp_accumulator) # Get only the whole number part
		if xp_gain >= 1:
			player_node.add_xp(xp_gain)
			_xp_accumulator -= xp_gain # Remove ONLY the awarded part, keep fraction
	
	# Apply Burst gain (% of 100 max burst)
	if player_node.has_method("add_burst_charge") and gain_percent > 0:
		player_node.add_burst_charge(gain_percent)
