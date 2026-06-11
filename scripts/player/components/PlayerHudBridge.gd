class_name PlayerHudBridge
extends Node
## HUD plumbing for PlayerCore: pushes health/burst/ammo/special/XP state
## into PlayerHudCluster, PlayerOverheadHud and XPUI.
## Extracted from PlayerCore for modularity.

var _player: PlayerCore = null


func initialize(player: PlayerCore) -> void:
	_player = player


func init_ui() -> void:
	var overhead = _player.overhead_hud
	if overhead:
		overhead.update_health(_player.hp, _player.max_hp)
		overhead.update_burst(_player.burst_current, _player.burst_max)
		overhead.update_character(_player._character_index)
		update_overhead_ammo()
	update_xp_bar()
	_player._hud_initialized = true


func update_hud() -> void:
	var hud = _player.player_hud
	if hud and hud.is_inside_tree():
		hud.set_character(0, _player.is_burst_unlocked())
		hud.configure(_player.hp, _player.max_hp, _player.burst_current, _player.burst_max, _player.stamina, _player.max_stamina)


func update_health_display(change: int = 0, animate: bool = false) -> void:
	if _player.player_hud:
		_player.player_hud.update_health(_player.hp, _player.max_hp, change, animate)
	if _player.overhead_hud:
		_player.overhead_hud.update_health(_player.hp, _player.max_hp)


func update_xp_bar() -> void:
	var xp_ui = _player.xp_ui
	if xp_ui and xp_ui.has_method("set_xp"):
		xp_ui.set_xp(_player.xp, _player.xp_to_next)
		xp_ui.set_level(_player.level)


func update_burst_visibility() -> void:
	# Burst bar should only be visible if the character has burst unlocked
	var current_has_burst := _player.get_talent_level(_player._character_index, "burst") > 0

	var hud = _player.player_hud
	if hud and hud.has_method("set_burst_unlocked"):
		hud.set_burst_unlocked(current_has_burst)
		# Also refresh the burst gauge value to prevent visual reset
		if current_has_burst:
			hud.update_burst(_player.burst_current, _player.burst_max, false)
	var overhead = _player.overhead_hud
	if overhead and overhead.has_method("update_burst_unlocked"):
		overhead.update_burst_unlocked(current_has_burst)
		# Also refresh the burst gauge value
		if current_has_burst:
			overhead.update_burst(_player.burst_current, _player.burst_max)


func update_overhead_ammo() -> void:
	var overhead = _player.overhead_hud
	var controller = _player.get_current_controller()
	if not overhead or not controller:
		return

	var cur_ammo = controller.ammo
	var max_ammo = controller.max_ammo
	var is_reloading = controller.is_reloading
	var reload_time = 1.5
	if controller.data:
		reload_time = controller.data.reload_time

	if max_ammo <= 0:
		# Unlimited ammo
		overhead.update_ammo(1, 1, false, reload_time)
	else:
		overhead.update_ammo(cur_ammo, max_ammo, is_reloading, reload_time)


func update_overhead_special() -> void:
	var overhead = _player.overhead_hud
	var controller = _player.get_current_controller()
	if not overhead or not controller:
		return

	var unlocked = controller.special_unlocked
	var progress = 1.0

	# Update Scarlet's special unlocked status (index 1 in CharacterRegistry)
	if _player._character_index == 1: # Scarlet's index in CharacterRegistry
		overhead.update_scarlet_special_unlocked(unlocked)

	# Get special cooldown progress from controller
	if controller.has_method("get_special_cooldown_progress"):
		progress = controller.get_special_cooldown_progress()
	elif controller.has_method("get_special_progress"):
		progress = controller.get_special_progress()

	# Check if controller supports charges (Snow White turrets)
	if controller.has_method("get_special_charges"):
		var charges = controller.get_special_charges()
		var max_charges = controller.get_special_max_charges()
		if overhead.has_method("update_special_ability_with_charges"):
			overhead.update_special_ability_with_charges(unlocked, progress, charges, max_charges)
			return

	# Check for Wells locked state (Future Marian active)
	var is_locked: bool = false
	if "_special_blocked" in controller:
		is_locked = controller._special_blocked

	overhead.update_special_ability(unlocked, progress, is_locked)
