class_name CharacterRegistry
extends RefCounted
## Registry that manages all playable characters.
## Loads character data and provides access to controllers.

# Preload class scripts
const CharacterDataScript = preload("res://scripts/characters/CharacterData.gd")
const CharacterControllerScript = preload("res://scripts/characters/CharacterController.gd")

# Singleton-style access
static var _instance: CharacterRegistry = null

# All registered characters (by ID)
var _characters: Dictionary = {}

# Character order (for UI)
var _character_order: Array[String] = []

# Characters that start unlocked by default (source of truth)
const DEFAULT_UNLOCKED: Array[String] = ["snow_white", "scarlet", "rapunzel"]

# Controller scripts
const CONTROLLER_SCRIPTS = {
	"scarlet": preload("res://scripts/characters/ScarletController.gd"),
	"snow_white": preload("res://scripts/characters/SnowWhiteController.gd"),
	"rapunzel": preload("res://scripts/characters/RapunzelController.gd"),
	"kilo": preload("res://scripts/characters/KiloController.gd"),
	"sin": preload("res://scripts/characters/SinController.gd"),
	"crown": preload("res://scripts/characters/CrownController.gd"),
	"commander": preload("res://scripts/characters/CommanderController.gd"),
	"marian": preload("res://scripts/characters/MarianController.gd"),
	"cecil": preload("res://scripts/characters/CecilController.gd"),
	"nayuta": preload("res://scripts/characters/NayutaController.gd"),
}

## Get the singleton instance
static func get_instance() -> CharacterRegistry:
	if _instance == null:
		_instance = CharacterRegistry.new()
		_instance._load_all_characters()
	return _instance

## Load all character data from resources
func _load_all_characters() -> void:
	# Define characters in order (this determines UI order)
	# Order: Snow White, Scarlet, Rapunzel, Nayuta, Commander, Marian, Crown, Kilo, Cecil, Sin
	
	_register_character("snow_white", {
		"display_name": "Snow White",
		"description": "Sniper with piercing shots and turrets",
		"sprite_path": "snow-white-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(0.4, 0.7, 1.0),
		"secondary_color": Color(0.2, 0.4, 0.8),
		"burst_color": Color(0.6, 0.9, 1.0),
		"base_speed": 320.0,
		"base_hp": 10,
		"base_damage": 7.0,
		"crit_chance": 0.30,  # 30% crit - sniper precision
		"weapon_type": 1,  # Rifle
		"ammo_capacity": 7,
		"reload_time": 1.5,
		"attack_cooldown": 0.35,
		"projectile_speed": 1650.0,
		"special_name": "Auto-Turret",
		"special_description": "Deploys turret with 4 missiles. 1 charge, 8s recharge.",
		"special_upgrade1": "Ammo Cache: +2 turret missile capacity per level. Max: 10.",
		"special_upgrade2": "More Turrets: +2 max turret charges per level. Max: 7.",
		"burst_name": "Seven Dwarves",
		"burst_description": "90° ice beam dealing 50 damage. Massive range.",
		"burst_upgrade1": "Incendiary Rounds: Burns enemies for 34% max HP/s for 3s. Bosses take 12% instead.",
		"burst_upgrade2": "Fully Active: Kills during burst refill burst gauge.",
	})
	
	_register_character("scarlet", {
		"display_name": "Scarlet",
		"description": "Melee fighter who sacrifices HP for power",
		"sprite_path": "scarlet-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(0.9, 0.3, 0.3),
		"secondary_color": Color(0.6, 0.1, 0.1),
		"burst_color": Color(1.0, 0.2, 0.2),
		"base_speed": 500.0,
		"base_hp": 10,
		"base_damage": 10.0,
		"crit_chance": 0.25,  # 25% crit chance
		"weapon_type": 0,  # Melee
		"ammo_capacity": -1,
		"attack_cooldown": 0.3,
		"special_name": "Dash Slash",
		"special_description": "Dash releases a piercing wave dealing 8 damage. 4s cooldown.",
		"special_upgrade1": "Quick Dash: -1s cooldown per level. At max: 1s cooldown.",
		"special_upgrade2": "Vampiric Slash: Heals 5/15/25% max HP per enemy hit.",
		"burst_name": "Scarlet Flash",
		"burst_description": "Costs 50% HP. Hits all enemies on screen. Teleports to last target.",
		"burst_upgrade1": "Execution: Instantly kills non-elite, non-boss enemies. Heals 15% max HP per kill.",
		"burst_upgrade2": "Expose Weakness: Marked enemies take +50% damage from all sources.",
	})
	
	_register_character("rapunzel", {
		"display_name": "Rapunzel",
		"description": "Rocket launcher with healing abilities",
		"sprite_path": "rapunzel-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(1.0, 0.85, 0.3),
		"secondary_color": Color(0.8, 0.6, 0.1),
		"burst_color": Color(1.0, 0.95, 0.5),
		"base_speed": 310.0,
		"base_hp": 12,
		"base_damage": 15.0,
		"crit_chance": 0.10,  # 10% crit - support focused
		"weapon_type": 2,  # Launcher
		"ammo_capacity": 4,
		"reload_time": 3.0,
		"attack_cooldown": 0.5,
		"projectile_speed": 400.0,
		"special_name": "Divine Blessing",
		"special_description": "Create a healing zone. Heals 3% max HP/s for 9s. 10s cooldown.",
		"special_upgrade1": "Rejuvenation: Healing increased to 10/17.5/25% max HP/s.",
		"special_upgrade2": "Expanding Aura: Zone size/duration +50/150/300%.",
		"burst_name": "Garden of Shangri-La",
		"burst_description": "Full heal + 4s stun on all enemies.",
		"burst_upgrade1": "Blinding Radiance: Stun duration increased to 8s.",
		"burst_upgrade2": "Divine Protection: Grants 8 seconds of invincibility.",
	})
	
	_register_character("nayuta", {
		"display_name": "Nayuta",
		"description": "SMG with clone summoning",
		"sprite_path": "nayuta-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(0.6, 0.3, 0.9),
		"secondary_color": Color(0.4, 0.15, 0.7),
		"burst_color": Color(0.7, 0.4, 1.0),
		"base_speed": 340.0,
		"base_hp": 10,
		"base_damage": 2.0,
		"crit_chance": 0.20,  # 20% crit - clone synergy
		"weapon_type": 4,  # Dual SMG
		"ammo_capacity": 30,
		"reload_time": 2.0,
		"attack_cooldown": 0.08,
		"projectile_speed": 900.0,
		"special_name": "SUMMON CLONE",
		"special_description": "Summons clone with 1/2 HP/attack. Lives until killed. 8s cooldown.",
		"special_upgrade1": "NIMPH Return: Clone death heals 20/35/50% max HP.",
		"special_upgrade2": "WEAPON MASTER: Clones can use sword/rocket/sniper.",
		"burst_name": "Asceticism",
		"burst_description": "Purple galaxy explosion damages all enemies on screen.",
		"burst_upgrade1": "Nirvana: Stun bosses/elites for 8s.",
		"burst_upgrade2": "Impermanence: Bosses/elites take 50% more damage.",
	})
	
	_register_character("commander", {
		"display_name": "Commander",
		"description": "Leader with ally summoning",
		"sprite_path": "commander-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(0.72, 0.45, 0.22),
		"secondary_color": Color(0.5, 0.3, 0.15),
		"burst_color": Color(1.0, 0.84, 0.28),
		"base_speed": 270.0,
		"base_hp": 7,
		"base_damage": 6.0,
		"crit_chance": 0.15,
		"weapon_type": 6,  # Assault Rifle
		"ammo_capacity": 30,
		"reload_time": 2.0,
		"attack_cooldown": 0.2,
		"projectile_speed": 900.0,
		"special_name": "I've Got a Meeting",
		"special_description": "Stuns all enemies on screen for 3s. 12s cooldown.",
		"special_upgrade1": "Hold That Thought: +1s duration per level. Max: 6s stun.",
		"special_upgrade2": "Enikk is Calling: -2s cooldown per level. Min: 6s cooldown.",
		"burst_name": "Goddess Squad",
		"burst_description": "Summons 1 random ally (Scarlet/Snow White/Rapunzel) for 10s.",
		"burst_upgrade1": "Reinforcements I: Summons 2 allies instead of 1.",
		"burst_upgrade2": "Reinforcements II: Summons 3 allies. All 3 types available.",
	})
	
	_register_character("marian", {
		"display_name": "Marian",
		"description": "Minigun with charm and epic beam burst",
		"sprite_path": "marian-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(0.5, 0.2, 0.8),
		"secondary_color": Color(0.3, 0.1, 0.5),
		"burst_color": Color(0.7, 0.3, 1.0),
		"base_speed": 310.0,
		"base_hp": 10,
		"base_damage": 2.0,
		"crit_chance": 0.15,  # 15% crit
		"weapon_type": 5,  # Minigun
		"ammo_capacity": 100,
		"reload_time": 3.5,
		"attack_cooldown": 0.06,
		"projectile_speed": 1100.0,
		"special_name": "Rapture Queen",
		"special_description": "Charms normal enemies in area to fight for you. 10s cooldown.",
		"special_upgrade1": "Queen Gene: AoE +50/100/200%. Lv1: +Tanks. Lv2: +Elites. Lv3: Stun Bosses.",
		"special_upgrade2": "Royal Dominion: -2s cooldown per level. At max: 4s cooldown.",
		"burst_name": "New World",
		"burst_description": "5 second aimable purple laser beam. Follow mouse to aim.",
		"burst_upgrade1": "Missile Barrage: Fire 4 homing missiles every 2.5s during burst.",
		"burst_upgrade2": "Queen Beam: Beam leaves purple fire for 5s.",
	})
	
	_register_character("crown", {
		"display_name": "Crown",
		"description": "Minigun cavalry with golden nova burst",
		"sprite_path": "crown-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(1.0, 0.85, 0.3),
		"secondary_color": Color(0.8, 0.65, 0.1),
		"burst_color": Color(1.0, 0.95, 0.5),
		"base_speed": 320.0,
		"base_hp": 12,
		"base_damage": 2.0,
		"crit_chance": 0.15,  # 15% crit
		"weapon_type": 5,  # Minigun
		"ammo_capacity": 100,
		"reload_time": 3.5,
		"attack_cooldown": 0.06,
		"projectile_speed": 1100.0,
		"special_name": "Summon Trombe",
		"special_description": "Summon Trombe, charge forward with V-damage. Invincible. 2.5s duration, 10s cooldown.",
		"special_upgrade1": "Swift Steed: -2s cooldown per level. At max: 4s cooldown.",
		"special_upgrade2": "Royal Charge: Survivors explode after 1.5s for 2x ATK. +50% dmg, +20% range per level.",
		"burst_name": "Last Kingdom",
		"burst_description": "Massive golden AoE blast fills the screen for massive damage.",
		"burst_upgrade1": "One for All: Burst damage contributes to burst gauge charging.",
		"burst_upgrade2": "Naked King: Adds massive 3s golden frontal beam.",
	})
	
	_register_character("kilo", {
		"display_name": "Kilo",
		"description": "Shotgun specialist with explosive blasts",
		"sprite_path": "kilo-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(1.0, 0.5, 0.2),
		"secondary_color": Color(0.8, 0.3, 0.1),
		"burst_color": Color(1.0, 0.6, 0.3),
		"base_speed": 320.0,
		"base_hp": 8,
		"base_damage": 3.0,
		"crit_chance": 0.20,  # 20% crit - DPS focused
		"weapon_type": 3,  # Shotgun
		"ammo_capacity": 8,
		"reload_time": 2.5,
		"attack_cooldown": 0.4,
		"projectile_speed": 850.0,
		"projectile_count": 5,
		"projectile_spread": 15.0,
		"special_name": "Explosive Shells",
		"special_description": "Pellet hits trigger V-shaped explosions behind enemies. 3s cooldown.",
		"special_upgrade1": "Searing Beams: Beams burn for 15/25/35% HP/s for 3s.",
		"special_upgrade2": "Amplified Blast: Explosion +50/100/200% size & +30/60/100% dmg.",
		"burst_name": "Assign Priority",
		"burst_description": "Infinite ammo, rapid fire, 2.2x damage for 5s.",
		"burst_upgrade1": "Extended Assault: Burst lasts 10 seconds.",
		"burst_upgrade2": "T.A.L.O.S. Shield: Invincible during burst.",
	})
	
	_register_character("cecil", {
		"display_name": "Cecil",
		"description": "SMG with drone robots and hacking burst",
		"sprite_path": "cecil-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(0.2, 0.6, 1.0),
		"secondary_color": Color(0.1, 0.4, 0.8),
		"burst_color": Color(0.4, 0.8, 1.0),
		"base_speed": 250.0,
		"base_hp": 6,
		"base_damage": 2.0,
		"crit_chance": 0.15,  # 15% crit
		"weapon_type": 4,  # Dual SMG
		"ammo_capacity": 30,
		"reload_time": 2.0,
		"attack_cooldown": 0.08,
		"projectile_speed": 900.0,
		"special_name": "Drone Deploy",
		"special_description": "Deploys 2 invincible drones. Right-click toggles Hunt/Shield modes.",
		"special_upgrade1": "Overclock: Drone speed +50/100/200%.",
		"special_upgrade2": "Barrier Protocol: Shield absorbs +1 hit per level. Max: 4.",
		"burst_name": "System Hack",
		"burst_description": "Freeze all enemies 1.5s. Non-elite/boss become permanent allies.",
		"burst_upgrade1": "Malware: Hacked allies deal +50% damage.",
		"burst_upgrade2": "Exploit: Elites/bosses take 25% of their max HP as damage.",
	})
	
	_register_character("sin", {
		"display_name": "Sin",
		"description": "SMG with charm and life drain abilities",
		"sprite_path": "sin-sprite.png",
		"portrait_path": "portrait-sq.png",
		"burst_sound_path": "burst.wav",
		"primary_color": Color(0.7, 0.2, 0.9),
		"secondary_color": Color(0.5, 0.1, 0.7),
		"burst_color": Color(0.85, 0.4, 0.95),
		"base_speed": 340.0,
		"base_hp": 6,
		"base_damage": 2.0,
		"crit_chance": 0.15,  # 15% crit
		"weapon_type": 4,  # Dual SMG
		"ammo_capacity": 30,
		"reload_time": 2.0,
		"attack_cooldown": 0.08,
		"projectile_speed": 900.0,
		"special_name": "Heavy Talker",
		"special_description": "Charms normal enemies in area to fight for you. 10s cooldown.",
		"special_upgrade1": "Loud Talker: Charm AoE +50/100/200%.",
		"special_upgrade2": "Captivating: -2s cooldown per level. At max: 4s cooldown.",
		"burst_name": "Words Can Kill",
		"burst_description": "8s DOT on all visible enemies. Heals 5% max HP per 4s per enemy.",
		"burst_upgrade1": "You'll Steal for Me: Kills during burst charge burst gauge.",
		"burst_upgrade2": "You'll Die for Me: Enemies dying during burst explode for 4 damage.",
	})

## Register a character with given data
func _register_character(id: String, config: Dictionary) -> void:
	var data = CharacterDataScript.new()
	data.id = id
	
	# Apply all config values
	for key in config:
		if key in data:
			data.set(key, config[key])
	
	# Set controller script path
	data.controller_script = "res://scripts/characters/%sController.gd" % id.capitalize().replace("_", "")
	
	_characters[id] = data
	_character_order.append(id)

## Get character data by ID
func get_character(id: String) -> Resource:  # CharacterData
	return _characters.get(id)

## Get character data by index
func get_character_by_index(index: int) -> Resource:  # CharacterData
	if index >= 0 and index < _character_order.size():
		return _characters.get(_character_order[index])
	return null

## Get character index by ID
func get_character_index(id: String) -> int:
	return _character_order.find(id)

## Get total number of characters
func get_character_count() -> int:
	return _character_order.size()

## Get all character IDs in order
func get_all_character_ids() -> Array[String]:
	return _character_order.duplicate()

## Create a new controller instance for a character
func create_controller(id: String, player: Node2D) -> RefCounted:  # CharacterController
	var data = get_character(id)
	if data == null:
		push_error("CharacterRegistry: Unknown character ID: %s" % id)
		return null
	
	var script = CONTROLLER_SCRIPTS.get(id)
	if script == null:
		push_error("CharacterRegistry: No controller script for: %s" % id)
		return null
	
	var controller = script.new()
	controller.initialize(player, data)
	return controller

## Create controller by index
func create_controller_by_index(index: int, player: Node2D) -> RefCounted:  # CharacterController
	if index >= 0 and index < _character_order.size():
		return create_controller(_character_order[index], player)
	return null

## Get character sprite texture
func get_sprite(id: String) -> Texture2D:
	var data = get_character(id)
	if data:
		return data.get_sprite()
	return null

## Get character portrait texture
func get_portrait(id: String) -> Texture2D:
	var data = get_character(id)
	if data:
		return data.get_portrait()
	return null

## Get character burst sound
func get_burst_sound(id: String) -> AudioStream:
	# Commander special case: randomly pick between burst-1.mp3 and burst-2.mp3
	if id == "commander":
		var burst_num: int = randi_range(1, 2)
		var sound_path := "res://assets/characters/commander/burst-%d.mp3" % burst_num
		if ResourceLoader.exists(sound_path):
			return load(sound_path)
		# Fallback to default if random file doesn't exist
	
	var data = get_character(id)
	if data:
		return data.get_burst_sound()
	return null


## Get all character display names in order
func get_all_character_names() -> Array[String]:
	var names: Array[String] = []
	for id in _character_order:
		var data = _characters.get(id)
		if data:
			names.append(data.display_name)
		else:
			names.append(id)
	return names


## Get character display name by ID
func get_character_name(id: String) -> String:
	var data = get_character(id)
	if data:
		return data.display_name
	return id


## Get character display name by index
func get_character_name_by_index(index: int) -> String:
	var data = get_character_by_index(index)
	if data:
		return data.display_name
	return ""


## Get all portrait paths in order
func get_all_portrait_paths() -> Array[String]:
	var paths: Array[String] = []
	for id in _character_order:
		var data = _characters.get(id)
		if data:
			var folder = id.replace("_", "-")
			paths.append("res://assets/characters/%s/%s" % [folder, data.portrait_path])
	return paths


## Get portrait path by ID
func get_portrait_path(id: String) -> String:
	var data = get_character(id)
	if data:
		var folder = id.replace("_", "-")
		return "res://assets/characters/%s/%s" % [folder, data.portrait_path]
	return ""


## Get character ID by index
func get_character_id(index: int) -> String:
	if index >= 0 and index < _character_order.size():
		return _character_order[index]
	return ""
