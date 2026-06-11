extends Node
class_name PlayerWeapons
## Player weapon management module.
##
## Handles weapon equipping, firing, and ammo.
## Extracted from PlayerCore for better separation of concerns.

signal weapon_fired(weapon_type: String)
signal weapon_equipped(weapon_index: int)
signal ammo_changed(weapon_index: int, current: int, maximum: int)

# Equipped weapons (weapon system to be implemented)
var equipped_weapons: Array = []
var current_weapon_index: int = 0

# Firing state
var attack_timer: float = 0.0
var attack_cooldown: float = 0.3


func _process(delta: float) -> void:
	# Update attack cooldown
	if attack_timer > 0.0:
		attack_timer -= delta


## Check if can fire
func can_fire() -> bool:
	return attack_timer <= 0.0


## Fire current weapon
func fire(_target_position: Vector2) -> bool:
	if not can_fire():
		return false
	
	# Trigger cooldown
	attack_timer = attack_cooldown
	
	# Weapon firing logic would go here
	# For now, just emit signal
	weapon_fired.emit("current_weapon")
	
	return true


## Equip weapon
func equip_weapon(weapon_index: int) -> void:
	if weapon_index >= 0 and weapon_index < equipped_weapons.size():
		current_weapon_index = weapon_index
		weapon_equipped.emit(weapon_index)


## Add weapon to inventory
func add_weapon(weapon_data: Dictionary) -> void:
	equipped_weapons.append(weapon_data)


## Get current weapon
func get_current_weapon() -> Dictionary:
	if current_weapon_index >= 0 and current_weapon_index < equipped_weapons.size():
		return equipped_weapons[current_weapon_index]
	return {}
