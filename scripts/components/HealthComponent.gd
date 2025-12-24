extends Node


signal died(overkill: int)
signal health_changed(current: int, max: int)
signal damaged(amount, source)

@export var max_hp: int = 10
var current_hp: int: set = _set_current_hp

var _is_dead: bool = false
var _pending_overkill: int = 0
var _processing_death: bool = false # Prevent auto-revive during death cleanup
var _last_damage_source: String = "unknown" # Track source for kill attribution

func _ready() -> void:
	current_hp = max_hp

func _set_current_hp(value: int) -> void:
	var old_hp = current_hp
	current_hp = clamp(value, 0, max_hp)
	if old_hp != current_hp:
		health_changed.emit(current_hp, max_hp)
	
	if current_hp == 0 and not _is_dead:
		die(_pending_overkill)
		_pending_overkill = 0
	elif current_hp > 0 and _is_dead:
		# EXPORT FIX: Allow auto-revive even if processing death (Spawning override)
		# If HP is explicitly set > 0, we must be alive.
		_is_dead = false
		_processing_death = false
		

func set_max_hp(val: int) -> void:
	max_hp = val
	current_hp = min(current_hp, max_hp)

func damage(amount: int, source: String = "unknown") -> void:
	# DebugLog.log("[Health] damage: " + str(amount) + " hp: " + str(current_hp) + " -> " + str(current_hp - amount))
	# EXPORT DEBUGGING
	if _is_dead:
		# print("[Health] Ignoring damage (already dead)")
		return
	
	# UNIVERSAL FRIENDLY FIRE PROTECTION (Deepest Level)
	if owner:
		# Player Invincibility Cheat
		if owner.is_in_group("player") and CheatManager.is_cheat_active("invincible"):
			return
			
		if owner.is_in_group("charmed_allies"):
			# Check against generic friendly sources AND specific weapon types
			var blocked_sources = [
				"player", "projectile", "cecil_drone", "summon", "ally", "burst",
				"smg", "sniper", "shotgun", "rocket", "minigun", "sword", "assault", "blade"
			]
			if source in blocked_sources:
				return
		
	var potential_hp = current_hp - amount
	# print("[Health] Taking damage: ", amount, ". New HP: ", potential_hp)
	
	if potential_hp < 0:
		_pending_overkill = - potential_hp
	else:
		_pending_overkill = 0
		
	_last_damage_source = source # Store for death attribution
	current_hp -= amount
	damaged.emit(amount, source)

func heal(amount: int) -> void:
	if _is_dead:
		return
		
	current_hp = min(current_hp + amount, max_hp)

func die(overkill: int = 0) -> void:
	if _is_dead:
		return
	_processing_death = true # Prevent auto-revive during death processing
	_is_dead = true
	current_hp = 0
	# print("[Health] Died! Overkill: ", overkill)
	died.emit(overkill)
	
	# Emit global event for achievement tracking
	# Use tracked damage source instead of hardcoded "player"
	if EventBus and owner:
		EventBus.enemy_killed.emit(owner, _last_damage_source)
	
	# Reset processing flag after death signal handlers complete
	call_deferred("_clear_processing_death")

func is_dead() -> bool:
	return _is_dead

func reset() -> void:
	# print("[Health] Reset called. Clearing dead flags.")
	_is_dead = false
	_processing_death = false
	_last_damage_source = "unknown" # Reset for pool reuse
	# HP restoration must be done by owner (set_max_hp/current_hp)
	_pending_overkill = 0

func _clear_processing_death() -> void:
	_processing_death = false
