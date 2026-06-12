class_name PlayerInputHandler
extends Node
## Player input: aim (mouse/controller + aim assist), dash/run input,
## attack/special firing, and key events (burst, reload, talent tree).
## Extracted from PlayerCore for modularity.

const MusicPlayerUIScript = preload("res://scripts/ui/MusicPlayerUI.gd")

const AIM_ASSIST_ANGLE := 15.0 # degrees - subtle cone
const AIM_ASSIST_RANGE := 350.0 # pixels
const AIM_ASSIST_STRENGTH := 0.4 # how strongly to pull toward target

var _player: PlayerCore = null

## Current aim direction (read by controllers via PlayerCore.aim_direction)
var aim_direction: Vector2 = Vector2.RIGHT

## Attack cooldown timer
var attack_timer: float = 0.0

var _using_controller: bool = false


func initialize(player: PlayerCore) -> void:
	_player = player


func is_using_controller() -> bool:
	return _using_controller


## Per-frame aim update (called from PlayerCore._process for smooth tracking)
func update_aim() -> void:
	# Controller aim
	var stick_aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick_aim.length() > 0.3:
		_using_controller = true
		aim_direction = stick_aim.normalized()
		aim_direction = _apply_aim_assist(aim_direction)
	elif not _using_controller:
		# Mouse aim
		var mouse_pos := _player.get_global_mouse_position()
		aim_direction = (mouse_pos - _player.global_position).normalized()

	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT


## Per-physics-frame input: dash/run, movement, attack timer and attacks
func physics_update(delta: float) -> void:
	_handle_dash_input()

	# Delegate movement to component
	var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _player._movement:
		_player._movement.handle_movement(delta, input_vector)

	# Update attack timer
	if attack_timer > 0:
		attack_timer -= delta

	_handle_attacks()


func _handle_dash_input() -> void:
	if _player.dashing:
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement = _player._movement

	# Dash input - only on press
	if Input.is_action_just_pressed("dash"):
		if movement:
			movement.try_dash(input_dir if input_dir.length() > 0 else aim_direction)

	# Running - holding dash key while not dashing (will also start after dash ends while held)
	if movement:
		if Input.is_action_pressed("dash") and not _player.dashing:
			movement.set_running(true)
		elif not Input.is_action_pressed("dash"):
			movement.set_running(false)

	# Burst is handled exclusively in _input(event) to prevent duplicate triggers.


func _handle_attacks() -> void:
	var controller = _player.get_current_controller()
	if not controller:
		return

	# Check if Kilo burst mode is active for automatic fire
	var is_kilo_burst: bool = controller is KiloController and controller.burst_active

	# Use get_is_automatic() from controller base class instead of hardcoded checks
	var is_auto_fire: bool = false
	if controller.has_method("get_is_automatic"):
		is_auto_fire = controller.get_is_automatic()
	else:
		# Fallback for old controllers? Shouldn't happen if base class updated
		is_auto_fire = controller is CommanderController or controller is SinController or controller is CecilController or controller is CrownController or controller is MarianController or controller is NayutaController

	# Primary attack - during Kilo burst or auto-fire weapons: continuous while holding, no stamina cost
	var wants_attack := false

	# Block attacks if mouse is hovering over music player UI
	if MusicPlayerUIScript.is_mouse_over():
		wants_attack = false
	elif is_kilo_burst or is_auto_fire:
		wants_attack = Input.is_action_pressed("attack")
	else:
		wants_attack = Input.is_action_just_pressed("attack")

	var can_fire := wants_attack and attack_timer <= 0

	if not is_kilo_burst and not is_auto_fire:
		can_fire = can_fire and _player.stamina >= _player.attack_stamina_cost

	if can_fire:
		if controller.attack(aim_direction):
			if not is_kilo_burst and not is_auto_fire:
				_player.stamina -= _player.attack_stamina_cost

			# Set cooldown based on controller
			if controller.has_method("get_attack_cooldown"):
				attack_timer = controller.get_attack_cooldown()
			else:
				attack_timer = _player.attack_cooldown

	# Special attack (thrust) - independent of attack cooldown so it works while firing
	if Input.is_action_just_pressed("thrust") and _player.stamina >= _player.attack_stamina_cost:
		if controller.use_special(aim_direction):
			_player.stamina -= _player.attack_stamina_cost


func _input(event: InputEvent) -> void:
	if _player == null or _player.shop_open:
		return

	# Detect mouse usage to switch aim mode - lower threshold to catch subtle movements
	if event is InputEventMouseMotion and event.relative.length_squared() > 0.01:
		_using_controller = false

	# Burst activation via controller button (Y/Triangle)
	if event.is_action_pressed("burst") and not event.is_echo():
		_player._attempt_burst_activation()

	# Keyboard inputs
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				_player._attempt_burst_activation()
			KEY_R:
				_try_manual_reload()

	# Skill tree via remappable action
	if event.is_action_pressed("show_talent_tree") and not event.is_echo():
		_player._show_talent_tree()


func _try_manual_reload() -> void:
	# Allow player to manually reload with R key
	var controller = _player.get_current_controller()
	if not controller:
		return

	# Delegate reload to controller if it supports it
	if controller.has_method("manual_reload"):
		controller.manual_reload()
		_player._update_overhead_ammo()


## Apply subtle aim assist for controller users - pulls aim toward nearby enemies
func _apply_aim_assist(base_aim: Vector2) -> Vector2:
	if not _using_controller:
		return base_aim

	var best_target: Node2D = null
	var best_score: float = 0.0

	# Find best target in cone
	for enemy in TargetCache.get_enemies():
		if not is_instance_valid(enemy):
			continue
		var to_enemy: Vector2 = enemy.global_position - _player.global_position
		var dist: float = to_enemy.length()
		if dist > AIM_ASSIST_RANGE or dist < 10:
			continue

		var angle_diff: float = rad_to_deg(absf(base_aim.angle_to(to_enemy.normalized())))
		if angle_diff > AIM_ASSIST_ANGLE:
			continue

		# Score: closer + more aligned = better
		var score: float = (1.0 - dist / AIM_ASSIST_RANGE) * (1.0 - angle_diff / AIM_ASSIST_ANGLE)
		if score > best_score:
			best_score = score
			best_target = enemy

	if best_target:
		var target_aim: Vector2 = (best_target.global_position - _player.global_position).normalized()
		return base_aim.lerp(target_aim, AIM_ASSIST_STRENGTH * best_score)
	return base_aim
