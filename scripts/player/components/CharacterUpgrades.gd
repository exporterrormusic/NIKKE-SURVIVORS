extends Node
class_name CharacterUpgrades
## Manages character-specific shop upgrades.
## Extracted from PlayerCore for modularity.

## Rapunzel: "I'm a healer, but..." - heal 2% on kill
var has_rapunzel_healer: bool = false

## Commander: "Obviously Anderson" - 2x burst generation
var has_commander_burst: bool = false

## Crown: "Royal Knowledge" - 2x XP
var has_crown_xp: bool = false

## Cecil: "Three Wishes..." - 3 extra lives
var has_cecil_lives: bool = false
var cecil_lives_remaining: int = 0

## Kilo: "Protect Me Talos" - shield on kills
var has_kilo_shield: bool = false
var kilo_shield_current: int = 0
var kilo_shield_max: int = 0
var kilo_shield_visual: Node2D = null

## Nayuta: "Duplicity" - 10% clone spawn on kills
var has_nayuta_duplicity: bool = false

## Reference to player
var _player: Node = null

## Shop menu script for checking upgrades
const ShopMenuScript = preload("res://scripts/ui/ShopMenu.gd")


signal shield_changed(current: int, maximum: int)
signal lives_changed(remaining: int)
signal revive_triggered


func initialize(player: Node) -> void:
	_player = player


func apply_for_character(char_id: String, slot_unlocked: bool) -> void:
	"""Apply shop upgrade for a specific character if unlocked."""
	if not slot_unlocked:
		return
	
	match char_id:
		"rapunzel":
			if ShopMenuScript.has_character_upgrade("rapunzel", "basic_attack"):
				has_rapunzel_healer = true
				print("[CharacterUpgrades] Rapunzel 'I'm a healer, but...' upgrade active")
		"commander":
			if ShopMenuScript.has_character_upgrade("commander", "basic_attack"):
				has_commander_burst = true
				print("[CharacterUpgrades] Commander 'Obviously Anderson' upgrade active")
		"crown":
			if ShopMenuScript.has_character_upgrade("crown", "basic_attack"):
				has_crown_xp = true
				print("[CharacterUpgrades] Crown 'Royal Knowledge' upgrade active")
		"cecil":
			if ShopMenuScript.has_character_upgrade("cecil", "basic_attack"):
				has_cecil_lives = true
				cecil_lives_remaining = 3
				print("[CharacterUpgrades] Cecil 'Three Wishes...' upgrade active (3 lives)")
		"kilo":
			if ShopMenuScript.has_character_upgrade("kilo", "basic_attack"):
				has_kilo_shield = true
				if _player:
					kilo_shield_max = int(_player.max_hp * 0.5)
				kilo_shield_current = 0
				_create_shield_visual()
				print("[CharacterUpgrades] Kilo 'Protect Me Talos' upgrade active (max shield: %d)" % kilo_shield_max)
		"nayuta":
			if ShopMenuScript.has_character_upgrade("nayuta", "basic_attack"):
				has_nayuta_duplicity = true
				print("[CharacterUpgrades] Nayuta 'Duplicity' upgrade active (10% clone spawn)")


func on_enemy_killed(killer_source: String) -> void:
	"""Called when an enemy is killed. Handles kill-based upgrades."""
	var valid_kill := killer_source in ["player", "projectile", "cecil_drone", "summon"]
	var player_kill := killer_source in ["player", "projectile", "cecil_drone"]
	
	# Rapunzel healing
	if has_rapunzel_healer and player_kill and _player:
		var heal_amount := maxi(1, int(_player.max_hp * 0.02))
		if _player.has_method("heal"):
			_player.heal(heal_amount)
	
	# Kilo shield
	if has_kilo_shield and valid_kill and _player:
		var shield_gain := maxi(1, int(_player.max_hp * 0.01))
		kilo_shield_current = mini(kilo_shield_current + shield_gain, kilo_shield_max)
		shield_changed.emit(kilo_shield_current, kilo_shield_max)
		_update_shield_visual()
	
	# Nayuta duplicity
	if has_nayuta_duplicity and randf() < 0.10:
		_spawn_duplicity_clone()


func try_absorb_damage(damage: int) -> int:
	"""Try to absorb damage with Kilo's shield. Returns remaining damage."""
	if not has_kilo_shield or kilo_shield_current <= 0:
		return damage
	
	if kilo_shield_current >= damage:
		kilo_shield_current -= damage
		shield_changed.emit(kilo_shield_current, kilo_shield_max)
		_update_shield_visual()
		_spawn_shield_hit_effect()
		return 0
	else:
		var remaining := damage - kilo_shield_current
		kilo_shield_current = 0
		shield_changed.emit(kilo_shield_current, kilo_shield_max)
		_update_shield_visual()
		_spawn_shield_hit_effect()
		return remaining


func try_revive() -> bool:
	"""Try to use Cecil's extra life. Returns true if revived."""
	if not has_cecil_lives or cecil_lives_remaining <= 0:
		return false
	
	cecil_lives_remaining -= 1
	lives_changed.emit(cecil_lives_remaining)
	revive_triggered.emit()
	print("[CharacterUpgrades] Cecil's extra life used! %d lives remaining" % cecil_lives_remaining)
	return true


func get_xp_multiplier() -> float:
	"""Get XP multiplier from Crown upgrade."""
	if has_crown_xp:
		return 2.0
	return 1.0


func _create_shield_visual() -> void:
	if kilo_shield_visual and is_instance_valid(kilo_shield_visual):
		return
	if not _player:
		return
	
	var KiloShieldScript = preload("res://scripts/effects/KiloShieldVisual.gd")
	kilo_shield_visual = Node2D.new()
	kilo_shield_visual.set_script(KiloShieldScript)
	kilo_shield_visual.name = "KiloShieldVisual"
	_player.add_child(kilo_shield_visual)


func _update_shield_visual() -> void:
	if kilo_shield_visual and is_instance_valid(kilo_shield_visual):
		if kilo_shield_visual.has_method("update_shield"):
			kilo_shield_visual.update_shield(kilo_shield_current, kilo_shield_max)


func _spawn_shield_hit_effect() -> void:
	if not _player:
		return
	var ShieldHitScript = preload("res://scripts/effects/ShieldHitEffect.gd")
	var effect = ShieldHitScript.new()
	_player.get_parent().add_child(effect)
	effect.global_position = _player.global_position


func _spawn_duplicity_clone() -> void:
	if not _player:
		return
	
	var NayutaCloneScript = preload("res://scripts/characters/effects/NayutaClone.gd")
	var clone: Node2D = NayutaCloneScript.new()
	_player.get_parent().add_child(clone)
	clone.global_position = _player.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	
	# Clone stats
	var hp_level_mult: float = 1.0 + (_player.level - 1) * 0.25
	var clone_hp := maxi(1, int((_player.max_hp / 4.0) * hp_level_mult))
	var clone_attack := 0.2
	var weapon_type := "smg"
	
	clone.call("initialize", _player, weapon_type, clone_hp, clone_attack, false, _player.level)
