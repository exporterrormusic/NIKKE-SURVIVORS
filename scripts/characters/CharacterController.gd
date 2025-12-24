class_name CharacterController
extends RefCounted
## Base class for character-specific combat logic.
## Each character extends this and implements their unique attack, special, and burst.

const MusicPlayerUI := preload("res://scripts/ui/MusicPlayerUI.gd")

# Reference to the player node
var player: Node2D = null

# Character data resource
var data: Resource = null # CharacterData

# State tracking
var ammo: int = -1
var max_ammo: int = -1
var base_max_ammo: int = -1
var is_reloading: bool = false
var reload_timer: float = 0.0

var special_unlocked: bool = false # Must be unlocked via talent
var special_timer: float = 0.0
var special_ready: bool = true

var burst_active: bool = false
var burst_timer: float = 0.0

var attack_timer: float = 0.0

# Signals that the player should connect to
signal ammo_changed(current: int, maximum: int)
signal reload_started(duration: float)
signal reload_finished()
signal special_cooldown_changed(progress: float)
signal burst_activated()
signal burst_ended()

## Initialize the controller with player reference and character data
func initialize(p_player: Node2D, p_data: Resource) -> void: # CharacterData
	player = p_player
	data = p_data
	
	# Initialize ammo
	max_ammo = data.ammo_capacity
	base_max_ammo = max_ammo
	
	# Apply initial squad upgrades (if any apply at start, e.g. main character)
	apply_squad_upgrades()
			
	ammo = max_ammo
	
	# Reset timers
	attack_timer = 0.0
	special_timer = 0.0
	reload_timer = 0.0
	burst_timer = 0.0
	
	# Character-specific initialization
	_on_initialize()

## Apply dynamic squad upgrades (called when squad composition changes)
func apply_squad_upgrades() -> void:
	# Reset to base stats before re-applying modifiers
	max_ammo = base_max_ammo
	
	# Snow White's "Master Mechanic" (Ammo Boost) - same logic as old Kilo upgrade
	# Requires: 1. Upgrade purchased, 2. Snow White unlocked in current squad
	if has_upgrade("snow_white", "master_mechanic"):
		# Check if Snow White is in the squad
		var snow_white_active = false
		if player and player.has_method("is_character_in_squad"):
			snow_white_active = player.is_character_in_squad("snow_white")
		
		if snow_white_active:
			var w_type = _get_weapon_type_name().to_lower()
			# +100% for Rocket/Sniper/Launcher
			if w_type in ["sniper", "rocket", "launcher"]:
				max_ammo *= 2
				print("[CharacterController] Applied Snow White Ammo Boost (2x) to %s. New Max: %d" % [w_type, max_ammo])
			# +50% for Minigun/SMG/Shotgun/Assault Rifle
			elif w_type in ["minigun", "smg", "assault_rifle", "shotgun", "assault rifle"]:
				max_ammo = int(max_ammo * 1.5)
				print("[CharacterController] Applied Snow White Ammo Boost (1.5x) to %s. New Max: %d" % [w_type, max_ammo])
	
	# Kilo's "Build-a-Bullet" (Bullet Regen) is handled per-shot in _consume_ammo_with_regen()
				
	# If current ammo exceeds new max, clamp it. If we just gained ammo capacity, we usually don't fill it instantly unless reloading.
	if ammo > max_ammo:
		ammo = max_ammo
	
	# Notify UI
	ammo_changed.emit(ammo, max_ammo)

# Kilo bullet regen tracking
var _kilo_shot_counter: int = 0

## Helper to check for shop upgrades without creating circular dependency
func has_upgrade(char_id: String, upgrade_id: String) -> bool:
	var shop = load("res://scripts/ui/ShopMenu.gd")
	if shop:
		return shop.has_character_upgrade(char_id, upgrade_id)
	return false

## Called when controller is initialized - override for custom setup
func _on_initialize() -> void:
	pass

## Called when controller is being destroyed - override to clean up resources
func cleanup() -> void:
	_on_cleanup()

## Override for custom cleanup
func _on_cleanup() -> void:
	pass

## Process frame update - call from Player._physics_process
func process(delta: float) -> void:
	# Update attack cooldown
	if attack_timer > 0:
		attack_timer -= delta
	
	# Update special cooldown
	if special_timer > 0:
		special_timer -= delta
		special_cooldown_changed.emit(1.0 - (special_timer / data.special_cooldown))
		if special_timer <= 0:
			special_timer = 0
			special_ready = true
			special_cooldown_changed.emit(1.0)
	
	# Update reload
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0:
			_finish_reload()
	
	# Update burst
	if burst_active:
		burst_timer -= delta
		if burst_timer <= 0:
			_end_burst()
	
	# Character-specific processing
	_on_process(delta)

## Physics frame update - call from Player._physics_process
func physics_process(delta: float) -> void:
	# Character-specific physics processing
	_on_physics_process(delta)

## Called every physics frame - override for physics-based processing
func _on_physics_process(_delta: float) -> void:
	pass

## Called every frame - override for custom processing
func _on_process(_delta: float) -> void:
	pass

## Attempt to attack - returns true if attack was performed
func attack(direction: Vector2) -> bool:
	# Block attacks when hovering UI elements like the Music Player
	if MusicPlayerUI and MusicPlayerUI.is_hovered:
		return false
	
	if attack_timer > 0:
		return false
	
	if not _can_attack():
		return false
	
	# Consume ammo if applicable
	if max_ammo > 0 and not burst_active:
		ammo -= 1
		
		# Kilo's "Build-a-Bullet": Every 3rd shot regenerates 1 ammo
		if has_upgrade("kilo", "talos_ammo"):
			var kilo_active = false
			if player and player.has_method("is_character_in_squad"):
				kilo_active = player.is_character_in_squad("kilo")
			
			if kilo_active:
				_kilo_shot_counter += 1
				if _kilo_shot_counter >= 3:
					_kilo_shot_counter = 0
					ammo = mini(ammo + 1, max_ammo)
		
		ammo_changed.emit(ammo, max_ammo)
		
		if ammo <= 0:
			start_reload()
	
	attack_timer = data.attack_cooldown
	
	# Track shot for "No Shots Fired" achievement
	var ach_mgr = Engine.get_main_loop().root.get_node_or_null("/root/AchievementManager")
	if ach_mgr and ach_mgr.has_method("on_shot_fired"):
		ach_mgr.on_shot_fired()
	
	# Perform the attack
	_perform_attack(direction)
	return true

## Check if can attack - override to add conditions
func _can_attack() -> bool:
	if is_reloading:
		return false
	if max_ammo > 0 and ammo <= 0:
		return false
	return true

## Perform the actual attack - MUST override
func _perform_attack(_direction: Vector2) -> void:
	push_error("%s._perform_attack not implemented!" % get_script().resource_path.get_file())

## Attempt to use special attack - returns true if used
func use_special(direction: Vector2) -> bool:
	# Block when hovering UI elements like the Music Player
	if MusicPlayerUI and MusicPlayerUI.is_hovered:
		return false
	
	if not special_unlocked:
		return false
	if not special_ready:
		return false
	
	if not _can_use_special():
		return false
	
	special_ready = false
	special_timer = data.special_cooldown
	special_cooldown_changed.emit(0.0)
	
	_perform_special(direction)
	return true

## Check if can use special - override to add conditions
func _can_use_special() -> bool:
	return true

## Perform the special attack - MUST override
func _perform_special(_direction: Vector2) -> void:
	push_error("CharacterController._perform_special not implemented!")

## Start reloading
func start_reload() -> void:
	if is_reloading or max_ammo <= 0:
		return
	if ammo >= max_ammo:
		return
	
	is_reloading = true
	reload_timer = data.reload_time
	reload_started.emit(data.reload_time)
	
	# Play reload sound
	if player and player.audio_director:
		var weapon_type := _get_weapon_type_name()
		player.audio_director.play_weapon_reload_sound(weapon_type)

## Manual reload triggered by player (R key)
func manual_reload() -> void:
	if is_reloading or max_ammo <= 0:
		return
	if ammo >= max_ammo:
		return
	
	start_reload()

## Get weapon type name for audio
func _get_weapon_type_name() -> String:
	# Override in subclasses for specific weapon types
	return "sniper" # Default

## Finish reloading
func _finish_reload() -> void:
	is_reloading = false
	ammo = max_ammo
	reload_finished.emit()
	ammo_changed.emit(ammo, max_ammo)

## Activate burst ability
func activate_burst() -> bool:
	if burst_active:
		return false
	
	burst_active = true
	burst_timer = data.burst_duration
	
	_on_burst_start()
	burst_activated.emit()
	return true

## End burst ability
func _end_burst() -> void:
	burst_active = false
	burst_timer = 0.0
	
	_on_burst_end()
	burst_ended.emit()

## Called when burst starts - override for custom behavior
func _on_burst_start() -> void:
	pass

## Called when burst ends - override for custom behavior
func _on_burst_end() -> void:
	pass

## Get the damage multiplier (including burst bonus)
func get_damage_multiplier() -> float:
	if burst_active:
		return data.burst_damage_multiplier
	return 1.0

## Check if the character is invincible (e.g., during burst)
func is_invincible() -> bool:
	return false # Override in subclasses

## Get reload progress (0.0 to 1.0)
func get_reload_progress() -> float:
	if not is_reloading:
		return 1.0
	return 1.0 - (reload_timer / data.reload_time)

## Get special cooldown progress (0.0 to 1.0)
func get_special_progress() -> float:
	if special_ready:
		return 1.0
	return 1.0 - (special_timer / data.special_cooldown)

## Force reset special cooldown (e.g. from upgrade)
func reset_special_cooldown() -> void:
	special_timer = 0.0
	special_ready = true
	special_cooldown_changed.emit(1.0)

## Get whether this character uses automatic fire (hold to shoot)
## Override in subclasses (e.g. Miniguns, ARs, SMGs)
func get_is_automatic() -> bool:
	return false


## Play a weapon fire sound via the audio director
## Shared helper to avoid duplicate implementations in all subclasses
func _play_sound(weapon_type: String) -> void:
	if player and player.audio_director:
		player.audio_director.play_weapon_fire_sound(weapon_type)


## Get the attack cooldown for this character
## Override in subclasses for characters with dynamic cooldowns (e.g. spin-up, burst mode)
func get_attack_cooldown() -> float:
	return data.attack_cooldown
