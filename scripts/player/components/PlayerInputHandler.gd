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

## Hold-to-charge attack (e.g. Snow White's "Charging" talent). Accumulates while
## the attack button is held, then fires one charged shot on release.
const MAX_CHARGE_TIME := 3.0
var _attack_charge_time: float = 0.0

## Hold-to-charge burst (Snow White's "Focused Fire"). Held burst key narrows the
## cone and boosts damage; released to fire.
const BURST_CHARGE_MAX := 2.5
var _burst_charge_time: float = 0.0

var _using_controller: bool = false

## Hold-to-trigger special (e.g. Nayuta's RETURN UNTO ME). Only engaged when the
## current controller's is_special_hold_enabled() is true.
const SPECIAL_HOLD_THRESHOLD := 1.0 # Seconds to hold before the hold action fires
var _special_hold_time: float = 0.0
var _special_hold_fired: bool = false

## Hold-to-charge special (Scarlet's "Musashi"): hold the skill to grow the wave.
const SPECIAL_CHARGE_MAX := 2.0
var _special_charge_time: float = 0.0


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

	_handle_attacks(delta)
	_handle_burst_charge(delta)


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


func _handle_attacks(delta: float) -> void:
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
	var charge_enabled: bool = controller.has_method("is_charge_attack_enabled") and controller.is_charge_attack_enabled()
	var wants_attack := false
	var charge_release := false
	var charge_ratio := 0.0

	# Block attacks if mouse is hovering over music player UI
	if MusicPlayerUIScript.is_mouse_over():
		wants_attack = false
		_attack_charge_time = 0.0
	elif is_kilo_burst or is_auto_fire:
		wants_attack = Input.is_action_pressed("attack")
	elif charge_enabled:
		# Hold to charge (no fire while held); release to fire one charged shot.
		if Input.is_action_pressed("attack"):
			_attack_charge_time = minf(_attack_charge_time + delta, MAX_CHARGE_TIME)
		elif _attack_charge_time > 0.0:
			charge_release = true
			charge_ratio = clampf(_attack_charge_time / MAX_CHARGE_TIME, 0.0, 1.0)
			_attack_charge_time = 0.0
			wants_attack = true
	else:
		wants_attack = Input.is_action_just_pressed("attack")

	# Drive Snow White's muzzle charge orb (no-op for non-charge characters).
	if charge_enabled and controller.has_method("update_charge_visual"):
		var vis_ratio := 0.0
		if Input.is_action_pressed("attack") and not MusicPlayerUIScript.is_mouse_over():
			vis_ratio = clampf(_attack_charge_time / MAX_CHARGE_TIME, 0.0, 1.0)
		controller.update_charge_visual(vis_ratio)

	var can_fire := wants_attack and attack_timer <= 0

	if not is_kilo_burst and not is_auto_fire:
		can_fire = can_fire and _player.stamina >= _player.attack_stamina_cost

	if can_fire:
		# Hand the charged-shot width to the controller before it fires.
		if charge_release and ("pending_charge_ratio" in controller):
			controller.pending_charge_ratio = charge_ratio
		if controller.attack(aim_direction):
			if not is_kilo_burst and not is_auto_fire:
				_player.stamina -= _player.attack_stamina_cost

			# Set cooldown based on controller
			if controller.has_method("get_attack_cooldown"):
				attack_timer = controller.get_attack_cooldown()
			else:
				attack_timer = _player.attack_cooldown

	# Special attack (thrust) - independent of attack cooldown so it works while firing
	_handle_special_input(delta, controller)


func _handle_special_input(delta: float, controller) -> void:
	# Scarlet "Nothing Personal, Kid": while a Dash Slash wave is in flight, a
	# press teleports to it (consuming it) instead of firing/charging a new one.
	if controller.has_method("has_active_wave") and controller.has_active_wave():
		if Input.is_action_just_pressed("thrust"):
			controller.do_teleport()
		_special_charge_time = 0.0
		if controller.has_method("update_special_charge_visual"):
			controller.update_special_charge_visual(0.0)
		return

	# Scarlet "Musashi": hold the skill to charge a bigger wave, release to fire.
	if controller.has_method("is_special_charge_enabled") and controller.is_special_charge_enabled():
		_handle_special_charge(delta, controller)
		return

	# Controllers that opt into hold-special (e.g. Nayuta) tap for the normal
	# special and hold for the secondary action; everyone else fires on press.
	var hold_enabled: bool = controller.has_method("is_special_hold_enabled") and controller.is_special_hold_enabled()

	if not hold_enabled:
		if Input.is_action_just_pressed("thrust") and _player.stamina >= _player.attack_stamina_cost:
			if controller.use_special(aim_direction):
				_player.stamina -= _player.attack_stamina_cost
		return

	if Input.is_action_pressed("thrust"):
		# Holding: fire the hold action once the threshold is crossed
		_special_hold_time += delta
		if not _special_hold_fired and _special_hold_time >= SPECIAL_HOLD_THRESHOLD:
			_special_hold_fired = true
			controller.use_special_hold(aim_direction)
	else:
		# Button is up. Fire the normal summon for a genuine tap: either the
		# release happened this frame, OR a tap was mid-flight and its release
		# edge was missed while the game was paused (talent tree/shop) and the
		# handler was dormant. Without the latter case the tap would be silently
		# dropped. A hold action that already fired suppresses the tap.
		var was_tap: bool = Input.is_action_just_released("thrust") or _special_hold_time > 0.0
		if was_tap and not _special_hold_fired and _special_hold_time < SPECIAL_HOLD_THRESHOLD:
			_try_tap_special(controller)
		_special_hold_time = 0.0
		_special_hold_fired = false


## Fire the normal special as a stamina-gated quick tap (shared by the hold path)
func _try_tap_special(controller) -> void:
	if _player.stamina >= _player.attack_stamina_cost:
		if controller.use_special(aim_direction):
			_player.stamina -= _player.attack_stamina_cost


## Musashi: accumulate while the skill is held (and ready), fire on release. A
## quick tap charges ~nothing and fires a near-normal wave.
func _handle_special_charge(delta: float, controller) -> void:
	var ready: bool = controller.has_method("is_special_ready") and controller.is_special_ready()
	if Input.is_action_pressed("thrust") and (_special_charge_time > 0.0 or ready):
		_special_charge_time = minf(_special_charge_time + delta, SPECIAL_CHARGE_MAX)
	elif _special_charge_time > 0.0:
		# Released: fire the charged wave.
		var ratio := clampf(_special_charge_time / SPECIAL_CHARGE_MAX, 0.0, 1.0)
		_special_charge_time = 0.0
		if controller.has_method("set_pending_special_charge"):
			controller.set_pending_special_charge(ratio)
		if _player.stamina >= _player.attack_stamina_cost:
			if controller.use_special(aim_direction):
				_player.stamina -= _player.attack_stamina_cost

	# Drive the pale-purple charge orb.
	if controller.has_method("update_special_charge_visual"):
		var vis := clampf(_special_charge_time / SPECIAL_CHARGE_MAX, 0.0, 1.0) if _special_charge_time > 0.0 else 0.0
		controller.update_special_charge_visual(vis)


## True when the current controller wants burst to be hold-to-charge (Focused Fire).
func _is_burst_charge_active() -> bool:
	var c = _player.get_current_controller() if _player else null
	return c != null and c.has_method("is_burst_charge_enabled") and c.is_burst_charge_enabled()


## Focused Fire: accumulate while the burst key is held (gauge ready), then fire
## the charged burst on release. No-op for controllers without burst charging.
func _handle_burst_charge(delta: float) -> void:
	var controller = _player.get_current_controller()
	if controller == null or not (controller.has_method("is_burst_charge_enabled") and controller.is_burst_charge_enabled()):
		_burst_charge_time = 0.0
		return

	var held := Input.is_action_pressed("burst") or Input.is_key_pressed(KEY_E)
	if held and _player.is_burst_ready():
		_burst_charge_time = minf(_burst_charge_time + delta, BURST_CHARGE_MAX)
	elif _burst_charge_time > 0.0:
		# Released: fire the charged burst.
		var ratio := clampf(_burst_charge_time / BURST_CHARGE_MAX, 0.0, 1.0)
		_burst_charge_time = 0.0
		if controller.has_method("set_pending_burst_charge"):
			controller.set_pending_burst_charge(ratio)
		_player._attempt_burst_activation()

	# Drive the ghost-arc preview (narrows as it charges, flashes when full).
	if controller.has_method("update_burst_charge_visual"):
		var vis := clampf(_burst_charge_time / BURST_CHARGE_MAX, 0.0, 1.0) if _burst_charge_time > 0.0 else 0.0
		controller.update_burst_charge_visual(vis)


func _input(event: InputEvent) -> void:
	if _player == null or _player.shop_open:
		return

	# Detect mouse usage to switch aim mode - lower threshold to catch subtle movements
	if event is InputEventMouseMotion and event.relative.length_squared() > 0.01:
		_using_controller = false

	# Burst activation via controller button (Y/Triangle). When burst-charge is
	# active (Focused Fire), the per-frame hold handler fires it on release instead.
	if event.is_action_pressed("burst") and not event.is_echo():
		if not _is_burst_charge_active():
			_player._attempt_burst_activation()

	# Keyboard inputs
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				if not _is_burst_charge_active():
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
